# Contrato de integración PraxIA Finanzas ↔ Agente Fiscal v1.0

El contrato es el documento que define qué puede ver el Agente Fiscal, qué puede pedir, qué está obligado a devolver cuando no sabe, y qué tiene prohibido hacer para siempre. Se aprobó el 2026-08-04 y desde entonces gobierna el código: cada operación de lectura, cada código de error y cada campo del envelope tienen un número de sección detrás.

**Versión:** 1.0 · **Estado:** Aprobado · **Aprobado por:** el titular, 2026-08-04 · **Alcance:** *«Contrato lógico y técnico de solo lectura»*

---

## Por qué existe un contrato y no una lista de endpoints

Un contrato de integración entre dos sistemas del mismo dueño puede parecer burocracia. No lo es cuando uno de los dos lados es un agente de IA: sin contrato, el alcance del agente es lo que el código permita hoy, y "lo que el código permita hoy" cambia con cada refactor. Por eso el §16 dice:

> *«Está prohibido introducir cambios silenciosos al contrato por refactors del código contable subyacente.»*

La fuente de verdad financiera es una sola:

> *«PraxIA Finanzas es la única fuente de verdad financiera. No existen sistemas paralelos.»*
> — §2

---

## Las 21 secciones

| § | Título | Qué fija |
|---|---|---|
| 1 | Propósito | Para qué se consulta: detectar obligaciones emergentes, preparar borradores, estimar vencimientos, señalar inconsistencias, proponer clasificaciones, preparar reportes y solicitar aprobación humana |
| 2 | Principios no negociables | Las reglas que no se discuten por caso (ver abajo) |
| 3 | Propiedad y responsabilidades | Qué garantiza Finanzas, a qué se obliga el Fiscal, qué hace el Aprobador Humano |
| 4 | Clasificación de datos | Qué categorías de dato existen y cómo se tratan |
| 5 | Entidades financieras relevantes | Las 10 tablas que el Fiscal puede consultar |
| 6 | Garantías arquitectónicas | Las no-consecuencias: crear una cosa no crea otra |
| 7 | Contrato lógico de consulta | Las 9 operaciones, con parámetros, semántica y advertencias fijas |
| 8 | Envelope | La forma obligatoria de toda respuesta |
| 9 | Estados y semántica | Qué significa cada estado de cada entidad |
| 10 | Propuestas fiscales | Cómo se formula una propuesta y qué NO pasa al aprobarla |
| 11 | Trazabilidad | `actor` y `proposito` obligatorios en todo |
| 12 | Idempotencia | Claves de identidad y qué no se puede reutilizar |
| 13 | Discrepancias | 8 categorías de choque de evidencia y cómo se tratan |
| 14 | Seguridad y permisos | Mínimo privilegio, credenciales, auditoría de consulta |
| 15 | Errores y abstención | Los 9 códigos con los que el agente dice "no sé" |
| 16 | Versionado | Cómo se cambia el contrato y qué está prohibido |
| 17 | Fuera de alcance v1 | 12 cosas que el agente no hace en esta versión |
| 18 | Criterios de aceptación futura | Qué habría que cumplir para ampliar el alcance |
| 19 | Riesgos abiertos | 11 decisiones que siguen siendo del titular |
| 20 | Diagrama de frontera | Qué lee, qué escribe, dónde está la persona |
| 21 | Matriz de permisos | Operación por operación, quién puede qué |

Más el **Anexo A**, agregado el 2026-08-04 después de la aprobación, con cinco sub-secciones.

El texto completo de §4, §9, §18, §20 y §21 no fue transcripto en la auditoría de origen; lo que sigue de esas secciones es lo verificado, y lo que falta va marcado.

---

## §2 — Los principios no negociables

Son cinco frases cortas. Cada una tiene un mecanismo concreto en el código.

