-- =============================================================================
--  PraxIA Ops · artifacts/sql/08-cierre-y-estado-derivado.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Las invariantes del cierre (migración v4.7, registro `v4_7_2026-08-05`)
--  escritas de nuevo para este repositorio. Los nombres de funciones,
--  triggers, estados y el grafo de transiciones son fieles al diseño
--  verificado; la implementación es una reconstrucción. Sin datos reales.
--
--  Las dos partes de esta migración salieron del mismo día y del mismo tipo de
--  hallazgo: una regla que estaba escrita en el código y que, por dos caminos
--  distintos, no se ejecutaba.
--
--    Parte 1 — El 2026-08-05 se clasificaron 22 movimientos. Quedaron con
--              `ambito` y `deducible` correctos y `estado_fiscal` en
--              'sin_clasificar'. El agente fiscal los veía clasificados y el
--              cierre los seguía marcando como bloqueantes. «Dos partes del
--              sistema, dos respuestas distintas a la misma pregunta, sin que
--              nada avisara de la contradicción.»
--
--    Parte 2 — `puedeTransicionar()` existía en el código y NUNCA se
--              ejecutaba: la ruta HTTP hacía UPDATE directo y el CHECK de la
--              tabla sólo verificaba que el valor fuera uno de los seis. Un
--              pedido con estado 'presentado' sobre un período recién abierto
--              se aceptaba. «El sistema quedaría afirmando que se presentó
--              ante ARCA algo que nunca se presentó.»
--
--  Por qué en la base y no en el código, textual de la migración original:
--  «Porque la regla ya estaba escrita en el código y no alcanzó. […] La base
--  es el único lugar por donde pasan todos los caminos.»
--
--  Motor:    PostgreSQL 16
--  Requiere: 03, 04 y 07
--  Orden:    ejecutar después del 07 y antes del 09
--  Corte:    2026-08-06
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- PARTE 1 · movimiento_estado_fiscal_derivado()
-- =============================================================================
-- INVARIANTE: estado_fiscal no puede contradecir a (ambito, deducible).
--
--   ambito NOT NULL y deducible NOT NULL y estado_fiscal = 'sin_clasificar'
--       → 'clasificado'
--   (ambito NULL o deducible NULL) y estado_fiscal = 'clasificado'
--       → 'sin_clasificar'
--
-- Lo que NO toca, y es la parte importante:
--
--   observado · incluido_en_cierre · presentado
--
-- Esos tres son decisiones deliberadas de un proceso posterior, no
-- consecuencias del encuadre. Un movimiento ya presentado ante el organismo no
-- puede volver a 'clasificado' porque alguien le corrija un campo: la
-- corrección no deshace la presentación, y un trigger que la deshiciera estaría
-- borrando el hecho de que se presentó. Lo mismo con `observado`: alguien
-- decidió mirarlo, y completar el ámbito no significa que ya lo miró.
--
-- Corolario de diseño: un trigger derivador tiene que saber DÓNDE PARAR. El que
-- deriva todo lo que puede derivar termina pisando decisiones humanas.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.movimiento_estado_fiscal_derivado()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.ambito IS NOT NULL
       AND NEW.deducible IS NOT NULL
       AND NEW.estado_fiscal = 'sin_clasificar'
    THEN
        NEW.estado_fiscal := 'clasificado';

    ELSIF (NEW.ambito IS NULL OR NEW.deducible IS NULL)
       AND NEW.estado_fiscal = 'clasificado'
    THEN
        NEW.estado_fiscal := 'sin_clasificar';
    END IF;

    -- Cualquier otro valor de estado_fiscal se deja intacto a propósito:
    -- observado, incluido_en_cierre y presentado los pone un proceso posterior
    -- y no son consecuencia del encuadre.
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.movimiento_estado_fiscal_derivado() IS
    'Invariante v4.7: estado_fiscal no contradice a (ambito, deducible). '
    'Sincroniza únicamente el par sin_clasificar/clasificado. NO toca '
    'observado, incluido_en_cierre ni presentado: esos tres los decide un '
    'proceso posterior y un movimiento ya presentado no puede volver atrás '
    'porque alguien le corrija un campo.';

