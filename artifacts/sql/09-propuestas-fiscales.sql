-- =============================================================================
--  PraxIA Ops · artifacts/sql/09-propuestas-fiscales.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  El modelo de propuestas fiscales (migración v4.8, registro
--  `v4_8_2026-08-05`) escrito de nuevo para este repositorio. Los nombres de
--  columnas, constraints, índices, funciones, estados y las citas de los
--  comentarios son fieles al diseño verificado; los tipos exactos y los datos
--  de ejemplo son una reconstrucción. Sin datos reales.
--
--  Qué es esta tabla: el único lugar donde el Agente Fiscal escribe.
--
--      «Esta tabla no toca ningún saldo, ninguna deuda y ningún movimiento:
--       no tiene forma de hacerlo, y eso es a propósito.»
--
--  Y la regla del contrato que la gobierna, §10:
--
--      «La aprobación no ejecuta nada financieramente.»
--
--  Todo lo que sigue —los tres constraints de tabla, el índice único parcial y
--  los tres triggers— existe para sostener esas dos frases cuando el que las
--  tiene que respetar no es una persona sino un proceso que corre solo.
--
--  Motor:    PostgreSQL 16
--  Requiere: 03, 04, 07 y 08
--  Orden:    último
--  Corte:    2026-08-06
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Un solo dueño por tabla
-- -----------------------------------------------------------------------------
-- `fiscal_propuestas` se crea acá y en ningún otro lado. El archivo 04 cubre
-- las invariantes del núcleo financiero —borrado lógico, pagos de deuda,
-- saldos— y no toca esta tabla: un archivo que tuviera que destruir lo que hizo
-- otro para hacer su trabajo sería la señal de que el reparto está mal hecho.
--
-- El modelo tiene 23 columnas y ninguna sobra: separa la huella del contenido
-- de la huella de la evidencia, exige actor y propósito en cada fila por el §11
-- del contrato, guarda la confianza como número y las advertencias como lista,
-- y modela la reconsideración como un enlace a la decisión anterior en vez de
-- como una edición.
-- -----------------------------------------------------------------------------

