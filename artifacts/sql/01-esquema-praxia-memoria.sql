-- =============================================================================
--  PraxIA Ops · artifacts/sql/01-esquema-praxia-memoria.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Este archivo fue escrito de nuevo a partir del diseño verificado del esquema
--  `praxia` (memoria de PraxIA Memory Core). Los nombres de tablas, columnas,
--  categorías y la semántica de la función de deduplicación son fieles al
--  diseño real; los tipos exactos, defaults, constraints e índices son una
--  reconstrucción razonable escrita para enseñar el patrón, no para replicar
--  el servidor. No contiene datos, credenciales ni identificadores reales.
--
--  Motor:   PostgreSQL 16
--  Orden:   ejecutar 01 → 02 → 03 → 04 → 05 → 06
--  Corte:   2026-08-05
--  Licencia: Apache 2.0
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Esquema y extensiones
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS praxia;

COMMENT ON SCHEMA praxia IS
    'Memoria estructurada del ecosistema PraxIA Ops. Capa 2 de la memoria en '
    '4 capas: hechos, eventos, proyectos, tareas y errores de agente. '
    'La capa 1 (corta) vive en n8n, la capa 3 (documental) en Markdown, '
    'la capa 4 (auditada) es agent_errors + logs de ejecución.';

-- `unaccent` es la pieza que hace que "gestion" encuentre "gestión".
-- Los mensajes de Telegram vienen sin acentos la mitad de las veces.
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;

-- -----------------------------------------------------------------------------
-- 1. Normalización
-- -----------------------------------------------------------------------------
-- Una sola definición de "forma normalizada" para todo el esquema: la usan la
-- deduplicación de hechos, la búsqueda full-text y la huella de errores.
--
-- Se declara IMMUTABLE a propósito, usando la forma de dos argumentos de
-- unaccent() —la única que es inmutable—, porque hace falta para columnas
-- generadas e índices. Es el patrón documentado para este caso.

