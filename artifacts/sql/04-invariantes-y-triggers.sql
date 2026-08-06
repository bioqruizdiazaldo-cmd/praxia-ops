-- =============================================================================
--  PraxIA Ops · artifacts/sql/04-invariantes-y-triggers.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Los guards de PraxIA Finanzas escritos como código ejecutable. Los nombres
--  y las invariantes son fieles al diseño verificado (v4.5, v4.7 y v4.8); la
--  implementación fue escrita de nuevo para este repositorio.
--
--  La idea central: las reglas de negocio que no pueden violarse NUNCA viven
--  en la base, no en el prompt del agente ni en el cliente. Un prompt se
--  rodea con una reformulación; un trigger, no.
--
--  Este archivo crea también las tablas mínimas de deudas y propuestas
--  (v4.3/v4.5/v4.8) porque sin ellas los guards no se pueden ejecutar.
--
--  Motor:   PostgreSQL 16
--  Requiere: 03-esquema-finanzas-nucleo.sql
--  Corte:   2026-08-05
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Utilidad compartida
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION praxia_finanzas.tocar_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_movimientos_updated_at ON praxia_finanzas.movimientos;
CREATE TRIGGER trg_movimientos_updated_at
    BEFORE UPDATE ON praxia_finanzas.movimientos
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.tocar_updated_at();

-- -----------------------------------------------------------------------------
-- 1. Tablas de deuda y propuestas (mínimas, para que los guards corran)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.deudas_pendientes (
    id             bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    descripcion    text         NOT NULL,
    acreedor       text,
    monto_original numeric(18,2) NOT NULL CHECK (monto_original > 0),
    moneda         char(3)      NOT NULL CHECK (moneda ~ '^[A-Z]{3}$'),
    saldo          numeric(18,2) NOT NULL CHECK (saldo >= 0),
    vencimiento    date,
    perfil_id      smallint     NOT NULL REFERENCES praxia_finanzas.perfiles(id),
    estado         text         NOT NULL DEFAULT 'abierta'
                                CHECK (estado IN ('abierta','parcial','saldada','anulada')),
    created_at     timestamptz  NOT NULL DEFAULT now(),
    updated_at     timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT deuda_saldo_no_supera_original CHECK (saldo <= monto_original)
);

COMMENT ON TABLE praxia_finanzas.deudas_pendientes IS
    'Deudas, cuotas y gastos esperados. Registrar una deuda NO modifica '
    'saldos: el impacto financiero ocurre únicamente al vincular un pago real.';

CREATE TABLE IF NOT EXISTS praxia_finanzas.deuda_pagos (
    id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    deuda_id      bigint        NOT NULL REFERENCES praxia_finanzas.deudas_pendientes(id),
    movimiento_id bigint        REFERENCES praxia_finanzas.movimientos(id),
    monto         numeric(18,2) NOT NULL CHECK (monto > 0),
    moneda        char(3)       NOT NULL CHECK (moneda ~ '^[A-Z]{3}$'),
    fecha         date          NOT NULL DEFAULT current_date,
    anulado       boolean       NOT NULL DEFAULT false,
    anulado_at    timestamptz,
    created_at    timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT deuda_pagos_anulado_con_fecha CHECK (anulado = (anulado_at IS NOT NULL))
);

COMMENT ON TABLE praxia_finanzas.deuda_pagos IS
    'Pagos totales y parciales de una deuda, sin duplicar movimientos. Anular '
    'un pago es baja lógica y devuelve el saldo automáticamente.';

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_propuestas (
    id               bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    movimiento_id    bigint      NOT NULL REFERENCES praxia_finanzas.movimientos(id),
    contenido        jsonb       NOT NULL,
    motivo           text        NOT NULL,
    -- Identidad del contenido propuesto: sirve para no volver a proponer lo mismo.
    huella           text        NOT NULL,
    -- Identidad de la evidencia sobre la que se propuso: si la evidencia
    -- cambió, la propuesta caducó y no puede aprobarse.
    huella_evidencia text        NOT NULL,
    estado           text        NOT NULL DEFAULT 'pendiente'
                                 CHECK (estado IN ('pendiente','aprobada','rechazada','caducada')),
    decidida_at      timestamptz,
    decidida_por     text,
    created_at       timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT propuesta_decidida_con_fecha
        CHECK (estado IN ('pendiente','caducada') OR decidida_at IS NOT NULL)
);

