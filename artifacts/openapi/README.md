# Contrato de la API financiera

Descripción del contrato HTTP de PraxIA Finanzas: recursos, familias de endpoints, autenticación por token con scopes, códigos de error, política de no-DELETE e idempotencia.

> **Descripción, no copia.** Acá no está el YAML de producción. Está descripto el contrato y, al final, un fragmento OpenAPI 3.1 **escrito para este repositorio** que muestra `POST /api/ingesta`. Los ejemplos son sintéticos.

---

## Lo primero: el estado de las versiones

La API declara **PraxIA Finanzas 3.6.0** en su OpenAPI. El esquema de base está en **v4.8**. **El contrato publicado va atrás del sistema real** y está anotado como deuda técnica en la [ficha del subsistema](../../systems/praxia-finanzas/).

Se dice acá y no en una nota al pie porque es exactamente el tipo de cosa que un repositorio de portafolio esconde.

---

## Principios del contrato

### 1. Un solo camino de alta

> *"Toda entrada — Telegram, dashboard, PDF, CSV, email o un agente — produce el mismo contrato universal y termina en la misma base."*

`POST /api/ingesta` es la única forma de crear un movimiento. Los adaptadores de PDF, CSV, Excel y correo no escriben en tablas: **normalizan hacia el contrato y llaman a la misma puerta.** El bot de Telegram tampoco escribe. Un agente vía MCP tampoco.

Consecuencia de diseño: hay un solo lugar donde validar, uno donde deduplicar y uno donde auditar. Agregar un canal es escribir un adaptador, no tocar el núcleo.

### 2. Ningún endpoint `DELETE`

**No existe. En ningún recurso.** No es que esté restringido: no está en el router.

Es la primera de tres capas. Las otras dos son el rol `praxia_finanzas_rw` sin permiso `DELETE` y el trigger `prohibir_delete_fisico`. Cada una falla de una manera distinta, así que están las tres.

Dar de baja se hace con `POST /api/movimientos/{id}/anular`, que escribe baja lógica y auditoría.

### 3. Todo nace pendiente

Un movimiento creado por `POST /api/ingesta` nace en estado `pendiente`, venga de donde venga. Confirmar es una llamada aparte y auditada: `POST /api/movimientos/{id}/confirmar`.

Un agente con permiso de escritura puede crear pendientes. No puede confirmarlos.

### 4. La ausencia de dato no se rellena

Un endpoint que no puede calcular un valor no devuelve cero: omite la fila o devuelve el motivo. `GET /api/saldos` puede devolver saldos en pesos y no en dólares si falta la cotización, y dice por qué.

---

## Recursos

| Recurso | Descripción |
|---|---|
| `ingesta` | La puerta única de alta. Contrato universal |
| `movimientos` | Ingresos y gastos, con ciclo de vida pendiente → confirmado → anulado |
| `transferencias` | Dos patas unidas por `transfer_id`; no son gasto |
| `valuaciones` | Valuación de activos a una fecha |
| `documentos` | Archivos con `sha256`, análisis e importación |
| `deudas` | Deudas, estados, elegibles y pagos |
| `catalogos` | Perfiles, cuentas, categorías |
| `resumen` / `reporte-mensual` / `saldos` / `pendientes` / `duplicados` | Lecturas agregadas |
| `fiscal` | Perfiles, comprobantes, clasificación y cierres |
| `fiscal-lectura` | Capa de solo lectura, 9 operaciones. Contrato Finanzas↔Fiscal v1.0 |
| `fiscal-propuestas` | Propuestas del motor y su decisión humana |
| `salud` / `fiscal-diagnostico` | Diagnóstico |

---

## Familias de endpoints

Más de 60 rutas. Agrupadas por lo que hacen, no listadas en bruto:

| Familia | Verbos | Qué resuelve |
|---|---|---|
| **Salud y contrato** | GET | `salud`, `openapi.yaml`. Descubrimiento y diagnóstico |
| **Lectura agregada** | GET | Resumen, reporte mensual, saldos, catálogos, duplicados. Es lo que consume el dashboard al abrir |
| **Ingesta y alta** | POST | `ingesta` (único camino), `transferencia`, `valuacion`, `email` |
| **Ciclo de vida de movimientos** | GET · PATCH · POST | Listar, ver pendientes, corregir, confirmar, anular, consultar auditoría |
| **Documentos** | GET · POST | Subir, listar, analizar e importar. Deduplicación por `sha256` |
| **Deudas y pagos** | GET · POST · PATCH | Alta, estados, resumen, exportación, movimientos elegibles, pagos y anulación de pagos |
| **Fiscal operativo** | GET · POST | Perfiles, comprobantes, clasificación, chequeos, borrador, estado y exportación de cierres |
| **Capa de lectura fiscal** | **Solo GET** | Nueve operaciones: movimientos confirmados y pendientes, deuda, pagos de deuda, obligaciones, documentos, cambios históricos, resumen de período y discrepancias |
| **Propuestas fiscales** | GET · POST | Crear, listar y decidir propuestas del motor |
| **Diagnóstico fiscal** | GET | Consistencia del subsistema |

La **capa de lectura fiscal** merece el subrayado: es solo-GET por diseño, con su contrato aprobado el 2026-08-04. Es la superficie que consume el motor que propone clasificaciones. **El subsistema que propone no puede escribir.**

---

## Autenticación y scopes

### HTTP

Todos los endpoints exigen token. Sin token: `401`. Con token válido pero sin el scope necesario: `403`.

```http
Authorization: Bearer <token>
```

### MCP

El servidor MCP es un proceso aparte (TypeScript, Express, SSE, OAuth/JWT/PKCE) y expone 22 herramientas en **4 scopes**:

| Scope | Herramientas | Qué habilita |
|---|---|---|
| `praxia.read` | 8 | Salud, catálogos, saldos, movimientos, pendientes, resumen, auditoría, duplicados |
| `praxia.fiscal.read` | 10 | Cierre fiscal + las nueve operaciones de la capa de lectura fiscal |
| `praxia.write` | 1 | `registrar_movimiento` — entra por `POST /api/ingesta` y nace pendiente |
| `praxia.modify` | 4 | `corregir_movimiento`, `confirmar_movimiento`, `anular_movimiento`, `importar_documento`. Marcadas **"¡REQUIERE CONFIRMACIÓN EXPLÍCITA!"** |

**18 de 22 herramientas son de lectura.** Un agente financiero útil es, sobre todo, un agente que sabe mirar.

El scope es lo que separa "el agente puede consultar mis finanzas" de "el agente puede confirmar movimientos". Un cliente MCP con `praxia.read` puede leerlo todo y no puede cambiar nada, y eso no depende de que el prompt se lo pida.

---

## Idempotencia

`POST /api/ingesta` exige `idempotency_key` en el cuerpo. La clave se guarda en `ingesta_raw` con una restricción `UNIQUE`.

| Situación | Respuesta |
|---|---|
| Clave nueva | `201 Created` con el movimiento creado en estado `pendiente` |
| Clave ya vista, mismo contenido | `200 OK` con el movimiento **existente** y `duplicado: true` |
| Clave ya vista, contenido distinto | `409 Conflict` |

El tercer caso es el que suele faltar en las implementaciones apuradas. Reutilizar una clave con otro contenido no es un reintento: es un error del cliente, y taparlo con un `200` esconde un bug.

Por qué importa acá más que en otros sistemas: los canales de entrada son siete y varios reintentan solos. Un webhook de Telegram que se reenvía, un doble tap en el dashboard, un agente que repite la llamada porque no vio la respuesta. Sin idempotencia, cada uno de esos es un gasto duplicado.

**Cómo se arma la clave:** algo estable derivado del contenido y del canal —por ejemplo `sha256(canal + actor + fecha + monto + descripcion_normalizada)`— y no un UUID al azar. Un UUID nuevo por reintento no deduplica nada.

---

## Códigos de error

| Código | Cuándo | Ejemplo |
|---|---|---|
| `200` | Lectura correcta, o alta idempotente ya existente | — |
| `201` | Recurso creado | Movimiento nuevo por ingesta |
| `400` | Contrato mal formado | Falta `monto`, moneda de tres letras inválida, fecha inexistente |
| `401` | Sin token o token inválido | — |
| `403` | Token válido, scope insuficiente | Un cliente `praxia.read` intentando confirmar |
| `404` | Recurso inexistente | Movimiento que no existe |
| `405` | Método no permitido | **Cualquier `DELETE`** |
| `409` | Conflicto de estado o de idempotencia | Confirmar un movimiento anulado; misma clave con otro contenido |
| `422` | Contrato bien formado, regla de negocio violada | Pago en moneda distinta a la deuda; pago que excede el saldo; personal + deducible |
| `429` | Límite de tasa | — |
| `500` | Error no previsto | Queda registrado en la auditoría de errores |