CREATE OR REPLACE FUNCTION praxia.normalizar(txt text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT btrim(
             regexp_replace(
               regexp_replace(
                 lower(public.unaccent('public.unaccent'::regdictionary, coalesce(txt, ''))),
                 '[^a-z0-9]+', ' ', 'g'),
               '\s+', ' ', 'g')
           );
$$;

COMMENT ON FUNCTION praxia.normalizar(text) IS
    'Forma canónica de un texto: minúsculas, sin acentos, sin puntuación y con '
    'espacios colapsados. Es la base de la deduplicación y de la búsqueda.';

-- Marca de tiempo de última modificación, en un solo lugar.
CREATE OR REPLACE FUNCTION praxia.tocar_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia.tocar_updated_at() IS
    'Trigger genérico: mantiene updated_at sin depender de que la aplicación se acuerde.';

-- -----------------------------------------------------------------------------
-- 2. memory_facts — el corazón de la memoria
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia.memory_facts (
    id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    fact        text        NOT NULL
                            CHECK (length(btrim(fact)) BETWEEN 3 AND 2000),

    -- Columna generada: la forma normalizada nunca se escribe a mano, así que
    -- no puede quedar desincronizada del texto original.
    fact_norm   text        GENERATED ALWAYS AS (praxia.normalizar(fact)) STORED,

    -- Etiquetas cerradas. Una categoría abierta se convierte en cien categorías
    -- con una sola fila cada una.
    category    text        NOT NULL DEFAULT 'recordar'
                            CHECK (category IN ('decision','recordar','preferencia',
                                                'regla','seguridad','familia')),

    project     text,

    confidence  numeric(3,2) NOT NULL DEFAULT 1.00
                            CHECK (confidence >= 0 AND confidence <= 1),

    -- Baja lógica. Un hecho superado se desactiva; la historia no se borra.
    active      boolean     NOT NULL DEFAULT true,

    source      text        NOT NULL DEFAULT 'telegram',

    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE praxia.memory_facts IS
    'Hechos estables que el agente debe poder recuperar: decisiones, reglas, '
    'preferencias. Es lo que se consulta para responder. No guarda '
    'conversaciones ni transcripciones, y por política nunca guarda secretos.';

COMMENT ON COLUMN praxia.memory_facts.fact IS
    'El hecho, en lenguaje natural. Los hechos se citan por número (el hecho #14).';
COMMENT ON COLUMN praxia.memory_facts.fact_norm IS
    'Forma normalizada, generada. Soporta la deduplicación y la búsqueda full-text.';
COMMENT ON COLUMN praxia.memory_facts.category IS
    'Etiqueta cerrada: decision | recordar | preferencia | regla | seguridad | familia.';
COMMENT ON COLUMN praxia.memory_facts.confidence IS
    'Confianza declarada, 0 a 1. Un hecho inferido entra con menos que uno afirmado.';
COMMENT ON COLUMN praxia.memory_facts.active IS
    'Baja lógica. Falso = superado. Los hechos inactivos no salen en las consultas.';

-- Deduplicación estructural: no puede haber dos hechos activos con la misma
-- forma normalizada. Es lo que evita cinco filas diciendo lo mismo.
CREATE UNIQUE INDEX IF NOT EXISTS memory_facts_norm_activo_uniq
    ON praxia.memory_facts (fact_norm)
    WHERE active;

-- Índice de búsqueda en español sobre la forma normalizada.
CREATE INDEX IF NOT EXISTS memory_facts_fts_idx
    ON praxia.memory_facts
    USING gin (to_tsvector('spanish', fact_norm));

CREATE INDEX IF NOT EXISTS memory_facts_categoria_idx
    ON praxia.memory_facts (category)
    WHERE active;

CREATE INDEX IF NOT EXISTS memory_facts_proyecto_idx
    ON praxia.memory_facts (project)
    WHERE active AND project IS NOT NULL;

DROP TRIGGER IF EXISTS trg_memory_facts_updated_at ON praxia.memory_facts;
CREATE TRIGGER trg_memory_facts_updated_at
    BEFORE UPDATE ON praxia.memory_facts
    FOR EACH ROW EXECUTE FUNCTION praxia.tocar_updated_at();

-- -----------------------------------------------------------------------------
-- 3. memory_events — materia prima, no memoria consultable
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia.memory_events (
    id                 bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    agent              text        NOT NULL DEFAULT 'oppenheimer',
    source             text        NOT NULL DEFAULT 'telegram',
    device             text,
    user_message       text,
    assistant_response text,
    intent             text,
    project            text,
    importance         smallint    NOT NULL DEFAULT 3
                                   CHECK (importance BETWEEN 1 AND 5),
    tags               jsonb       NOT NULL DEFAULT '[]'::jsonb,
    raw_json           jsonb       NOT NULL DEFAULT '{}'::jsonb,
    created_at         timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT memory_events_tags_es_arreglo CHECK (jsonb_typeof(tags) = 'array')
);

COMMENT ON TABLE praxia.memory_events IS
    'Registro de interacciones. Es materia prima: de acá pueden salir hechos, '
    'pero no se consulta para responder. Separar eventos de hechos es lo que '
    'impide que la memoria se convierta en un log gigante e inútil.';

COMMENT ON COLUMN praxia.memory_events.raw_json IS
    'Carga cruda del evento, para poder reconstruir sin perder información.';
COMMENT ON COLUMN praxia.memory_events.importance IS
    'Importancia estimada, 1 a 5. Sirve para decidir qué merece promoverse a hecho.';

CREATE INDEX IF NOT EXISTS memory_events_fecha_idx
    ON praxia.memory_events (created_at DESC);

CREATE INDEX IF NOT EXISTS memory_events_tags_idx
    ON praxia.memory_events USING gin (tags);

-- -----------------------------------------------------------------------------
-- 4. projects
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia.projects (
    id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proyecto    text        NOT NULL UNIQUE,
    status      text        NOT NULL DEFAULT 'activo'
                            CHECK (status IN ('idea','activo','pausado','cerrado')),
    priority    smallint    NOT NULL DEFAULT 3
                            CHECK (priority BETWEEN 1 AND 5),
    owner       text        NOT NULL DEFAULT 'aldo',
    next_action text,
    active      boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    -- Un proyecto activo sin próxima acción es un deseo, no un proyecto.
    -- No se prohíbe, se marca: la vista de revisión los levanta.
    CONSTRAINT projects_cerrado_sin_next_action
        CHECK (status <> 'cerrado' OR next_action IS NULL)
);

COMMENT ON TABLE praxia.projects IS
    'Proyectos vivos. La columna next_action es deliberada: un proyecto sin '
    'próxima acción concreta no avanza, y el agente puede señalarlo.';

COMMENT ON COLUMN praxia.projects.next_action IS
    'La próxima acción concreta. Al cerrar el proyecto se vacía.';

DROP TRIGGER IF EXISTS trg_projects_updated_at ON praxia.projects;
CREATE TRIGGER trg_projects_updated_at
    BEFORE UPDATE ON praxia.projects
    FOR EACH ROW EXECUTE FUNCTION praxia.tocar_updated_at();

-- -----------------------------------------------------------------------------
-- 5. tasks
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia.tasks (
    id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tarea       text        NOT NULL CHECK (length(btrim(tarea)) >= 3),
    tarea_norm  text        GENERATED ALWAYS AS (praxia.normalizar(tarea)) STORED,
    project_id  bigint      REFERENCES praxia.projects(id),
    status      text        NOT NULL DEFAULT 'pendiente'
                            CHECK (status IN ('pendiente','en_curso','bloqueada',
                                              'hecha','cancelada')),
    priority    smallint    NOT NULL DEFAULT 3
                            CHECK (priority BETWEEN 1 AND 5),
    due_date    date,
    owner       text        NOT NULL DEFAULT 'aldo',
    active      boolean     NOT NULL DEFAULT true,
    done_at     timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    -- Una tarea hecha tiene fecha de hecha. Sin excepciones.
    CONSTRAINT tasks_hecha_con_fecha
        CHECK ((status = 'hecha') = (done_at IS NOT NULL))
);

COMMENT ON TABLE praxia.tasks IS
    'Tareas, opcionalmente asociadas a un proyecto. Misma política que el resto '
    'del esquema: baja lógica, estados cerrados y actualización trazable.';

COMMENT ON COLUMN praxia.tasks.tarea_norm IS
    'Forma normalizada, para deduplicar "comprar pilas" contra "Comprar pilas.".';

CREATE UNIQUE INDEX IF NOT EXISTS tasks_norm_abiertas_uniq
    ON praxia.tasks (tarea_norm, coalesce(project_id, 0))
    WHERE active AND status IN ('pendiente','en_curso','bloqueada');

CREATE INDEX IF NOT EXISTS tasks_vencimiento_idx
    ON praxia.tasks (due_date)
    WHERE active AND status <> 'hecha';

DROP TRIGGER IF EXISTS trg_tasks_updated_at ON praxia.tasks;
CREATE TRIGGER trg_tasks_updated_at
    BEFORE UPDATE ON praxia.tasks
    FOR EACH ROW EXECUTE FUNCTION praxia.tocar_updated_at();

-- -----------------------------------------------------------------------------
-- 6. agent_errors — capa 4, memoria auditada
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia.agent_errors (
    id             bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    workflow_name  text        NOT NULL,
    node_name      text,
    error_message  text        NOT NULL,

    -- Huella estable del error: mismo workflow + mismo nodo + mismo mensaje
    -- con los números e identificadores enmascarados. Es la clave de la
    -- deduplicación: cien fallas iguales son una fila con contador en 100.
    fingerprint    text        NOT NULL,

    severity       text        NOT NULL DEFAULT 'error'
                               CHECK (severity IN ('info','warning','error','critical')),

    occurrences    integer     NOT NULL DEFAULT 1 CHECK (occurrences > 0),

    first_seen_at  timestamptz NOT NULL DEFAULT now(),
    last_seen_at   timestamptz NOT NULL DEFAULT now(),

    -- Anti-spam: no se alerta de nuevo hasta que pase la ventana.
    last_alert_at  timestamptz,

    execution_ref  text,
    payload        jsonb       NOT NULL DEFAULT '{}'::jsonb,

    resolved       boolean     NOT NULL DEFAULT false,
    resolved_at    timestamptz,

    CONSTRAINT agent_errors_fingerprint_uniq UNIQUE (fingerprint),
    CONSTRAINT agent_errors_resuelto_con_fecha
        CHECK ((resolved) = (resolved_at IS NOT NULL))
);

COMMENT ON TABLE praxia.agent_errors IS
    'Errores capturados por el errorWorkflow global. Una fila por clase de '
    'error, no una por ejecución fallida: la deduplicación por huella es lo '
    'que hace que el canal de alertas siga siendo legible cuando algo se rompe '
    'en bucle.';

COMMENT ON COLUMN praxia.agent_errors.fingerprint IS
    'SHA-256 de workflow + nodo + mensaje normalizado con números enmascarados.';
COMMENT ON COLUMN praxia.agent_errors.occurrences IS
    'Cuántas veces se vio esta clase de error desde first_seen_at.';
COMMENT ON COLUMN praxia.agent_errors.last_alert_at IS
    'Última alerta enviada. Junto con la ventana anti-spam decide si se avisa.';
COMMENT ON COLUMN praxia.agent_errors.execution_ref IS
    'Referencia opaca a la ejecución que disparó la última ocurrencia.';

CREATE INDEX IF NOT EXISTS agent_errors_abiertos_idx
    ON praxia.agent_errors (last_seen_at DESC)
    WHERE NOT resolved;

-- -----------------------------------------------------------------------------
-- 7. upsert_agent_error — deduplicación y reserva de alerta en una sola llamada
-- -----------------------------------------------------------------------------
-- El avisador de errores llama a esta función y hace lo que ella le dice.
-- Devuelve tres cosas: el id de la fila, cuántas veces pasó, y si corresponde
-- alertar. Que la decisión de alertar viva acá y no en el workflow es lo que
-- garantiza que sea atómica: dos ejecuciones simultáneas no mandan dos avisos.

CREATE OR REPLACE FUNCTION praxia.upsert_agent_error(
    p_workflow      text,
    p_node          text     DEFAULT NULL,
    p_message       text     DEFAULT '',
    p_severity      text     DEFAULT 'error',
    p_execution_ref text     DEFAULT NULL,
    p_payload       jsonb    DEFAULT '{}'::jsonb,
    p_alert_window  interval DEFAULT interval '15 minutes'
)
RETURNS TABLE (error_id bigint, total_ocurrencias integer, debe_alertar boolean)
LANGUAGE plpgsql
AS $$
DECLARE
    v_now         timestamptz := now();
    v_fingerprint text;
    v_id          bigint;
    v_occ         integer;
    v_alert       boolean;
BEGIN
    -- Enmascarar números, hashes e ids hace que "timeout after 30012 ms" y
    -- "timeout after 29876 ms" sean el mismo error. Sin esto, la deduplicación
    -- no dedupica nada.
    v_fingerprint := encode(
        sha256(convert_to(
            coalesce(p_workflow, '') || '|' ||
            coalesce(p_node, '')     || '|' ||
            regexp_replace(praxia.normalizar(p_message), '[0-9]+', '#', 'g'),
            'UTF8')),
        'hex');

    INSERT INTO praxia.agent_errors AS ae (
        workflow_name, node_name, error_message, fingerprint,
        severity, execution_ref, payload
    )
    VALUES (
        p_workflow, p_node, p_message, v_fingerprint,
        p_severity, p_execution_ref, coalesce(p_payload, '{}'::jsonb)
    )
    ON CONFLICT (fingerprint) DO UPDATE
        SET occurrences   = ae.occurrences + 1,
            last_seen_at  = v_now,
            error_message = EXCLUDED.error_message,
            severity      = EXCLUDED.severity,
            execution_ref = EXCLUDED.execution_ref,
            payload       = EXCLUDED.payload,
            resolved      = false,
            resolved_at   = NULL
    RETURNING ae.id,
              ae.occurrences,
              (ae.last_alert_at IS NULL OR ae.last_alert_at < v_now - p_alert_window)
      INTO v_id, v_occ, v_alert;

    -- Reserva de la alerta: se marca acá, dentro de la misma transacción, para
    -- que nadie más la mande por la misma ventana.
    IF v_alert THEN
        UPDATE praxia.agent_errors
           SET last_alert_at = v_now
         WHERE id = v_id;
    END IF;

    RETURN QUERY SELECT v_id, v_occ, v_alert;
END;
$$;

COMMENT ON FUNCTION praxia.upsert_agent_error(text, text, text, text, text, jsonb, interval) IS
    'Registra un error deduplicando por huella y reserva la alerta de forma '
    'atómica. Devuelve (error_id, total_ocurrencias, debe_alertar). El workflow '
    'avisa por Telegram sólo si debe_alertar es verdadero.';

COMMIT;

-- =============================================================================
-- Verificación rápida (sintética). Descomentar para probar en un laboratorio:
--
--   SELECT * FROM praxia.upsert_agent_error(
--       'Oppenheimer - Agente de Email', 'Gmail - Send',
--       'timeout after 30012 ms');
--   SELECT * FROM praxia.upsert_agent_error(
--       'Oppenheimer - Agente de Email', 'Gmail - Send',
--       'timeout after 29876 ms');
--   -- Esperado: una sola fila, total_ocurrencias = 2,
--   --           debe_alertar = true la primera vez y false la segunda.
-- =============================================================================