COMMENT ON TABLE praxia_finanzas.fiscal_propuestas IS
    'Propuestas de clasificación fiscal que el motor eleva a decisión humana. '
    'El agente propone a partir de precedentes; la persona decide. La '
    'aprobación no ejecuta nada financieramente.';

-- No insistir con lo mismo: una sola propuesta pendiente por (movimiento, huella).
-- Es la traducción estructural de "un agente que puede repreguntar sin límite
-- termina consiguiendo el sí por cansancio".
CREATE UNIQUE INDEX IF NOT EXISTS propuesta_pendiente_uniq
    ON praxia_finanzas.fiscal_propuestas (movimiento_id, huella)
    WHERE estado = 'pendiente';

DROP TRIGGER IF EXISTS trg_deudas_updated_at ON praxia_finanzas.deudas_pendientes;
CREATE TRIGGER trg_deudas_updated_at
    BEFORE UPDATE ON praxia_finanzas.deudas_pendientes
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.tocar_updated_at();

-- =============================================================================
-- GUARD 1 · prohibir_delete_fisico
-- -----------------------------------------------------------------------------
-- INVARIANTE: la historia financiera es append-only. Nada se borra físicamente.
-- Corregir es escribir una corrección; dar de baja es marcar la baja. Un
-- registro borrado es una pregunta que nadie va a poder contestar después.
--
-- Esta es la tercera de tres capas: no existe endpoint DELETE, el rol de la
-- aplicación no tiene el permiso, y además el trigger lo bloquea. Las tres
-- porque cada una falla de una manera distinta.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.prohibir_delete_fisico()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'DELETE físico prohibido sobre %.%. Usar baja lógica y auditoría.',
        TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = 'raise_exception',
              HINT = 'Anular el registro (estado = anulado) y registrar el motivo.';
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.prohibir_delete_fisico() IS
    'Invariante: nada se borra físicamente. Se aplica a todas las tablas con '
    'valor histórico o probatorio.';

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'movimientos', 'movimientos_auditoria', 'ingesta_raw',
        'transferencias', 'deudas_pendientes', 'deuda_pagos',
        'fiscal_propuestas', 'fx_rates'
    ]
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_no_delete ON praxia_finanzas.%I', t);
        EXECUTE format(
            'CREATE TRIGGER trg_no_delete BEFORE DELETE ON praxia_finanzas.%I '
            'FOR EACH STATEMENT EXECUTE FUNCTION praxia_finanzas.prohibir_delete_fisico()', t);
    END LOOP;
END;
$$;

-- =============================================================================
-- GUARD 2 · movimiento_estado_fiscal_derivado   (migración v4.7)
-- -----------------------------------------------------------------------------
-- INVARIANTE: estado_fiscal NO PUEDE DIVERGIR de ambito + deducible.
--
-- Antes de v4.7 eran tres campos independientes y bastaba con corregir el
-- ámbito y olvidarse del estado fiscal para tener un movimiento que decía dos
-- cosas distintas. La solución no fue "acordarse": fue derivar. Si un valor se
-- puede calcular, no se guarda como decisión independiente.
--
-- Además rechaza la combinación imposible: nada personal es deducible.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.movimiento_estado_fiscal_derivado()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.ambito = 'personal' AND NEW.deducible THEN
        RAISE EXCEPTION
            'Combinación imposible: ambito personal con deducible = true (movimiento %).',
            coalesce(NEW.id::text, 'nuevo')
            USING HINT = 'Si el gasto es deducible, su ámbito es profesional.';
    END IF;

    NEW.estado_fiscal :=
        CASE
            WHEN NEW.ambito = 'personal' THEN 'no_fiscal'
            WHEN NEW.deducible           THEN 'fiscal_deducible'
            ELSE                              'fiscal_no_deducible'
        END;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.movimiento_estado_fiscal_derivado() IS
    'Invariante v4.7: estado_fiscal se deriva de ambito + deducible. No se '
    'declara, se calcula. Elimina de raíz la desincronización entre los tres.';