-- Este archivo es el único dueño del derivador: define la función y su trigger,
-- y no depende de que ningún archivo anterior haya creado alguno.
DROP TRIGGER IF EXISTS trg_mov_estado_fiscal_derivado ON praxia_finanzas.movimientos;

CREATE TRIGGER trg_mov_estado_fiscal_derivado
    BEFORE INSERT OR UPDATE OF ambito, deducible, estado_fiscal
    ON praxia_finanzas.movimientos
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.movimiento_estado_fiscal_derivado();

-- -----------------------------------------------------------------------------
-- Corrección de las filas que ya estaban incoherentes
-- -----------------------------------------------------------------------------
-- El trigger evita el problema hacia adelante; no arregla lo que ya está mal.
-- La migración real corrigió acá las 22 filas del incidente. El rollback de esa
-- migración advierte que estas correcciones NO se revierten: «volverlas atrás
-- sería reintroducir el error».

UPDATE praxia_finanzas.movimientos
   SET estado_fiscal = 'clasificado'
 WHERE ambito IS NOT NULL
   AND deducible IS NOT NULL
   AND estado_fiscal = 'sin_clasificar';

UPDATE praxia_finanzas.movimientos
   SET estado_fiscal = 'sin_clasificar'
 WHERE (ambito IS NULL OR deducible IS NULL)
   AND estado_fiscal = 'clasificado';

-- =============================================================================
-- PARTE 2 · cierre_transicion_valida()
-- =============================================================================
-- INVARIANTE: el cierre recorre sus seis estados por el camino, o no se mueve.
--
--   abierto            → en_revision
--   en_revision        → listo_para_aprobar | abierto
--   listo_para_aprobar → aprobado | en_revision
--   aprobado           → presentado | reabierto
--   presentado         → reabierto
--   reabierto          → en_revision
--
-- Tres cosas que el grafo dice y conviene leer despacio:
--
--   1. No hay atajo de 'abierto' a 'presentado'. Ese salto era exactamente el
--      bug: aceptar que un período recién abierto figurara como presentado
--      ante el organismo.
--   2. Se puede volver atrás, pero sólo un paso y por un camino nombrado:
--      en_revision vuelve a abierto, listo_para_aprobar vuelve a en_revision.
--      Retroceder no es un estado nuevo, es una transición explícita.
--   3. Lo aprobado y lo presentado no se editan: se REABREN. `reabierto` es un
--      estado propio, con fecha y motivo obligatorio, porque volver sobre un
--      período cerrado tiene que dejar marca.
--
-- El error lleva un HINT con el recorrido correcto. Un mensaje que dice "no
-- podés" y no dice "el camino es este" obliga a leer el código para operar.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.cierre_transicion_valida()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_permitidos text[];
BEGIN
    IF NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
        RETURN NEW;
    END IF;

    v_permitidos := CASE OLD.estado
        WHEN 'abierto'            THEN ARRAY['en_revision']
        WHEN 'en_revision'        THEN ARRAY['listo_para_aprobar','abierto']
        WHEN 'listo_para_aprobar' THEN ARRAY['aprobado','en_revision']
        WHEN 'aprobado'           THEN ARRAY['presentado','reabierto']
        WHEN 'presentado'         THEN ARRAY['reabierto']
        WHEN 'reabierto'          THEN ARRAY['en_revision']
        ELSE                           ARRAY[]::text[]
    END;

    IF NOT (NEW.estado = ANY (v_permitidos)) THEN
        RAISE EXCEPTION
            'Transición de cierre inválida: "%" -> "%" (actor %, período %).',
            OLD.estado, NEW.estado, OLD.actor, OLD.periodo
            USING ERRCODE = 'check_violation',
                  HINT = format(
                      'Desde "%s" sólo se puede pasar a: %s. Recorrido completo: '
                      'abierto -> en_revision -> listo_para_aprobar -> aprobado -> '
                      'presentado; y desde aprobado o presentado se vuelve por '
                      'reabierto -> en_revision.',
                      OLD.estado,
                      coalesce(nullif(array_to_string(v_permitidos, ', '), ''), '(ninguno)'));
    END IF;

    -- Requisitos de cada destino. Están también en la capa de aplicación, con
    -- un mensaje más amable; acá está la garantía, que es distinto.
    IF NEW.estado = 'aprobado' AND btrim(coalesce(NEW.aprobado_por, '')) = '' THEN
        RAISE EXCEPTION 'Aprobar un cierre requiere aprobado_por: una aprobación sin firma no es una aprobación.'
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.estado = 'reabierto' AND btrim(coalesce(NEW.motivo_reapertura, '')) = '' THEN
        RAISE EXCEPTION 'Reabrir un cierre requiere motivo_reapertura.'
            USING ERRCODE = 'check_violation',
                  HINT = 'Sin motivo escrito no queda registro de por qué dejó de valer algo ya dado por bueno.';
    END IF;

    -- Sellos de tiempo del recorrido. Se completan acá para que ninguna ruta
    -- pueda marcar un estado sin dejar su fecha.
    NEW.revisado_en   := CASE WHEN NEW.estado = 'en_revision'
                              THEN coalesce(NEW.revisado_en, now()) ELSE NEW.revisado_en END;
    NEW.aprobado_en   := CASE WHEN NEW.estado = 'aprobado'
                              THEN coalesce(NEW.aprobado_en, now()) ELSE NEW.aprobado_en END;
    NEW.presentado_en := CASE WHEN NEW.estado = 'presentado'
                              THEN coalesce(NEW.presentado_en, now()) ELSE NEW.presentado_en END;
    NEW.reabierto_en  := CASE WHEN NEW.estado = 'reabierto'
                              THEN coalesce(NEW.reabierto_en, now()) ELSE NEW.reabierto_en END;
    NEW.actualizado_en := now();

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.cierre_transicion_valida() IS
    'Invariante v4.7: el cierre sólo se mueve por las aristas de su grafo de '
    'seis estados. La misma regla vive en la capa de aplicación con un mensaje '
    'más claro, y hay un test que compara ambos grafos y falla si divergen: la '
    'del código es cortesía, esta es la garantía.';

