# PraxIA Finanzas — guía de uso

Cómo se cargan y se consultan movimientos, cómo funcionan las deudas y los pagos, y qué pide confirmación antes de tocar nada.

## La idea central

Hay **una sola puerta de entrada** y **una sola base**.

> *"Toda entrada — Telegram, dashboard, PDF, CSV, email o un agente — produce el mismo contrato universal y termina en la misma base (`praxia_finanzas`)."*

No importa si cargás un gasto por Telegram desde el auto o si importás el resumen de la tarjeta en PDF: los dos caminos terminan en `POST /api/ingesta` y producen un registro con la misma forma. Eso significa que no hay dos verdades posibles.

Y hay una regla que no se negocia:

> *"PraxIA Finanzas es la única fuente de verdad financiera. No existen sistemas paralelos. La ausencia de datos no debe convertirse en un dato inventado."*

## Lo que nunca pasa

**Nada se borra.** No existe ningún endpoint `DELETE` en toda la API. Hay un trigger en la base llamado `prohibir_delete_fisico` que lo impide, y el rol que usa la aplicación (`praxia_finanzas_rw`) **no tiene permiso de DELETE**.

Lo que se deshace, se anula: queda con estado anulado y con su rastro en la tabla de auditoría.

**Nada se inventa.** Si no hay cotización para una fecha, no hay fila. Textual: *"Ninguna cotización se inventa. Ausencia de dato es ausencia de fila, nunca un cero."*

---

## Cómo se carga un movimiento

Cinco caminos. Elegí el que te quede más cómodo en el momento.

### 1. Por Telegram

El más usado. Le hablás a Oppenheimer y él lo enruta a Finanzas.

Ejemplos **sintéticos**:

- "Anotá 45000 de nafta."
- "Gasté 12500 en el supermercado ayer."
- "Cobré 300000 del proyecto X."

Qué pasa por detrás: el mensaje se convierte en el contrato universal, entra por `POST /api/ingesta` y queda registrado. El texto original se guarda cifrado en `ingesta_raw`, junto con el canal, el actor y una `idempotency_key` — esa clave es la que impide que un reintento cargue el mismo gasto dos veces.

También podés mandarlo por **voz**: se transcribe con Whisper y sigue el mismo camino. Verificá el monto después, la transcripción de números largos no es infalible.

### 2. Por el dashboard

La sección `carga` del dashboard tiene el formulario. Sirve cuando querés poner todos los campos con precisión: perfil, cuenta, categoría, moneda, fecha, proyecto.

### 3. Por documento: PDF, CSV o Excel