DROP TRIGGER IF EXISTS trg_mov_estado_fiscal ON praxia_finanzas.movimientos;
CREATE TRIGGER trg_mov_estado_fiscal
    BEFORE INSERT OR UPDATE OF ambito, deducible, estado_fiscal
    ON praxia_finanzas.movimientos
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.movimiento_estado_fiscal_derivado();

-- =============================================================================
-- GUARD 3 · deuda_pago_validar   (migración v4.5)
-- -----------------------------------------------------------------------------
-- INVARIANTE: un pago se hace en la MISMA MONEDA que la deuda que cancela.
--
-- Mezclar monedas en la cancelación obliga a elegir una cotización, y elegir
-- una cotización dentro de un trigger es inventar un dato. La regla del
-- contrato es explícita: ninguna cotización se inventa. Si hay que pagar una
-- deuda en dólares con pesos, eso son dos operaciones —un cambio y un pago—
-- y hay que registrarlas como dos.
--
-- El guard valida además que el pago no exceda el saldo y que el movimiento
-- de respaldo, si existe, sea de la misma moneda.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.deuda_pago_validar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_deuda        praxia_finanzas.deudas_pendientes%ROWTYPE;
    v_mov_moneda   char(3);
    v_pagado_otros numeric(18,2);
BEGIN
    SELECT * INTO v_deuda
    FROM praxia_finanzas.deudas_pendientes
    WHERE id = NEW.deuda_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La deuda % no existe.', NEW.deuda_id;
    END IF;

    IF v_deuda.estado = 'anulada' THEN
        RAISE EXCEPTION 'No se puede pagar una deuda anulada (deuda %).', NEW.deuda_id;
    END IF;

    -- 1. Misma moneda que la deuda.
    IF NEW.moneda <> v_deuda.moneda THEN
        RAISE EXCEPTION
            'Moneda del pago (%) distinta de la moneda de la deuda (%).',
            NEW.moneda, v_deuda.moneda
            USING HINT = 'Registrar el cambio de moneda como una operación aparte.';
    END IF;

    -- 2. Misma moneda que el movimiento de respaldo, si lo hay.
    IF NEW.movimiento_id IS NOT NULL THEN
        SELECT m.moneda INTO v_mov_moneda
        FROM praxia_finanzas.movimientos m
        WHERE m.id = NEW.movimiento_id;

        IF v_mov_moneda IS NULL THEN
            RAISE EXCEPTION 'El movimiento de respaldo % no existe.', NEW.movimiento_id;
        END IF;

        IF v_mov_moneda <> NEW.moneda THEN
            RAISE EXCEPTION
                'El movimiento de respaldo está en % y el pago en %.',
                v_mov_moneda, NEW.moneda;
        END IF;
    END IF;

    -- 3. No pagar más de lo que se debe.
    SELECT coalesce(sum(p.monto), 0) INTO v_pagado_otros
    FROM praxia_finanzas.deuda_pagos p
    WHERE p.deuda_id = NEW.deuda_id
      AND NOT p.anulado
      AND (TG_OP = 'INSERT' OR p.id <> NEW.id);

    IF NOT NEW.anulado AND v_pagado_otros + NEW.monto > v_deuda.monto_original THEN
        RAISE EXCEPTION
            'El pago excede el saldo: ya pagado %, se intenta pagar %, deuda original %.',
            v_pagado_otros, NEW.monto, v_deuda.monto_original;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.deuda_pago_validar() IS
    'Invariante v4.5: un pago está en la misma moneda que su deuda y que su '
    'movimiento de respaldo, y nunca excede el saldo pendiente.';

DROP TRIGGER IF EXISTS trg_deuda_pago_validar ON praxia_finanzas.deuda_pagos;
CREATE TRIGGER trg_deuda_pago_validar
    BEFORE INSERT OR UPDATE ON praxia_finanzas.deuda_pagos
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.deuda_pago_validar();

-- =============================================================================
-- GUARD 4 · recalcular_saldo_deuda   (migración v4.5)
-- -----------------------------------------------------------------------------
-- INVARIANTE: el saldo de una deuda es una CONSECUENCIA de sus pagos, nunca un
-- valor escrito a mano.
--
-- Cualquier saldo que se pueda escribir directamente termina, tarde o
-- temprano, contradiciendo la suma de los pagos. Acá el saldo se recalcula
-- después de cada alta, corrección o anulación de pago, y el estado de la
-- deuda se deriva del saldo.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.recalcular_saldo_deuda()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_deuda_id bigint := coalesce(NEW.deuda_id, OLD.deuda_id);
    v_pagado   numeric(18,2);
    v_original numeric(18,2);
    v_saldo    numeric(18,2);
