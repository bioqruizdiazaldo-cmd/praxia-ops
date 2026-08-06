# La capa de lectura — las nueve operaciones

La capa de lectura es todo lo que el Agente Fiscal puede ver de PraxIA Finanzas. Son nueve operaciones con nombre fijo, parámetros validados y una forma de respuesta única, implementadas en un módulo sin dependencias externas del que no puede salir una escritura. Cada operación devuelve, además del dato, lo que el dato no dice de sí mismo: advertencias fijas y discrepancias detectadas.

Implementación: `api/fiscal_lectura.mjs` (~62 KB, ~1400 líneas). Constantes del módulo: `CONTRACT_VERSION = '1.0'`, `SOURCE_SYSTEM = 'praxia-finanzas-core'`, `AGENT_ROLE = 'fiscal_reader'`, `TZ_NEGOCIO = 'America/Argentina/Cordoba'`. Única dependencia: `node:crypto`. El pool de `pg` llega por parámetro, no se instancia acá.

---

## El guardia de solo lectura

Toda consulta pasa por una sola función, y esa función no deja pasar nada que no sea una lectura.

```js
export async function ejecutar(pool, sql, params = []) {
  const limpio = String(sql).trim();
  if (!/^(SELECT|WITH)\b/i.test(limpio)) throw new Error('fiscal_lectura: solo se permiten consultas SELECT o WITH');
  if (limpio.includes(';')) throw new Error('fiscal_lectura: el punto y coma está prohibido (una sentencia por consulta)');
  return pool.query(limpio, params);
}
```

Dos reglas, y la segunda es la que importa: prohibir el punto y coma impide que una consulta legítima arrastre una segunda sentencia detrás. Sin eso, `SELECT` seguido de `; UPDATE` pasaría el primer filtro.

> *«No confía en el rol de base de datos: aunque el operador desplegara esta capa con un usuario con permisos de escritura por error, desde acá no sale un INSERT. El rol de solo lectura es la segunda barrera, no la única.»*
> — `api/fiscal_lectura.mjs`, comentario del guardia

Es un caso raro y sano de defensa en profundidad invertida: la barrera de aplicación existe **porque** la barrera de infraestructura todavía no está desplegada (ver [limites-y-deudas.md](limites-y-deudas.md)), y seguirá existiendo cuando lo esté.

---

## Las nueve operaciones

| # | Nombre exacto | Parámetros | Devuelve | TZ |
|---|---|---|---|---|
| 1 | `ConsultarMovimientosConfirmados` | `desde`, `hasta` (oblig.); `moneda`, `cuenta`, `categoria`, `proyecto`, `limite`, `cursor` | Movimientos con `estado='confirmado'`: id, fecha, direccion, monto_original, moneda, tc_usado, fuente_tc, monto_usd, descripcion, estado, es_transferencia, más los códigos de cuenta, categoría, proyecto y perfil | UTC |
| 2 | `ConsultarMovimientosPendientes` | `desde`, `hasta`; `moneda`, `cuenta`, `monto_minimo`, `situacion` ∈ {`todos`, `pendiente`, `revision`} | Lo mismo más `requiere_revision` y `review_reason` | UTC |
| 3 | `ConsultarDeuda` | Mínimo `estado` **o** un extremo de vencimiento; `tipo`, `perfil_id`, `plan_pago_id` | 26 columnas de `deudas_pendientes` más el booleano calculado `vencida`. Orden por vencimiento ascendente | Córdoba |
| 4 | `ConsultarPagosDeDeuda` | `deuda_id` (oblig.); `estado` ∈ {`activa`, `anulada`}, `fecha_desde`, `fecha_hasta` | Filas de `deuda_pagos` con los datos del movimiento asociado | UTC |
| 5 | `ConsultarObligacionesFiscales` | `periodo` AAAAMM (oblig.); `periodo_hasta`, `impuesto`, `estado` (8 válidos) | `fiscal_obligaciones` con importes estimado, determinado y pagado, más las referencias a comprobantes y movimiento de pago | Córdoba |
| 6 | `ConsultarDocumentosAsociados` | `entidad` ∈ {`obligacion`, `movimiento`, `plan_pago`}, `entidad_id`, `tipo_doc` | Metadata del documento más `sha256` y `contenido_disponible`. **Nunca `ruta`** | UTC |
| 7 | `ConsultarCambiosHistoricos` | `entidad` (7 válidas), `entidad_id`, `desde`, `hasta`, `actor` | Líneas normalizadas de la tabla de auditoría **correcta**, con `tabla_origen` en cada fila | UTC |
| 8 | `ConsultarResumenPorPeriodo` | `desde_mes`, `hasta_mes` (YYYY-MM), `agrupar_por` ∈ {`categoria`, `proyecto`, `cuenta`, `perfil`} | Sumatorias por mes, grupo y **moneda** | Córdoba |
| 9 | `ConsultarDiscrepanciasAbiertas` | `severidad` ∈ {`alta`, `media`, `baja`}, `tipo` | Hallazgos de los 13 detectores, ordenados por severidad, cada uno con las **dos** evidencias del choque | UTC |