| Principio (cita textual, §2) | Dónde vive en el código |
|---|---|
| *«PraxIA Finanzas es la única fuente de verdad financiera. No existen sistemas paralelos.»* | El Fiscal no tiene tablas propias salvo `fiscal_propuestas`, y esa no participa de ningún cálculo de saldo |
| *«Toda corrección debe formularse como propuesta.»* | `fiscal_propuestas` con 6 tipos y estado `pendiente` obligatorio al nacer |
| *«Toda acción con impacto financiero o fiscal requiere aprobación humana.»* | 403 duro del token fiscal sobre `/api/fiscal-propuestas/decidir` |
| *«La ausencia de datos no debe convertirse en un dato inventado.»* | Los 9 códigos de abstención del §15 y la abstención total ante fallo de un detector |
| *«Las discrepancias deben conservar ambas evidencias y nunca resolverse sobrescribiendo datos conflictivos de forma unilateral.»* | Cada hallazgo de `ConsultarDiscrepanciasAbiertas` viaja con las **dos** evidencias del choque |

Y el marco general, del §1:

> *«Este contrato no autoriza correcciones automáticas, la generación de asientos ni alteraciones de ningún tipo sobre el núcleo de PraxIA Finanzas.»*

---

## §3 — Quién garantiza qué

### Lo que garantiza PraxIA Finanzas

- Conserva los movimientos originales y su conciliación.
- Administra cuentas, saldos, deudas recurrentes y pagos reales.
- Mantiene la evidencia documental.
- Confirma los pagos reales aplicados.
- Conserva el historial y la pista de auditoría.

### A lo que se obliga el Agente Fiscal

- Consultar bajo **mínimo privilegio**.
- Interpretar las consecuencias fiscales de hechos financieros.
- Generar borradores y propuestas.
- Detectar faltantes documentales y solicitar documentación.
- Calcular estimaciones **identificadas estrictamente como tales**.
- **Nunca modificar la evidencia financiera original.**

### Qué hace el Aprobador Humano

> *«Acepta o rechaza la propuesta y registra una justificación. La aprobación no modifica datos ni ejecuta acciones. […] ARCA permanece fuera del alcance de v1.»*
> — §3

---

## §6 — Las garantías arquitectónicas

Cuatro no-consecuencias explícitas, todas en la misma cita:

> *«Crear una obligación no crea automáticamente un movimiento. […] Crear una obligación no crea automáticamente un pago. […] Registrar una propuesta fiscal no altera saldos. […] No debe existir doble contabilización.»*
> — §6

Son el antídoto contra el atajo más tentador de cualquier sistema contable automatizado: derivar el hecho del registro. Acá el registro de una obligación es una expectativa, no un hecho consumado, y hay que ir a buscar el hecho por separado.

---

## §5 — Sobre qué se consulta

Diez tablas declaradas como entidades financieras relevantes. La nota más importante es sobre `movimientos`:

> *«No afirmar que los movimientos son técnicamente inmutables si el sistema admite cambios auditados.»*
> — §5

Es la clase de honestidad que hace útil un contrato: el sistema **sí** admite modificar un movimiento por vía auditada, y decir lo contrario en la documentación crearía una garantía falsa sobre la que alguien construiría después.

---

## §7 y §8 — La consulta y su envelope

El §7 define las nueve operaciones de lectura. Están documentadas una por una en [capa-de-lectura.md](capa-de-lectura.md). Dos citas del §7 que condicionan todo lo demás:

> *«Moneda: Original conservada; no sumar monedas distintas sin política aprobada.»*
> — §7, `ConsultarMovimientosConfirmados`

> *«Una lista vacía significa únicamente que no existen discrepancias abiertas registradas o detectadas según las fuentes, reglas y alcance consultados. No demuestra por sí sola la ausencia de errores, omisiones o discrepancias no detectadas.»*
> — §7, `ConsultarDiscrepanciasAbiertas`

### El envelope del §8

Toda respuesta —correcta o no— sale con la misma estructura. No hay "respuesta simple" ni atajo para el caso feliz.