BEGIN
    SELECT d.monto_original INTO v_original
    FROM praxia_finanzas.deudas_pendientes d
    WHERE d.id = v_deuda_id;

    SELECT coalesce(sum(p.monto), 0) INTO v_pagado
    FROM praxia_finanzas.deuda_pagos p
    WHERE p.deuda_id = v_deuda_id
      AND NOT p.anulado;

    v_saldo := v_original - v_pagado;

    UPDATE praxia_finanzas.deudas_pendientes d
       SET saldo  = v_saldo,
           estado = CASE
                        WHEN d.estado = 'anulada' THEN 'anulada'
                        WHEN v_saldo = 0          THEN 'saldada'
                        WHEN v_pagado > 0         THEN 'parcial'
                        ELSE 'abierta'
                    END
     WHERE d.id = v_deuda_id;

    RETURN NULL;  -- trigger AFTER: el valor de retorno se ignora
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.recalcular_saldo_deuda() IS
    'Invariante v4.5: saldo = monto_original - suma de pagos no anulados. El '
    'estado de la deuda se deriva del saldo. Nadie escribe el saldo a mano.';

DROP TRIGGER IF EXISTS trg_recalcular_saldo_deuda ON praxia_finanzas.deuda_pagos;
CREATE TRIGGER trg_recalcular_saldo_deuda
    AFTER INSERT OR UPDATE ON praxia_finanzas.deuda_pagos
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.recalcular_saldo_deuda();

-- -----------------------------------------------------------------------------
-- GUARD 4-bis · movimiento_respaldo_deuda_guard
-- -----------------------------------------------------------------------------
-- INVARIANTE: "un pago se contabiliza exactamente una vez". Un mismo
-- movimiento no puede respaldar dos pagos vigentes. Se implementa como índice
-- único parcial: más barato y más difícil de esquivar que un trigger.

CREATE UNIQUE INDEX IF NOT EXISTS movimiento_respaldo_deuda_guard
    ON praxia_finanzas.deuda_pagos (movimiento_id)
    WHERE movimiento_id IS NOT NULL AND NOT anulado;

COMMENT ON INDEX praxia_finanzas.movimiento_respaldo_deuda_guard IS
    'Invariante: un movimiento respalda a lo sumo un pago vigente. Es lo que '
    'impide que la misma transferencia cancele dos deudas.';

-- =============================================================================
-- GUARD 5 · propuesta_nace_pendiente   (migración v4.8)
-- -----------------------------------------------------------------------------
-- INVARIANTE: ninguna propuesta del agente nace aprobada.
--
-- Sin este guard, el camino más corto para que un agente apruebe sus propias
-- propuestas es insertarlas ya aprobadas. No hace falta mala intención: basta
-- un cliente que rellene el campo por defecto.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.propuesta_nace_pendiente()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado IS DISTINCT FROM 'pendiente' THEN
        RAISE EXCEPTION
            'Una propuesta fiscal nace pendiente; se intentó crear con estado "%".',
            NEW.estado
            USING HINT = 'La decisión se registra después, por POST /api/fiscal-propuestas/decidir.';
    END IF;

    NEW.decidida_at  := NULL;
    NEW.decidida_por := NULL;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.propuesta_nace_pendiente() IS
    'Invariante v4.8: toda propuesta se crea en estado pendiente y sin datos '
    'de decisión. El agente propone; no decide.';

DROP TRIGGER IF EXISTS trg_propuesta_nace_pendiente ON praxia_finanzas.fiscal_propuestas;
CREATE TRIGGER trg_propuesta_nace_pendiente
    BEFORE INSERT ON praxia_finanzas.fiscal_propuestas
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.propuesta_nace_pendiente();

