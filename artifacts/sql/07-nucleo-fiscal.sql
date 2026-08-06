-- =============================================================================
--  PraxIA Ops · artifacts/sql/07-nucleo-fiscal.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  El núcleo fiscal (migración v4.0, registro `v4_0_2026-07-28`) escrito de
--  nuevo para este repositorio. Los nombres de tablas, columnas, estados,
--  funciones, índices y vistas son fieles al diseño verificado; los tipos
--  exactos, los rangos de los CHECK y los datos de ejemplo son una
--  reconstrucción razonable. No hay CUIT, montos ni identificadores reales.
--
--  El principio de la migración original, textual:
--
--      «No hay una segunda contabilidad. Todo lo fiscal se DERIVA de
--       `movimientos`, `ingesta_raw` y `documentos`, y apunta de vuelta a
--       ellos. Ninguna columna nueva cambia cómo se calcula un saldo.»
--
--  Por eso este archivo es ADITIVO: agrega tablas y columnas, no toca ninguna
--  fórmula de saldo, y todo lo que crea es o bien evidencia (comprobantes),
--  o bien encuadre (perfiles, reglas), o bien proceso (obligaciones, cierres,
--  borradores), o bien rastro (auditoría).
--
--  Motor:    PostgreSQL 16
--  Requiere: 03-esquema-finanzas-nucleo.sql (y el 04 para reutilizar
--            `prohibir_delete_fisico()`, si se ejecuta la serie completa)
--  Orden:    ejecutar después del 06 y antes del 08
--  Corte:    2026-08-06
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS praxia_finanzas;

-- -----------------------------------------------------------------------------
-- 0. Una aclaración necesaria sobre el archivo 03
-- -----------------------------------------------------------------------------
-- El archivo 03 dejó en `movimientos` una versión simplificada del encuadre
-- fiscal (`ambito` obligatorio, `deducible` obligatorio, `estado_fiscal` con
-- tres valores derivados) que alcanzaba para explicar la idea de "derivar en
-- vez de sincronizar". El diseño real de v4.0 es distinto y más honesto:
--
--   · `ambito` y `deducible` son NULLABLE, porque "todavía no lo clasifiqué"
--     es un estado legítimo y distinto de "es personal y no se deduce". Todo
--     el motor de propuestas se apoya en esa diferencia: sin NULL no hay
--     "movimiento sin encuadre" que reportar.
--   · `estado_fiscal` tiene CINCO valores y describe el AVANCE del movimiento
--     dentro del proceso fiscal, no su clasificación.
--
-- Acá se alinea el archivo 03 con el diseño real. Quién deriva `estado_fiscal`
-- a partir de ese encuadre es asunto del archivo 08, que instala la versión
-- fiel de v4.7: este archivo pone la forma, el 08 pone la regla.
-- -----------------------------------------------------------------------------

-- =============================================================================
-- 1. fiscal_perfiles — la condición fiscal con vigencia
-- =============================================================================
-- INVARIANTE: la condición fiscal es TEMPORAL y SIMULTÁNEA.
--
--   Temporal   — un cálculo de julio usa la condición vigente EN JULIO, no la
--                de hoy. Guardar "condición actual" en una columna del
--                contribuyente hace imposible recalcular un período anterior
--                sin mentir.
--   Simultánea — una misma persona puede ser monotributista y estar en
--                relación de dependencia el mismo día. No es un caso raro: es
--                el caso normal de casi cualquier profesional. Por eso la
--                función de consulta devuelve un CONJUNTO de filas, no una.
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_perfiles (
    id               bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    actor            text        NOT NULL CHECK (btrim(actor) <> ''),

    condicion        text        NOT NULL CHECK (condicion IN (
                                     'monotributo',
                                     'responsable_inscripto',
                                     'exento',
                                     'relacion_dependencia',
                                     'profesional_independiente',
                                     'prestador_organismo_publico',
                                     'inversor',
                                     'no_alcanzado',
                                     'otro')),
    subcategoria     text,
    actividad        text,
    codigo_actividad text,
    jurisdiccion     text,
    organismo        text,

    -- El CUIT se guarda cifrado del lado del servidor y NUNCA sale del API.
    -- Lo único que se expone es `cuit_parcial`, con el formato que el propio
    -- sistema define. El valor de este archivo es sintético.
    cuit_cifrado     bytea,
    cuit_parcial     text        CHECK (cuit_parcial IS NULL
                                        OR cuit_parcial ~ '^[0-9]{2}-\*{4}[0-9]{4}-[0-9]$'),

    vigencia_desde   date        NOT NULL,
    vigencia_hasta   date,

    estado           text        NOT NULL DEFAULT 'vigente'
                                 CHECK (estado IN ('vigente','historico',
                                                   'en_tramite','baja','observado')),

    fuente           text,
    verificado_en    timestamptz,
    metadata         jsonb       NOT NULL DEFAULT '{}'::jsonb
                                 CHECK (jsonb_typeof(metadata) = 'object'),
    creado_en        timestamptz NOT NULL DEFAULT now(),
    actualizado_en   timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fiscal_perfil_vigencia_coherente
        CHECK (vigencia_hasta IS NULL OR vigencia_hasta >= vigencia_desde)
);

COMMENT ON TABLE praxia_finanzas.fiscal_perfiles IS
    'Condición fiscal de un contribuyente con vigencia temporal y simultánea. '
    'Invariante: nunca asumir que la condición de hoy es la de siempre. Los '
    'cálculos de un período usan la vigente EN ESE período, no la actual. '
    'Corolario: una condición no se corrige editando la fila, se cierra con '
    'vigencia_hasta y se abre una fila nueva.';

COMMENT ON COLUMN praxia_finanzas.fiscal_perfiles.actor IS
    'Identificador lógico del contribuyente. Es el eje de aislamiento: los '
    'chequeos de cierre y las obligaciones se resuelven por actor, para que '
    'nunca se mezclen dos contribuyentes en un mismo período.';
COMMENT ON COLUMN praxia_finanzas.fiscal_perfiles.condicion IS
    'Nueve condiciones posibles. Pueden coexistir varias vigentes a la vez: '
    'monotributo y relación de dependencia el mismo día es lo habitual, no una '
    'anomalía. Ningún constraint las declara mutuamente excluyentes a propósito.';
COMMENT ON COLUMN praxia_finanzas.fiscal_perfiles.cuit_cifrado IS
    'CUIT cifrado server-side. La base guarda el ciframiento, no la clave. '
    'Ninguna operación de lectura devuelve esta columna.';
COMMENT ON COLUMN praxia_finanzas.fiscal_perfiles.cuit_parcial IS
    'Forma publicable del CUIT, formato 20-****1234-5. Alcanza para que un '
    'humano reconozca de quién se trata y no alcanza para identificarlo ante '
    'un tercero. El valor de este repositorio es sintético.';
COMMENT ON COLUMN praxia_finanzas.fiscal_perfiles.estado IS
    'vigente · historico · en_tramite · baja · observado. Ojo con la '
    'diferencia entre `estado` y la vigencia por fechas: un perfil `historico` '
    'sigue siendo válido PARA SU PERÍODO. Ese fue exactamente el bug que '
    'corrigió la v4.13.';
COMMENT ON COLUMN praxia_finanzas.fiscal_perfiles.verificado_en IS
    'Cuándo se contrastó esta condición contra una constancia real. Una '
    'condición sin verificar sirve para orientar y no para determinar un importe.';

CREATE INDEX IF NOT EXISTS idx_fiscal_perfil_actor
    ON praxia_finanzas.fiscal_perfiles (actor, vigencia_desde DESC);