-- =============================================================================
-- 1. praxia_finanzas.fiscal_propuestas
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_propuestas (

    -- --- Identidad -----------------------------------------------------------
    id                     bigserial     PRIMARY KEY,
    proposal_id            uuid          NOT NULL DEFAULT gen_random_uuid(),

    tipo                   text          NOT NULL CHECK (tipo IN (
                                             'clasificacion_fiscal',
                                             'imputacion_periodo',
                                             'liquidacion',
                                             'rectificativa',
                                             'ajuste',
                                             'cierre_periodo')),
    periodo                integer       CHECK (periodo IS NULL
                                                OR (periodo >= 200001
                                                    AND periodo % 100 BETWEEN 1 AND 12)),
    version_contrato       text          NOT NULL DEFAULT '1.0-draft',

    -- --- Las dos huellas -----------------------------------------------------
    huella                 char(64)      NOT NULL CHECK (huella ~ '^[0-9a-f]{64}$'),
    registros_origen       jsonb         NOT NULL
                                         CHECK (jsonb_typeof(registros_origen) = 'array'
                                                AND jsonb_array_length(registros_origen) > 0),
    huella_evidencia       char(64)      NOT NULL CHECK (huella_evidencia ~ '^[0-9a-f]{64}$'),

    -- --- El contenido de la propuesta ---------------------------------------
    criterio_propuesto     text          NOT NULL CHECK (btrim(criterio_propuesto) <> ''),
    explicacion            text          NOT NULL CHECK (btrim(explicacion) <> ''),
    nivel_de_confianza     numeric(4,3)  NOT NULL
                                         CHECK (nivel_de_confianza >= 0
                                                AND nivel_de_confianza <= 1),
    evidencia              jsonb         NOT NULL DEFAULT '[]'::jsonb
                                         CHECK (jsonb_typeof(evidencia) = 'array'),
    impacto_esperado       jsonb         NOT NULL
                                         CHECK (jsonb_typeof(impacto_esperado) = 'object'),
    advertencias           jsonb         NOT NULL DEFAULT '[]'::jsonb
                                         CHECK (jsonb_typeof(advertencias) = 'array'),

    -- --- La decisión humana --------------------------------------------------
    estado_aprobacion      text          NOT NULL DEFAULT 'pendiente'
                                         CHECK (estado_aprobacion IN (
                                             'pendiente','aprobada','rechazada','caducada')),
    aprobador              text,
    fecha_creacion         timestamptz   NOT NULL DEFAULT now(),
    fecha_decision         timestamptz,
    motivo_decision        text,

    -- --- Trazabilidad (contrato §11) ----------------------------------------
    actor                  text          NOT NULL CHECK (btrim(actor) <> ''),
    proposito              text          NOT NULL CHECK (btrim(proposito) <> ''),

    -- --- Reconsideración -----------------------------------------------------
    reconsidera_a          bigint        REFERENCES praxia_finanzas.fiscal_propuestas(id),
    motivo_reconsideracion text,

    -- =========================================================================
    -- Los tres constraints de tabla
    -- =========================================================================

    -- «Una decisión sin quién ni por qué no es una decisión, es un cambio de
    -- estado.» Por eso el constraint es por estado y no una regla general:
    --   pendiente → los tres campos de decisión vacíos, sin excepción;
    --   caducada  → sólo fecha, porque caducar lo hace el sistema y no hay
    --               persona a la que atribuirlo;
    --   aprobada / rechazada → aprobador, motivo y fecha, los tres.
    CONSTRAINT chk_prop_decision_completa CHECK (
        CASE estado_aprobacion
            WHEN 'pendiente' THEN aprobador       IS NULL
                              AND fecha_decision  IS NULL
                              AND motivo_decision IS NULL
            WHEN 'caducada'  THEN fecha_decision  IS NOT NULL
            ELSE                  btrim(coalesce(aprobador, ''))       <> ''
                              AND btrim(coalesce(motivo_decision, '')) <> ''
                              AND fecha_decision IS NOT NULL
        END
    ),

    -- Repreguntar algo ya decidido sólo es legítimo si se dice por qué. Sin
    -- este constraint, `reconsidera_a` sería una forma silenciosa de volver a
    -- pedir lo mismo con otra cara.
    CONSTRAINT chk_prop_reconsideracion CHECK (
        reconsidera_a IS NULL
        OR btrim(coalesce(motivo_reconsideracion, '')) <> ''
    ),

    -- Una propuesta que se reconsidera a sí misma es un ciclo de longitud uno:
    -- rompe la cadena de decisiones y hace imposible reconstruir cuál fue la
    -- primera respuesta.
    CONSTRAINT chk_prop_no_se_reconsidera_a_si_misma CHECK (
        reconsidera_a IS NULL OR reconsidera_a <> id
    )
);

-- -----------------------------------------------------------------------------
-- Comentarios: qué protege cada cosa y por qué
-- -----------------------------------------------------------------------------

COMMENT ON TABLE praxia_finanzas.fiscal_propuestas IS
    'El único lugar donde escribe el Agente Fiscal. Registra qué propone, sobre '
    'qué evidencia, con cuánta confianza y qué decidió la persona. '
    '«Esta tabla no toca ningún saldo, ninguna deuda y ningún movimiento: no '
    'tiene forma de hacerlo, y eso es a propósito.» Regla del contrato §10: '
    '«La aprobación no ejecuta nada financieramente.» Aprobar registra una '
    'decisión; aplicarla es un acto separado, por otra ruta y con otra credencial.';

COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.proposal_id IS
    'Identificador público de la propuesta. Se expone en el API en lugar del id '
    'interno: un entero correlativo le cuenta al cliente cuántas propuestas hubo '
    'antes, que no es asunto suyo.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.tipo IS
    'Seis tipos cerrados. La lista es cerrada porque cada tipo tiene una forma '
    'distinta de impacto_esperado, y un tipo libre haría imposible validarlos.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.periodo IS
    'AAAAMM, nullable: hay propuestas que no son de un período (una '
    'clasificación de criterio general, por ejemplo). Nullable no significa '
    'opcional-por-comodidad, significa que el concepto a veces no aplica.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.version_contrato IS
    'Versión del contrato Finanzas↔Fiscal bajo la que se generó. §16: «Está '
    'prohibido introducir cambios silenciosos al contrato por refactors del '
    'código contable subyacente». Sin esta columna, un cambio de contrato '
    'reinterpretaría propuestas viejas sin que nadie lo note.';

COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.huella IS
    'sha256 de (tipo, periodo, registros de origen canonizados, version_contrato). '
    'Impide REPREGUNTAR: dos análisis distintos sobre los mismos registros y el '
    'mismo período son la misma pregunta hecha al humano dos veces, aunque la '
    'respuesta sugerida difiera. Deliberadamente NO incluye el contenido de la '
    'propuesta, y el orden de los orígenes no la altera.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.huella_evidencia IS
    'sha256 de las filas de origen RELEÍDAS. Impide aprobar contra evidencia '
    'vencida: «Aprobar un texto que ya no describe la realidad es peor que no '
    'tener propuesta.» Al aprobar se recalcula; si cambió, la propuesta caduca. '
    'No incluye `actualizado_en` ni nada que se mueva solo, porque «una '
    'propuesta que caduca sin que nadie haya cambiado nada enseña a la gente a '
    'ignorar el aviso».';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.registros_origen IS
    'Lista NO VACÍA de {tipo, id} sobre los que se propone. Cinco tipos '
    'releíbles: movimiento, obligacion, obligacion_fiscal, comprobante, cierre. '
    'La lista es cerrada porque «una propuesta cuya evidencia no se puede releer '
    'no se puede hacer caducar», y sin caducidad la garantía no existe.';

COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.criterio_propuesto IS
    'Qué propone hacer, en una frase que una persona pueda aceptar o rechazar '
    'sin abrir la base. Es lo que se aprueba, y por eso queda congelado apenas '
    'hay decisión.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.explicacion IS
    'Por qué lo propone. En la práctica es la cita del precedente: «el 12/07 '
    'clasificaste un movimiento con esta misma descripción como profesional '
    'deducible». Verificable y desmentible en un segundo, que es el punto.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.nivel_de_confianza IS
    'Entre 0 y 1, y NUNCA 1: un precedente da 0.60, dos o tres 0.75, cuatro o '
    'más 0.85. El techo por debajo de 1 no es humildad decorativa: un 1.00 '
    'invita a aprobar sin leer.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.evidencia IS
    'Los precedentes concretos con fecha y ejemplos. Array, aunque esté vacío: '
    'una propuesta sin evidencia se distingue de una con evidencia vacía porque '
    'la primera no debería existir.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.impacto_esperado IS
    'Qué cambiaría SI alguien la aplicara. Es una descripción, no una '
    'instrucción: no hay nada en esta tabla que sepa ejecutarla.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.advertencias IS
    'Lo que el aprobador tiene que saber antes de decir que sí. Siempre incluye '
    '«La propuesta se apoya en un precedente, no en el comprobante de este '
    'gasto», y con un solo precedente agrega que «alcanza para sugerir, no para '
    'dar por sentado».';

COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.estado_aprobacion IS
    'pendiente → aprobada | rechazada | caducada. Los tres destinos son '
    'TERMINALES: «Una decisión humana registrada es evidencia: si después hay '
    'que cambiar de idea, se crea una propuesta nueva que apunta a esta. '
    'Reescribir la vieja borraría el hecho de que se decidió distinto, que suele '
    'ser el dato más importante de los dos.»';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.aprobador IS
    'Quién decidió. Una decisión sin firma humana no es una decisión. Lo pone el '
    'servidor desde la credencial, nunca el cuerpo del pedido.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.motivo_decision IS
    'Texto libre, obligatorio TAMBIÉN al aprobar. El §10 pide el registro humano '
    'en las dos direcciones: un "sí" sin motivo no se puede revisar después.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.actor IS
    'Quién pidió el análisis. Sale de la credencial, no de lo que el cliente diga '
    'que es. Obligatorio por el §11 del contrato.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.proposito IS
    'Para qué se pidió. Obligatorio por el §11. Una consulta sin propósito '
    'declarado no se puede auditar: queda "alguien miró algo".';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.reconsidera_a IS
    'Enlace a la decisión anterior sobre la misma pregunta. Reconsiderar es '
    'crear una fila nueva que apunta a la vieja, jamás editar la vieja: así la '
    'cadena completa de decisiones queda legible.';