| Campo | Contenido | Para qué está |
|---|---|---|
| `contract_version` | `'1.0'` | Que el cliente sepa contra qué contrato está hablando |
| `request_id` | `req_` + 12 hex | Correlacionar la respuesta con la línea de auditoría |
| `generated_at` | Timestamp de generación | Cuándo se armó la respuesta |
| `source_system` | `'praxia-finanzas-core'` | Quién respondió |
| `data_as_of` | Corte de los datos | Hasta cuándo son válidos |
| `status` | `ok` / `error` | Sin ambigüedad |
| `operation` | Nombre de la operación | Qué se preguntó |
| `records` | Las filas | El dato |
| `source_record_ids` | Los IDs concretos leídos | Poder rehacer la consulta a mano |
| `warnings` | Advertencias | Incluidas las **fijas** por operación, que van siempre |
| `discrepancies` | Choques de evidencia detectados en esta consulta | Lo que el dato no dice de sí mismo |
| `pagination` | `{ next_cursor, has_more }` | Paginación por cursor |
| `trace_context` | `{ agent_role, query_hash, zona_horaria_negocio }` | Quién preguntó, qué preguntó y bajo qué huso |

El detalle relevante: `warnings` y `discrepancies` **no son opcionales ni decorativos**. El servidor MCP devuelve el envelope tal cual, *«el MCP no lo reinterpreta ni lo resume, porque las advertencias y las discrepancias son parte de la respuesta, no decoración.»*

---

## §11 y §12 — Trazabilidad e idempotencia

**§11** exige `actor` y `proposito` en toda operación y en toda propuesta. En la tabla `fiscal_propuestas` ambos son `NOT NULL` con `CHECK (btrim(...) <> '')`: no alcanza con mandar la cadena vacía.

**§12** fija la idempotencia y prohíbe un atajo específico:

> *«**REGLA:** Mantener estrictamente separada la clave real `(plantilla_id, occurrence_key)`. Está prohibido reutilizarla para gobernar las entidades propuestas.»*
> — §12

Traducido: la clave que identifica una ocurrencia recurrente **real** no puede usarse para deduplicar propuestas. Una propuesta sobre una ocurrencia no es la ocurrencia. Por eso las propuestas tienen su propia clave de identidad, la `huella`, descripta en [propuestas-y-huellas.md](propuestas-y-huellas.md).

---

## §13 — Las ocho categorías de discrepancia

El §13 clasifica ocho casos de choque de evidencia. La regla que los gobierna a todos:

> *«Las discrepancias futuras documentadas no se corrigen automáticamente; se preservan ambas evidencias y se escalan.»*
> — §13

Los nombres literales de las ocho categorías del contrato no fueron transcriptos en la auditoría de origen: `[PENDIENTE DE VERIFICAR]`. Lo que **sí** está verificado es la implementación, que es más granular que el contrato: **13 detectores** en `ConsultarDiscrepanciasAbiertas`, agrupados por severidad.

| Severidad | Detectores implementados |
|---|---|
| **Alta** | `deuda_pagada_sin_evidencia` · `saldo_incoherente` · `moneda_inconsistente_en_imputacion` · `movimiento_sin_clasificacion_fiscal` · `posible_separador_de_miles_mal_leido` · `movimiento_no_coincide_con_su_comprobante` |
| **Media** | `obligacion_vencida_sin_pago` · `fiscal_obligacion_vencida_sin_pago` · `comprobante_duplicado_por_archivo` · `comprobante_duplicado_fuera_del_indice` · `movimiento_sin_categoria` · `obligacion_sin_periodo_imputable` |
| **Baja** | `movimiento_pendiente_antiguo` |

Ninguno de los trece propone una corrección. Todos devuelven las dos evidencias que chocan y dejan la resolución del lado humano. El caso más elocuente es `posible_separador_de_miles_mal_leido`, que detecta el par de un mismo importe leído con coma decimal y con punto de miles: hay un test dedicado a que el detector **no elija cuál de los dos está mal**.

---

## §14 y §15 — Permisos y abstención

El §14 fija mínimo privilegio y exige auditoría de consulta. La implementación registra cada consulta como una línea JSON en el log del proceso, no en la base, y la razón está en [capa-de-lectura.md](capa-de-lectura.md).

El §15 define los nueve códigos con los que el agente dice "no sé", en lugar de devolver algo plausible:

| Código | Cuándo |
|---|---|
| `RECORD_NOT_FOUND` | El registro citado no existe |
| `INSUFFICIENT_EVIDENCE` | Falta un dato obligatorio para poder afirmar algo |
| `UNAUTHORIZED_ACCESS` | La operación no corresponde al alcance o al estado |
| `INCOMPATIBLE_CONTRACT_VERSION` | El cliente habla otra versión del contrato |
| `CORRUPT_DATA` | La evidencia releída no coincide con la registrada |
| `UNKNOWN_CURRENCY` | Moneda no reconocida por la política vigente |
| `AMBIGUOUS_PERIOD` | El período no se puede resolver sin adivinar |
| `SOURCE_UNAVAILABLE` | La fuente no respondió, o respondió parcialmente |
| `INVALID_DATE_RANGE` | El rango pedido no es válido |

---

## §17 — Fuera de alcance v1

Doce ítems declarados. No son "todavía no": son "no en esta versión, y ampliarlo requiere cambiar el contrato".

1. Escritura directa Fiscal → base de datos.
2. Modificación de movimientos históricos o actuales.
3. **Presentar declaraciones o interactuar con ARCA.**
4. Pago automático de deudas, VEPs o saldos.
5. Asientos correctivos automáticos.
6. Modificación de saldos de cuentas.
7. Reclasificación automática sin supervisión.
8. Acceso a claves fiscales productivas.
9. Despliegue y DevOps.
10. Integración productiva ejecutable.
11. Implementación real de HTTP/RPC — **matizado por el Anexo A.4**.
12. Alteración de vistas del Dashboard.

---

## §19 y §21 — Lo que queda del lado humano

El **§19** lista once decisiones abiertas, todas del titular: vistas SQL vs. API · nivel de detalle accesible · retención de auditoría · tratamiento de documentos · moneda y conversión · datos personales, PII crudo vs. anonimizado · sincronización, *pooling* vs. *push* · mecanismo de aprobación, WebUI vs. Telegram, con recomendación de panel dashboard · acceso futuro de escritura · integración con ARCA · mecanismo seguro de secretos. Están detalladas en [limites-y-deudas.md](limites-y-deudas.md).

El **§21** es la matriz de permisos operación por operación. Su texto literal no fue transcripto en la auditoría de origen: `[PENDIENTE DE VERIFICAR]`. La matriz **efectiva**, verificada contra `api/auth.mjs` y contra `ops/verificar_alcances.sh`, es:

| Operación | Token fiscal | Token general |
|---|---|---|
| `GET /api/fiscal-lectura/*` (las 9 operaciones) | Permitido | Permitido |
| `GET /api/fiscal-diagnostico` | Permitido | Permitido |
| `GET /api/fiscal-diagnostico?registrar=true` (crea propuestas) | Permitido | Permitido |
| `GET /api/fiscal-propuestas` | Permitido | Permitido |
| `POST /api/fiscal-propuestas` (crear) | Permitido | Permitido |
| `POST /api/fiscal-propuestas/decidir` | **403 duro** | Permitido |
| Rutas de escritura financiera: obligaciones, movimientos, ingesta, cierres | **403** | Permitido |

El desarrollo completo, con el motivo de que el 403 se compruebe **primero y por igualdad exacta**, está en [seguridad-y-permisos.md](seguridad-y-permisos.md).

---

## El Anexo A — verificar la documentación contra la realidad

### Qué es

Un anexo de cinco sub-secciones agregado el **2026-08-04**, el mismo día de la aprobación, con una aclaración explícita: *«no modifica ninguna cláusula»*. No es una corrección del contrato: es un registro de **dónde el cuerpo del contrato describe un esquema que la base real no confirma**.

### Por qué existe

Porque el contrato se escribió describiendo estados, columnas y relaciones, y nadie había comprobado que existieran. Un contrato de integración que nombra una columna inexistente no falla el día que se firma: falla el día que alguien escribe código contra él y obtiene `null` en lugar de un error.

### Cómo se verificó