DROP TRIGGER IF EXISTS trg_cierre_transicion_valida ON praxia_finanzas.fiscal_cierres;
CREATE TRIGGER trg_cierre_transicion_valida
    BEFORE UPDATE OF estado ON praxia_finanzas.fiscal_cierres
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.cierre_transicion_valida();

-- -----------------------------------------------------------------------------
-- chk_cierre_nace_abierto
-- -----------------------------------------------------------------------------
-- El complemento estático del trigger: un cierre no puede DECIR que está
-- presentado sin tener la fecha de presentación. El trigger cubre los UPDATE de
-- estado; esto cubre también los INSERT, que es por donde se colaría una fila
-- nacida directamente en 'presentado'.
--
-- Se agrega NOT VALID a propósito: no se revisan las filas viejas. Validar
-- retroactivamente obligaría a inventarle una fecha de presentación a un
-- período histórico, y un dato inventado para satisfacer un constraint es peor
-- que el constraint sin validar.

ALTER TABLE praxia_finanzas.fiscal_cierres
    DROP CONSTRAINT IF EXISTS chk_cierre_nace_abierto;
ALTER TABLE praxia_finanzas.fiscal_cierres
    ADD CONSTRAINT chk_cierre_nace_abierto
    CHECK (estado <> 'presentado' OR presentado_en IS NOT NULL) NOT VALID;

COMMENT ON CONSTRAINT chk_cierre_nace_abierto ON praxia_finanzas.fiscal_cierres IS
    'Invariante v4.7: nadie declara un período presentado sin fecha de '
    'presentación. NOT VALID a propósito: las filas anteriores no se tocan.';