-- -----------------------------------------------------------------------------
-- fiscal_perfiles_vigentes(actor, fecha)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION praxia_finanzas.fiscal_perfiles_vigentes(
    p_actor text,
    p_fecha date DEFAULT current_date
)
RETURNS SETOF praxia_finanzas.fiscal_perfiles
LANGUAGE sql
STABLE
AS $$
    SELECT p.*
    FROM praxia_finanzas.fiscal_perfiles p
    WHERE p.actor = p_actor
      AND p.vigencia_desde <= p_fecha
      AND (p.vigencia_hasta IS NULL OR p.vigencia_hasta >= p_fecha)
      -- v4.13: NO se exige estado = 'vigente'. Un perfil marcado `historico`
      -- sigue habiendo estado vigente en su período, y filtrarlo hacía que un
      -- cierre retroactivo dijera "no hay condición fiscal" sobre un período
      -- que sí la tenía. Sólo se descartan las dos formas de "esto no cuenta":
      -- dado de baja y observado.
      AND p.estado NOT IN ('baja','observado')
    ORDER BY p.vigencia_desde DESC, p.id DESC;
$$;

COMMENT ON FUNCTION praxia_finanzas.fiscal_perfiles_vigentes(text, date) IS
    'Condiciones fiscales vigentes de un actor a una fecha. Devuelve SETOF, no '
    'una fila: la simultaneidad es parte del modelo. Cero filas significa que '
    'no hay condición conocida para ese día, y eso es un bloqueante del cierre, '
    'no un cero.';

-- =============================================================================
-- 2. comprobantes — la factura como entidad propia
-- =============================================================================
-- INVARIANTE: el comprobante es evidencia, el movimiento es plata. Son dos
-- cosas distintas y se vinculan N:N.
--
-- Modelar la factura como un campo del movimiento parece más simple hasta que
-- aparece la primera factura que se paga en tres cuotas, o el primer pago que
-- cancela dos facturas. A partir de ahí, o se duplica el movimiento o se
-- pierde la factura. Las dos opciones son peores que una tabla más.
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.comprobantes (
    id                      bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- --- Identificación ------------------------------------------------------
    tipo                    text        NOT NULL CHECK (tipo IN (
                                            'factura_a','factura_b','factura_c',
                                            'factura_m','factura_e',
                                            'nota_credito','nota_debito',
                                            'recibo','ticket','liquidacion','otro')),
    letra                   char(1)     CHECK (letra IS NULL OR letra IN ('A','B','C','E','M')),
    punto_venta             integer     CHECK (punto_venta IS NULL
                                               OR punto_venta BETWEEN 0 AND 99999),
    numero                  bigint      CHECK (numero IS NULL OR numero > 0),

    -- --- Fechas --------------------------------------------------------------
    fecha_emision           date        NOT NULL,
    fecha_imputacion        date,

    -- --- Partes --------------------------------------------------------------
    cuit_emisor_cifrado     bytea,
    cuit_emisor_parcial     text        CHECK (cuit_emisor_parcial IS NULL
                                               OR cuit_emisor_parcial ~ '^[0-9]{2}-\*{4}[0-9]{4}-[0-9]$'),
    razon_social_emisor     text,
    cuit_receptor_cifrado   bytea,
    cuit_receptor_parcial   text        CHECK (cuit_receptor_parcial IS NULL
                                               OR cuit_receptor_parcial ~ '^[0-9]{2}-\*{4}[0-9]{4}-[0-9]$'),
    razon_social_receptor   text,

    sentido                 text        NOT NULL CHECK (sentido IN ('recibido','emitido')),

    -- --- Importes ------------------------------------------------------------
    moneda                  char(3)     NOT NULL DEFAULT 'ARS'
                                        CHECK (moneda ~ '^[A-Z]{3}$'),
    tipo_cambio             numeric(20,8) CHECK (tipo_cambio IS NULL OR tipo_cambio > 0),
    neto_gravado            numeric(18,2) NOT NULL DEFAULT 0,
    neto_no_gravado         numeric(18,2) NOT NULL DEFAULT 0,
    exento                  numeric(18,2) NOT NULL DEFAULT 0,
    iva_total               numeric(18,2) NOT NULL DEFAULT 0,
    otros_tributos          numeric(18,2) NOT NULL DEFAULT 0,
    percepciones            numeric(18,2) NOT NULL DEFAULT 0,
    retenciones             numeric(18,2) NOT NULL DEFAULT 0,
    total                   numeric(18,2) NOT NULL CHECK (total <> 0),

    -- --- Autorización --------------------------------------------------------
    cae                     text        CHECK (cae IS NULL OR cae ~ '^[0-9]{14}$'),
    cae_vencimiento         date,

    -- --- Respaldo documental -------------------------------------------------
    documento_id            bigint,
    sha256                  char(64)    CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
    ingesta_id              bigint      REFERENCES praxia_finanzas.ingesta_raw(id),

    -- --- Estado y período ----------------------------------------------------
    estado_validacion       text        NOT NULL DEFAULT 'sin_validar'
                                        CHECK (estado_validacion IN (
                                            'sin_validar','validado','observado',
                                            'rechazado','anulado')),
    periodo_fiscal          integer     CHECK (periodo_fiscal IS NULL
                                               OR (periodo_fiscal >= 200001
                                                   AND periodo_fiscal % 100 BETWEEN 1 AND 12)),

    notas                   text,
    metadata                jsonb       NOT NULL DEFAULT '{}'::jsonb
                                        CHECK (jsonb_typeof(metadata) = 'object'),
    creado_en               timestamptz NOT NULL DEFAULT now(),
    actualizado_en          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT comprobante_cae_con_vencimiento
        CHECK (cae IS NULL OR cae_vencimiento IS NOT NULL),
    CONSTRAINT comprobante_imputacion_no_anterior
        CHECK (fecha_imputacion IS NULL OR fecha_imputacion >= fecha_emision)
);

COMMENT ON TABLE praxia_finanzas.comprobantes IS
    'La factura, el ticket o el recibo como entidad propia, con su respaldo '
    'documental y su hash. No reemplaza al movimiento: el movimiento es la '
    'plata, el comprobante es la evidencia, y se vinculan N:N por '
    'comprobante_movimientos. La diferencia entre `total` y la suma imputada es '
    'lo que el cierre reporta como descalce.';

COMMENT ON COLUMN praxia_finanzas.comprobantes.fecha_emision IS
    'Fecha impresa en el comprobante. Es un hecho, no una decisión.';
COMMENT ON COLUMN praxia_finanzas.comprobantes.fecha_imputacion IS
    'La que manda para el cierre. Se separa de fecha_emision porque una factura '
    'emitida el 31 puede corresponder al mes siguiente, y esa decisión tiene '
    'que ser explícita y editable, no un efecto colateral de la fecha impresa.';
COMMENT ON COLUMN praxia_finanzas.comprobantes.sentido IS
    'recibido (crédito fiscal potencial) o emitido (débito fiscal). Es lo que '
    'separa las dos columnas del libro IVA, y por eso no se infiere del signo '
    'del movimiento asociado: un comprobante puede no tener movimiento todavía.';
COMMENT ON COLUMN praxia_finanzas.comprobantes.total IS
    'Total del comprobante tal como está impreso. No se recalcula desde los '
    'parciales: si no cierra, eso es un hallazgo que hay que ver, no un dato '
    'que la base deba corregir sola.';
COMMENT ON COLUMN praxia_finanzas.comprobantes.sha256 IS
    'Hash del archivo de respaldo. Es la clave de deduplicación real: el mismo '
    'PDF reenviado por otro canal tiene el mismo hash y no entra dos veces.';