-- =============================================================================
-- GUARD 6 · propuesta_contenido_inmutable   (migración v4.8)
-- -----------------------------------------------------------------------------
-- INVARIANTE: lo que se aprueba es exactamente lo que se propuso.
--
-- Si el contenido pudiera editarse después de creado, la aprobación humana no
-- probaría nada: alguien aprueba A y lo que queda registrado es B. Cambiar la
-- propuesta obliga a crear una propuesta nueva, con su propia huella.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.propuesta_contenido_inmutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.movimiento_id    IS DISTINCT FROM OLD.movimiento_id
    OR NEW.contenido        IS DISTINCT FROM OLD.contenido
    OR NEW.motivo           IS DISTINCT FROM OLD.motivo
    OR NEW.huella           IS DISTINCT FROM OLD.huella
    OR NEW.huella_evidencia IS DISTINCT FROM OLD.huella_evidencia
    OR NEW.created_at       IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'El contenido de la propuesta % es inmutable. Sólo puede cambiar su estado.',
            OLD.id
            USING HINT = 'Crear una propuesta nueva en vez de editar esta.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.propuesta_contenido_inmutable() IS
    'Invariante v4.8: una propuesta creada no se edita. Sólo su estado cambia. '
    'Es lo que hace que la aprobación humana signifique algo.';

DROP TRIGGER IF EXISTS trg_propuesta_inmutable ON praxia_finanzas.fiscal_propuestas;
CREATE TRIGGER trg_propuesta_inmutable
    BEFORE UPDATE ON praxia_finanzas.fiscal_propuestas
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.propuesta_contenido_inmutable();

-- =============================================================================
-- GUARD 7 · propuesta_transicion_valida   (migración v4.8)
-- -----------------------------------------------------------------------------
-- INVARIANTE: los estados siguen su máquina, sin atajos y sin vuelta atrás.
--
--   pendiente → aprobada | rechazada | caducada
--   aprobada  → (terminal)
--   rechazada → (terminal)
--   caducada  → (terminal)
--
-- Un estado terminal que se puede reabrir no es terminal. "Des-aprobar" una
-- propuesta borraría la evidencia de que alguien la aprobó.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.propuesta_transicion_valida()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado <> 'pendiente' THEN
        RAISE EXCEPTION
            'Transición inválida: % -> %. Los estados decididos son terminales.',
            OLD.estado, NEW.estado;
    END IF;

    IF NEW.estado NOT IN ('aprobada','rechazada','caducada') THEN
        RAISE EXCEPTION 'Estado destino desconocido: %.', NEW.estado;
    END IF;

    -- Una decisión humana necesita fecha y firma. La caducidad, no: la produce
    -- el sistema cuando cambia la evidencia.
    IF NEW.estado IN ('aprobada','rechazada') THEN
        IF NEW.decidida_por IS NULL OR btrim(NEW.decidida_por) = '' THEN
            RAISE EXCEPTION 'Falta decidida_por: una decisión sin responsable no se registra.';
        END IF;
        NEW.decidida_at := coalesce(NEW.decidida_at, now());
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.propuesta_transicion_valida() IS
    'Invariante v4.8: sólo se decide una propuesta pendiente, la decisión es '
    'terminal y toda aprobación o rechazo lleva responsable y fecha.';

DROP TRIGGER IF EXISTS trg_propuesta_transicion ON praxia_finanzas.fiscal_propuestas;
CREATE TRIGGER trg_propuesta_transicion
    BEFORE UPDATE OF estado ON praxia_finanzas.fiscal_propuestas
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.propuesta_transicion_valida();

COMMIT;

-- =============================================================================
-- Pruebas manuales sugeridas (todas deben FALLAR salvo la primera).
-- Valores sintéticos.
--
--   -- Debe pasar:
--   INSERT INTO praxia_finanzas.deudas_pendientes
--       (descripcion, monto_original, moneda, saldo, perfil_id)
--   VALUES ('Deuda de ejemplo', 1000.00, 'USD', 1000.00, 1);
--
--   -- Debe fallar: moneda distinta
--   INSERT INTO praxia_finanzas.deuda_pagos (deuda_id, monto, moneda)
--   VALUES (1, 100.00, 'ARS');
--
--   -- Debe fallar: personal y deducible a la vez
--   UPDATE praxia_finanzas.movimientos SET ambito='personal', deducible=true WHERE id=1;
--
--   -- Debe fallar: borrado físico
--   DELETE FROM praxia_finanzas.movimientos WHERE id = 1;
-- =============================================================================