-- =============================================================================
-- cierre_chequeos(p_periodo integer, p_actor text)
-- =============================================================================
-- ADVERTENCIA DE FIDELIDAD: la función real tiene TRECE ramas UNION ALL —
-- ocho bloqueantes y cinco advertencias. Acá hay SEIS, elegidas por ser las
-- más ilustrativas. Las que faltan son `posibles_duplicados`,
-- `ingresos_sin_comprobante`, `transferencias_sin_conciliar`,
-- `documentos_sin_procesar`, `comprobantes_observados`, `iva_sin_desglose` y
-- `periodos_inconsistentes`.
--
-- Sobre por qué no se corrige en producción, textual: «`cierre_chequeos()` es
-- una función de trece ramas UNION ALL, y `CREATE OR REPLACE` obliga a
-- reescribirla entera. Hacerlo sin tener las trece delante es cómo se rompe
-- algo en silencio.» Esa frase describe una deuda técnica real y también el
-- motivo por el que este archivo dice cuántas ramas le faltan.
--
-- Dos reglas de diseño que sí están completas acá:
--
--   1. `bloqueante = true` impide declarar `listo_para_aprobar`, y no hay
--      parámetro para forzarlo. «Si lo hubiera, alguien lo usaría.»
--   2. Cada chequeo devuelve los IDs concretos en `referencia`: «decir "hay 3
--      problemas" sin decir cuáles no sirve de nada.»
--
-- Nota de alcance: en producción (v4.9) los movimientos filtran por
-- `contribuyente_id`. En esta reconstrucción `movimientos` no tiene esa
-- columna, así que `p_actor` gobierna los chequeos de perfil y de reglas, y los
-- de movimientos se resuelven por período. La firma y la semántica de la salida
-- son las reales.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.cierre_chequeos(
    p_periodo integer,
    p_actor   text
)
RETURNS TABLE (
    codigo     text,
    severidad  text,
    bloqueante boolean,
    titulo     text,
    detalle    text,
    cantidad   integer,
    referencia jsonb
)
LANGUAGE sql
STABLE
AS $$
WITH rango AS (
    SELECT make_date(p_periodo / 100, p_periodo % 100, 1) AS desde,
           (make_date(p_periodo / 100, p_periodo % 100, 1)
              + interval '1 month' - interval '1 day')::date AS hasta
)

-- 1 · movimientos_pendientes (BLOQUEANTE)
--    Un pendiente no integra saldos ni totales fiscales. Cerrar con pendientes
--    es congelar un resumen que ya se sabe que va a cambiar.
SELECT 'movimientos_pendientes'::text,
       'alta'::text,
       true,
       'Movimientos sin confirmar en el período'::text,
       'Un movimiento pendiente no integra saldos ni totales fiscales. Si el '
       'período se cierra así, el resumen congelado va a diferir del real en '
       'cuanto alguien confirme.'::text,
       count(*)::int,
       jsonb_build_object('movimiento_ids', jsonb_agg(m.id ORDER BY m.id))
FROM praxia_finanzas.movimientos m
WHERE m.periodo_fiscal = p_periodo
  AND m.estado = 'pendiente'
HAVING count(*) > 0

UNION ALL

-- 2 · sin_clasificar (BLOQUEANTE)
--    Es el chequeo que la v4.7 volvió confiable: antes miraba un campo que
--    podía contradecir al encuadre real.
SELECT 'sin_clasificar'::text,
       'alta'::text,
       true,
       'Movimientos sin encuadre fiscal'::text,
       'Hay movimientos confirmados sin ambito o sin deducible. No se puede '
       'determinar el resultado del período sin saber qué entra y qué no, y '
       'suponerlo sería inventar la respuesta.'::text,
       count(*)::int,
       jsonb_build_object('movimiento_ids', jsonb_agg(m.id ORDER BY m.id))
FROM praxia_finanzas.movimientos m
WHERE m.periodo_fiscal = p_periodo
  AND m.estado = 'confirmado'
  AND m.tipo  <> 'transferencia'
  AND m.estado_fiscal = 'sin_clasificar'
HAVING count(*) > 0

UNION ALL

-- 3 · gastos_sin_comprobante (BLOQUEANTE)
--    Deducir sin respaldo documental es la forma más común de que un cierre
--    prolijo no sobreviva a una revisión.
SELECT 'gastos_sin_comprobante'::text,
       'alta'::text,
       true,
       'Gastos deducibles sin comprobante'::text,
       'Se declaró deducible un gasto que no tiene comprobante vinculado. La '
       'deducción existe si existe el respaldo: sin comprobante, el importe no '
       'se puede sostener frente a nadie.'::text,
       count(*)::int,
       jsonb_build_object('movimiento_ids', jsonb_agg(m.id ORDER BY m.id))