COMMENT ON COLUMN praxia_finanzas.fiscal_propuestas.motivo_reconsideracion IS
    'Por qué se vuelve sobre algo ya decidido. Sin esto, reconsiderar sería el '
    'atajo para repreguntar lo mismo hasta obtener otra respuesta.';

COMMENT ON CONSTRAINT chk_prop_decision_completa ON praxia_finanzas.fiscal_propuestas IS
    '«Una decisión sin quién ni por qué no es una decisión, es un cambio de '
    'estado.» Pendiente exige los tres campos de decisión vacíos; caducada, '
    'sólo la fecha (la produce el sistema); aprobada y rechazada, aprobador, '
    'motivo y fecha.';
COMMENT ON CONSTRAINT chk_prop_reconsideracion ON praxia_finanzas.fiscal_propuestas IS
    'Reconsiderar exige decir por qué. Es el freno explícito a «un agente que '
    'puede repreguntar sin límite termina consiguiendo el "sí" por cansancio».';
COMMENT ON CONSTRAINT chk_prop_no_se_reconsidera_a_si_misma ON praxia_finanzas.fiscal_propuestas IS
    'Sin ciclos de longitud uno: una propuesta que se reconsidera a sí misma '
    'hace irrecuperable cuál fue la primera decisión.';

-- =============================================================================
-- 2. Los cinco índices
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_propuesta_proposal_id
    ON praxia_finanzas.fiscal_propuestas (proposal_id);

-- -----------------------------------------------------------------------------
-- El índice único PARCIAL: el que impide repreguntar
-- -----------------------------------------------------------------------------
-- Una sola propuesta PENDIENTE por huella. Parcial, y ahí está todo:
--
--   · Si fuera total, no se podría reconsiderar nunca: la segunda propuesta
--     sobre los mismos registros chocaría con la primera, ya decidida, y la
--     reconsideración legítima quedaría bloqueada por el índice.
--   · Si no existiera, el agente podría acumular veinte propuestas idénticas
--     esperando decisión. «Un agente que puede repreguntar sin límite termina
--     consiguiendo el "sí" por cansancio.»
--
-- La cláusula WHERE es exactamente la frontera entre las dos cosas: insistir
-- sobre algo no resuelto está prohibido; volver sobre algo resuelto, con
-- motivo escrito, está permitido.
-- -----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uq_propuesta_huella_pendiente
    ON praxia_finanzas.fiscal_propuestas (huella)
    WHERE estado_aprobacion = 'pendiente';

COMMENT ON INDEX praxia_finanzas.uq_propuesta_huella_pendiente IS
    'Invariante v4.8: una sola propuesta pendiente por huella. Parcial a '
    'propósito: prohíbe insistir sobre lo no resuelto y permite reconsiderar lo '
    'ya decidido, que son dos cosas distintas.';

CREATE INDEX IF NOT EXISTS idx_propuesta_estado
    ON praxia_finanzas.fiscal_propuestas (estado_aprobacion, fecha_creacion DESC);

CREATE INDEX IF NOT EXISTS idx_propuesta_periodo
    ON praxia_finanzas.fiscal_propuestas (periodo, tipo);

CREATE INDEX IF NOT EXISTS idx_propuesta_huella
    ON praxia_finanzas.fiscal_propuestas (huella);

COMMENT ON INDEX praxia_finanzas.idx_propuesta_huella IS
    'No parcial: la búsqueda por huella ANTES de insertar tiene que encontrar '
    'también las decididas, para poder responder "esto ya se decidió" en vez de '
    'crear una segunda propuesta idéntica.';