Para resúmenes de tarjeta, extractos bancarios y planillas. Ver [Importar un documento](#importar-un-documento) más abajo.

### 4. Por email

Hay un endpoint dedicado (`POST /api/email`) con su propio adaptador. Sirve para que los comprobantes que te llegan por mail entren sin copiar y pegar.

`[PENDIENTE DE VERIFICAR]`: la fuente confirma el adaptador de email y su cobertura de tests, pero no documenta la dirección ni el mecanismo exacto de captura del lado del usuario.

### 5. Por un agente

Herramientas MCP: un asistente conectado (ChatGPT, Claude, Cowork) puede llamar a `registrar_movimiento`. Esa herramienta vive en el scope `praxia.write`, que es el único scope de escritura y tiene **una sola** herramienta adentro. Deliberado.

---

## Consultar lo que ya está cargado

### Desde Telegram

- "¿Cuánto tengo en pesos?"
- "¿Cuánto gasté este mes?"
- "¿Qué movimientos tengo pendientes?"

El enrutamiento de consultas financieras de Oppenheimer hacia PraxIA se hizo el 2026-08-02/03, y es un **workflow de solo lectura**. Desde Telegram consultás; para modificar hay pasos con confirmación.

### Desde el dashboard

Las siete secciones, abajo.

### Desde un agente por MCP

El scope `praxia.read` tiene ocho herramientas de solo lectura:

| Herramienta | Qué trae |
|---|---|
| `salud` | Si el sistema responde |
| `consultar_catalogos` | Perfiles, cuentas, categorías, proyectos |
| `consultar_saldos` | Saldos por moneda |
| `consultar_movimientos` | Movimientos con filtros |
| `consultar_pendientes` | Lo que espera confirmación |
| `consultar_resumen` | Resumen agregado |
| `consultar_auditoria` | El historial de cambios de un movimiento |
| `consultar_duplicados` | Posibles cargas repetidas |

Hay además diez herramientas de lectura fiscal en el scope `praxia.fiscal.read`.

---

## Las 7 secciones del dashboard

El dashboard es una SPA de **un solo archivo** HTML/JS vanilla. No hay React, no hay Vue, no hay Tailwind: son 1.911 líneas en `api/public/index.html`. Esa decisión bajó la superficie de mantenimiento a casi cero.

| Sección | Para qué la usás |
|---|---|
| `inicio` | Panorama general: saldos, resumen del período, estado del sistema |
| `movs` | Listado de movimientos, con filtros. Desde acá corregís, confirmás y anulás |
| `pend` | Solo lo que quedó pendiente de confirmación. Es tu bandeja de entrada financiera |
| `carga` | Formulario de alta manual, con todos los campos |
| `deudas` | Deudas pendientes, su saldo y sus pagos. Vinculación de pagos |
| `importar` | Subida de PDF, CSV, Excel; análisis previo e importación |
| `fiscal` | Comprobantes, clasificación, chequeos de cierre, borradores, exportación |

Desde el dashboard podés **ver, corregir, confirmar, anular, vincular pagos y exportar**. Lo que no podés es borrar, porque no existe.

### Sobre el Dashboard UI v3

Hay un prototipo de nueva interfaz —obligaciones recurrentes, 17 estados, tema claro/oscuro con contraste AA— que fue revisado y **aprobado en diseño, no migrado**. Es la Fase 6 del ADR. Lo que usás hoy sigue siendo la versión de un solo archivo.

---

## El ciclo de un movimiento

Este es el concepto más importante de todo el sistema financiero.

```
        (alta)
          ↓
      PENDIENTE ──confirmar──→ CONFIRMADO
          │                         │
          └────────anular───────────┘
                     ↓
                  ANULADO
```

**Todo movimiento nace pendiente.** No importa por dónde entró. Un gasto dictado por voz, un renglón de un PDF importado, una carga desde el dashboard: todos arrancan esperando tu confirmación.

**Pendiente** significa "está registrado pero todavía no lo diste por bueno". Vive en `v_pendientes_completables` si le falta información completable, o en `v_requiere_revision` si algo no cierra.

**Confirmado** significa que lo validaste. Recién ahí cuenta como dato firme.

**Anulado** significa que lo diste de baja. **No desapareció**: sigue en la tabla, con estado anulado, y el cambio quedó en `movimientos_auditoria`. Podés consultar la auditoría completa de cualquier movimiento con `GET /api/movimientos/{id}/auditoria`.

### Corregir en lugar de anular

Si el monto o la categoría estaban mal, corregís (`PATCH /api/movimientos/{id}`) en vez de anular y volver a cargar. La corrección también queda auditada. Anular es para cuando el movimiento no debería haber existido.

### Auto-confirmación

Existe lógica de auto-confirmación con cobertura de tests propia. `[PENDIENTE DE VERIFICAR]`: la fuente confirma que existe y que está testeada, pero no documenta las condiciones exactas bajo las cuales un movimiento se auto-confirma. Si te aparece algo ya confirmado sin que lo hayas tocado, es esto.

---

## Importar un documento

El flujo es de tres pasos, a propósito: subir no es importar.

### Paso 1 — Subir

`POST /api/documentos`. El archivo se registra en la tabla `documentos` con su **SHA-256**, su tipo MIME y su ubicación.

El SHA-256 es la huella del archivo. Si subís dos veces el mismo resumen de tarjeta, el sistema lo detecta por hash y no lo procesa de nuevo. Esa es la deduplicación de la v3.6.

### Paso 2 — Analizar

`POST /api/documentos/{id}/analizar`. El adaptador correspondiente —PDF, CSV, Excel o email— lee el contenido y propone los movimientos que encontró.

Acá **todavía no se cargó nada**. Estás viendo una propuesta.

### Paso 3 — Importar

`POST /api/documentos/{id}/importar`. Recién ahora los movimientos entran a la base, y entran **pendientes**.

### Formatos soportados

| Formato | Uso típico |
|---|---|
| PDF | Resúmenes de tarjeta, facturas, comprobantes |
| CSV | Exportaciones de banco |
| Excel | Planillas propias o de terceros |
| Email | Comprobantes que llegan por correo |

Los cuatro adaptadores se completaron en la Fase 3 del 2026-07-28, con 141/141 tests en verde en ese momento.

### Duplicados

Además del hash de archivo, hay detección de movimientos duplicados: `GET /api/duplicados` y la herramienta MCP `consultar_duplicados`. Sirve para cuando el mismo gasto entró por dos vías —lo dictaste por voz y después vino en el resumen de la tarjeta—.

---

## Deudas y pagos

Acá está la regla que más confunde al principio y la que más ordena una vez que la entendés.

### La regla

> *"Registrar una deuda, una cuota, un vencimiento o un gasto esperado no modifica saldos. El impacto financiero ocurre únicamente al registrar o vincular un pago real, y un pago se contabiliza exactamente una vez."*

Desarmada en tres partes:

**Anotar una deuda no gasta plata.** Si registrás que le debés 500.000 al proveedor, tus saldos no se mueven ni un peso. Lo que hiciste fue documentar un compromiso.

**El saldo se mueve cuando pagás.** El impacto aparece al registrar el pago real o al vincular un movimiento existente como pago de esa deuda.

**Un pago cuenta una sola vez.** Si ya tenías cargado el movimiento "transferencia 200.000" y lo vinculás como pago de la deuda, no se crea un segundo movimiento. Se vincula el que ya existe.

### Por qué importa

Sin esta regla, cargar las cuotas de algo a doce meses te destruiría los saldos: aparecerían doce gastos que todavía no ocurrieron. Con esta regla, ves la deuda completa **y** el saldo real, que son dos preguntas distintas.

### Cómo se opera

| Qué querés | Cómo |
|---|---|
| Anotar una deuda | Sección `deudas` del dashboard, o `POST /api/deudas` |
| Ver todas las deudas | `GET /api/deudas`, o la vista `v_deudas` |
| Ver el panorama | `GET /api/deudas/resumen` |
| Cambiar el estado de una deuda | `POST /api/deudas/{id}/estado` |
| Ver qué movimientos podrían ser pago de esa deuda | `GET /api/deudas/{id}/elegibles` |
| Registrar un pago | `POST /api/deudas/{id}/pagos` |
| Anular un pago mal cargado | `POST /api/deudas/{id}/pagos/{pagoId}/anular` |
| Exportar | `GET /api/deudas/exportar` |

### Las protecciones

Tres guards en la base, agregados en la v4.5, que no dependen de que la aplicación se porte bien:

- **`deuda_pago_validar`**: un pago tiene que estar en la **misma moneda** que la deuda. No podés pagar una deuda en dólares con un movimiento en pesos sin pasar por conversión explícita.
- **`recalcular_saldo_deuda`**: el saldo de la deuda se recalcula solo cuando entra o se anula un pago. No hay un campo que alguien pueda desincronizar a mano.
- **`movimiento_respaldo_deuda_guard`**: impide vincular como respaldo un movimiento que no corresponde.

Los pagos pueden ser **totales o parciales**, y la v4.5 (2026-08-01) resolvió justamente que se pudieran hacer sin duplicar movimientos.

### Planes de pago y obligaciones recurrentes

La v4.6 agregó `plantillas_recurrentes`, `planes_pago` y `fiscal_obligaciones`, con una identidad de ocurrencia `(plantilla_id, occurrence_key)`. Esa clave compuesta es lo que garantiza que la cuota de agosto se genere una sola vez aunque el generador corra dos veces.

`[PENDIENTE DE VERIFICAR]`: la fuente confirma las tablas y la identidad de ocurrencia, pero no documenta el flujo de usuario para crear una plantilla recurrente desde el dashboard actual. El prototipo de UI que lo contempla está aprobado en diseño, no migrado.

---

## Transferencias

Una transferencia entre tus propias cuentas **no es un gasto**. El sistema lo trata explícitamente: se registra como dos patas ligadas por un `transfer_id`, y esas dos patas no cuentan como gasto en los reportes.

Se carga por `POST /api/transferencia`. Hay una vista `v_transferencias_invalidas` que muestra las que quedaron con una sola pata o desbalanceadas.

---

## Monedas y cotizaciones

El sistema maneja varias monedas y guarda cotizaciones en `fx_rates`, con una función `fx_vigente()` que devuelve la que corresponde a una fecha.

La regla ya citada aplica acá con todo su peso: si no hay cotización cargada para esa fecha, **no hay fila**, y el reporte va a mostrar el hueco en vez de un cero que mentiría.

Hay vistas dedicadas: `v_saldos_por_moneda`, `v_patrimonio_usd`, `v_gasto_mensual_usd`.

El tratamiento USD/ARS quedó resuelto en una adenda del ADR del 2026-08-04.

---

## Cierre fiscal y propuestas del agente

### Qué es un cierre

Cerrar un período fiscal es declarar que los movimientos de ese período están completos y clasificados. Una vez cerrado, no se toca.

### El flujo

1. **Clasificar** los movimientos: `POST /api/fiscal/movimientos/{id}/clasificar`. Cada movimiento tiene un `ambito` y un flag `deducible`.
2. **Correr los chequeos**: `GET /api/fiscal/cierres/{periodo}/chequeos` ejecuta la función `cierre_chequeos()` y te dice qué falta.
3. **Armar el borrador**: `POST /api/fiscal/cierres/{periodo}/borrador`.
4. **Cambiar el estado**: `POST /api/fiscal/cierres/{periodo}/estado`. Las transiciones válidas están controladas por `cierre_transicion_valida` — no podés saltar de cualquier estado a cualquier otro.
5. **Exportar**: `GET /api/fiscal/cierres/{periodo}/exportar`.

### El estado fiscal no se puede desalinear

Desde la v4.7 existe la función `movimiento_estado_fiscal_derivado`: el `estado_fiscal` de un movimiento **se deriva** de su `ambito` más su `deducible`. Ya no puede divergir. Antes eran tres campos que alguien podía dejar inconsistentes; ahora son dos campos y una derivación.

### Las propuestas del agente

La v4.8 (2026-08-05) agregó `fiscal_propuestas`. Cómo se usa en el día a día está en el [capítulo 09](09-agente-fiscal-guia-de-uso.md).

**Cómo funciona.** El motor (`fiscal_motor.mjs`) mira cómo clasificaste antes y propone cómo clasificar lo nuevo. Textual:

> *"...de las decisiones anteriores de Aldo. De ningún otro lado. El agente mejora a medida que Aldo decide, sin que nadie lo reentrene. Y el primer mes propone poco, que es lo correcto — todavía no sabe nada."*

Si el primer mes te propone casi nada, no está roto. Está siendo honesto.

**Las tres protecciones**, implementadas como triggers en la base:

| Trigger | Qué garantiza |
|---|---|
| `propuesta_nace_pendiente` | Ninguna propuesta puede nacer ya aprobada |
| `propuesta_contenido_inmutable` | El contenido de una propuesta no se puede cambiar después de creada. Lo que aprobás es exactamente lo que se te mostró |
| `propuesta_transicion_valida` | Los cambios de estado siguen un camino permitido |

**Huella y huella de evidencia.** Cada propuesta lleva dos campos: `huella` y `huella_evidencia`. Sirven para dos cosas distintas.

La `huella` evita que el agente te vuelva a proponer lo mismo que ya rechazaste. La `huella_evidencia` evita que apruebes algo cuya evidencia cambió desde que se generó la propuesta — si el movimiento subyacente se modificó, la propuesta caducó.

La razón de todo esto está en una frase del contrato:

> *"Un agente que puede repreguntar sin límite termina consiguiendo el 'sí' por cansancio."*

**Y la garantía más importante**:

> *"La aprobación no ejecuta nada financieramente."*

Aprobar una propuesta fiscal clasifica. No mueve plata, no crea movimientos, no paga nada.

Se opera con `POST /api/fiscal-propuestas` (generar), `GET /api/fiscal-propuestas` (listar) y `POST /api/fiscal-propuestas/decidir` (aprobar o rechazar).

### La capa de lectura fiscal

Hay una capa completa de solo lectura (`/api/fiscal-lectura/...`) con nueve operaciones, aprobada el 2026-08-04 junto con el contrato Finanzas↔Fiscal v1.0: movimientos confirmados, movimientos pendientes, deuda, pagos de deuda, obligaciones fiscales, documentos, cambios históricos, resumen del período y discrepancias.

Sirve para que un contador o un agente externo mire todo lo que necesita **sin ninguna posibilidad de escribir**.

---

## Qué pide confirmación explícita

Cuatro operaciones. En las herramientas MCP están marcadas literalmente con **"¡REQUIERE CONFIRMACIÓN EXPLÍCITA!"** y viven en un scope aparte, `praxia.modify`:

| Operación | Qué hace |
|---|---|
| `corregir_movimiento` | Cambia datos de un movimiento existente |
| `confirmar_movimiento` | Pasa un movimiento de pendiente a confirmado |
| `anular_movimiento` | Da de baja lógica un movimiento |
| `importar_documento` | Vuelca los movimientos de un documento a la base |

La separación en scopes OAuth es la que hace que esto sea real y no una promesa del prompt: un agente con token de `praxia.read` **no puede** llamar a `anular_movimiento` aunque quiera. Le falta el permiso.

| Scope | Herramientas | Qué puede |
|---|---|---|
| `praxia.read` | 8 | Solo leer |
| `praxia.fiscal.read` | 10 | Solo leer, ámbito fiscal |
| `praxia.write` | 1 | Registrar un movimiento nuevo |
| `praxia.modify` | 4 | Modificar, con confirmación |

Además: **todos los endpoints de la API exigen token**, y **ninguno es DELETE**.

---

## Datos sensibles

Si en un texto de carga aparece algo sensible, no viaja al modelo. El sistema lo cifra server-side y lo reemplaza por un `placeholder_token` del tipo `⟦S1⟧` **antes** de mandar nada al LLM. El dato real queda en la tabla `datos_sensibles`; el modelo ve el marcador.

El texto original de cada ingesta también se guarda cifrado en `ingesta_raw`.

---

## Estado de madurez

Para que sepas qué esperar.

| Dimensión | Estado |
|---|---|
| Versión de la app | `praxia-contable@0.2.0` |
| Versión declarada en OpenAPI | PraxIA Finanzas 3.6.0 |
| Esquema de base | v4.13 |
| Contrato Finanzas↔Fiscal | v1.0, aprobado 2026-08-04 |
| Servidor MCP | `praxia-finanzas-mcp@1.0.0` |
| Tests | **606 casos en verde, 0 salteados**, con harness PGlite que replica el esquema real |

Los tests cubren: ingesta, normalización de montos (incluidos los ambiguos y el separador decimal), fechas y "mes pedido", tipo de cambio, sanitización, datos sensibles, transferencias y su guard, los cuatro adaptadores, deudas y pagos, auto-confirmación, reporte mensual, exportación del dashboard, migraciones v4.6 y v4.7, lectura fiscal, propuestas fiscales, delegación de rutas, herramientas MCP e integración con Oppenheimer.

### Una advertencia real

El 2026-08-05 se descubrió que **producción estaba tres migraciones atrás del repositorio desde el 31/07**, porque —textual— *"nadie había mirado el servidor, solo el repositorio"*. Se puso al día con backup verificado, migraciones con `ON_ERROR_STOP=1` dentro de transacción y verificación de no-regresión (de 25 a 35 tablas).

La lección práctica para vos: si una funcionalidad que leíste acá no aparece en tu dashboard, puede que el servidor esté atrasado respecto del repo. Es un síntoma conocido, no una alucinación tuya.

> Última verificación: 2026-08-05