FROM praxia_finanzas.movimientos m
WHERE m.periodo_fiscal = p_periodo
  AND m.estado = 'confirmado'
  AND m.tipo   = 'gasto'
  AND m.deducible IS TRUE
  AND m.comprobante_id IS NULL
  AND NOT EXISTS (
        SELECT 1 FROM praxia_finanzas.comprobante_movimientos cm
        WHERE cm.movimiento_id = m.id)
HAVING count(*) > 0

UNION ALL

-- 4 · descalce_comprobante (BLOQUEANTE)
--    |total - total_imputado| > 0.01. La tolerancia es de un centavo: por
--    debajo es redondeo, por encima es que falta o sobra plata en algún lado.
--    El chequeo NO decide cuál de las dos evidencias está mal: conserva las
--    dos y las muestra. «Las discrepancias deben conservar ambas evidencias.»
SELECT 'descalce_comprobante'::text,
       'alta'::text,
       true,
       'Comprobantes que no cierran con sus movimientos'::text,
       'El total del comprobante y la suma imputada a sus movimientos difieren '
       'en más de un centavo. Puede faltar un pago o sobrar una imputación: el '
       'chequeo no elige cuál, muestra las dos evidencias.'::text,
       count(*)::int,
       jsonb_build_object(
           'comprobantes', jsonb_agg(jsonb_build_object(
               'comprobante_id', vc.id,
               'total',          vc.total,
               'total_imputado', vc.total_imputado,
               'descalce',       vc.descalce) ORDER BY vc.id))
FROM praxia_finanzas.v_comprobantes vc
WHERE vc.periodo_fiscal = p_periodo
  AND vc.estado_validacion <> 'anulado'
  AND vc.movimientos_vinculados > 0
  AND abs(vc.descalce) > 0.01
HAVING count(*) > 0

UNION ALL

-- 5 · reglas_sin_verificar (BLOQUEANTE)
--    es_ficticia = true, o verificado_en IS NULL. Las dos producen el mismo
--    importe equivocado: una porque el dato es de laboratorio, la otra porque
--    nadie lo contrastó nunca contra la norma.
SELECT 'reglas_sin_verificar'::text,
       'alta'::text,
       true,
       'Reglas fiscales ficticias o sin verificar en uso'::text,
       'Hay obligaciones del período apoyadas en reglas marcadas como ficticias '
       'o que nadie verificó contra su fuente. Una regla sin verificar no sirve '
       'para determinar un importe.'::text,
       count(*)::int,
       jsonb_build_object(
           'reglas', jsonb_agg(jsonb_build_object(
               'regla_id',      r.id,
               'codigo',        r.codigo,
               'es_ficticia',   r.es_ficticia,
               'verificado_en', r.verificado_en) ORDER BY r.id))
FROM praxia_finanzas.fiscal_reglas r
WHERE (r.es_ficticia OR r.verificado_en IS NULL)
  AND EXISTS (
        SELECT 1
        FROM praxia_finanzas.fiscal_obligaciones o
        WHERE o.regla_id = r.id
          AND o.actor    = p_actor
          AND o.estado  <> 'anulada'
          AND (o.periodo = p_periodo OR o.periodo = (p_periodo / 100) * 100))
HAVING count(*) > 0

UNION ALL

-- 6 · sin_perfil_fiscal (BLOQUEANTE)
--    Sin condición fiscal vigente en el período no hay nada que determinar.
--    Ojo: `fiscal_perfiles_vigentes()` acepta el estado `historico` desde la
--    v4.13 justamente para que un cierre retroactivo no dispare este chequeo
--    sobre un período que sí tenía condición.
SELECT 'sin_perfil_fiscal'::text,
       'alta'::text,
       true,
       'Sin condición fiscal vigente en el período'::text,
       format('No hay condición fiscal vigente para "%s" al cierre del período '
              '%s. Sin condición no se puede determinar qué corresponde '
              'declarar, y cualquier cálculo sería una suposición.',
              p_actor, p_periodo),
       1,
       jsonb_build_object('actor', p_actor, 'periodo', p_periodo)