-- =============================================================================
-- TRIGGER 1 · propuesta_nace_pendiente()
-- -----------------------------------------------------------------------------
-- INVARIANTE: ninguna propuesta nace decidida.
--
-- «Insertar directamente en 'aprobada' saltearía el recorrido entero: el humano
-- nunca la vio.» No hace falta mala intención para que pase: alcanza con un
-- cliente que mande el campo con un default, o con un INSERT copiado de un
-- ejemplo. Por eso el guard además LIMPIA los campos de decisión, en vez de
-- confiar en que vengan vacíos.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.propuesta_nace_pendiente()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado_aprobacion IS DISTINCT FROM 'pendiente' THEN
        RAISE EXCEPTION
            'Una propuesta fiscal nace pendiente; se intentó crear con estado "%".',
            NEW.estado_aprobacion
            USING ERRCODE = 'check_violation',
                  HINT = 'Aprobar es un acto humano posterior, no un valor inicial.';
    END IF;

    NEW.aprobador       := NULL;
    NEW.fecha_decision  := NULL;
    NEW.motivo_decision := NULL;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.propuesta_nace_pendiente() IS
    'Invariante v4.8: toda propuesta se crea pendiente y sin datos de decisión. '
    '«Aprobar es un acto humano posterior, no un valor inicial.» El agente '
    'propone; no decide, y no puede simular haber sido decidido.';

DROP TRIGGER IF EXISTS trg_propuesta_nace_pendiente ON praxia_finanzas.fiscal_propuestas;
CREATE TRIGGER trg_propuesta_nace_pendiente
    BEFORE INSERT ON praxia_finanzas.fiscal_propuestas
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.propuesta_nace_pendiente();

-- =============================================================================
-- TRIGGER 2 · propuesta_contenido_inmutable()
-- -----------------------------------------------------------------------------
-- INVARIANTE: lo que se aprobó es exactamente lo que quedó escrito.
--
-- «Si el texto se puede editar después, la firma no vale nada: sería posible
--  aprobar "clasificar el movimiento 41 como personal" y que mañana el registro
--  diga "como profesional", con la misma aprobación adosada.»
--
-- Congela CATORCE columnas, y sólo a partir de que la propuesta dejó de estar
-- pendiente. Mientras está pendiente se puede corregir: todavía no hay ninguna
-- firma que proteger. Las tres columnas de decisión están entre las congeladas
-- porque cambiar el aprobador o el motivo después es tan grave como cambiar el
-- criterio.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.propuesta_contenido_inmutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.estado_aprobacion = 'pendiente' THEN
        RETURN NEW;
    END IF;

    IF NEW.tipo               IS DISTINCT FROM OLD.tipo
    OR NEW.periodo            IS DISTINCT FROM OLD.periodo
    OR NEW.huella             IS DISTINCT FROM OLD.huella
    OR NEW.huella_evidencia   IS DISTINCT FROM OLD.huella_evidencia
    OR NEW.registros_origen   IS DISTINCT FROM OLD.registros_origen
    OR NEW.criterio_propuesto IS DISTINCT FROM OLD.criterio_propuesto
    OR NEW.explicacion        IS DISTINCT FROM OLD.explicacion
    OR NEW.impacto_esperado   IS DISTINCT FROM OLD.impacto_esperado
    OR NEW.nivel_de_confianza IS DISTINCT FROM OLD.nivel_de_confianza
    OR NEW.evidencia          IS DISTINCT FROM OLD.evidencia
    OR NEW.advertencias       IS DISTINCT FROM OLD.advertencias
    OR NEW.aprobador          IS DISTINCT FROM OLD.aprobador
    OR NEW.fecha_decision     IS DISTINCT FROM OLD.fecha_decision
    OR NEW.motivo_decision    IS DISTINCT FROM OLD.motivo_decision
    THEN
        RAISE EXCEPTION
            'La propuesta % ya fue decidida ("%"): su contenido es inmutable.',
            OLD.id, OLD.estado_aprobacion
            USING ERRCODE = 'check_violation',
                  HINT = 'Crear una propuesta nueva con reconsidera_a apuntando a esta, y su motivo.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.propuesta_contenido_inmutable() IS
    'Invariante v4.8: catorce columnas quedan congeladas apenas la propuesta '
    'deja de estar pendiente. «Si el texto se puede editar después, la firma no '
    'vale nada.» Mientras está pendiente se puede corregir: no hay todavía '
    'ninguna decisión que proteger.';

