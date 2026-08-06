-- =============================================================================
--  PraxIA Ops · artifacts/sql/05-vistas-de-lectura.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Vistas de lectura de `praxia_finanzas`, escritas de nuevo. Los nombres son
--  los del diseño verificado; el cuerpo es una reconstrucción razonable.
--
--  Criterio de diseño que atraviesa todas: la conversión de moneda se hace con
--  CROSS JOIN LATERAL contra fx_vigente(). Si no hay cotización, la fila NO
--  APARECE. Un LEFT JOIN habría producido NULL, y un coalesce(...,0) aguas
--  abajo habría convertido "no sé" en "cero". Ausencia de dato es ausencia de
--  fila, nunca un cero.
--
--  Motor:   PostgreSQL 16
--  Requiere: 01 (praxia.normalizar), 03 y 04
--  Corte:   2026-08-05
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. v_saldos_por_moneda
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_saldos_por_moneda AS
SELECT
    p.codigo                     AS perfil,
    c.moneda                     AS moneda,
    sum(m.monto)::numeric(18,2)  AS saldo,
    count(*)                     AS movimientos
FROM praxia_finanzas.movimientos m
JOIN praxia_finanzas.cuentas  c ON c.id = m.cuenta_id
JOIN praxia_finanzas.perfiles p ON p.id = m.perfil_id
WHERE m.estado = 'confirmado'      -- lo pendiente no es saldo
GROUP BY p.codigo, c.moneda;

COMMENT ON VIEW praxia_finanzas.v_saldos_por_moneda IS
    'Saldo por perfil y moneda, contando SÓLO movimientos confirmados. Es la '
    'vista de "cuánto tengo": un pendiente todavía no es plata.';

-- -----------------------------------------------------------------------------
-- 2. v_patrimonio_usd
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_patrimonio_usd AS
WITH por_moneda AS (
    SELECT moneda, sum(saldo)::numeric(18,2) AS saldo
    FROM praxia_finanzas.v_saldos_por_moneda
    GROUP BY moneda
)
SELECT
    pm.moneda,
    pm.saldo,
    fx.tasa,
    fx.fecha_cotizacion,
    fx.fuente,
    round(pm.saldo * fx.tasa, 2) AS saldo_usd
FROM por_moneda pm
-- CROSS JOIN, no LEFT JOIN: sin cotización no hay fila. Es deliberado.
CROSS JOIN LATERAL (
    SELECT 1::numeric AS tasa, current_date AS fecha_cotizacion, 'paridad'::text AS fuente
    WHERE pm.moneda = 'USD'
    UNION ALL
    SELECT f.tasa, f.fecha_cotizacion, f.fuente
    FROM praxia_finanzas.fx_vigente(pm.moneda, 'USD'::char(3), current_date) f
    WHERE pm.moneda <> 'USD'
) fx;

COMMENT ON VIEW praxia_finanzas.v_patrimonio_usd IS
    'Patrimonio expresado en dólares, por moneda de origen. Si falta la '
    'cotización de una moneda, esa moneda NO aparece: es preferible un total '
    'incompleto y visible a un total completo e inventado.';

-- -----------------------------------------------------------------------------
-- 3. v_gasto_mensual_usd
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_gasto_mensual_usd AS
SELECT
    date_trunc('month', m.fecha)::date        AS periodo,
    p.codigo                                  AS perfil,
    sum(round(abs(m.monto) * fx.tasa, 2))::numeric(18,2) AS gasto_usd,
    count(*)                                  AS movimientos
FROM praxia_finanzas.movimientos m
JOIN praxia_finanzas.perfiles p ON p.id = m.perfil_id
-- La cotización se toma a la FECHA DEL MOVIMIENTO, no a la de hoy. Un gasto de
-- marzo valuado con la cotización de agosto es un número que no significa nada.
CROSS JOIN LATERAL (
    SELECT 1::numeric AS tasa WHERE m.moneda = 'USD'
    UNION ALL
    SELECT f.tasa
    FROM praxia_finanzas.fx_vigente(m.moneda, 'USD'::char(3), m.fecha) f
    WHERE m.moneda <> 'USD'
) fx
WHERE m.estado = 'confirmado'
  AND m.tipo   = 'gasto'
  AND m.transfer_id IS NULL          -- una transferencia NO es un gasto
GROUP BY 1, 2;

COMMENT ON VIEW praxia_finanzas.v_gasto_mensual_usd IS
    'Gasto mensual en dólares por perfil, valuado a la cotización vigente a la '
    'fecha de cada movimiento. Excluye transferencias: mover plata de una '
    'cuenta propia a otra no es gastar.';

-- -----------------------------------------------------------------------------
-- 4. v_pendientes_completables
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_pendientes_completables AS
SELECT
    m.id,
    m.fecha,
    m.descripcion,
    m.monto,
    m.moneda,
    c.codigo   AS cuenta,
    cat.codigo AS categoria,
    p.codigo   AS perfil,
    m.created_at
