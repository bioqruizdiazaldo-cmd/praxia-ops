# Cuándo uso una API propia

Por qué en un sistema construido con enfoque no-code hay, igual, una API HTTP escrita a mano en Node.js sin framework — y cuándo eso es la decisión equivocada.

## Criterio

Escribir una API propia en 2026 hay que justificarlo. Hay BaaS que te dan CRUD, auth y realtime en una tarde. Hay runtimes de automatización que exponen webhooks. Hay frameworks que generan endpoints desde el esquema.

La justificación no puede ser "quería tener el control". Tiene que ser un requisito que las alternativas no cubren.

### Las tres razones que sí alcanzan

**1. El contrato de escritura es el activo, no la UI.**
Cuando hay más de un cliente escribiendo —un chat, una web, un import, un agente— el contrato de ingesta es la pieza central del sistema. Si vive dentro de una herramienta, queda atado al ciclo de vida de esa herramienta: su modelo de auth, su formato, su versionado. Un contrato que tiene que sobrevivir a los clientes conviene tenerlo aparte.

**2. Necesitás garantías que la plataforma no expresa.**
"Este sistema no borra nunca." "Esta operación es idempotente por clave de negocio." "Este token puede leer pero no confirmar." Se puede *acordar* respetarlas en cualquier plataforma; hacerlas **imposibles de violar** requiere controlar el código.

**3. La lógica necesita tests de verdad.**
Un workflow visual no se testea con `node --test`. Si la lógica es aritmética financiera, normalización de montos y derivación de estados, querés un runner, fixtures y un número de casos que suba en cada PR.

### Las razones que no alcanzan

| Motivo | Por qué no |
|---|---|
| "Quiero control" | No es un requisito, es una preferencia. Costo real: mantenimiento indefinido |
| "Los frameworks son pesados" | Cierto e irrelevante si el problema es CRUD |
| "Después escalamos" | El escalamiento que no vas a necesitar no justifica código que sí vas a mantener |
| "No confío en los vendors" | Válido como política, pero decilo como política y bancate el costo |

### Cuándo NO conviene una API propia

- **CRUD sobre pocas tablas para un solo cliente.** Un BaaS lo resuelve mejor y con auth incluida.
- **Prototipo.** Hasta que el contrato no se estabilizó, escribir HTTP a mano es congelar algo que todavía se mueve.
- **Autenticación de usuarios finales.** Registro, recupero de contraseña, MFA, sesiones. Ahí sí conviene delegar: es un problema resuelto y hacerlo mal es caro.
- **Equipo chico sin quien lo mantenga.** Una API propia es una obligación permanente.

## En este sistema

`api/server.mjs`, aproximadamente 70 KB, **Node.js ESM sin framework, `node:http` puro, router por regex**. Única dependencia de runtime: `pg`. Extras para generar salidas: `exceljs`, `pdfkit`, `archiver`. Versión `praxia-contable@0.2.0`; el OpenAPI declara `PraxIA Finanzas 3.6.0`.

Más de 60 endpoints. **Ninguno es `DELETE`.**

### Por qué sin framework

Honestamente: es una decisión defendible, no una obviedad, y el costo hay que asumirlo.

Lo que se gana:

- **Superficie de dependencias mínima.** Una sola dependencia de runtime es una sola cadena de suministro que auditar. En un sistema que toca datos financieros, eso pesa.
- **Sin sorpresas de middleware.** Ningún parser de body que acepte algo que no esperabas, ningún manejo de errores que devuelva un stack trace.
- **Arranque y footprint chicos**, en un VPS que corre varios contenedores.

Lo que se pierde, sin adornos:

- **Validación de esquemas** hay que escribirla. Un framework con validadores te ahorra código real.
- **El router por regex escala mal.** Con 60+ rutas, el orden importa y una regex ambigua es un bug sutil. Hay tests de **delegación de rutas fiscales** justamente por esto: no testean lógica, testean que la ruta llegue al handler correcto.
- **Es contracultural.** Un dev que llega espera Express o Fastify.

El balance se sostiene por el tamaño: un archivo de 70 KB con un dominio acotado y 554 tests es mantenible. Al doble, la decisión habría que revisarla.

### El contrato universal de ingesta

Es la pieza que justifica todo lo demás. Textual:

> *"Toda entrada — Telegram, dashboard, PDF, CSV, email o un agente — produce el mismo contrato universal y termina en la misma base (`praxia_finanzas`)."*

Único camino de alta: **`POST /api/ingesta`**.

```jsonc
// SINTÉTICO — la forma, no el esquema real
{
  "canal": "telegram",            // telegram|dashboard|pdf|csv|email|agente
  "actor": "perfil-demo",
  "idempotency_key": "demo-2026-08-05-0001",
  "texto_original": "café 3500 con la tarjeta",
  "propuesta": {
    "tipo": "gasto",
    "monto": 3500,
    "moneda": "ARS",
    "fecha": "2026-08-05",
    "cuenta": "tarjeta-demo",
    "categoria": null            // null explícito: queda pendiente, no se inventa
  }
}
```

Cinco consecuencias de tener un solo camino:

1. **Una sola validación.** Un adaptador de CSV nuevo no puede saltearse una regla porque no hay otra puerta.
2. **Una sola auditoría.** `ingesta_raw` guarda el texto original cifrado, el canal, el actor y la clave de idempotencia. Siempre se puede reconstruir de dónde salió una fila.
3. **Los adaptadores son traductores, no escritores.** PDF, CSV, Excel y email (Fase 3, 2026-07-28, 141/141 tests) producen el contrato; no tocan `movimientos`.
4. **Agregar un canal es agregar un traductor.** No se rediseña nada.
5. **`null` es un valor legítimo.** Un campo que el adaptador no pudo determinar queda `null` y el movimiento cae en pendientes. La alternativa —completar con un default— es exactamente lo que la regla del sistema prohíbe: *"La ausencia de datos no debe convertirse en un dato inventado."*

### Idempotencia

`ingesta_raw` tiene `idempotency_key` con unicidad. Un reenvío del mismo ticket devuelve el resultado original en vez de crear un segundo gasto.

Esto no es opcional en este sistema: el canal principal es Telegram, y en Telegram el usuario reenvía, edita y manda dos veces. La red falla y el workflow reintenta. Sin idempotencia, cada reintento es plata duplicada.

La regla que lo sostiene:

> *"…un pago se contabiliza exactamente una vez."*

Y la implementación coherente en la capa de recurrencias: la identidad de ocurrencia en v4.6 es **`(plantilla_id, occurrence_key)`**. La misma cuota del mismo mes no puede generarse dos veces aunque el job corra dos veces. Es la misma idea que la clave de idempotencia, aplicada al tiempo en vez de al canal.

**Criterio general**: la clave de idempotencia la elige el **cliente** y tiene que derivar de la identidad del evento de negocio, no de un timestamp ni de un UUID nuevo por request. Un UUID nuevo en cada reintento no es idempotencia, es decoración.

### Ausencia total de DELETE

No hay ningún endpoint `DELETE`. Lo más cercano son:

- `POST /api/movimientos/{id}/anular` — baja lógica, auditada.
- `POST /api/deudas/{id}/pagos/{pagoId}/anular` — ídem para pagos.

Y del otro lado del stack, respaldando lo mismo: `movimientos_auditoria`, `deuda_auditoria`, `fiscal_auditoria` (inmutable), el trigger `prohibir_delete_fisico` y el rol sin permiso de `DELETE`.

Cuatro capas para una regla. El razonamiento es el mismo que en [01](01-cuando-uso-sql.md): cada capa cubre un camino distinto. La ausencia del verbo cubre al cliente honesto; el rol, al script; el trigger, a la conexión manual.

Y hay un efecto secundario que no esperaba y resultó valioso: **un agente que no tiene una herramienta de borrado no puede alucinar un borrado**. La seguridad más barata es la capacidad que no existe.

### Autenticación por token con scopes

Todos los endpoints exigen token. Los scopes se corresponden con los del MCP (`read`, `fiscal.read`, `write`, `modify`), de modo que el servidor MCP no puede otorgar más de lo que su token tiene.

```js
// SINTÉTICO — el patrón
const RUTAS_SCOPE = [
  [/^\/api\/fiscal-lectura\//,        'fiscal.read'],
  [/^\/api\/fiscal\//,                'fiscal.read'],
  [/^\/api\/(ingesta|transferencia)$/,'write'],
  [/\/(confirmar|anular)$/,           'modify'],
  [/^\/api\//,                        'read'],      // default restrictivo
];
```

Dos criterios acá:

**El default es el scope más restrictivo.** Una ruta nueva que nadie clasificó cae en `read`. Si el default fuera permisivo, olvidarse de clasificar sería una escalada de privilegios silenciosa.

**Los scopes son del sistema, no del servidor MCP.** Si mañana entra otro cliente, hereda el mismo modelo. Los permisos viven en la API porque la API es la que puede hacerlos cumplir.

### OpenAPI como contrato

`GET /api/openapi.yaml` sirve la especificación desde la propia API. Tres funciones:

1. **Documentación que no se desactualiza en un wiki aparte.**
2. **Fuente para los adaptadores.** Quien escribe un cliente lee el YAML.
3. **Objeto de revisión.** Un cambio en el contrato es un diff en el YAML. Esto es exactamente lo que los workflows de n8n **no** tienen, y es la mitad del argumento para tener una API propia: la lógica financiera vive en un artefacto con diffs legibles.

**Nota de honestidad**: el paquete es `praxia-contable@0.2.0` y el OpenAPI declara `PraxIA Finanzas 3.6.0`, mientras el esquema de base va por v4.8. Tres versionados distintos que no están alineados. No es crítico —cada uno versiona una cosa distinta— pero es deuda de coherencia y conviene declararla. `[PENDIENTE DE VERIFICAR: política de versionado unificada]`

### Qué NO está en la API

Delimitar también define.

- **Orquestación**: n8n. La API no llama servicios externos ni espera aprobaciones.
- **Autenticación de usuarios finales**: no existe. El sistema es monousuario con perfiles; la auth es por token de servicio. Cuando entren clientes, esto se rediseña y probablemente se delegue.
- **Presentación**: el dashboard es un archivo estático servido aparte; la API devuelve JSON.
- **Lógica que puede vivir en SQL**: los saldos son vistas, no queries armadas en JS.

## Regla

Escribí una API propia cuando el contrato de escritura tenga que sobrevivir a los clientes, o cuando necesites garantías —idempotencia, ausencia de borrado, scopes— que la plataforma no puede hacer cumplir. Para CRUD de un solo cliente, un BaaS es mejor decisión y menos código que mantener.

> Última verificación: 2026-08-05