DROP TRIGGER IF EXISTS trg_propuesta_inmutable ON praxia_finanzas.fiscal_propuestas;
CREATE TRIGGER trg_propuesta_inmutable
    BEFORE UPDATE ON praxia_finanzas.fiscal_propuestas
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.propuesta_contenido_inmutable();

-- =============================================================================
-- TRIGGER 3 · propuesta_transicion_valida()
-- -----------------------------------------------------------------------------
-- INVARIANTE: la máquina de estados, con sus tres terminales.
--
--   pendiente → aprobada | rechazada | caducada
--   aprobada  → (nada)
--   rechazada → (nada)
--   caducada  → (nada)
--
-- «Una decisión humana registrada es evidencia: si después hay que cambiar de
--  idea, se crea una propuesta nueva que apunta a esta. Reescribir la vieja
--  borraría el hecho de que se decidió distinto, que suele ser el dato más
--  importante de los dos.»
--
-- El mismo grafo vive en JavaScript (`TRANSICIONES_PROPUESTA` /
-- `puedeTransicionar()`) y hay un test que compara los dos y falla si divergen.
-- No es redundancia: el de arriba da un mensaje claro antes de intentar; el de
-- acá es el que se cumple aunque nadie pase por arriba.
--
-- El mensaje de error distingue los dos casos —estado terminal vs. destino
-- desconocido— porque son dos errores del operador distintos y llevan a dos
-- correcciones distintas.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.propuesta_transicion_valida()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado_aprobacion IS NOT DISTINCT FROM OLD.estado_aprobacion THEN
        RETURN NEW;
    END IF;

    IF OLD.estado_aprobacion <> 'pendiente' THEN
        RAISE EXCEPTION
            'La propuesta % está en un estado terminal ("%"): no admite pasar a "%".',
            OLD.id, OLD.estado_aprobacion, NEW.estado_aprobacion
            USING ERRCODE = 'check_violation',
                  HINT = 'Una decisión registrada es evidencia. Para cambiar de idea se crea una propuesta nueva con reconsidera_a.';
    END IF;

    IF NEW.estado_aprobacion NOT IN ('aprobada','rechazada','caducada') THEN
        RAISE EXCEPTION
            'Transición inválida: "pendiente" -> "%".', NEW.estado_aprobacion
            USING ERRCODE = 'check_violation',
                  HINT = 'Desde pendiente sólo se puede pasar a aprobada, rechazada o caducada.';
    END IF;

    -- Caducar lo hace el sistema y no lleva firma; decidir la lleva siempre.
    IF NEW.estado_aprobacion IN ('aprobada','rechazada') THEN
        IF btrim(coalesce(NEW.aprobador, '')) = '' THEN
            RAISE EXCEPTION 'Falta aprobador: una decisión sin firma humana no es una decisión.'
                USING ERRCODE = 'check_violation';
        END IF;
        IF btrim(coalesce(NEW.motivo_decision, '')) = '' THEN
            RAISE EXCEPTION 'Falta motivo_decision: el §10 pide el registro humano en texto libre, también cuando se aprueba.'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    NEW.fecha_decision := coalesce(NEW.fecha_decision, now());
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.propuesta_transicion_valida() IS
    'Invariante v4.8: sólo se decide una propuesta pendiente, los tres destinos '
    'son terminales y aprobar o rechazar exige firma y motivo. Caducar lo hace '
    'el sistema, por eso es el único destino sin firma.';

DROP TRIGGER IF EXISTS trg_propuesta_transicion ON praxia_finanzas.fiscal_propuestas;
CREATE TRIGGER trg_propuesta_transicion
    BEFORE UPDATE OF estado_aprobacion ON praxia_finanzas.fiscal_propuestas
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.propuesta_transicion_valida();