Las zonas horarias no son un detalle de formato. Las operaciones que trabajan con **vencimientos y períodos fiscales** usan `America/Argentina/Cordoba`, porque un vencimiento es una fecha de calendario del negocio. Las que trabajan con **hechos registrados** usan UTC, porque un hecho ocurrió en un instante. Mezclarlas produce vencimientos corridos un día, que es una de las siete instancias catalogadas del patrón "falla en silencio".

---

## Operación por operación

### 1 · `ConsultarMovimientosConfirmados`

Solo `estado='confirmado'`. Lo pendiente y lo anulado no aparecen acá, y eso es deliberado: es la operación sobre la que se apoyan los totales.

La regla de moneda del contrato aplica de lleno:

> *«Moneda: Original conservada; no sumar monedas distintas sin política aprobada.»*
> — Contrato §7

Devuelve `monto_original` y `moneda` juntos, y además `tc_usado`, `fuente_tc` y `monto_usd` cuando existen, para que quien consuma pueda ver **con qué tipo de cambio y de dónde salió** cualquier conversión, en lugar de recibir un número ya convertido sin procedencia.

Es la única operación de la lista, junto con la 2, que expone paginación completa por cursor.

### 2 · `ConsultarMovimientosPendientes`

Agrega `requiere_revision` y `review_reason`, y el parámetro `situacion` para pedir solo lo pendiente, solo lo que está en revisión, o ambas cosas.

**Advertencia fija:** los movimientos pendientes **no integran saldos ni totales fiscales**. Va en `warnings` siempre, incluso cuando la lista viene vacía. La razón es que un pendiente se parece mucho a un confirmado en la pantalla, y sumarlo a un total es exactamente el tipo de error que nadie nota.

### 3 · `ConsultarDeuda`

Exige **como mínimo** un `estado` o un extremo de vencimiento. No hay forma de pedir "toda la deuda": un listado sin filtro invita a leerlo como exhaustivo.

Devuelve 26 columnas de `deudas_pendientes` más un booleano calculado `vencida`, que se resuelve contra la fecha de Córdoba y no contra UTC. Orden por vencimiento ascendente, porque lo primero que hay que ver es lo que vence antes.

Caso borde heredado del Anexo A.2: `deudas_pendientes` **no tiene** `proveedor_id`, `cliente_id`, `categoria_id` ni `proyecto_id`, aunque el cuerpo del contrato los mencionaba. Los filtros por esas dimensiones no existen porque las columnas no existen.

### 4 · `ConsultarPagosDeDeuda`

Requiere `deuda_id`: no se listan pagos sueltos. Devuelve las filas de `deuda_pagos` junto con los datos del movimiento que las respalda.

**Emite discrepancias en dos casos:**

- La deuda figura como **pagada y no tiene pagos registrados**. Es el detector `deuda_pagada_sin_evidencia`, severidad alta.
- El pago está en una **moneda distinta** de la de la deuda. Es `moneda_inconsistente_en_imputacion`, severidad alta, y corresponde a la decisión #1 del ADR: una obligación en USD **no se cancela** con un movimiento en ARS. Se imputa en `obligacion_cargos` sin tocar saldo, y la capa fiscal lo reporta en lugar de resolverlo.

