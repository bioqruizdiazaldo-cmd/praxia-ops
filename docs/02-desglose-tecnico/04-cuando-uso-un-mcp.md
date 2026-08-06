# Cuándo uso un MCP

Cuándo conviene exponer las capacidades de un sistema como servidor MCP en vez de una API REST, un workflow o un plugin propio.

## Criterio

MCP (Model Context Protocol) es un protocolo para que un cliente LLM descubra y llame herramientas de un servidor, con un esquema declarado por herramienta. En una línea: **es el equivalente de OpenAPI para modelos, con descubrimiento en tiempo de ejecución**.

Eso es todo. No es un framework de agentes, no reemplaza a la API y no te da orquestación. Mueve una sola cosa de lugar: **quién sabe qué herramientas existen**.

### El eje de la decisión: quién controla al cliente

| Quién consume | Herramienta correcta |
|---|---|
| Mi propio workflow, que yo escribí | **HTTP directo a la API.** Ya sabés qué endpoints hay |
| Mi agente, en mi runtime | **Herramienta / subworkflow.** Ver [03](03-cuando-construyo-un-subagente.md) |
| Un LLM que no controlo, en un cliente que no escribí | **MCP** |
| Otro servicio, sin LLM en el medio | **API REST + OpenAPI** |
| Un humano con navegador | **Frontend.** Ver [06](06-cuando-uso-frontend.md) |
| Un evento externo | **Webhook al workflow** |

La fila que justifica MCP es la tercera. Si querés que Claude Desktop, ChatGPT, Cowork o el cliente que salga el mes que viene puedan operar tu sistema, tenés dos opciones: escribir y mantener un adaptador por cliente, o hablar el protocolo que todos entienden.

### Lo que MCP te da que una API no

1. **Descubrimiento.** El cliente pregunta qué herramientas hay y recibe nombres, descripciones y esquemas. No hay que pegarle la documentación al prompt.
2. **Las descripciones son parte del contrato.** En una API REST la descripción es para el humano que lee los docs. En MCP es lo que el modelo lee para decidir si llamar la herramienta. Una descripción ambigua es un bug funcional.
3. **Autorización por scope, negociada al conectar.** El usuario aprueba un conjunto de permisos, no cada llamada.
4. **Sesión.** Con SSE hay conexión persistente y notificaciones, cosa que una API stateless no da.

### Lo que MCP te cuesta

- Un servicio más que correr, versionar, monitorear y actualizar.
- Una superficie de autenticación nueva (OAuth, tokens, callbacks) que se puede configurar mal.
- Un cliente que **razona** sobre tus herramientas. La ambigüedad se paga en llamadas equivocadas.
- El protocolo todavía se mueve. Lo que hoy funciona puede requerir mantenimiento.

### Regla de oro del diseño

Una herramienta MCP no es un endpoint. Es una **capacidad expresada en el vocabulario del dominio**, con un nombre que un modelo pueda elegir sin ambigüedad y una descripción que le diga cuándo NO usarla.

## En este sistema

El servidor MCP de PraxIA Finanzas es un servicio **separado**: TypeScript, Express, `@modelcontextprotocol/sdk`, transporte SSE, autenticación OAuth con JWT y PKCE. Versión `praxia-finanzas-mcp@1.0.0`. La API financiera es Node.js ESM sin framework y corre aparte.

Están separados a propósito. La API tiene un contrato estable con clientes conocidos; el MCP es una **fachada** sobre ese contrato, orientada a que un modelo elija bien. Si fueran el mismo servicio, cada cambio en la ergonomía para LLMs tocaría el contrato HTTP, y viceversa.

### 22 herramientas en 4 scopes

| Scope | Cant. | Herramientas |
|---|---|---|
| `praxia.read` | 8 | `salud`, `consultar_catalogos`, `consultar_saldos`, `consultar_movimientos`, `consultar_pendientes`, `consultar_resumen`, `consultar_auditoria`, `consultar_duplicados` |
| `praxia.fiscal.read` | 10 | `consultar_cierre_fiscal`, `fiscal_movimientos_confirmados`, `fiscal_movimientos_pendientes`, `fiscal_deuda`, `fiscal_deuda_pagos`, `fiscal_obligaciones`, `fiscal_documentos`, `fiscal_cambios_historicos`, `fiscal_resumen_periodo`, `fiscal_discrepancias` |
| `praxia.write` | 1 | `registrar_movimiento` |
| `praxia.modify` | 4 | `corregir_movimiento`, `confirmar_movimiento`, `anular_movimiento`, `importar_documento` |