WHERE NOT EXISTS (
        SELECT 1
        FROM praxia_finanzas.fiscal_perfiles_vigentes(
                 p_actor, (SELECT hasta FROM rango)))

ORDER BY 3 DESC, 1;
$$;

COMMENT ON FUNCTION praxia_finanzas.cierre_chequeos(integer, text) IS
    'Chequeos previos al cierre de un período. Versión abreviada: SEIS de las '
    'TRECE ramas reales (ocho bloqueantes y cinco advertencias en producción). '
    'bloqueante = true impide declarar listo_para_aprobar, y no existe '
    'parámetro para forzarlo: si existiera, alguien lo usaría. Cada rama '
    'devuelve los IDs concretos en `referencia`, porque decir "hay 3 problemas" '
    'sin decir cuáles no sirve de nada.';

COMMIT;

-- =============================================================================
-- Verificación posterior a la migración
-- =============================================================================
-- La migración real termina con un bloque como este: corrige, y después
-- comprueba que la corrección efectivamente dejó la base coherente. Si algo
-- quedó mal, ABORTA con RAISE EXCEPTION en vez de reportar y seguir.
--
-- El criterio es el mismo del ON_ERROR_STOP: una migración que sigue después de
-- un error deja la base en un estado que nadie puede describir. Y una migración
-- que dice "listo" sin verificar es peor todavía, porque además tranquiliza.
-- =============================================================================

DO $$
DECLARE
    v_incoherentes  int;
    v_cierres_malos int;
BEGIN
    SELECT count(*) INTO v_incoherentes
    FROM praxia_finanzas.movimientos m
    WHERE (m.ambito IS NOT NULL AND m.deducible IS NOT NULL
           AND m.estado_fiscal = 'sin_clasificar')
       OR ((m.ambito IS NULL OR m.deducible IS NULL)
           AND m.estado_fiscal = 'clasificado');

    IF v_incoherentes > 0 THEN
        RAISE EXCEPTION
            'v4.7 incompleta: quedan % movimientos con estado_fiscal '
            'contradiciendo a (ambito, deducible).', v_incoherentes;
    END IF;

    SELECT count(*) INTO v_cierres_malos
    FROM praxia_finanzas.fiscal_cierres c
    WHERE c.estado = 'presentado' AND c.presentado_en IS NULL;

    IF v_cierres_malos > 0 THEN
        RAISE EXCEPTION
            'v4.7 incompleta: hay % cierres declarados presentados sin fecha '
            'de presentación.', v_cierres_malos;
    END IF;

    RAISE NOTICE 'v4.7 verificada: estado_fiscal coherente y ningún cierre presentado sin fecha.';
END;
$$;

INSERT INTO praxia_finanzas.schema_migrations (version, descripcion) VALUES
    ('v4.7-cierre', 'estado_fiscal derivado con trigger, máquina de estados del '
                    'cierre en la base, chk_cierre_nace_abierto y cierre_chequeos() '
                    'abreviada')
ON CONFLICT (version) DO NOTHING;

-- =============================================================================
-- Pruebas manuales sugeridas. Valores sintéticos.
--
--   -- Debe pasar: abrir un cierre y pasarlo a revisión.
--   INSERT INTO praxia_finanzas.fiscal_cierres (actor, periodo)
--   VALUES ('actor_demo', 202607);
--   UPDATE praxia_finanzas.fiscal_cierres
--      SET estado = 'en_revision' WHERE actor='actor_demo' AND periodo=202607;
--
--   -- Debe FALLAR: el salto que era el bug.
--   UPDATE praxia_finanzas.fiscal_cierres
--      SET estado = 'presentado' WHERE actor='actor_demo' AND periodo=202607;
--
--   -- Debe FALLAR: aprobar sin firma.
--   UPDATE praxia_finanzas.fiscal_cierres
--      SET estado = 'aprobado' WHERE actor='actor_demo' AND periodo=202607;
--
--   -- Debe devolver el chequeo `sin_perfil_fiscal`:
--   SELECT codigo, bloqueante, cantidad
--   FROM praxia_finanzas.cierre_chequeos(202607, 'actor_demo');
-- =============================================================================