Caso borde del Anexo A.1: `deuda_pagos` solo tiene los estados `activa` y `anulada`. Los tres estados que el contrato describía (`confirmado`, `conciliado`, `anulado`) no existen.

### 5 · `ConsultarObligacionesFiscales`

`periodo` en formato AAAAMM es obligatorio; `periodo_hasta` permite un rango. Los estados válidos son **ocho**, no los cinco del §9 del contrato — otra corrección del Anexo A.

Devuelve los tres importes por separado: `importe_estimado`, `importe_determinado` e `importe_pagado`. Que estén separados es la aplicación literal de la obligación del §3 de *calcular estimaciones identificadas estrictamente como tales*. Un estimado nunca ocupa el lugar de un determinado.

### 6 · `ConsultarDocumentosAsociados`

Devuelve metadata, `sha256` y el booleano `contenido_disponible`. **Nunca devuelve `ruta`.** La columna está comentada en el esquema como *«ruta interna, NUNCA una URL pública»*, y hay un test dedicado a verificar que no se filtre por esta vía.

El caso borde más interesante del subsistema está acá. Como **no existe tabla puente movimiento ↔ documento** (Anexo A.2), para la entidad `movimiento` la operación resuelve por `ingesta_raw` y devuelve `via: 'ingesta_raw'` junto con una advertencia explícita de que **eso no es una asociación declarada**: es el archivo que entró por el mismo canal, no una vinculación que alguien haya afirmado.

La alternativa habría sido devolver el documento sin aclaración, y habría sido plausible y equivocada.

### 7 · `ConsultarCambiosHistoricos`

Siete entidades válidas. Como hay **tres** tablas de auditoría y no una, la operación tiene que elegir la correcta según la entidad pedida, y devuelve `tabla_origen` en **cada fila** para que el consumidor sepa de dónde salió cada línea en lugar de recibir un historial homogéneo aparente.

Hay un test específico que verifica que cada entidad se resuelva contra la tabla de auditoría que le corresponde.

### 8 · `ConsultarResumenPorPeriodo`

Agrupa por mes, por la dimensión pedida y **por moneda**, siempre. No hay opción de sumar monedas.

Dos comportamientos que la distinguen:

- Los meses sin datos vienen con **ceros explícitos** y la marca `sin_datos: true`. Un mes ausente del array se lee como cero; un mes presente con `sin_datos` se lee como "no hay registros", que es una afirmación distinta.
- **No tiene paginación.** Es la única de las nueve. Un resumen paginado sería un resumen parcial, y un resumen parcial se lee como el total.

### 9 · `ConsultarDiscrepanciasAbiertas`

Corre los trece detectores y devuelve los hallazgos ordenados por severidad, cada uno con las dos evidencias que chocan. Es la operación cuya semántica el contrato se molestó en acotar por escrito:

> *«Una lista vacía significa únicamente que no existen discrepancias abiertas registradas o detectadas según las fuentes, reglas y alcance consultados. No demuestra por sí sola la ausencia de errores, omisiones o discrepancias no detectadas.»*
> — Contrato §7

---

## Los trece detectores

| Detector | Severidad | Qué choca |
|---|---|---|
| `deuda_pagada_sin_evidencia` | Alta | La deuda dice pagada; no hay pagos |
| `saldo_incoherente` | Alta | El saldo no cierra contra sus movimientos |
| `moneda_inconsistente_en_imputacion` | Alta | Se imputa un pago en una moneda distinta de la obligación |
| `movimiento_sin_clasificacion_fiscal` | Alta | Movimiento confirmado sin encuadre fiscal |
| `posible_separador_de_miles_mal_leido` | Alta | Dos importes que son el mismo número leído con coma decimal y con punto de miles |
| `movimiento_no_coincide_con_su_comprobante` | Alta | El importe del movimiento no coincide con el del comprobante vinculado |
| `obligacion_vencida_sin_pago` | Media | Deuda vencida sin pago |
| `fiscal_obligacion_vencida_sin_pago` | Media | Obligación fiscal vencida sin pago |
| `comprobante_duplicado_por_archivo` | Media | Dos comprobantes con el mismo archivo |
| `comprobante_duplicado_fuera_del_indice` | Media | Duplicado que el índice único parcial no alcanza a cubrir |
| `movimiento_sin_categoria` | Media | Movimiento sin categoría asignada |
| `obligacion_sin_periodo_imputable` | Media | Obligación que no se puede imputar a un período |
| `movimiento_pendiente_antiguo` | Baja | Pendiente que quedó viejo |