La distribución es el diseño: **18 de lectura, 1 de alta, 4 de modificación**. Un cliente que sólo necesita responder "¿cuánto gasté este mes?" pide `praxia.read` y físicamente no puede escribir nada.

### Por qué `fiscal.read` está separado de `read`

Es la decisión de diseño más interesante del servidor y no es obvia: ambos son de lectura, ¿por qué no un solo scope?

Porque **la sensibilidad del dato no es la misma que la operación**. Saldos y movimientos son datos operativos. El detalle fiscal —comprobantes, IVA por período, obligaciones, discrepancias, cambios históricos— es material sensible con implicancias regulatorias.

Separarlos permite conectar un asistente de uso diario con `praxia.read` y que jamás vea la capa fiscal, mientras que una sesión específica de trabajo contable pide los dos scopes. Sin la separación, cualquier cliente que quisiera ver un saldo tendría acceso a todo el historial fiscal.

El principio general: **agrupá los scopes por sensibilidad del dato, no sólo por verbo**. `read` / `write` es la partición más obvia y casi nunca la suficiente.

Del lado de la API, esto está respaldado por la capa `/api/fiscal-lectura/*`: 9 operaciones, todas `GET`, contrato Finanzas↔Fiscal v1.0 aprobado el 2026-08-04. El scope MCP no es una convención de nombres: mapea a rutas que estructuralmente no pueden escribir.

### Las 4 de modificación y la confirmación explícita

Las herramientas de `praxia.modify` están marcadas, en su descripción, con **"¡REQUIERE CONFIRMACIÓN EXPLÍCITA!"**.

Hay que ser preciso sobre qué es y qué no es esa marca:

**Qué es**: una instrucción al modelo, en el texto que lee para decidir. Es la última capa de la escalera, la más débil.

**Qué no es**: una garantía. Un modelo puede ignorarla. Por eso debajo hay capas que no dependen del texto:

1. El scope OAuth: si el cliente no pidió `praxia.modify`, la herramienta ni siquiera se lista.
2. El token de la API con scopes propios.
3. La ausencia total de `DELETE` en la API: lo peor que puede hacer `anular_movimiento` es una baja lógica auditada.
4. El trigger `prohibir_delete_fisico` en la base.
5. El rol `praxia_finanzas_rw` sin permiso de `DELETE`.

La marca en la descripción es una **mejora de ergonomía sobre un piso ya seguro**. Ese orden importa: si la única defensa es una mayúscula en un string, no hay defensa.

Vale notar cuál NO está en `modify`: `registrar_movimiento` está en `write`, sola. Crear un movimiento nuevo es reversible por anulación y auditado. Corregir uno existente cambia historia. Son riesgos distintos y por eso son scopes distintos.

### Nombres de herramientas: la ambigüedad es un bug

Los nombres siguen un patrón consistente: `consultar_*` para lectura general, `fiscal_*` para lectura fiscal, verbo directo para las que actúan (`registrar_`, `corregir_`, `confirmar_`, `anular_`, `importar_`).

El patrón resuelve tres problemas concretos:

**Colisión entre servidores.** Un cliente con varios MCP conectados puede tener dos herramientas llamadas `search`. El prefijo de dominio evita que el modelo elija el servidor equivocado.

**Discriminación dentro del servidor.** `consultar_movimientos` y `fiscal_movimientos_confirmados` devuelven cosas parecidas. La diferencia tiene que estar en el nombre, no sólo en la descripción, porque el nombre es lo primero que pesa.

**Legibilidad del log.** Cuando revisás qué hizo el agente, `anular_movimiento` se entiende. `update_status` no.

Un caso donde la ambigüedad me parece real y vale la pena declararlo: `consultar_duplicados` y `fiscal_discrepancias` podrían confundirse. Una busca movimientos repetidos; la otra, inconsistencias entre la vista fiscal y la financiera. La descripción los separa; el nombre no del todo. `[PENDIENTE DE VERIFICAR: si hubo llamadas cruzadas entre ambas en producción]`

### Cómo se diseña una herramienta MCP

Cuatro criterios que usé y que no son obvios cuando venís de diseñar APIs REST.

**La descripción es código, no documentación.**
En una API, la descripción la lee un humano que ya decidió qué endpoint quiere. En MCP la lee el modelo **para decidir**. Una descripción vaga produce llamadas equivocadas de la misma forma que un bug produce resultados equivocados. La plantilla que funciona:

```
<qué hace en una oración>.
Usar cuando <situación concreta>.
NO usar para <la confusión más probable, con el nombre de la otra herramienta>.
Devuelve <forma del resultado>.
```