-- El guard de borrado físico del archivo 04 se reinstala sobre la tabla nueva:
-- una propuesta rechazada es evidencia de que alguien dijo que no.
DROP TRIGGER IF EXISTS trg_no_delete ON praxia_finanzas.fiscal_propuestas;
CREATE TRIGGER trg_no_delete
    BEFORE DELETE ON praxia_finanzas.fiscal_propuestas
    FOR EACH STATEMENT EXECUTE FUNCTION praxia_finanzas.prohibir_delete_fisico();

INSERT INTO praxia_finanzas.schema_migrations (version, descripcion) VALUES
    ('v4.8-propuestas', 'fiscal_propuestas con doble huella, tres constraints de '
                        'tabla, índice único parcial por huella pendiente y los '
                        'tres triggers de nacimiento, inmutabilidad y transición')
ON CONFLICT (version) DO NOTHING;

COMMIT;

-- =============================================================================
-- 3. Los guards en acción
-- =============================================================================
-- Todo lo que sigue es sintético. Los sub-bloques capturan la excepción a
-- propósito: el archivo tiene que poder correr entero y dejar constancia de que
-- los guards actuaron, en vez de abortar en el primer rechazo.
--
-- Si alguno de estos bloques imprimiera "NO FALLÓ", el archivo estaría roto.
--
-- Toda la demostración vive dentro de un único DO que se saltea si la tabla ya
-- tiene filas. Es lo que hace que este archivo se pueda volver a aplicar sobre
-- la misma base sin acumular basura ni reportar un rechazo por el motivo
-- equivocado.
-- =============================================================================