Dos de ellos —`posible_separador_de_miles_mal_leido` y `movimiento_no_coincide_con_su_comprobante`— se agregaron en la v4.8, llevando la cuenta de 11 a 13, después de que apareciera un caso real de importe mal parseado.

`posible_separador_de_miles_mal_leido` tiene un archivo de test propio con 13 casos: verifica la detección del par, la severidad alta, que el detector **no elija cuál de los dos está mal**, la ventana de días, que la anulación apague el hallazgo, que el comprobante sirva como evidencia, y que una imputación parcial no permita afirmar nada.

---

## Abstención total ante fallo de un detector

Si **cualquiera** de los trece detectores falla, la operación entera devuelve `SOURCE_UNAVAILABLE`. No devuelve los doce que sí corrieron.

> *«un resultado parcial se leería como "no hay discrepancias"»*

Es la misma lógica que gobierna `diagnosticarPeriodo` en el motor: *«Un diagnóstico parcial se leería como "no falta nada más". Abstención.»* La forma correcta de fallar en un sistema de control es dejar de responder, no responder menos.

---

## Paginación por cursor

- Cursor opaco en **base64url** que codifica `{o: offset}`.
- Límite por defecto **100**, tope **500**.
- Se piden `limite + 1` filas para saber si hay más **sin ejecutar un `COUNT(*)`**. El registro extra no se devuelve: se descarta y se usa para poblar `has_more`.
- `next_cursor` y `has_more` viajan en el bloque `pagination` del envelope.

Hay tests que recorren un conjunto entero paginando y verifican que **no se repita ni se saltee ninguna fila**, que es el fallo silencioso clásico de la paginación por offset.

`ConsultarResumenPorPeriodo` es la excepción: no pagina.

---

## El envelope

Toda respuesta sale de `envelope()`, con o sin error, con o sin datos:

```
contract_version · request_id · generated_at · source_system · data_as_of
status · operation · records · source_record_ids
warnings · discrepancies
pagination { next_cursor, has_more }
trace_context { agent_role, query_hash, zona_horaria_negocio }
```

Dos campos merecen atención:

- **`request_id`** es único por llamada (`req_` + 12 hex) y sirve para correlacionar con la línea de auditoría.
- **`query_hash`** es **estable** para la misma consulta con los mismos parámetros. Hay un test que verifica exactamente esa asimetría: `request_id` único vs. `query_hash` estable. Sirve para reconocer que dos respuestas distintas contestan la misma pregunta.

Los nueve códigos de abstención del §15 —`RECORD_NOT_FOUND`, `INSUFFICIENT_EVIDENCE`, `UNAUTHORIZED_ACCESS`, `INCOMPATIBLE_CONTRACT_VERSION`, `CORRUPT_DATA`, `UNKNOWN_CURRENCY`, `AMBIGUOUS_PERIOD`, `SOURCE_UNAVAILABLE`, `INVALID_DATE_RANGE`— viajan dentro del mismo envelope con `status: 'error'`. No hay un formato de error aparte.

---

## Cómo se llama

### Por HTTP

Nueve rutas, **todas GET**. El mapa `RUTAS` vive en `fiscal_lectura.mjs` y el enrutado en `api/server.mjs`:

```
/api/fiscal-lectura/movimientos-confirmados
/api/fiscal-lectura/movimientos-pendientes
/api/fiscal-lectura/deuda
/api/fiscal-lectura/deuda-pagos
/api/fiscal-lectura/obligaciones-fiscales
/api/fiscal-lectura/documentos
/api/fiscal-lectura/cambios-historicos
/api/fiscal-lectura/resumen-periodo
/api/fiscal-lectura/discrepancias
```

- Cualquier verbo distinto de GET → **405**.
- `status === 'error'` en el envelope → **HTTP 422**. El envelope viaja igual: el cliente recibe el código de abstención, no una página de error.
- **`actor` sale de la credencial** (`scope:<scope>`), nunca del body ni del query string.
- **`proposito`** lo declara el cliente y es obligatorio.