COMMENT ON COLUMN praxia_finanzas.comprobantes.documento_id IS
    'Referencia al documento almacenado. La RUTA del archivo nunca sale del '
    'API: hacia afuera se expone sha256 y un booleano de disponibilidad.';
COMMENT ON COLUMN praxia_finanzas.comprobantes.estado_validacion IS
    'sin_validar · validado · observado · rechazado · anulado. `observado` es '
    'un aviso del cierre, no un bloqueante: significa "esto hay que mirarlo", '
    'no "esto está mal".';
COMMENT ON COLUMN praxia_finanzas.comprobantes.periodo_fiscal IS
    'AAAAMM. Lo completa el trigger completar_periodo_comprobante() desde '
    'fecha_imputacion o, si no la hay, desde fecha_emision. Es editable a mano: '
    'el trigger sólo rellena el hueco, nunca pisa una decisión ya tomada.';

CREATE INDEX IF NOT EXISTS idx_comprobante_periodo
    ON praxia_finanzas.comprobantes (periodo_fiscal, sentido);
CREATE INDEX IF NOT EXISTS idx_comprobante_emision
    ON praxia_finanzas.comprobantes (fecha_emision DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_comprobante_sha256
    ON praxia_finanzas.comprobantes (sha256)
    WHERE sha256 IS NOT NULL;

-- -----------------------------------------------------------------------------
-- El índice único PARCIAL: por qué la condición está en el WHERE
-- -----------------------------------------------------------------------------
-- Un comprobante fiscal se identifica por (tipo, punto de venta, número, CUIT
-- del emisor). Esa cuádrupla es única en el mundo y sirve para detectar la
-- misma factura cargada dos veces.
--
-- Pero MUCHOS comprobantes reales no tienen los cuatro datos: un ticket de
-- estacionamiento no trae punto de venta, un recibo informal no trae número,
-- un PDF mal leído puede no dejar CUIT. Un índice único total obligaría a
-- inventar valores para poder cargarlos, y un dato inventado para satisfacer
-- un índice es exactamente la clase de mentira que este sistema evita.
--
-- La solución es un índice único PARCIAL: la unicidad se exige sólo cuando
-- están los tres datos que la hacen significativa. Sin ellos, no hay identidad
-- que proteger, y la deduplicación queda en manos del sha256 del archivo.
--
-- Se indexa por `cuit_emisor_parcial` y no por `cuit_emisor_cifrado` a
-- propósito: nada garantiza que el ciframiento sea determinístico, y un índice
-- sobre un ciframiento no determinístico no deduplica nada.
-- -----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS idx_comprobante_unico
    ON praxia_finanzas.comprobantes (tipo, punto_venta, numero, cuit_emisor_parcial)
    WHERE punto_venta IS NOT NULL
      AND numero      IS NOT NULL
      AND cuit_emisor_parcial IS NOT NULL;

COMMENT ON INDEX praxia_finanzas.idx_comprobante_unico IS
    'Unicidad de la identificación fiscal (tipo, punto de venta, número, CUIT '
    'emisor), aplicada SÓLO cuando los tres datos existen. Parcial a propósito: '
    'un ticket sin punto de venta debe poder cargarse sin inventar uno.';

-- =============================================================================
-- 3. comprobante_iva — IVA discriminado por alícuota
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.comprobante_iva (
    id             bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    comprobante_id bigint        NOT NULL
                                 REFERENCES praxia_finanzas.comprobantes(id) ON DELETE CASCADE,
    alicuota       numeric(5,2)  NOT NULL CHECK (alicuota >= 0 AND alicuota <= 100),
    base_imponible numeric(18,2) NOT NULL,
    importe        numeric(18,2) NOT NULL,
    creado_en      timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT comprobante_iva_unico UNIQUE (comprobante_id, alicuota)
);

COMMENT ON TABLE praxia_finanzas.comprobante_iva IS
    'IVA discriminado por alícuota. Una factura puede traer 21% y 10,5% juntos, '
    'y guardar sólo el iva_total pierde la información que pide el libro IVA. '
    'Es una tabla hija, no columnas, porque el conjunto de alícuotas cambia por '
    'normativa y una columna por alícuota se convierte en una migración cada vez.';

COMMENT ON COLUMN praxia_finanzas.comprobante_iva.alicuota IS
    'Porcentaje, no fracción: 21.00, no 0.21. Guardar el porcentaje tal como '
    'figura impreso evita la ambigüedad de leer 0.21 y no saber si es 21% o 0,21%.';
COMMENT ON CONSTRAINT comprobante_iva_unico ON praxia_finanzas.comprobante_iva IS
    'Invariante: una alícuota aparece una sola vez por comprobante. Dos filas '
    'al 21% en la misma factura son un doble ingreso, no un caso de negocio, y '
    'duplicarían silenciosamente el crédito fiscal del período.';

-- =============================================================================
-- 4. comprobante_movimientos — el puente N:N
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.comprobante_movimientos (
    comprobante_id   bigint        NOT NULL
                                   REFERENCES praxia_finanzas.comprobantes(id) ON DELETE CASCADE,
    movimiento_id    bigint        NOT NULL
                                   REFERENCES praxia_finanzas.movimientos(id) ON DELETE CASCADE,
    importe_imputado numeric(18,2) CHECK (importe_imputado IS NULL OR importe_imputado > 0),
    nota             text,
    creado_en        timestamptz   NOT NULL DEFAULT now(),

    PRIMARY KEY (comprobante_id, movimiento_id)
);

COMMENT ON TABLE praxia_finanzas.comprobante_movimientos IS
    'Relación N:N entre comprobantes y movimientos. N:N y no 1:1 porque una '
    'factura se puede pagar en cuotas (un comprobante, varios movimientos) y un '
    'pago puede cancelar varias facturas (un movimiento, varios comprobantes). '
    'Cualquier modelo más simple obliga a duplicar un lado de la relación.';

COMMENT ON COLUMN praxia_finanzas.comprobante_movimientos.importe_imputado IS
    'Cuánto de este movimiento corresponde a este comprobante. NULL significa '
    '"el total del movimiento" y es el caso normal. Está separado del monto del '
    'movimiento porque una transferencia puede pagar media factura, y afirmar '
    'que la pagó entera sería inventar una imputación.';

CREATE INDEX IF NOT EXISTS idx_comprobante_mov_movimiento
    ON praxia_finanzas.comprobante_movimientos (movimiento_id);

-- =============================================================================
-- 5. Las columnas fiscales de `movimientos`
-- =============================================================================
-- Todas nullable a propósito, salvo estado_fiscal. "Todavía no lo clasifiqué"
-- tiene que ser distinguible de "lo clasifiqué como no deducible": la primera
-- es trabajo pendiente, la segunda es una decisión tomada. Un DEFAULT que
-- rellene el hueco borra esa diferencia y el cierre deja de ver el pendiente.
-- =============================================================================

ALTER TABLE praxia_finanzas.movimientos
    ALTER COLUMN ambito    DROP NOT NULL,
    ALTER COLUMN ambito    DROP DEFAULT,
    ALTER COLUMN deducible DROP NOT NULL,
    ALTER COLUMN deducible DROP DEFAULT;

ALTER TABLE praxia_finanzas.movimientos
    DROP CONSTRAINT IF EXISTS movimientos_ambito_check;
ALTER TABLE praxia_finanzas.movimientos
    ADD CONSTRAINT movimientos_ambito_check
    CHECK (ambito IS NULL OR ambito IN ('personal','profesional','mixto'));

ALTER TABLE praxia_finanzas.movimientos
    ADD COLUMN IF NOT EXISTS deducible_porcentaje   numeric(5,2),
    ADD COLUMN IF NOT EXISTS motivo_no_deducible    text,
    ADD COLUMN IF NOT EXISTS periodo_fiscal         integer,
    ADD COLUMN IF NOT EXISTS fiscal_actividad       text,
    ADD COLUMN IF NOT EXISTS fiscal_jurisdiccion    text,
    ADD COLUMN IF NOT EXISTS tratamiento_impositivo text,
    ADD COLUMN IF NOT EXISTS comprobante_id         bigint
        REFERENCES praxia_finanzas.comprobantes(id);

ALTER TABLE praxia_finanzas.movimientos
    DROP CONSTRAINT IF EXISTS mov_deducible_porcentaje_rango;
ALTER TABLE praxia_finanzas.movimientos
    ADD CONSTRAINT mov_deducible_porcentaje_rango
    CHECK (deducible_porcentaje IS NULL
           OR (deducible_porcentaje >= 0 AND deducible_porcentaje <= 100));

ALTER TABLE praxia_finanzas.movimientos
    DROP CONSTRAINT IF EXISTS mov_periodo_fiscal_valido;
ALTER TABLE praxia_finanzas.movimientos
    ADD CONSTRAINT mov_periodo_fiscal_valido
    CHECK (periodo_fiscal IS NULL
           OR (periodo_fiscal >= 200001 AND periodo_fiscal % 100 BETWEEN 1 AND 12));

-- estado_fiscal pasa de los tres valores didácticos del archivo 03 a los cinco
-- reales de v4.0. Describe el AVANCE en el proceso, no la clasificación.
ALTER TABLE praxia_finanzas.movimientos
    DROP CONSTRAINT IF EXISTS movimientos_estado_fiscal_check;
ALTER TABLE praxia_finanzas.movimientos
    ALTER COLUMN estado_fiscal DROP DEFAULT;

UPDATE praxia_finanzas.movimientos
   SET estado_fiscal = 'sin_clasificar'
 WHERE estado_fiscal NOT IN ('sin_clasificar','clasificado','observado',
                             'incluido_en_cierre','presentado');

ALTER TABLE praxia_finanzas.movimientos
    ALTER COLUMN estado_fiscal SET DEFAULT 'sin_clasificar';
ALTER TABLE praxia_finanzas.movimientos
    ADD CONSTRAINT movimientos_estado_fiscal_check
    CHECK (estado_fiscal IN ('sin_clasificar','clasificado','observado',
                             'incluido_en_cierre','presentado'));

COMMENT ON COLUMN praxia_finanzas.movimientos.ambito IS
    'personal · profesional · mixto, o NULL. NULL significa "sin encuadrar", y '
    'es el estado que el motor busca para decidir sobre qué pedir criterio. Si '
    'tuviera DEFAULT, ningún movimiento aparecería nunca como pendiente de '
    'clasificar y el cierre se cerraría con todo sin mirar.';
COMMENT ON COLUMN praxia_finanzas.movimientos.deducible IS
    'Decisión humana, no consecuencia de la categoría. categorias.deducible_default '
    'es una sugerencia; esto es la decisión, y queda auditada campo por campo.';
COMMENT ON COLUMN praxia_finanzas.movimientos.deducible_porcentaje IS
    'Deducción parcial, 0 a 100. NULL con deducible = true significa 100%. Es '
    'para el caso del gasto mixto: el teléfono que se usa para las dos cosas.';
COMMENT ON COLUMN praxia_finanzas.movimientos.motivo_no_deducible IS
    'Obligatorio a nivel de aplicación cuando deducible = false. Un "no" sin '
    'motivo no se puede revisar seis meses después ni defender ante nadie.';
COMMENT ON COLUMN praxia_finanzas.movimientos.periodo_fiscal IS
    'AAAAMM derivado de la fecha por completar_periodo_fiscal(), editable a '
    'mano para los casos en que la imputación no coincide con la fecha.';
COMMENT ON COLUMN praxia_finanzas.movimientos.estado_fiscal IS
    'AVANCE del movimiento en el proceso fiscal, no su clasificación: '
    'sin_clasificar → clasificado → incluido_en_cierre → presentado, más '
    'observado. Los dos primeros los deriva el trigger de v4.7 desde ambito y '
    'deducible; los dos últimos los pone el proceso de cierre y NO vuelven '
    'atrás por una corrección de encuadre.';
COMMENT ON COLUMN praxia_finanzas.movimientos.comprobante_id IS
    'Atajo al comprobante principal. La relación real es la tabla puente: esta '
    'columna es conveniencia de lectura y no debe usarse para totalizar.';

CREATE INDEX IF NOT EXISTS idx_movimiento_periodo_fiscal
    ON praxia_finanzas.movimientos (periodo_fiscal, estado_fiscal);
CREATE INDEX IF NOT EXISTS idx_movimiento_sin_encuadre
    ON praxia_finanzas.movimientos (periodo_fiscal)
    WHERE ambito IS NULL OR deducible IS NULL;

-- =============================================================================
-- 6. fiscal_reglas — la normativa, parametrizada
-- =============================================================================
-- INVARIANTE: ninguna alícuota, escala ni fecha de vencimiento se hardcodea.
--
-- Una alícuota escrita en el código es una alícuota que nadie puede auditar y
-- que queda vieja sin que nada avise. Acá vive como fila, con fuente, fecha de
-- verificación y vigencia. Y hay una columna que existe precisamente para
-- poder poner datos que TODAVÍA NO SON CIERTOS sin que se cuelen en un
-- cálculo: `es_ficticia`.
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_reglas (
    id             bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    codigo         text        NOT NULL UNIQUE CHECK (btrim(codigo) <> ''),
    nombre         text        NOT NULL,
    organismo      text        NOT NULL,
    jurisdiccion   text,
    impuesto       text        NOT NULL,

    -- A qué se aplica: una actividad, una condición, una categoría, todo.
    aplica_a       text        CHECK (aplica_a IS NULL OR aplica_a IN (
                                   'condicion','actividad','categoria',
                                   'jurisdiccion','todos')),
    aplica_valor   text,

    tipo_regla     text        NOT NULL CHECK (tipo_regla IN (
                                   'alicuota','escala','monto_fijo',
                                   'vencimiento','tope','otro')),
    parametros     jsonb       NOT NULL DEFAULT '{}'::jsonb
                               CHECK (jsonb_typeof(parametros) = 'object'),
    frecuencia     text        CHECK (frecuencia IS NULL OR frecuencia IN (
                                   'mensual','bimestral','trimestral',
                                   'cuatrimestral','semestral','anual','unica')),

    vigencia_desde date        NOT NULL,
    vigencia_hasta date,

    fuente         text,
    fuente_url     text,
    verificado_en  timestamptz,
    verificado_por text,

    -- La columna que hace honesto al resto de la tabla.
    es_ficticia    boolean     NOT NULL DEFAULT false,

    metadata       jsonb       NOT NULL DEFAULT '{}'::jsonb
                               CHECK (jsonb_typeof(metadata) = 'object'),
    creado_en      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fiscal_regla_vigencia_coherente
        CHECK (vigencia_hasta IS NULL OR vigencia_hasta >= vigencia_desde),
    CONSTRAINT fiscal_regla_verificada_con_quien
        CHECK (verificado_en IS NULL OR btrim(coalesce(verificado_por,'')) <> '')
);

COMMENT ON TABLE praxia_finanzas.fiscal_reglas IS
    'Alícuotas, escalas, topes y vencimientos como datos con fuente y vigencia. '
    'Nada de esto se hardcodea. Una regla sin verificar no sirve para determinar '
    'un importe, y el cierre la marca como bloqueante.';

COMMENT ON COLUMN praxia_finanzas.fiscal_reglas.es_ficticia IS
    'Marca de dato de laboratorio. Existe para poder cargar reglas de prueba sin '
    'que se cuelen en un cálculo real: si una regla ficticia aparece en un '
    'período productivo, el cierre lo reporta como BLOQUEANTE. Es la alternativa '
    'honesta a "después la corrijo", que nunca pasa.';
COMMENT ON COLUMN praxia_finanzas.fiscal_reglas.verificado_en IS
    'Cuándo se contrastó esta regla contra la norma publicada. NULL es tan '
    'bloqueante como es_ficticia: una regla que nadie verificó y una regla '
    'inventada producen el mismo importe equivocado.';
COMMENT ON COLUMN praxia_finanzas.fiscal_reglas.fuente_url IS
    'Dónde mirar para volver a verificarla. Sin esto, "verificado" es una '
    'afirmación que hay que creer.';
COMMENT ON COLUMN praxia_finanzas.fiscal_reglas.parametros IS
    'Los valores de la regla, en jsonb porque su forma depende de tipo_regla: '
    'una alícuota es un número, una escala es una lista de tramos, un '
    'vencimiento es un día o una tabla por terminación de CUIT.';

CREATE INDEX IF NOT EXISTS idx_fiscal_regla_impuesto
    ON praxia_finanzas.fiscal_reglas (impuesto, vigencia_desde DESC);
CREATE INDEX IF NOT EXISTS idx_fiscal_regla_sin_verificar
    ON praxia_finanzas.fiscal_reglas (id)
    WHERE es_ficticia OR verificado_en IS NULL;

-- =============================================================================
-- 7. fiscal_obligaciones — la regla instanciada en un período
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_obligaciones (
    id                        bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    actor                     text        NOT NULL CHECK (btrim(actor) <> ''),
    regla_id                  bigint      REFERENCES praxia_finanzas.fiscal_reglas(id),

    organismo                 text        NOT NULL,
    impuesto                  text        NOT NULL,
    jurisdiccion              text        NOT NULL DEFAULT 'nacional',
    frecuencia                text        CHECK (frecuencia IS NULL OR frecuencia IN (
                                              'mensual','bimestral','trimestral',
                                              'cuatrimestral','semestral','anual','unica')),

    -- AAAAMM para las periódicas; AAAA00 para las anuales.
    periodo                   integer     NOT NULL
                                          CHECK (periodo >= 200000
                                                 AND periodo % 100 BETWEEN 0 AND 12),
    vencimiento               date,

    estado                    text        NOT NULL DEFAULT 'pendiente'
                                          CHECK (estado IN (
                                              'pendiente','estimada','determinada',
                                              'presentada','pagada','vencida',
                                              'exenta','anulada')),

    moneda                    char(3)     NOT NULL DEFAULT 'ARS'
                                          CHECK (moneda ~ '^[A-Z]{3}$'),
    importe_estimado          numeric(18,2),
    importe_determinado       numeric(18,2),
    importe_pagado            numeric(18,2) NOT NULL DEFAULT 0,

    comprobante_presentacion_id bigint    REFERENCES praxia_finanzas.comprobantes(id),
    comprobante_pago_id       bigint      REFERENCES praxia_finanzas.comprobantes(id),
    movimiento_pago_id        bigint      REFERENCES praxia_finanzas.movimientos(id),

    observaciones             text,
    metadata                  jsonb       NOT NULL DEFAULT '{}'::jsonb
                                          CHECK (jsonb_typeof(metadata) = 'object'),
    creado_en                 timestamptz NOT NULL DEFAULT now(),
    actualizado_en            timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fiscal_obligacion_determinada_con_importe
        CHECK (estado <> 'determinada' OR importe_determinado IS NOT NULL)
);

COMMENT ON TABLE praxia_finanzas.fiscal_obligaciones IS
    'Una regla instanciada en un período concreto para un actor concreto. '
    'Garantía del contrato: crear una obligación NO crea automáticamente un '
    'movimiento ni un pago. Registrar lo que hay que pagar y pagarlo son dos '
    'hechos distintos, y confundirlos es como aparece la doble contabilización.';

COMMENT ON COLUMN praxia_finanzas.fiscal_obligaciones.periodo IS
    'AAAAMM para las periódicas, AAAA00 para las anuales. El 00 no es un mes '
    'inválido colado: es la forma de decir "el año entero" sin una columna extra '
    'que haya que recordar mirar.';
COMMENT ON COLUMN praxia_finanzas.fiscal_obligaciones.estado IS
    'Ocho estados: pendiente · estimada · determinada · presentada · pagada · '
    'vencida · exenta · anulada. Son ocho y no cinco porque "estimada" y '
    '"determinada" son cosas distintas: una estimación es del sistema, una '
    'determinación es del contador, y mezclarlas hace que un número tentativo '
    'termine pareciendo un número firme.';
COMMENT ON COLUMN praxia_finanzas.fiscal_obligaciones.importe_estimado IS
    'Cálculo del sistema, identificado estrictamente como tal por el contrato. '
    'Nunca se muestra sin decir que es una estimación.';
COMMENT ON COLUMN praxia_finanzas.fiscal_obligaciones.importe_determinado IS
    'El importe que corresponde pagar, ya determinado por una persona con '
    'responsabilidad profesional. El agente no lo escribe.';
COMMENT ON COLUMN praxia_finanzas.fiscal_obligaciones.movimiento_pago_id IS
    'El movimiento real que la canceló, si lo hubo. Nulo mientras no exista: la '
    'obligación no crea el pago, lo referencia cuando ocurre.';

-- El índice único PARCIAL: una obligación por (actor, organismo, impuesto,
-- jurisdicción, período) — salvo las anuladas, que pueden ser muchas. Sin la
-- cláusula WHERE, anular y volver a cargar la misma obligación sería imposible,
-- y la salida sería borrar la anulada, que es justo lo que no se hace acá.
CREATE UNIQUE INDEX IF NOT EXISTS idx_obligacion_unica
    ON praxia_finanzas.fiscal_obligaciones
       (actor, organismo, impuesto, jurisdiccion, periodo)
    WHERE estado <> 'anulada';

COMMENT ON INDEX praxia_finanzas.idx_obligacion_unica IS
    'Invariante: una sola obligación viva por actor, organismo, impuesto, '
    'jurisdicción y período. Parcial sobre estado <> anulada para que anular y '
    'recargar sea posible sin borrar la historia.';

CREATE INDEX IF NOT EXISTS idx_obligacion_vencimiento
    ON praxia_finanzas.fiscal_obligaciones (vencimiento)
    WHERE estado NOT IN ('pagada','exenta','anulada');

-- =============================================================================
-- 8. fiscal_cierres — el cierre mensual
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_cierres (
    id                bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    actor             text        NOT NULL CHECK (btrim(actor) <> ''),
    periodo           integer     NOT NULL
                                  CHECK (periodo >= 200001 AND periodo % 100 BETWEEN 1 AND 12),

    estado            text        NOT NULL DEFAULT 'abierto'
                                  CHECK (estado IN ('abierto','en_revision',
                                                    'listo_para_aprobar','aprobado',
                                                    'presentado','reabierto')),

    abierto_en        timestamptz NOT NULL DEFAULT now(),
    revisado_en       timestamptz,
    aprobado_por      text,
    aprobado_en       timestamptz,
    presentado_en     timestamptz,
    reabierto_en      timestamptz,
    motivo_reapertura text,

    resumen           jsonb       NOT NULL DEFAULT '{}'::jsonb
                                  CHECK (jsonb_typeof(resumen) = 'object'),
    chequeos          jsonb       NOT NULL DEFAULT '[]'::jsonb
                                  CHECK (jsonb_typeof(chequeos) = 'array'),

    notas             text,
    metadata          jsonb       NOT NULL DEFAULT '{}'::jsonb
                                  CHECK (jsonb_typeof(metadata) = 'object'),
    creado_en         timestamptz NOT NULL DEFAULT now(),
    actualizado_en    timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fiscal_cierre_actor_periodo UNIQUE (actor, periodo),
    CONSTRAINT fiscal_cierre_aprobado_con_firma
        CHECK (aprobado_en IS NULL OR btrim(coalesce(aprobado_por,'')) <> ''),
    CONSTRAINT fiscal_cierre_reapertura_con_motivo
        CHECK (reabierto_en IS NULL OR btrim(coalesce(motivo_reapertura,'')) <> '')
);

COMMENT ON TABLE praxia_finanzas.fiscal_cierres IS
    'El cierre de un período para un actor. Seis estados y una máquina que los '
    'gobierna (ver 08-cierre-y-estado-derivado.sql). Un cierre no es un flag: es '
    'un procedimiento con pasos, y cada paso tiene requisitos que no se pueden '
    'saltear.';

COMMENT ON COLUMN praxia_finanzas.fiscal_cierres.resumen IS
    'Los totales CONGELADOS al aprobar. Es una foto, no una consulta: si mañana '
    'la base devuelve otra cosa para el mismo período, es que alguien tocó un '
    'movimiento de un período cerrado — y eso se ve, que es justamente el punto.';
COMMENT ON COLUMN praxia_finanzas.fiscal_cierres.chequeos IS
    'La salida de cierre_chequeos() en el momento de la transición. Guardar el '
    'resultado y no volver a correrlo permite responder "qué sabíamos cuando lo '
    'aprobamos", que es distinto de "qué sabemos ahora".';
COMMENT ON COLUMN praxia_finanzas.fiscal_cierres.motivo_reapertura IS
    'Obligatorio si hay reapertura. Reabrir un período cerrado es la operación '
    'más delicada del sistema: sin motivo escrito no queda registro de por qué '
    'dejó de valer algo que ya se había dado por bueno.';

CREATE INDEX IF NOT EXISTS idx_fiscal_cierre_periodo
    ON praxia_finanzas.fiscal_cierres (periodo, estado);

-- =============================================================================
-- 9. fiscal_auditoria — append-only de verdad
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_auditoria (
    id             bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    entidad        text        NOT NULL CHECK (entidad IN (
                                   'movimiento','comprobante','cierre',
                                   'obligacion','perfil_fiscal','borrador')),
    entidad_id     bigint,
    accion         text        NOT NULL CHECK (btrim(accion) <> ''),

    campo          text,
    valor_anterior text,
    valor_nuevo    text,
    motivo         text,

    actor          text        NOT NULL CHECK (btrim(actor) <> ''),
    origen         text        NOT NULL DEFAULT 'api'
                               CHECK (origen IN ('api','dashboard','telegram',
                                                 'mcp','n8n','migracion')),
    metadata       jsonb       NOT NULL DEFAULT '{}'::jsonb
                               CHECK (jsonb_typeof(metadata) = 'object'),
    creado_en      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE praxia_finanzas.fiscal_auditoria IS
    'Rastro de todo cambio fiscal, campo por campo. Append-only real: el trigger '
    'trg_faud_inmutable rechaza UPDATE y DELETE. Una auditoría que se puede '
    'editar no es una auditoría, es una nota.';

COMMENT ON COLUMN praxia_finanzas.fiscal_auditoria.campo IS
    'Se audita campo por campo y no la fila entera: "cambió el movimiento 41" no '
    'sirve para nada; "ambito pasó de NULL a profesional el 5/8 por Aldo" sí.';
COMMENT ON COLUMN praxia_finanzas.fiscal_auditoria.origen IS
    'Distinguir mcp y n8n de dashboard es lo que permite responder, meses '
    'después, qué hizo un agente y qué hizo una persona.';

CREATE INDEX IF NOT EXISTS idx_fiscal_auditoria_entidad
    ON praxia_finanzas.fiscal_auditoria (entidad, entidad_id, creado_en DESC);

CREATE OR REPLACE FUNCTION praxia_finanzas.fiscal_auditoria_inmutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'La auditoría fiscal es append-only: no se puede % una fila.',
        lower(TG_OP)
        USING ERRCODE = 'raise_exception',
              HINT = 'Si un asiento de auditoría está mal, se agrega otro que lo explique.';
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.fiscal_auditoria_inmutable() IS
    'Invariante v4.0: la auditoría fiscal sólo crece. Corregir un asiento es '
    'agregar otro, nunca reescribir el anterior — reescribirlo destruiría '
    'exactamente el hecho que la auditoría existe para conservar.';

DROP TRIGGER IF EXISTS trg_faud_inmutable ON praxia_finanzas.fiscal_auditoria;
CREATE TRIGGER trg_faud_inmutable
    BEFORE UPDATE OR DELETE ON praxia_finanzas.fiscal_auditoria
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.fiscal_auditoria_inmutable();

-- =============================================================================
-- 10. fiscal_borradores — lo que produce el agente
-- =============================================================================

CREATE TABLE IF NOT EXISTS praxia_finanzas.fiscal_borradores (
    id              bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    cierre_id       bigint      NOT NULL
                                REFERENCES praxia_finanzas.fiscal_cierres(id) ON DELETE CASCADE,
    tipo            text        NOT NULL CHECK (tipo IN ('mensual','anual',
                                                         'checklist','observaciones')),
    generado_por    text        NOT NULL DEFAULT 'agente_fiscal',
    contenido       jsonb       NOT NULL DEFAULT '{}'::jsonb
                                CHECK (jsonb_typeof(contenido) = 'object'),
    recomendaciones jsonb       NOT NULL DEFAULT '[]'::jsonb
                                CHECK (jsonb_typeof(recomendaciones) = 'array'),

    supervisado_por text,
    supervisado_en  timestamptz,
    estado          text        NOT NULL DEFAULT 'borrador'
                                CHECK (estado IN ('borrador','revisado',
                                                  'aceptado','descartado')),
    creado_en       timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fiscal_borrador_supervision_completa
        CHECK ((supervisado_en IS NULL) = (supervisado_por IS NULL))
);

COMMENT ON TABLE praxia_finanzas.fiscal_borradores IS
    'La salida del agente fiscal: un borrador con su contenido y sus '
    'recomendaciones, atado a un cierre. Nace en estado `borrador` y sólo una '
    'persona lo mueve de ahí. Nota fija que acompaña a cada uno: "Borrador '
    'supervisado. No se presentó nada ante ningún organismo y ningún movimiento '
    'se modificó al generarlo."';

COMMENT ON COLUMN praxia_finanzas.fiscal_borradores.generado_por IS
    'Quién lo produjo. El default es el agente porque es el caso normal, y '
    'queda escrito para que nadie confunda un borrador automático con una '
    'revisión hecha por una persona.';
COMMENT ON COLUMN praxia_finanzas.fiscal_borradores.recomendaciones IS
    'Cada recomendación lleva qué pasa, por qué importa, cuántos casos, dónde '
    'mirar y requiere_decision_humana en true. Una recomendación sin "dónde '
    'mirar" obliga a rehacer el trabajo del agente a mano.';

CREATE INDEX IF NOT EXISTS idx_fiscal_borrador_cierre
    ON praxia_finanzas.fiscal_borradores (cierre_id, creado_en DESC);

-- =============================================================================
-- 11. Triggers de período: completar_periodo_fiscal / completar_periodo_comprobante
-- =============================================================================
-- INVARIANTE: todo hecho fiscal cae en un período, y el período se deriva de la
-- fecha salvo que alguien decida otra cosa.
--
-- El detalle importante está en el `IS NULL`: el trigger RELLENA el hueco, no
-- PISA la decisión. Un trigger que recalcula siempre haría imposible imputar a
-- mano una factura del 31 al mes siguiente, que es un caso normal y no un error.
-- =============================================================================

CREATE OR REPLACE FUNCTION praxia_finanzas.completar_periodo_fiscal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.periodo_fiscal IS NULL AND NEW.fecha IS NOT NULL THEN
        NEW.periodo_fiscal := (extract(year from NEW.fecha)::int * 100)
                              + extract(month from NEW.fecha)::int;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.completar_periodo_fiscal() IS
    'Deriva movimientos.periodo_fiscal (AAAAMM) desde la fecha, sólo si está '
    'vacío. Rellena el hueco; no pisa una imputación decidida a mano.';

DROP TRIGGER IF EXISTS trg_mov_periodo_fiscal ON praxia_finanzas.movimientos;
CREATE TRIGGER trg_mov_periodo_fiscal
    BEFORE INSERT OR UPDATE OF fecha, periodo_fiscal
    ON praxia_finanzas.movimientos
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.completar_periodo_fiscal();

CREATE OR REPLACE FUNCTION praxia_finanzas.completar_periodo_comprobante()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_fecha date := coalesce(NEW.fecha_imputacion, NEW.fecha_emision);
BEGIN
    IF NEW.periodo_fiscal IS NULL AND v_fecha IS NOT NULL THEN
        NEW.periodo_fiscal := (extract(year from v_fecha)::int * 100)
                              + extract(month from v_fecha)::int;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION praxia_finanzas.completar_periodo_comprobante() IS
    'Deriva comprobantes.periodo_fiscal desde fecha_imputacion y, si no la hay, '
    'desde fecha_emision. El orden de preferencia es la regla: para el cierre '
    'manda la imputación, no la emisión.';

DROP TRIGGER IF EXISTS trg_comprobante_periodo ON praxia_finanzas.comprobantes;
CREATE TRIGGER trg_comprobante_periodo
    BEFORE INSERT OR UPDATE OF fecha_emision, fecha_imputacion, periodo_fiscal
    ON praxia_finanzas.comprobantes
    FOR EACH ROW EXECUTE FUNCTION praxia_finanzas.completar_periodo_comprobante();

-- =============================================================================
-- 12. Las cuatro vistas fiscales
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_comprobantes
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_comprobantes AS
SELECT
    c.id,
    c.tipo,
    c.letra,
    c.punto_venta,
    c.numero,
    CASE
        WHEN c.punto_venta IS NOT NULL AND c.numero IS NOT NULL
        THEN lpad(c.punto_venta::text, 5, '0') || '-' || lpad(c.numero::text, 8, '0')
    END                                              AS numero_completo,
    c.sentido,
    c.fecha_emision,
    c.fecha_imputacion,
    coalesce(c.fecha_imputacion, c.fecha_emision)    AS fecha_computo,
    c.periodo_fiscal,
    c.moneda,
    c.total,
    c.iva_total,
    c.percepciones,
    c.retenciones,
    c.estado_validacion,
    c.cuit_emisor_parcial,
    c.razon_social_emisor,
    c.cuit_receptor_parcial,
    c.razon_social_receptor,
    c.cae,
    c.cae_vencimiento,
    c.sha256,
    (c.sha256 IS NOT NULL)                           AS tiene_respaldo,
    v.movimientos_vinculados,
    coalesce(v.total_imputado, 0)                    AS total_imputado,
    round(c.total - coalesce(v.total_imputado, 0), 2) AS descalce,
    coalesce(i.iva_por_alicuota, '[]'::jsonb)        AS iva_por_alicuota
FROM praxia_finanzas.comprobantes c
LEFT JOIN LATERAL (
    SELECT count(*)::int AS movimientos_vinculados,
           sum(coalesce(cm.importe_imputado, abs(m.monto))) AS total_imputado
    FROM praxia_finanzas.comprobante_movimientos cm
    JOIN praxia_finanzas.movimientos m ON m.id = cm.movimiento_id
    WHERE cm.comprobante_id = c.id
      AND m.estado <> 'anulado'
) v ON true
LEFT JOIN LATERAL (
    SELECT jsonb_agg(jsonb_build_object(
               'alicuota',       ci.alicuota,
               'base_imponible', ci.base_imponible,
               'importe',        ci.importe)
           ORDER BY ci.alicuota) AS iva_por_alicuota
    FROM praxia_finanzas.comprobante_iva ci
    WHERE ci.comprobante_id = c.id
) i ON true;

COMMENT ON VIEW praxia_finanzas.v_comprobantes IS
    'El comprobante con su numeración armada, su fecha de cómputo, sus '
    'movimientos vinculados, el total imputado y el IVA por alícuota agregado. '
    'La diferencia entre `total` y `total_imputado` es lo que el cierre reporta '
    'como descalce: no se corrige sola porque no hay forma honesta de saber si '
    'sobra la factura o falta el pago.';

COMMENT ON COLUMN praxia_finanzas.v_comprobantes.fecha_computo IS
    'La fecha que manda para el período: imputación si existe, emisión si no. '
    'Se calcula acá una sola vez para que ninguna consulta elija distinto.';

-- -----------------------------------------------------------------------------
-- v_movimientos_fiscal
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_movimientos_fiscal AS
SELECT
    m.id,
    m.fecha,
    m.descripcion,
    m.monto,
    m.moneda,
    m.tipo,
    m.estado,
    m.perfil_id,
    m.cuenta_id,
    m.categoria_id,
    m.periodo_fiscal,
    m.ambito,
    m.deducible,
    m.deducible_porcentaje,
    m.motivo_no_deducible,
    m.estado_fiscal,
    m.fiscal_actividad,
    m.fiscal_jurisdiccion,
    m.tratamiento_impositivo,
    -- monto_deducible: 0 si no es deducible; si lo es, el porcentaje aplicado.
    -- `deducible IS NOT TRUE` cubre el NULL a propósito: un movimiento sin
    -- clasificar no aporta deducción, y tratarlo como deducible sería inventar.
    CASE
        WHEN m.deducible IS NOT TRUE THEN 0::numeric
        ELSE round(abs(m.monto) * coalesce(m.deducible_porcentaje, 100) / 100.0, 2)
    END                                    AS monto_deducible,
    (m.ambito IS NULL OR m.deducible IS NULL) AS sin_encuadre,
    c.id                                   AS comprobante_id,
    c.tipo                                 AS comprobante_tipo,
    c.total                                AS comprobante_total,
    c.estado_validacion                    AS comprobante_estado,
    c.sha256                               AS comprobante_sha256,
    ir.canal                               AS canal
FROM praxia_finanzas.movimientos m
LEFT JOIN praxia_finanzas.comprobantes c  ON c.id  = m.comprobante_id
LEFT JOIN praxia_finanzas.ingesta_raw  ir ON ir.id = m.ingesta_id;

COMMENT ON VIEW praxia_finanzas.v_movimientos_fiscal IS
    'El movimiento con su ropa fiscal puesta: encuadre, período, comprobante, '
    'monto deducible calculado y el canal por el que entró. `sin_encuadre` es la '
    'columna que mira el motor para saber sobre qué tiene que pedir criterio.';

COMMENT ON COLUMN praxia_finanzas.v_movimientos_fiscal.monto_deducible IS
    'Cero cuando deducible no es exactamente true. El NULL cuenta como cero a '
    'propósito: un movimiento sin clasificar no aporta deducción, y suponerlo '
    'deducible sería convertir una ausencia de dato en un dato.';
COMMENT ON COLUMN praxia_finanzas.v_movimientos_fiscal.canal IS
    'De dónde vino el movimiento: telegram, dashboard, pdf, csv, excel, email o '
    'agente. Sale de la ingesta, que es la única puerta de entrada.';

-- -----------------------------------------------------------------------------
-- v_fiscal_periodo
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_fiscal_periodo AS
SELECT
    m.periodo_fiscal,
    m.moneda,
    count(*) FILTER (WHERE m.tipo = 'ingreso')::int              AS n_ingresos,
    count(*) FILTER (WHERE m.tipo = 'gasto')::int                AS n_gastos,
    coalesce(sum(abs(m.monto)) FILTER (WHERE m.tipo = 'ingreso'), 0) AS ingresos,
    coalesce(sum(abs(m.monto)) FILTER (WHERE m.tipo = 'gasto'), 0)   AS gastos,
    coalesce(sum(abs(m.monto)) FILTER (
        WHERE m.tipo = 'gasto' AND m.ambito IN ('profesional','mixto')), 0)
                                                                 AS gastos_profesionales,
    coalesce(sum(round(abs(m.monto) * coalesce(m.deducible_porcentaje, 100) / 100.0, 2))
             FILTER (WHERE m.tipo = 'gasto' AND m.deducible IS TRUE), 0)
                                                                 AS gastos_deducibles,
    count(*) FILTER (WHERE m.estado_fiscal = 'sin_clasificar')::int AS sin_clasificar,
    count(*) FILTER (WHERE m.estado_fiscal = 'observado')::int      AS observados,
    count(*) FILTER (WHERE m.estado = 'pendiente')::int             AS pendientes,
    count(*) FILTER (WHERE m.tipo = 'ingreso' AND m.comprobante_id IS NULL)::int
                                                                 AS ingresos_sin_comprobante,
    count(*) FILTER (WHERE m.tipo = 'gasto'
                       AND m.ambito IN ('profesional','mixto')
                       AND m.comprobante_id IS NULL)::int        AS gastos_prof_sin_comprobante
FROM praxia_finanzas.movimientos m
WHERE m.estado <> 'anulado'
  AND m.tipo   <> 'transferencia'
GROUP BY m.periodo_fiscal, m.moneda;

COMMENT ON VIEW praxia_finanzas.v_fiscal_periodo IS
    'Totales del período. Excluye anulados y transferencias: una transferencia '
    'no es un gasto y contarla infla el resultado del mes sin que nadie lo note. '
    'Agrupa POR MONEDA porque pesos y dólares no se suman nunca: si el total del '
    'mes fuera un solo número, alguien tendría que haber elegido una cotización, '
    'y ninguna cotización se inventa.';

-- -----------------------------------------------------------------------------
-- v_fiscal_iva_periodo
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW praxia_finanzas.v_fiscal_iva_periodo AS
SELECT
    c.periodo_fiscal,
    c.sentido,
    ci.alicuota,
    count(DISTINCT c.id)::int      AS comprobantes,
    sum(ci.base_imponible)         AS base_imponible,
    sum(ci.importe)                AS iva,
    sum(ci.importe) FILTER (WHERE c.sentido = 'recibido') AS credito_fiscal,
    sum(ci.importe) FILTER (WHERE c.sentido = 'emitido')  AS debito_fiscal
FROM praxia_finanzas.comprobantes c
JOIN praxia_finanzas.comprobante_iva ci ON ci.comprobante_id = c.id
WHERE c.estado_validacion <> 'anulado'
GROUP BY c.periodo_fiscal, c.sentido, ci.alicuota;

COMMENT ON VIEW praxia_finanzas.v_fiscal_iva_periodo IS
    'IVA por período, sentido y alícuota, con crédito (recibido) y débito '
    '(emitido) separados. Es la forma del libro IVA. Separar por alícuota no es '
    'un lujo: un total único impide reconstruir la declaración y esconde el caso '
    'de la factura con 21% y 10,5% mezclados.';

-- =============================================================================
-- 13. Permisos de las tablas nuevas
-- =============================================================================
-- Los privilegios por defecto del archivo 06 ya otorgan SELECT/INSERT/UPDATE
-- sobre todo lo que se cree después. Acá se ajustan las tres excepciones que
-- el diseño real define, y que son las interesantes:
--
--   · fiscal_reglas    → SÓLO SELECT. Son normativa: las carga un administrador,
--                        no la API y mucho menos el agente.
--   · fiscal_auditoria → SELECT + INSERT. Escribir y leer, nunca corregir. El
--                        trigger ya lo impide; el permiso lo impide antes.
--   · los dos puentes  → además DELETE, porque desvincular un comprobante de un
--                        movimiento no destruye evidencia: los dos siguen ahí.
-- =============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'praxia_finanzas_rw') THEN
        EXECUTE 'REVOKE INSERT, UPDATE ON praxia_finanzas.fiscal_reglas FROM praxia_finanzas_rw';
        EXECUTE 'GRANT  SELECT ON praxia_finanzas.fiscal_reglas TO praxia_finanzas_rw';

        EXECUTE 'REVOKE UPDATE ON praxia_finanzas.fiscal_auditoria FROM praxia_finanzas_rw';
        EXECUTE 'GRANT  SELECT, INSERT ON praxia_finanzas.fiscal_auditoria TO praxia_finanzas_rw';

        EXECUTE 'GRANT  DELETE ON praxia_finanzas.comprobante_movimientos TO praxia_finanzas_rw';
        EXECUTE 'GRANT  DELETE ON praxia_finanzas.comprobante_iva TO praxia_finanzas_rw';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'praxia_finanzas_ro') THEN
        EXECUTE 'GRANT SELECT ON ALL TABLES IN SCHEMA praxia_finanzas TO praxia_finanzas_ro';
        EXECUTE 'GRANT EXECUTE ON FUNCTION praxia_finanzas.fiscal_perfiles_vigentes(text, date) '
                'TO praxia_finanzas_ro';
    END IF;
