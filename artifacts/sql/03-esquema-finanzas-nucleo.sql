-- =============================================================================
--  PraxIA Ops · artifacts/sql/03-esquema-finanzas-nucleo.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Núcleo del esquema `praxia_finanzas` escrito de nuevo a partir del diseño
--  verificado. Los nombres de tablas, columnas, estados y la semántica de
--  fx_vigente(), ingesta_raw e idempotency_key son fieles al diseño real. El
--  esquema de producción está en v4.8 y tiene 35 tablas; acá hay nueve
--  objetos, elegidos para que se entienda el modelo. Sin datos reales.
--
--  Motor:   PostgreSQL 16
--  Requiere: nada de los archivos anteriores (esquema independiente)
--  Orden:   ejecutar antes de 04, 05 y 06
--  Corte:   2026-08-05
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS praxia_finanzas;

COMMENT ON SCHEMA praxia_finanzas IS
    'Única fuente de verdad financiera y fiscal. Convive con el esquema praxia '
    '(memoria) en la misma base. No existen sistemas paralelos.';

-- -----------------------------------------------------------------------------
-- 1. perfiles — separación contable
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.perfiles (
    id         smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo     text        NOT NULL UNIQUE CHECK (codigo = upper(codigo)),
    nombre     text        NOT NULL,
    tipo       text        NOT NULL CHECK (tipo IN ('personal','profesional','proyecto')),
    activo     boolean     NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE praxia_finanzas.perfiles IS
    'Separación contable de primer nivel: personal, profesional y proyectos. '
    'Todo movimiento pertenece a exactamente un perfil. Es lo que permite '
    'responder "cuánto gasté" sin mezclar lo de casa con lo del consultorio.';

-- Datos sintéticos de ejemplo.
INSERT INTO praxia_finanzas.perfiles (codigo, nombre, tipo) VALUES
    ('PERFIL_PERSONAL',     'Perfil personal (ejemplo)',     'personal'),
    ('PERFIL_PROFESIONAL',  'Perfil profesional (ejemplo)',  'profesional'),
    ('PROYECTO_DEMO',       'Proyecto de demostración',      'proyecto')
ON CONFLICT (codigo) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. cuentas
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.cuentas (
    id         integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo     text        NOT NULL UNIQUE,
    nombre     text        NOT NULL,
    tipo       text        NOT NULL CHECK (tipo IN ('efectivo','banco','billetera',
                                                    'tarjeta','inversion')),
    -- Una cuenta tiene UNA moneda. Las cuentas multimoneda se modelan como
    -- varias cuentas. Simplifica todo lo que viene después.
    moneda     char(3)     NOT NULL CHECK (moneda ~ '^[A-Z]{3}$'),
    perfil_id  smallint    NOT NULL REFERENCES praxia_finanzas.perfiles(id),
    activo     boolean     NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE praxia_finanzas.cuentas IS
    'Cuentas bancarias, efectivo, billeteras, tarjetas e inversiones. Una '
    'moneda por cuenta: una cuenta multimoneda se modela como varias cuentas.';

CREATE INDEX IF NOT EXISTS cuentas_perfil_idx
    ON praxia_finanzas.cuentas (perfil_id) WHERE activo;

INSERT INTO praxia_finanzas.cuentas (codigo, nombre, tipo, moneda, perfil_id)
SELECT v.codigo, v.nombre, v.tipo, v.moneda, p.id
FROM (VALUES
        ('CAJA_ARS',   'Efectivo en pesos (ejemplo)',   'efectivo', 'ARS', 'PERFIL_PERSONAL'),
        ('BANCO_ARS',  'Cuenta bancaria (ejemplo)',     'banco',    'ARS', 'PERFIL_PERSONAL'),
        ('CAJA_USD',   'Efectivo en dólares (ejemplo)', 'efectivo', 'USD', 'PERFIL_PERSONAL'),
        ('PROF_ARS',   'Cuenta profesional (ejemplo)',  'banco',    'ARS', 'PERFIL_PROFESIONAL')
     ) AS v(codigo, nombre, tipo, moneda, perfil_codigo)
JOIN praxia_finanzas.perfiles p ON p.codigo = v.perfil_codigo
ON CONFLICT (codigo) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. categorias
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.categorias (
    id                integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo            text        NOT NULL UNIQUE,
    nombre            text        NOT NULL,
    tipo              text        NOT NULL CHECK (tipo IN ('ingreso','gasto','ajuste')),
    parent_id         integer     REFERENCES praxia_finanzas.categorias(id),
    -- Sugerencia, no verdad: el ámbito fiscal se decide por movimiento.
    deducible_default boolean     NOT NULL DEFAULT false,
    activo            boolean     NOT NULL DEFAULT true,
    created_at        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT categorias_no_es_su_propio_padre CHECK (parent_id IS NULL OR parent_id <> id)
);

COMMENT ON TABLE praxia_finanzas.categorias IS
    'Taxonomía de ingresos y gastos, con jerarquía opcional. '
    'deducible_default es una sugerencia para la clasificación fiscal, nunca '
    'una decisión: la decisión se toma por movimiento y queda auditada.';

INSERT INTO praxia_finanzas.categorias (codigo, nombre, tipo, deducible_default) VALUES
    ('SUELDO',      'Ingresos por trabajo (ejemplo)', 'ingreso', false),
    ('HONORARIOS',  'Honorarios (ejemplo)',           'ingreso', false),
    ('SUPERMERCADO','Supermercado (ejemplo)',         'gasto',   false),
    ('INSUMOS',     'Insumos profesionales (ejemplo)','gasto',   true),
    ('SERVICIOS',   'Servicios (ejemplo)',            'gasto',   false),
    ('AJUSTE',      'Ajuste de saldo (ejemplo)',      'ajuste',  false)
ON CONFLICT (codigo) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. fx_rates + fx_vigente()
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.fx_rates (
    id              bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    moneda_origen   char(3)      NOT NULL CHECK (moneda_origen ~ '^[A-Z]{3}$'),
    moneda_destino  char(3)      NOT NULL DEFAULT 'USD' CHECK (moneda_destino ~ '^[A-Z]{3}$'),
    fecha           date         NOT NULL,
    tasa            numeric(20,8) NOT NULL CHECK (tasa > 0),
    fuente          text         NOT NULL,
    created_at      timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT fx_par_distinto CHECK (moneda_origen <> moneda_destino),
    CONSTRAINT fx_unico UNIQUE (moneda_origen, moneda_destino, fecha, fuente)
);

COMMENT ON TABLE praxia_finanzas.fx_rates IS
    'Cotizaciones con fecha y fuente. Regla del contrato: "Ninguna cotización '
    'se inventa. Ausencia de dato es ausencia de fila, nunca un cero."';

CREATE INDEX IF NOT EXISTS fx_rates_busqueda_idx
    ON praxia_finanzas.fx_rates (moneda_origen, moneda_destino, fecha DESC);

-- Cotizaciones sintéticas de ejemplo (valores inventados).
INSERT INTO praxia_finanzas.fx_rates (moneda_origen, moneda_destino, fecha, tasa, fuente) VALUES
    ('ARS', 'USD', DATE '2026-07-01', 0.00080000, 'FUENTE_DEMO'),
    ('ARS', 'USD', DATE '2026-08-01', 0.00075000, 'FUENTE_DEMO')
ON CONFLICT ON CONSTRAINT fx_unico DO NOTHING;

-- La función devuelve FILAS, no un número. Es la traducción literal de la
-- regla: si no hay cotización aplicable, devuelve cero filas y el que llama
-- tiene que decidir qué hacer. Si devolviera numeric, la tentación de que un
-- NULL se convierta en 0 aguas abajo sería cuestión de tiempo.
CREATE OR REPLACE FUNCTION praxia_finanzas.fx_vigente(
    p_origen  char(3),
    p_destino char(3),
    p_fecha   date
)
RETURNS TABLE (tasa numeric, fecha_cotizacion date, fuente text)
LANGUAGE sql
STABLE
AS $$
    SELECT r.tasa, r.fecha, r.fuente
    FROM praxia_finanzas.fx_rates r
    WHERE r.moneda_origen  = p_origen
      AND r.moneda_destino = p_destino
      AND r.fecha         <= p_fecha
    ORDER BY r.fecha DESC, r.id DESC
    LIMIT 1;
$$;

COMMENT ON FUNCTION praxia_finanzas.fx_vigente(char, char, date) IS
    'Cotización vigente a una fecha (la última con fecha <= p_fecha). Devuelve '
    'cero filas si no hay dato: ausencia de cotización es ausencia de fila, '
    'nunca un cero.';

-- -----------------------------------------------------------------------------
-- 5. ingesta_raw — la única puerta de entrada
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.ingesta_raw (
    id                 bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    canal              text        NOT NULL
                                   CHECK (canal IN ('telegram','dashboard','pdf',
                                                    'csv','excel','email','agente')),
    actor              text        NOT NULL,

    -- Idempotencia: la misma entrada reenviada no produce un segundo
    -- movimiento. Es lo que hace que un reintento de red, un doble tap en el
    -- dashboard o un agente que repite la llamada sean inofensivos.
    idempotency_key    text        NOT NULL,

    -- El texto original se guarda CIFRADO del lado del servidor. Acá se
    -- representa como bytea sin especificar el mecanismo.
    contenido_cifrado  bytea       NOT NULL,
    contenido_hash     text        NOT NULL,

    -- El contrato universal ya normalizado, como jsonb.
    contrato           jsonb       NOT NULL DEFAULT '{}'::jsonb,

    recibido_at        timestamptz NOT NULL DEFAULT now(),
    procesado_at       timestamptz,
    resultado          text        NOT NULL DEFAULT 'pendiente'
                                   CHECK (resultado IN ('pendiente','procesado',
                                                        'duplicado','rechazado')),

    CONSTRAINT ingesta_idempotency_uniq UNIQUE (idempotency_key),
    CONSTRAINT ingesta_contrato_es_objeto CHECK (jsonb_typeof(contrato) = 'object')
);

COMMENT ON TABLE praxia_finanzas.ingesta_raw IS
    'Toda entrada al sistema, venga de Telegram, dashboard, PDF, CSV, email o '
    'un agente, deja una fila acá antes de convertirse en movimiento. Es el '
    'único camino de alta (POST /api/ingesta) y, por lo tanto, el único lugar '
    'donde validar, deduplicar y auditar la entrada.';

COMMENT ON COLUMN praxia_finanzas.ingesta_raw.idempotency_key IS
    'Clave única provista por el canal. Reenviar la misma clave devuelve el '
    'movimiento existente en vez de crear uno nuevo.';
COMMENT ON COLUMN praxia_finanzas.ingesta_raw.contenido_cifrado IS
    'Texto original cifrado server-side. Se conserva para poder reprocesar sin '
    'volver a pedirle nada al usuario.';
COMMENT ON COLUMN praxia_finanzas.ingesta_raw.contrato IS
    'El contrato universal normalizado: monto, moneda, fecha, descripción, '
    'cuenta, categoría y perfil. Mismo formato para los siete canales.';

CREATE INDEX IF NOT EXISTS ingesta_raw_pendientes_idx
    ON praxia_finanzas.ingesta_raw (recibido_at DESC)
    WHERE resultado = 'pendiente';

-- -----------------------------------------------------------------------------
-- 6. movimientos
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.movimientos (
    id            bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    fecha         date         NOT NULL,
    descripcion   text         NOT NULL CHECK (length(btrim(descripcion)) >= 2),

    -- Signo con significado: negativo es salida, positivo es entrada.
    -- Cero no es un movimiento.
    monto         numeric(18,2) NOT NULL CHECK (monto <> 0),
    moneda        char(3)      NOT NULL CHECK (moneda ~ '^[A-Z]{3}$'),

    cuenta_id     integer      NOT NULL REFERENCES praxia_finanzas.cuentas(id),
    categoria_id  integer      REFERENCES praxia_finanzas.categorias(id),
    perfil_id     smallint     NOT NULL REFERENCES praxia_finanzas.perfiles(id),
    proyecto      text,

    tipo          text         NOT NULL
                               CHECK (tipo IN ('ingreso','gasto','transferencia','ajuste')),

    -- Todo movimiento NACE pendiente. Confirmar es un acto explícito.
    estado        text         NOT NULL DEFAULT 'pendiente'
                               CHECK (estado IN ('pendiente','confirmado','anulado')),

    ambito        text         NOT NULL DEFAULT 'personal'
                               CHECK (ambito IN ('personal','profesional')),
    deducible     boolean      NOT NULL DEFAULT false,

    -- Derivado por trigger a partir de ambito + deducible (v4.7).
    -- No se escribe a mano: ver 04-invariantes-y-triggers.sql
    estado_fiscal text         NOT NULL DEFAULT 'no_fiscal'
                               CHECK (estado_fiscal IN ('no_fiscal',
                                                        'fiscal_no_deducible',
                                                        'fiscal_deducible')),

    -- Las dos patas de una transferencia comparten transfer_id.
    transfer_id   uuid,

    ingesta_id    bigint       REFERENCES praxia_finanzas.ingesta_raw(id),

    confirmado_at timestamptz,
    anulado_at    timestamptz,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT mov_anulado_con_fecha
        CHECK (estado <> 'anulado' OR anulado_at IS NOT NULL),
    CONSTRAINT mov_transferencia_con_id
        CHECK (tipo <> 'transferencia' OR transfer_id IS NOT NULL),
    -- Una transferencia no es un gasto: no lleva categoría de gasto.
    CONSTRAINT mov_transferencia_sin_categoria
        CHECK (tipo <> 'transferencia' OR categoria_id IS NULL)
);

COMMENT ON TABLE praxia_finanzas.movimientos IS
    'La tabla central. Todo movimiento nace pendiente y se confirma por un acto '
    'explícito y auditado. Nada se borra: se anula con baja lógica. Las '
    'transferencias llevan transfer_id y no cuentan como gasto.';

COMMENT ON COLUMN praxia_finanzas.movimientos.estado IS
    'pendiente -> confirmado -> (anulado). Nace pendiente siempre, venga de '
    'donde venga, incluso si lo cargó un agente.';
COMMENT ON COLUMN praxia_finanzas.movimientos.estado_fiscal IS
    'DERIVADO de ambito + deducible por trigger. No escribir a mano: si se '
    'escribe en contradicción, el trigger lo corrige o lo rechaza.';
COMMENT ON COLUMN praxia_finanzas.movimientos.transfer_id IS
    'Une las dos patas de una transferencia. Una sola pata es una transferencia '
    'inválida y aparece en la vista de revisión.';
COMMENT ON COLUMN praxia_finanzas.movimientos.ingesta_id IS
    'Trazabilidad hasta la entrada original, con su canal y su actor.';

CREATE INDEX IF NOT EXISTS movimientos_fecha_idx
    ON praxia_finanzas.movimientos (fecha DESC);
CREATE INDEX IF NOT EXISTS movimientos_estado_idx
    ON praxia_finanzas.movimientos (estado, fecha DESC);
CREATE INDEX IF NOT EXISTS movimientos_cuenta_idx
    ON praxia_finanzas.movimientos (cuenta_id, fecha DESC);
CREATE INDEX IF NOT EXISTS movimientos_transfer_idx
    ON praxia_finanzas.movimientos (transfer_id)
    WHERE transfer_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 7. transferencias — las dos patas
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.transferencias (
    id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transfer_id   uuid        NOT NULL DEFAULT gen_random_uuid(),
    movimiento_id bigint      NOT NULL REFERENCES praxia_finanzas.movimientos(id),
    pata          text        NOT NULL CHECK (pata IN ('origen','destino')),
    created_at    timestamptz NOT NULL DEFAULT now(),

    -- Exactamente una pata origen y una destino por transferencia.
    CONSTRAINT transferencias_pata_uniq UNIQUE (transfer_id, pata),
    -- Un movimiento participa de a lo sumo una transferencia.
    CONSTRAINT transferencias_movimiento_uniq UNIQUE (movimiento_id)
);

COMMENT ON TABLE praxia_finanzas.transferencias IS
    'Una transferencia son dos movimientos unidos por transfer_id: salida en '
    'una cuenta y entrada en otra. No es un gasto y no debe aparecer en los '
    'reportes de gasto. La restricción UNIQUE (transfer_id, pata) es lo que '
    'impide una transferencia con dos orígenes.';

-- -----------------------------------------------------------------------------
-- 8. movimientos_auditoria
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.movimientos_auditoria (
    id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    movimiento_id bigint      NOT NULL REFERENCES praxia_finanzas.movimientos(id),
    operacion     text        NOT NULL
                              CHECK (operacion IN ('alta','correccion','confirmacion',
                                                   'anulacion','reclasificacion')),
    actor         text        NOT NULL,
    origen        text        NOT NULL DEFAULT 'api'
                              CHECK (origen IN ('api','dashboard','telegram','mcp','migracion')),
    datos_antes   jsonb,
    datos_despues jsonb,
    motivo        text,
    registrado_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE praxia_finanzas.movimientos_auditoria IS
    'Historia de cada movimiento: quién lo cambió, desde dónde, qué había antes '
    'y qué quedó después. Es la contraparte obligatoria de la baja lógica: si '
    'no se borra, tiene que poder explicarse por qué está como está.';

COMMENT ON COLUMN praxia_finanzas.movimientos_auditoria.origen IS
    'Canal desde el que se hizo el cambio. Distinguir mcp de dashboard permite '
    'auditar qué hizo un agente y qué hizo una persona.';

CREATE INDEX IF NOT EXISTS movimientos_auditoria_mov_idx
    ON praxia_finanzas.movimientos_auditoria (movimiento_id, registrado_at DESC);

-- -----------------------------------------------------------------------------
-- 9. schema_migrations
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS praxia_finanzas.schema_migrations (
    version         text        PRIMARY KEY,
    descripcion     text        NOT NULL,
    aplicada_at     timestamptz NOT NULL DEFAULT now(),
    checksum_sha256 text
);

COMMENT ON TABLE praxia_finanzas.schema_migrations IS
    'Versión del esquema, en la propia base. Es la tabla que hay que consultar '
    'EN EL SERVIDOR, no en el repositorio: el 2026-08-05 se descubrió que '
    'producción estaba tres migraciones atrás porque nadie la había mirado.';

-- Registro sintético de las migraciones descriptas en la documentación.
INSERT INTO praxia_finanzas.schema_migrations (version, descripcion) VALUES
    ('v3.1', 'DDL base: perfiles, cuentas, categorías, fx, movimientos, ingesta, auditoría'),
    ('v3.6', 'Documentos con sha256 y deduplicación'),
    ('v4.0', 'Núcleo fiscal: comprobantes, IVA, obligaciones, cierres, auditoría inmutable'),
    ('v4.2', 'Exportaciones fiscales'),
    ('v4.3', 'Deudas pendientes'),
    ('v4.4', 'Deudas administrables y auditoría de deuda'),
    ('v4.5', 'Pagos de deuda con guards de moneda y recálculo de saldo'),
    ('v4.6', 'Obligaciones recurrentes, plantillas y planes de pago'),
    ('v4.7', 'estado_fiscal derivado y transiciones de cierre válidas'),
    ('v4.8', 'Propuestas fiscales con huella y contenido inmutable')
ON CONFLICT (version) DO NOTHING;

COMMIT;

-- =============================================================================
-- Lo que NO está en este archivo, a propósito
--
-- · datos_sensibles y su placeholder_token ⟦S1⟧ (cifrado server-side).
-- · valuaciones, cuotas_movimientos, proyectos.
-- · Todo el núcleo fiscal v4.0 (comprobantes, IVA, cierres, obligaciones).
-- · Documentos, plantillas recurrentes, planes de pago.
--
-- Están descriptos en systems/praxia-finanzas/README.md. Acá se publica lo
-- suficiente para entender el modelo, no lo suficiente para reproducirlo.
-- =============================================================================