DO $demo$
BEGIN
    IF EXISTS (SELECT 1 FROM praxia_finanzas.fiscal_propuestas) THEN
        RAISE NOTICE 'Demostración omitida: fiscal_propuestas ya tiene filas.';
        RETURN;
    END IF;

    -- --- Semilla: una propuesta legítima, que nace pendiente -----------------

    INSERT INTO praxia_finanzas.fiscal_propuestas
        (tipo, periodo, huella, registros_origen, huella_evidencia,
         criterio_propuesto, explicacion, nivel_de_confianza,
         evidencia, impacto_esperado, advertencias, actor, proposito)
    VALUES
        ('clasificacion_fiscal', 202607,
         repeat('a1', 32),
         '[{"tipo":"movimiento","id":41}]'::jsonb,
         repeat('b2', 32),
         'Clasificar como profesional, deducible al 100 por ciento.',
         'Hay dos movimientos anteriores con la misma descripción normalizada que '
         'clasificaste como profesional deducible.',
         0.750,
         '[{"tipo":"precedente","veces":2,"ultima_vez":"2026-07-12"}]'::jsonb,
         '{"movimientos_afectados":1,"cambia_saldo":false}'::jsonb,
         '["La propuesta se apoya en un precedente, no en el comprobante de este gasto."]'::jsonb,
         'agente_fiscal', 'diagnostico mensual del periodo 202607');

    -- --- Y su decisión humana, que sí es válida ------------------------------

    UPDATE praxia_finanzas.fiscal_propuestas
       SET estado_aprobacion = 'aprobada',
           aprobador         = 'aprobador_demo',
           motivo_decision   = 'Coincide con el criterio que vengo usando desde julio.'
     WHERE huella = repeat('a1', 32);

    -- -------------------------------------------------------------------------
    -- GUARD 1 · insertar directamente en estado 'aprobada'
    -- -------------------------------------------------------------------------
    BEGIN
        INSERT INTO praxia_finanzas.fiscal_propuestas
            (tipo, huella, registros_origen, huella_evidencia,
             criterio_propuesto, explicacion, nivel_de_confianza,
             impacto_esperado, actor, proposito,
             estado_aprobacion, aprobador, motivo_decision, fecha_decision)
        VALUES
            ('ajuste', repeat('c3', 32), '[{"tipo":"movimiento","id":99}]'::jsonb,
             repeat('d4', 32),
             'Ajustar el período de imputación.', 'Porque sí.', 0.600,
             '{}'::jsonb, 'agente_fiscal', 'atajo indebido',
             'aprobada', 'agente_fiscal', 'me apruebo solo', now());

        RAISE WARNING 'GUARD 1 NO FALLÓ — el archivo está roto.';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'GUARD 1 OK · nacer aprobada rechazado: %', SQLERRM;
    END;

    -- -------------------------------------------------------------------------
    -- GUARD 2 · editar el criterio de una propuesta ya decidida
    -- -------------------------------------------------------------------------
    BEGIN
        UPDATE praxia_finanzas.fiscal_propuestas
           SET criterio_propuesto = 'Clasificar como personal, no deducible.'
         WHERE huella = repeat('a1', 32);

        RAISE WARNING 'GUARD 2 NO FALLÓ — el archivo está roto.';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'GUARD 2 OK · editar propuesta decidida rechazado: %', SQLERRM;
    END;

    -- -------------------------------------------------------------------------
    -- GUARD 3 · volver de 'aprobada' a 'pendiente'
    -- -------------------------------------------------------------------------
    BEGIN
        UPDATE praxia_finanzas.fiscal_propuestas
           SET estado_aprobacion = 'pendiente'
         WHERE huella = repeat('a1', 32);

        RAISE WARNING 'GUARD 3 NO FALLÓ — el archivo está roto.';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'GUARD 3 OK · reabrir estado terminal rechazado: %', SQLERRM;
    END;

    -- -------------------------------------------------------------------------
    -- GUARD 4 · dos propuestas pendientes con la misma huella
    -- -------------------------------------------------------------------------
    -- La demostración del índice único parcial. La primera entra; la segunda no.
    BEGIN
        INSERT INTO praxia_finanzas.fiscal_propuestas
            (tipo, periodo, huella, registros_origen, huella_evidencia,
             criterio_propuesto, explicacion, nivel_de_confianza,
             impacto_esperado, actor, proposito)
        VALUES
            ('imputacion_periodo', 202607, repeat('e5', 32),
             '[{"tipo":"comprobante","id":7}]'::jsonb, repeat('f6', 32),
             'Imputar el comprobante al período siguiente.',
             'La fecha de imputación cae fuera del mes de emisión.', 0.600,
             '{"comprobantes_afectados":1}'::jsonb,
             'agente_fiscal', 'diagnostico mensual del periodo 202607');

        RAISE NOTICE 'GUARD 4 · primera propuesta pendiente creada, como corresponde.';

        INSERT INTO praxia_finanzas.fiscal_propuestas
            (tipo, periodo, huella, registros_origen, huella_evidencia,
             criterio_propuesto, explicacion, nivel_de_confianza,
             impacto_esperado, actor, proposito)
        VALUES
            ('imputacion_periodo', 202607, repeat('e5', 32),
             '[{"tipo":"comprobante","id":7}]'::jsonb, repeat('f6', 32),
             'Imputar el comprobante al período siguiente (dicho de otra manera).',
             'Segundo análisis sobre exactamente los mismos registros.', 0.850,
             '{"comprobantes_afectados":1}'::jsonb,
             'agente_fiscal', 'insistir hasta el sí');

        RAISE WARNING 'GUARD 4 NO FALLÓ — el archivo está roto.';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'GUARD 4 OK · segunda pendiente con la misma huella rechazada: %', SQLERRM;
    END;
END;
$demo$;

-- =============================================================================
-- Lo que este archivo NO incluye, a propósito
--
-- · `calcularHuella()` y `huellaDeFilas()` viven en JavaScript, no en la base:
--   la huella se calcula ANTES de insertar, para poder responder "esto ya se
--   preguntó" sin escribir una fila.
-- · La caducidad automática al aprobar contra evidencia cambiada la ejecuta
--   `decidirPropuesta()`: relee los orígenes, y si la huella cambió marca
--   `caducada` y devuelve CORRUPT_DATA. Rechazar NO revalida — «decir "no" a
--   algo que ya no aplica sigue siendo una respuesta válida».
-- · El control de alcance del token fiscal (403 duro sobre /decidir) vive en el
--   API: «un agente que puede aprobar sus propias propuestas no está pidiendo
--   permiso: está avisando. […] La separación no descansa en que el agente se
--   porte bien, descansa en que no tenga la credencial.»
-- =============================================================================