FROM praxia_finanzas.movimientos m
JOIN praxia_finanzas.cuentas    c   ON c.id   = m.cuenta_id
JOIN praxia_finanzas.perfiles   p   ON p.id   = m.perfil_id
JOIN praxia_finanzas.categorias cat ON cat.id = m.categoria_id
WHERE m.estado = 'pendiente'
  AND m.tipo  <> 'transferencia'
  AND length(btrim(m.descripcion)) >= 3
  AND m.fecha <= current_date;

COMMENT ON VIEW praxia_finanzas.v_pendientes_completables IS
    'Pendientes que tienen todo lo necesario para confirmarse de una: cuenta, '
    'categoría, perfil, descripción y fecha no futura. Es la cola de trabajo '
    'de un minuto por día.';

-- -----------------------------------------------------------------------------
-- 5. v_requiere_revision
-- -----------------------------------------------------------------------------
-- Un movimiento puede aparecer varias veces, una por cada motivo. Es a
-- propósito: si algo tiene dos problemas, hay que ver los dos.

CREATE OR REPLACE VIEW praxia_finanzas.v_requiere_revision AS
    -- Falta clasificar
    SELECT m.id, m.fecha, m.descripcion, m.monto, m.moneda,
           'sin_categoria'::text AS motivo
    FROM praxia_finanzas.movimientos m
    WHERE m.estado = 'pendiente'
      AND m.tipo  <> 'transferencia'
      AND m.categoria_id IS NULL

UNION ALL
    -- Fecha futura: casi siempre es un error de tipeo o de parseo
    SELECT m.id, m.fecha, m.descripcion, m.monto, m.moneda,
           'fecha_futura'::text
    FROM praxia_finanzas.movimientos m
    WHERE m.estado <> 'anulado'
      AND m.fecha > current_date

UNION ALL
    -- Transferencia con una sola pata viva: la plata sale y no entra
    SELECT m.id, m.fecha, m.descripcion, m.monto, m.moneda,
           'transferencia_incompleta'::text
    FROM praxia_finanzas.movimientos m
    WHERE m.transfer_id IS NOT NULL
      AND m.estado <> 'anulado'
      AND (SELECT count(*)
             FROM praxia_finanzas.movimientos m2
            WHERE m2.transfer_id = m.transfer_id
              AND m2.estado <> 'anulado') <> 2

UNION ALL
    -- Confirmado en moneda extranjera sin cotización aplicable: no se puede
    -- valuar, y no se va a inventar una tasa para taparlo
    SELECT m.id, m.fecha, m.descripcion, m.monto, m.moneda,
           'sin_cotizacion'::text
    FROM praxia_finanzas.movimientos m
    WHERE m.estado = 'confirmado'
      AND m.moneda <> 'USD'
      AND NOT EXISTS (
            SELECT 1 FROM praxia_finanzas.fx_vigente(m.moneda, 'USD'::char(3), m.fecha))

UNION ALL
    -- Posible duplicado: misma cuenta, misma fecha, mismo monto y descripción
    -- equivalente una vez normalizada
    SELECT m.id, m.fecha, m.descripcion, m.monto, m.moneda,
           'posible_duplicado'::text
    FROM praxia_finanzas.movimientos m
    WHERE m.estado <> 'anulado'
      AND EXISTS (
            SELECT 1
            FROM praxia_finanzas.movimientos d
            WHERE d.id        <> m.id
              AND d.estado    <> 'anulado'
              AND d.cuenta_id  = m.cuenta_id
              AND d.fecha      = m.fecha
              AND d.monto      = m.monto
              AND praxia.normalizar(d.descripcion) = praxia.normalizar(m.descripcion));

COMMENT ON VIEW praxia_finanzas.v_requiere_revision IS
    'Movimientos que un humano tiene que mirar, con el motivo explícito. Un '
    'movimiento puede salir varias veces, una por motivo. Es la vista que '
    'convierte "algo anda mal" en una lista accionable.';

-- -----------------------------------------------------------------------------
-- 6. v_deuda_resumen
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_deuda_resumen AS
SELECT
    p.codigo                              AS perfil,
    d.moneda,
    d.estado,
    count(*)                              AS cantidad,
    sum(d.monto_original)::numeric(18,2)  AS total_original,
    sum(d.saldo)::numeric(18,2)           AS total_saldo,
    min(d.vencimiento)                    AS proximo_vencimiento
FROM praxia_finanzas.deudas_pendientes d
JOIN praxia_finanzas.perfiles p ON p.id = d.perfil_id
WHERE d.estado <> 'anulada'
GROUP BY p.codigo, d.moneda, d.estado;

COMMENT ON VIEW praxia_finanzas.v_deuda_resumen IS
    'Cuánto se debe, en qué moneda y para cuándo, agrupado por perfil y estado. '
    'No se convierte a una moneda única a propósito: sumar deudas en monedas '
    'distintas exige una cotización, y esa decisión la toma quien consulta.';

COMMIT;

-- =============================================================================
-- Nota sobre rendimiento
--
-- Son vistas, no vistas materializadas. Con el volumen documentado (un sistema
-- chico en datos y denso en reglas) alcanza y sobra, y evita el problema de
-- toda vista materializada: quedar desactualizada sin que nadie se entere.
-- El disparador para materializar sería que el dashboard tarde en abrir, no
-- que la consulta "se vea pesada".
-- =============================================================================