La distinción entre `400` y `422` es deliberada: `400` es "no te entiendo", `422` es "te entiendo y no se puede". Las invariantes de la base —los guards— producen `422`, no `500`. Un trigger que rechaza una operación no es una falla del servidor.

### Forma del error

```json
{
  "error": {
    "codigo": "MONEDA_INCOMPATIBLE",
    "mensaje": "El pago está en ARS y la deuda en USD.",
    "detalle": "Registrar el cambio de moneda como una operación aparte.",
    "campo": "moneda"
  }
}
```

El `codigo` es de una lista cerrada y es lo que ramifica el cliente. El `mensaje` es para la persona. El `detalle` propone la salida — un error que sólo dice que no obliga al usuario a adivinar.

---

## Fragmento OpenAPI 3.1 — sintético

Escrito para este repositorio. **No es el archivo de producción.** Muestra el endpoint central con su cuerpo y sus respuestas.

```yaml
openapi: 3.1.0

info:
  title: PraxIA Finanzas — fragmento sintético
  version: 0.0.0-ejemplo
  summary: Fragmento didáctico. No es el contrato de producción.
  description: |
    Ejemplo escrito para el repositorio público praxia-ops. Muestra el único
    camino de alta del sistema. Todos los valores son sintéticos.

servers:
  - url: https://api.ejemplo.invalid
    description: Servidor de ejemplo (no resuelve)

security:
  - bearerAuth: []

paths:
  /api/ingesta:
    post:
      operationId: crearIngesta
      summary: Único camino de alta de movimientos
      description: |
        Recibe el contrato universal desde cualquier canal (telegram,
        dashboard, pdf, csv, excel, email, agente) y crea un movimiento en
        estado `pendiente`. Es idempotente por `idempotency_key`.

        No existe un endpoint DELETE en esta API. Dar de baja se hace con
        POST /api/movimientos/{id}/anular.
      tags: [ingesta]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ContratoUniversal'
            examples:
              gastoDesdeTelegram:
                summary: Gasto cargado por Telegram (datos sintéticos)
                value:
                  idempotency_key: "sha256:aaaa1111bbbb2222cccc3333dddd4444"
                  canal: telegram
                  actor: owner
                  fecha: "2026-08-04"
                  descripcion: "Insumos de oficina (ejemplo)"
                  monto: -18500.00
                  moneda: ARS
                  cuenta: BANCO_ARS
                  categoria: INSUMOS
                  perfil: PERFIL_PROFESIONAL
                  ambito: profesional
                  deducible: true
      responses:
        '201':
          description: Movimiento creado en estado pendiente
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/RespuestaIngesta'
              example:
                movimiento_id: 1001
                estado: pendiente
                estado_fiscal: fiscal_deducible
                duplicado: false
                ingesta_id: 5001
        '200':
          description: |
            La `idempotency_key` ya fue procesada con el mismo contenido.
            Se devuelve el movimiento existente. No se creó nada nuevo.
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/RespuestaIngesta'
              example:
                movimiento_id: 1001
                estado: pendiente
                estado_fiscal: fiscal_deducible
                duplicado: true
                ingesta_id: 5001
        '400':
          $ref: '#/components/responses/ContratoInvalido'
        '401':
          $ref: '#/components/responses/SinAutenticacion'
        '403':
          $ref: '#/components/responses/ScopeInsuficiente'
        '409':
          description: |
            La `idempotency_key` ya existe con un contenido distinto.
            No es un reintento: es un error del cliente.
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
              example:
                error:
                  codigo: IDEMPOTENCY_CONFLICTO
                  mensaje: "La clave de idempotencia ya fue usada con otro contenido."
                  campo: idempotency_key
        '422':
          description: |
            Contrato bien formado pero incompatible con una invariante del
            sistema (por ejemplo, ámbito personal con deducible verdadero).
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
              example:
                error:
                  codigo: AMBITO_DEDUCIBLE_INCOMPATIBLE
                  mensaje: "Un movimiento de ámbito personal no puede ser deducible."
                  detalle: "Si el gasto es deducible, su ámbito es profesional."
                  campo: deducible

components:

  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
      description: |
        Token con scopes. La escritura por esta ruta requiere `praxia.write`.
        Confirmar, corregir o anular requiere `praxia.modify`.

  schemas:

    ContratoUniversal:
      type: object
      additionalProperties: false
      required: [idempotency_key, canal, actor, fecha, descripcion, monto, moneda, cuenta, perfil]
      properties:
        idempotency_key:
          type: string
          minLength: 8
          maxLength: 128
          description: |
            Clave estable derivada del contenido y del canal. Un UUID al azar
            por reintento no deduplica nada.
        canal:
          type: string
          enum: [telegram, dashboard, pdf, csv, excel, email, agente]
        actor:
          type: string
          description: Quién origina la entrada. No transporta credenciales.
        fecha:
          type: string
          format: date
        descripcion:
          type: string
          minLength: 2
          maxLength: 500
        monto:
          type: number
          description: Negativo es salida, positivo es entrada. Cero no es un movimiento.
          not:
            const: 0
        moneda:
          type: string
          pattern: '^[A-Z]{3}$'
        cuenta:
          type: string
          description: Código de cuenta del catálogo.
        categoria:
          type: [string, 'null']
          description: |
            Puede venir vacía. Un movimiento sin categoría entra igual y
            aparece en la vista de revisión. No se adivina una categoría.
        perfil:
          type: string
        ambito:
          type: string
          enum: [personal, profesional]
          default: personal
        deducible:
          type: boolean
          default: false
        texto_original:
          type: [string, 'null']
          description: |
            Se guarda cifrado en ingesta_raw. Los datos sensibles se
            reemplazan por un token de tipo ⟦S1⟧ antes de cualquier
            procesamiento con un modelo de lenguaje.

    RespuestaIngesta:
      type: object
      required: [movimiento_id, estado, duplicado, ingesta_id]
      properties:
        movimiento_id:
          type: integer
        estado:
          type: string
          enum: [pendiente]
          description: Todo movimiento nace pendiente. Confirmar es otra llamada.
        estado_fiscal:
          type: string
          enum: [no_fiscal, fiscal_no_deducible, fiscal_deducible]
          description: Derivado de ambito + deducible. No se puede enviar.
          readOnly: true
        duplicado:
          type: boolean
          description: Verdadero si la clave de idempotencia ya había sido procesada.
        ingesta_id:
          type: integer

    Error:
      type: object
      required: [error]
      properties:
        error:
          type: object
          required: [codigo, mensaje]
          properties:
            codigo:
              type: string
              description: Valor de una lista cerrada. Es lo que ramifica el cliente.
            mensaje:
              type: string
            detalle:
              type: string
            campo:
              type: string

  responses:

    ContratoInvalido:
      description: El cuerpo no cumple el contrato universal.
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'

    SinAutenticacion:
      description: Falta el token o es inválido.
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'

    ScopeInsuficiente:
      description: Token válido, scope insuficiente para la operación.
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/Error'
```

---

## Lo que este fragmento no muestra

- Las más de 60 rutas reales.
- Los esquemas de deudas, pagos, documentos, comprobantes, cierres y propuestas.
- La capa de lectura fiscal con sus nueve operaciones.
- Los parámetros de filtrado y paginación.
- Los códigos de error concretos del sistema.

Alcanza para entender el contrato. No alcanza para reproducir la API.

---

## Documentos relacionados

- [PraxIA Finanzas](../../systems/praxia-finanzas/)
- [Cuándo uso una API propia](../../docs/02-desglose-tecnico/05-cuando-uso-una-api-propia.md)
- [Cuándo uso un MCP](../../docs/02-desglose-tecnico/04-cuando-uso-un-mcp.md)
- [ADR-007 — Sin borrado físico](../../docs/04-decisiones/adr-007-sin-borrado-fisico.md)
- [Esquema e invariantes en SQL](../sql/)

> Última verificación: 2026-08-05
