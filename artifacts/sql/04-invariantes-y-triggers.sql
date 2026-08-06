-- =============================================================================
--  PraxIA Ops · artifacts/sql/04-invariantes-y-triggers.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Las invariantes del NÚCLEO FINANCIERO escritas como código ejecutable:
--  borrado lógico, pagos de deuda, recálculo de saldos y respaldo único de un
--  movimiento. Los nombres y las invariantes son fieles al diseño verificado
--  (v4.3 y v4.5); la implementación fue escrita de nuevo para este repositorio.
--
--  La idea central: las reglas de negocio que no pueden violarse NUNCA viven
--  en la base, no en el prompt del agente ni en el cliente. Un prompt se
--  rodea con una reformulación; un trigger, no.
--
--  Este archivo crea también las tablas mínimas de deuda (v4.3/v4.5) porque
--  sin ellas los guards no se pueden ejecutar.
--
--  Las invariantes FISCALES viven en otros dos archivos, cada una con un solo
--  dueño: el 08 para el cierre y el estado derivado, el 09 para las propuestas.
--
--  Motor:   PostgreSQL 16
--  Requiere: 03-esquema-finanzas-nucleo.sql
--  Corte:   2026-08-06
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
-- 1. Tablas de deuda (mínimas, para que los guards corran)
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
--
-- La función es genérica a propósito: los archivos 07 y 09 la reutilizan para
-- las tablas fiscales que también son evidencia.
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
        'fx_rates'
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
-- GUARD 2 · deuda_pago_validar   (migración v4.5)
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
-- GUARD 3 · recalcular_saldo_deuda   (migración v4.5)
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

-- =============================================================================
-- GUARD 4 · movimiento_respaldo_deuda_guard
-- -----------------------------------------------------------------------------
-- INVARIANTE: "un pago se contabiliza exactamente una vez". Un mismo
-- movimiento no puede respaldar dos pagos vigentes. Se implementa como índice
-- único parcial: más barato y más difícil de esquivar que un trigger.
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS movimiento_respaldo_deuda_guard
    ON praxia_finanzas.deuda_pagos (movimiento_id)
    WHERE movimiento_id IS NOT NULL AND NOT anulado;

COMMENT ON INDEX praxia_finanzas.movimiento_respaldo_deuda_guard IS
    'Invariante: un movimiento respalda a lo sumo un pago vigente. Es lo que '
    'impide que la misma transferencia cancele dos deudas.';

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
--   -- Debe fallar: el pago excede el saldo
--   INSERT INTO praxia_finanzas.deuda_pagos (deuda_id, monto, moneda)
--   VALUES (1, 5000.00, 'USD');
--
--   -- Debe fallar: borrado físico
--   DELETE FROM praxia_finanzas.movimientos WHERE id = 1;
-- =============================================================================

-- =============================================================================
-- Dónde están las invariantes FISCALES
--
-- Este archivo cubre el núcleo financiero y nada más. Cada invariante fiscal
-- tiene un único dueño, y ninguno pisa lo que crea otro:
--
--   · 07-nucleo-fiscal.sql            — `fiscal_auditoria_inmutable()` (auditoría
--                                        append-only), `completar_periodo_fiscal()`
--                                        y `completar_periodo_comprobante()`.
--   · 08-cierre-y-estado-derivado.sql — `movimiento_estado_fiscal_derivado()`
--                                        y `cierre_transicion_valida()`.
--   · 09-propuestas-fiscales.sql      — `propuesta_nace_pendiente()`,
--                                        `propuesta_contenido_inmutable()` y
--                                        `propuesta_transicion_valida()`.
--
-- La regla que se sigue en toda la serie: una tabla, una invariante y un
-- archivo que la crea. Un archivo que tenga que destruir lo que hizo otro para
-- hacer su trabajo es una señal de que el reparto está mal hecho.
-- =============================================================================