Levantando **PGlite** —PostgreSQL embebido en WASM— con el DDL consolidado más 11 migraciones, y contando los objetos resultantes: **55**. Con una advertencia registrada en el propio anexo: *«No se consultó la base de producción»*. Es decir, se verificó contra el esquema que el repositorio produce, no contra el servidor. La distinción importa, y el anexo la deja escrita en lugar de esconderla.

### Qué encontró

**A.1 — Estados declarados que no existen.**

| El contrato decía | La base tiene |
|---|---|
| `movimientos.revision` | No existe. Es el booleano `requiere_revision` |
| `deuda_pagos` con `confirmado` / `conciliado` / `anulado` | Solo `activa` / `anulada` |
| `fiscal_obligaciones` con los 5 estados del §9 | **8** estados reales |

**A.2 — Columnas y FK inexistentes.**

- `deudas_pendientes` no tiene `proveedor_id`, `cliente_id`, `categoria_id` ni `proyecto_id`.
- `fiscal_obligaciones` usa `impuesto` e `importe_determinado`, no `impuesto_tipo` ni `monto_determinado`.
- `documentos` no tiene `bucket_url` sino `ruta`, y la columna está comentada como *«ruta interna, NUNCA una URL pública»*.
- Hay **tres** tablas de auditoría, no una. Por eso `ConsultarCambiosHistoricos` tiene que elegir la tabla correcta según la entidad y devolver `tabla_origen` en cada fila.
- **No existe tabla puente movimiento ↔ documento.** Esta es la que más consecuencias tuvo: obligó a que `ConsultarDocumentosAsociados` devolviera, para la entidad `movimiento`, un `via: 'ingesta_raw'` con la advertencia de que no es una asociación declarada.

**A.3 — Garantías que la base ya daba y el contrato no aprovechaba.** `documentos.sha256` tiene índice ÚNICO. `deuda_pagos` tiene los triggers `trg_pago_recalcular` y `trg_deuda_estado_derivado`.

**A.4 — Una prohibición que dejó de aplicar.** El §17 prohibía la "implementación real de HTTP" **mientras el contrato era borrador**. La aprobación habilita implementarlo **sin ampliar ningún permiso**: se puede exponer por HTTP exactamente lo que el contrato ya permitía leer, y nada más.

**A.5 — Qué queda sin implementar.** Ver [limites-y-deudas.md](limites-y-deudas.md).

### Por qué tratarlo como ejemplo, y no como un tropiezo

El Anexo A es la parte más valiosa del contrato. Un documento de arquitectura que nadie contrasta contra el sistema se convierte, con el tiempo, en una descripción de un sistema que no existe — y lo peligroso es que se sigue leyendo con confianza. Acá alguien se tomó el trabajo de levantar el esquema real, contar los objetos, comparar campo por campo, escribir las diferencias y **dejarlas publicadas junto al contrato en lugar de arreglar el contrato en silencio**.

El costo fue una tarde. El beneficio es que las nueve operaciones de lectura se escribieron contra el esquema que existe, no contra el que el contrato imaginaba. Uno de los hallazgos —la ausencia de puente movimiento↔documento— cambió la firma de una operación entera.

Es el mismo movimiento que después se repite en el resto del subsistema: el test que **lee el propio fuente** para verificar que no aparezcan escrituras, el test que compara el grafo de estados de la base contra el de JavaScript, el verificador de alcances que corre contra el entorno desplegado. La documentación no vale por lo que afirma: vale por lo que se puede comprobar.

---

## Documentos relacionados

- [Ficha del subsistema](README.md)
- [La capa de lectura — las 9 operaciones](capa-de-lectura.md)
- [Propuestas y huellas](propuestas-y-huellas.md)
- [Seguridad y permisos](seguridad-y-permisos.md)
- [Límites y deudas](limites-y-deudas.md)
- [PraxIA Finanzas](../praxia-finanzas/README.md)
- [ADR-004 — Aprobación humana en acciones consecuentes](../../docs/04-decisiones/adr-004-aprobacion-humana-en-acciones-consecuentes.md)
- [Modelo de permisos](../../docs/01-arquitectura/modelo-de-permisos.md)

> Última verificación: 2026-08-06