END;
$$;

-- =============================================================================
-- 14. Registro de la migración
-- =============================================================================

INSERT INTO praxia_finanzas.schema_migrations (version, descripcion) VALUES
    ('v4.0-nucleo', 'Núcleo fiscal reconstruido: perfiles, comprobantes, IVA por '
                    'alícuota, puentes, reglas, obligaciones, cierres, auditoría '
                    'append-only, borradores y las cuatro vistas fiscales')
ON CONFLICT (version) DO NOTHING;

COMMIT;

-- =============================================================================
-- Lo que NO está en este archivo, a propósito
--
-- · `documentos` y su columna `ruta` («ruta interna, NUNCA una URL pública»).
-- · `contribuyentes` con FK real y las funciones de v4.9 (`regimen_vigente()`,
--   `perfil_fiscal_sin_solapamiento()`, `imputacion_mismo_contribuyente()`).
-- · `catalogo_obligaciones`, `dias_no_habiles`, `terminacion_cuit` y
--   `vencimiento_habil()` (v4.11 y v4.12).
-- · `fiscal_exportaciones` (v4.2) y las plantillas recurrentes (v4.6, v4.10).
-- · El mecanismo real de cifrado del CUIT.
--
-- Producción tiene 39 tablas en v4.13. Acá hay las suficientes para entender
-- cómo se sostiene un cierre, y no las suficientes para reproducir el sistema.
-- =============================================================================