### Por MCP

Servidor MCP propio (`mcp/src/tools.ts`), nueve tools bajo el scope `praxia.fiscal.read`:

```
fiscal_movimientos_confirmados · fiscal_movimientos_pendientes · fiscal_deuda
fiscal_deuda_pagos · fiscal_obligaciones · fiscal_documentos
fiscal_cambios_historicos · fiscal_resumen_periodo · fiscal_discrepancias
```

Cada tool fija `actor = 'agente_fiscal'` y exige `proposito` de al menos 3 caracteres. Y devuelve el envelope **sin tocarlo**:

> *«el MCP no lo reinterpreta ni lo resume, porque las advertencias y las discrepancias son parte de la respuesta, no decoración.»*

Es una decisión con costo: el modelo recibe más texto del que "necesita" para contestar. El costo se paga a propósito, porque un resumen del envelope hecho por la capa de transporte es exactamente donde desaparecerían las advertencias.

---

## La auditoría de consulta

`auditarConsulta()` emite **una línea JSON al log del proceso** por cada operación, con:

| Campo | |
|---|---|
| `ts_utc` | Instante de la consulta |
| `contract_version` | Versión del contrato |
| `operacion` | Cuál de las nueve |
| `actor` | Sale de la credencial |
| `proposito` | Lo declara el cliente |
| `request_id` | Correlación con la respuesta |
| `query_hash` | Identidad de la pregunta |
| `status` | `ok` / `error` |
| Cantidad de registros | Cuántas filas se devolvieron |
| `source_record_ids` | Qué IDs concretos se leyeron |

### Por qué NO se persiste en la base

> *«el rol fiscal es de solo lectura y escribir una fila de auditoría sería una escritura.»*

Es la consecuencia honesta de tomarse en serio "solo lectura". La alternativa —hacer una excepción de INSERT para la tabla de auditoría— habría abierto exactamente el permiso que el diseño intenta no tener, y la excepción sería difícil de defender después: si el agente puede insertar en una tabla, la pregunta pasa a ser cuál.

La deuda queda declarada y con solución propuesta:

> *«Escribirla en una tabla exigiría permiso de INSERT, que es justamente lo que el rol fiscal no debe tener. Si se necesita persistirla, debe hacerlo un componente aparte que recoja el log.»*
> — Anexo A.5

Ver [limites-y-deudas.md](limites-y-deudas.md).

---

## Qué cubren los tests

| Archivo | Casos | Foco |
|---|---|---|
| `tests/test_fiscal_lectura.mjs` | 23 | Guardia `SELECT`/`WITH` y punto y coma · envelope · `request_id` único vs. `query_hash` estable · los 9 códigos del §15 · validaciones · cursor · auditoría · abstención ante base caída · existencia de las 9 operaciones · detectores sin repetidos |
| `tests/test_fiscal_lectura_sql.mjs` | 21 | Las 9 operaciones contra el esquema replicado con datos sembrados: filtros, paginación sin repetir ni saltear, `ruta` nunca expuesta, tabla de auditoría correcta por entidad, monedas no sumadas, ceros explícitos, detectores |
| `tests/test_detector_separador.mjs` | 13 | El detector de separador de miles, caso por caso |

El arnés (`tests/harness/esquema.mjs`) levanta PGlite y aplica el DDL consolidado más las migraciones en el orden real de producción:

> *«una prueba con un pool falso valida la forma de la respuesta, pero no detecta que una columna no existe o que un JOIN está mal escrito. Esto sí.»*

---

## Documentos relacionados

- [Ficha del subsistema](README.md)
- [El contrato v1.0](contrato-finanzas-fiscal.md)
- [Motor de precedentes](motor-de-precedentes.md)
- [Seguridad y permisos](seguridad-y-permisos.md)
- [Cuándo uso un MCP](../../docs/02-desglose-tecnico/04-cuando-uso-un-mcp.md)
- [Cuándo uso una API propia](../../docs/02-desglose-tecnico/05-cuando-uso-una-api-propia.md)
- [Testing y evidencia](../../docs/02-desglose-tecnico/09-testing-y-evidencia.md)

> Última verificación: 2026-08-06
