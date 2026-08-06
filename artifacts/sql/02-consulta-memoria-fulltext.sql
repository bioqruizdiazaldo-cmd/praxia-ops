-- =============================================================================
--  PraxIA Ops · artifacts/sql/02-consulta-memoria-fulltext.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Reconstrucción comentada de la consulta que ejecuta el subagente
--  "PraxIA Memory — Consultar". Es fiel al diseño verificado —transacción
--  READ ONLY, normalización de acentos, to_tsvector('spanish'), tier estricto
--  y tier laxo— pero está escrita de nuevo, con una consulta de ejemplo
--  sintética embebida. En producción el texto de la consulta llega como
--  parámetro ($1), nunca concatenado.
--
--  Motor:   PostgreSQL 16
--  Requiere: 01-esquema-praxia-memoria.sql
--  Corte:   2026-08-05
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- Por qué READ ONLY
-- -----------------------------------------------------------------------------
-- El camino de consulta no tiene ninguna razón para escribir. Declararlo en la
-- transacción es el permiso más barato y más difícil de saltear que existe:
-- aunque el SQL tenga un error, aunque alguien pegue un UPDATE por accidente,
-- aunque una función llamada acá adentro intente escribir, la transacción
-- aborta. No depende de roles, ni de revisión de código, ni de disciplina.

BEGIN TRANSACTION READ ONLY;

WITH
-- 1. Parámetro de entrada -----------------------------------------------------
--    Valor sintético, sólo para que el archivo corra de punta a punta.
--    En n8n esto es un parámetro posicional.
params AS (
    SELECT 'Qué decidí sobre la gestión de proyectos'::text AS consulta_cruda
),

-- 2. Normalización ------------------------------------------------------------
--    Se aplica la MISMA función que generó memory_facts.fact_norm. Que sea la
--    misma no es un detalle: si la consulta se normalizara distinto que el
--    dato, el índice no serviría y las coincidencias serían aleatorias.
normalizada AS (
    SELECT praxia.normalizar(consulta_cruda) AS q
    FROM params
),

-- 3. Tokens significativos ----------------------------------------------------
--    to_tsvector('spanish') ya descarta las stop-words por su cuenta. Esta
--    lista adicional existe para el tier laxo y para el fallback por LIKE,
--    donde no hay diccionario que las filtre. Sin esto, buscar "qué decidí
--    sobre la gestión" haría match con cualquier hecho que contenga "sobre".
tokens AS (
    SELECT t AS token
    FROM normalizada,
         LATERAL regexp_split_to_table(normalizada.q, '\s+') AS t
    WHERE length(t) >= 3
      AND t NOT IN (
          'que','como','cual','cuales','para','por','con','del','las','los',
          'una','unos','unas','sobre','este','esta','esto','estos','estas',
          'mis','sus','tus','hay','fue','son','ser','tengo','tiene','tenemos',
          'algo','todo','toda','todos','todas','mas','muy','pero','sin','ese',
          'esa','eso','ahi','aca','cuando','donde','quien','decidi','decidio'
      )
),

consulta AS (
    SELECT
        (SELECT q FROM normalizada)                 AS q,
        coalesce(array_agg(token), ARRAY[]::text[]) AS toks,
        -- La tsquery del tier laxo se arma acá y una sola vez. Si no quedó
        -- ningún token significativo se devuelve NULL en vez de una cadena
        -- vacía: to_tsquery('') es un error de sintaxis, y NULL simplemente
        -- no matchea. Evitar el error es más barato que atraparlo.
        CASE WHEN count(token) = 0
             THEN NULL::tsquery
             ELSE to_tsquery('spanish', array_to_string(array_agg(token), ' | '))
        END                                         AS tsq_laxo
    FROM tokens
),

-- 4. TIER ESTRICTO ------------------------------------------------------------
--    plainto_tsquery('spanish', ...) une TODOS los lexemas con AND. Un hecho
--    entra sólo si contiene todos los términos significativos de la consulta.
--    Alta precisión: lo que sale acá se puede citar como respuesta directa.
--
--    El stemming español es lo que hace que "proyectos" encuentre "proyecto"
--    y "gestión" encuentre "gestionar". Es exactamente lo que un usuario
--    espera y lo que un LIKE nunca le va a dar.
estricto AS (
    SELECT
        f.id,
        f.fact,
        f.category,
        f.project,
        f.confidence,
        f.updated_at,
        ts_rank(to_tsvector('spanish', f.fact_norm),
                plainto_tsquery('spanish', c.q)) AS rank
    FROM praxia.memory_facts f
    CROSS JOIN consulta c
    WHERE f.active                       -- los hechos superados no responden
      AND c.q <> ''
      AND to_tsvector('spanish', f.fact_norm) @@ plainto_tsquery('spanish', c.q)
),

-- 5. TIER LAXO ----------------------------------------------------------------
--    Une los términos con OR y agrega un fallback por coincidencia parcial
--    sobre la forma normalizada. Alta cobertura: sirve para "creo que había
--    algo sobre esto" y para nombres propios que el diccionario no lexematiza.
--
--    Se excluye lo que ya salió en el tier estricto para no repetir filas.
--    El agente recibe los dos grupos etiquetados y puede decir "encontré esto
--    exacto, y esto relacionado" en vez de mezclarlos en una sola bolsa.
laxo AS (
    SELECT
        f.id,
        f.fact,
        f.category,
        f.project,
        f.confidence,
        f.updated_at,
        ts_rank(to_tsvector('spanish', f.fact_norm), c.tsq_laxo) AS rank
    FROM praxia.memory_facts f
    CROSS JOIN consulta c
    WHERE f.active
      AND cardinality(c.toks) > 0
      AND (
            to_tsvector('spanish', f.fact_norm) @@ c.tsq_laxo
         OR EXISTS (
                SELECT 1
                FROM unnest(c.toks) AS tk
                WHERE f.fact_norm LIKE '%' || tk || '%'
            )
          )
      AND NOT EXISTS (SELECT 1 FROM estricto e WHERE e.id = f.id)
)

-- 6. Salida -------------------------------------------------------------------
--    El orden es primero por tier y después por ranking: la precisión manda
--    sobre la cobertura. El LIMIT existe para proteger la ventana de contexto
--    del modelo, no para proteger la base.
--
--    Si esta consulta devuelve cero filas, la respuesta correcta del agente es
--    "no tengo registrado". Si NO se ejecutó, esa respuesta está prohibida.
SELECT *
FROM (
    SELECT 1 AS tier_orden, 'estricto'::text AS tier,
           id, fact, category, project, confidence, updated_at, rank
    FROM estricto
    UNION ALL
    SELECT 2, 'laxo'::text,
           id, fact, category, project, confidence, updated_at, rank
    FROM laxo
) resultados
ORDER BY tier_orden ASC,
         rank DESC NULLS LAST,
         updated_at DESC
LIMIT 12;

COMMIT;

-- =============================================================================
-- Notas de diseño
--
-- · No hay embeddings ni búsqueda vectorial. Para un corpus de decenas de
--   hechos escritos por una sola persona, el full-text en español con
--   normalización de acentos es más preciso, más barato y —sobre todo— más
--   explicable: se puede decir exactamente por qué salió cada fila.
--
-- · La misma consulta con miles de hechos empezaría a devolver ruido en el
--   tier laxo. Ese es el disparador de revisión declarado en el ADR-003.
--
-- · El texto de la consulta NUNCA se concatena. Va como parámetro. La
--   normalización no es un mecanismo de seguridad.
-- =============================================================================