El "NO usar para" es la parte que más rinde. La mayoría de las descripciones sólo dicen qué hace la herramienta, y el modelo no se equivoca por no saber qué hace: se equivoca por no saber cuál de dos.

**La granularidad es de capacidad, no de endpoint.**
`consultar_resumen` no es un `GET` envuelto: es la pregunta "¿cómo vengo este mes?" respondida en una llamada. Si una tarea frecuente requiere tres llamadas encadenadas, el modelo va a fallar en alguna. Una herramienta por intención del usuario, no una por ruta HTTP.

**El error tiene que ser un resultado legible, no una excepción.**
Igual que los siete estados del Buscador Web ([02](02-cuando-uso-n8n.md)): si no hay dato para el período pedido, la respuesta correcta es un resultado que lo diga, no un 500. Un modelo puede razonar sobre "no hay movimientos en ese rango"; sobre un stack trace, no.

**Los parámetros opcionales tienen default seguro.**
Si `limite` no viene, el default es un número chico. Si el rango de fechas no viene, no se asume "todo el historial". Un modelo omite parámetros más seguido que un cliente escrito a mano.

### MCP y API: qué va en cada capa

| Aspecto | API HTTP | Servidor MCP |
|---|---|---|
| Unidad | Endpoint | Capacidad |
| Contrato | OpenAPI | Esquema por herramienta + descripción |
| Quién decide llamar | Código que alguien escribió | El modelo |
| Autorización | Token con scopes | OAuth negociado al conectar, mapeado a los mismos scopes |
| Estabilidad esperada | Alta: rompe clientes | Media: se puede reordenar sin romper nada |
| Dónde vive la garantía | **Acá** | En ningún lado propio |

La última fila es la que ordena el diseño: el MCP **no tiene garantías propias**. Todo lo que hace cumplir lo hace cumplir la API que tiene debajo. Un servidor MCP que valida reglas de negocio que la API no valida es un agujero esperando a que alguien llame la API directo.

### Riesgos, incluyendo uno propio

**Defaults inseguros.** Riesgo abierto declarado en la auditoría del 2026-08-05: el servidor MCP tiene un `JWT_SECRET` y un password de owner **hardcodeados como fallback**, que sólo aplican si faltan las variables de entorno.

En un despliegue con las variables bien puestas no se usan nunca. El problema es la clase de bug: un default que existe para que "funcione en local" y que en un entorno mal configurado te deja un secreto conocido en producción. El arreglo correcto no es cambiar el default por uno mejor, es **fallar al arrancar**:

```js
// SINTÉTICO — el patrón correcto
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || JWT_SECRET.length < 32) {
  console.error('JWT_SECRET ausente o demasiado corto. Abortando.');
  process.exit(1);
}
```

Un servicio que no arranca es un incidente de cinco minutos. Un servicio que arranca con un secreto conocido es un incidente que te enterás después.

**Superficie de ataque.** Un MCP con OAuth expuesto a internet suma: endpoints de autorización y callback, emisión y validación de tokens, y una conexión SSE de larga duración. Todo eso pasa por Traefik con TLS, sin puertos publicados al host. Ver [08](08-infra-y-despliegue.md).

**El cliente razona sobre tus herramientas.** Un cliente HTTP hace lo que le dijeron; un LLM decide. Si dos herramientas se parecen, va a elegir mal alguna vez. Mitigaciones: nombres discriminantes, scopes acotados, y que lo peor que pueda salir de una elección equivocada sea una baja lógica auditada.

**Rotación de credenciales.** Otro riesgo abierto: un `.env` con un token real quedó dentro de una carpeta sincronizada a la nube. Requiere rotación. Publicarlo es incómodo y es el punto: un inventario de riesgos que sólo tiene riesgos ajenos no es un inventario.

### Cuándo NO hubiera usado MCP acá

Si el único consumidor fuera Oppenheimer, no habría servidor MCP. Oppenheimer consulta finanzas por un workflow de solo lectura enrutado desde el orquestador (2026-08-02/03) — HTTP directo a la API, sin protocolo intermedio, sin OAuth, un salto menos.

El MCP existe porque el sistema se conecta con **clientes que no controlo**: ChatGPT, Claude y Cowork, conexión completada en la Fase 3 del 2026-07-28. Ahí el cálculo cambia: un protocolo estándar contra N adaptadores propios.

## Regla

Exponé MCP cuando el consumidor sea un LLM en un cliente que no escribiste vos. Diseñá los scopes por sensibilidad del dato, no sólo por verbo, y asegurate de que ninguna garantía dependa de una frase en la descripción de la herramienta.

> Última verificación: 2026-08-05
