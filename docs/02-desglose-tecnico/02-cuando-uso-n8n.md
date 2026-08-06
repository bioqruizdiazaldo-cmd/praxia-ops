# Cuándo uso n8n

Qué resuelve bien un runtime de orquestación visual, qué no resuelve, y en qué momento un nodo de código deja de ser una solución y pasa a ser un síntoma.

## Criterio

n8n no compite con escribir código. Compite con **no tener nada**.

La comparación honesta no es "n8n vs. un servicio en Go bien testeado". Es "n8n vs. seis scripts en cron, tres de los cuales fallan en silencio desde hace dos meses". Un runtime de orquestación te da, de fábrica, cosas que en un proyecto propio tardás semanas en construir: registro de ejecuciones, reintentos, credenciales fuera del código, triggers de todo tipo, y una representación visual del flujo que podés mirar cuando algo se rompe a las once de la noche.

### Lo que n8n resuelve bien

| Necesidad | Por qué encaja |
|---|---|
| Pegar 5+ APIs con auth distinta | Las credenciales viven fuera del flujo, referenciadas simbólicamente |
| Triggers heterogéneos (cron, webhook, mensaje, RSS) | Un solo runtime para todos |
| Observabilidad mínima sin construirla | Cada ejecución queda registrada con su input y output por nodo |
| Cambiar el orden de dos pasos | Se arrastra un cable, no se refactoriza |
| Un agente con herramientas | Los nodos `agent` + `toolWorkflow` son la abstracción correcta |
| Mostrarle el flujo a alguien que no programa | El grafo *es* la documentación |

### Lo que n8n no resuelve

| Límite | Consecuencia práctica |
|---|---|
| No es un sistema de versiones | El diff de un workflow es un diff de JSON: ilegible |
| No tiene ambientes | Dev, staging y prod son el mismo runtime salvo que los construyas |
| El estado propio vive donde vive | Si es SQLite, es un archivo; el backup es tuyo |
| Testear es manual por defecto | No hay `n8n test` que corra fixtures y falle el build |
| Lógica densa se vuelve ilegible | 15 nodos `IF` anidados son peor que 20 líneas de código |
| Performance | No es el lugar para procesar cientos de miles de filas |

### La regla de los tres caminos

Antes de agregar un nodo, me pregunto por dónde va a pasar esa lógica:

1. **Si es una garantía de datos** → va a SQL. Ver [01](01-cuando-uso-sql.md).
2. **Si es un contrato con clientes externos** → va a la API propia. Ver [05](05-cuando-uso-una-api-propia.md).
3. **Si es pegamento entre servicios, con timing y ramas** → va a n8n.

n8n es el tejido conectivo. Cuando empieza a ser el órgano, hay un problema de diseño.

## En este sistema

Al corte del **2026-08-03**: **217 workflows registrados, 25 activos, 25 archivados, 125 con nomenclatura de laboratorio**. En 7 días: **377 ejecuciones conservadas, 343 exitosas y 19 fallidas**. Runtime n8n **2.31.5** autohospedado en Docker.

El orquestador `Oppenheimer - Orquestador` nació el **2026-07-14 23:05**. Tenía **47 nodos** en el backup del 27/07 y **51 nodos** al corte del 03/08.

### Cómo está organizado

El orquestador es un agente con herramientas. Las herramientas son de dos clases:

**Nodos directos** — capacidades sin dominio propio: Telegram, OpenAI (chat, Whisper, TTS), Google Drive (`Buscar en Drive`, `Drive - Subir PDF`), Calendar, Gmail, Sheets, Tavily, Open-Meteo (`HTTP CLIMA`), Europe PMC + OpenAlex, PostgreSQL, `Calculator`, `Think`, `Memory Buffer`.

**Subworkflows como herramientas** — 15 subagentes invocados con `toolWorkflow` / `executeWorkflow`. El criterio para separar está en [03](03-cuando-construyo-un-subagente.md).

Lo importante de `toolWorkflow` es que el subagente se convierte en una herramienta con nombre, descripción y esquema de entrada, igual que cualquier otra. El orquestador no sabe que del otro lado hay 9 nodos: ve una función.

### Triggers reales

| Trigger | Workflow | Cuándo |
|---|---|---|
| Telegram Trigger + `If - Owner Only` | Orquestador | Mensaje entrante, filtrado por identidad |
| Cron | `Oppenheimer — Briefing Noticias` | 06:30 |
| Cron | `Oppenheimer - Briefing Diario` | 07:00 |
| Cron | `PraxIA Sync — Export MD` | 23:30 ART |
| Webhook | `Oppenheimer - Recordatorios` | Programación diferida (+ nodo `Wait`) |
| Webhook | `Oppenheimer - Alertas TradingView` | Alerta externa |
| `errorWorkflow` | `PraxIA — Avisador de Errores v1` | Cualquier fallo del runtime |

`If - Owner Only` merece una línea: es el primer nodo después del trigger y descarta todo lo que no venga de la identidad autorizada. La autorización es lo primero que pasa, no una validación intermedia. Un webhook de Telegram es público por definición; el filtro no es opcional.

### Manejo de errores: un solo punto de captura

`PraxIA — Avisador de Errores v1` está configurado como **`errorWorkflow` global**. Cualquier workflow que falle lo dispara. Registra en `praxia.agent_errors` vía la función `praxia.upsert_agent_error` y alerta por Telegram, con **deduplicación y anti-spam validados**.

Por qué esto vale más que un manejo de errores por workflow:

- **Cobertura por default.** Un workflow nuevo queda cubierto sin hacer nada. El manejo de errores opt-in siempre tiene huecos.
- **Un solo formato.** Todos los errores llegan igual y se guardan igual.
- **La deduplicación es obligatoria.** Un webhook que falla cada 30 segundos manda 2.880 mensajes por día. Sin dedup, la alerta se vuelve ruido y dejás de mirarla, que es peor que no tenerla.

La función `upsert_agent_error` hace dedup **y reserva de alertas** en la base, no en el workflow. Es una decisión deliberada: el estado de "ya avisé de esto" tiene que sobrevivir a un reinicio del runtime.

Cronología: creado el **2026-07-22**, integración productiva aprobada el **2026-07-23** con 44 workflows, orquestador de 37 nodos, `praxia.agent_errors` en 0 filas y Traefik OK.

**Deuda técnica declarada**: el workflow todavía se llama con el prefijo `[TEST]` aunque está activo en producción. Es cosmético y es exactamente el tipo de cosa que un sistema honesto publica en vez de esconder.

### El Memory Intent Gate: código determinístico dentro del flujo

Tres nodos: `Code - Memory Intent Gate` → `IF Memory Required` → `PraxIA Memory Preflight`.

Deciden, **con código y no con el LLM**, si hay que consultar la memoria antes de que el modelo conteste. El razonamiento está desarrollado en [07](07-memoria-y-rag.md), pero acá interesa la forma: es un nodo `Code` usado bien. La decisión es una función pura de un string a un booleano, se testea sin red, y no gasta tokens.

La regla de sistema que lo acompaña, textual:

> *"Está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con action=consultar y haber recibido facts=[]"*

Interesa el patrón: el gate garantiza la llamada, el prompt garantiza la interpretación. La garantía dura vive en el código, no en el texto.

### El contrato de salida del Buscador Web

`Oppenheimer — Buscador Web Tavily V1`, 9 nodos:

```
Validar consulta web → IF Consulta válida → Preparar búsqueda
  → HTTP Request - Tavily Search (Header Auth, neverError=true,
                                  timeout 20 s, salida en tavily_response)
  → Validar fuentes y salida → Conservar contexto / Envolver respuesta / Merge
```

Dos detalles que son buenas prácticas trasladables a cualquier runtime:

**`neverError=true` + timeout explícito.** El nodo HTTP no tira excepción ante un 500 de Tavily: devuelve la respuesta y deja que el nodo siguiente decida. Así el error de un tercero se convierte en un **estado del contrato** en vez de un stack trace. Los estados de salida son siete: `ok`, `clarification_required`, `no_reliable_source`, `search_not_configured`, `technical_error`, `stable_knowledge_handoff`, `insufficient_evidence`.

Siete estados en vez de "respuesta o error" es lo que permite que el orquestador reaccione distinto ante "no hay fuente confiable" y ante "la API no está configurada". Uno es un resultado legítimo; el otro es un bug de infraestructura.

**La salida va a un campo con nombre (`tavily_response`).** Suena trivial. El **2026-07-26** hubo una corrección estructural del contexto justamente por esto, validada 8/8. Cuando los nodos escriben en la raíz del item, dos nodos se pisan y el bug aparece tres pasos después. Namespacing explícito.

### Cuándo un nodo Code es la respuesta correcta

| Situación | Veredicto |
|---|---|
| Normalizar formatos (fechas, montos, acentos) | **Correcto.** Es una función pura |
| Una decisión determinística que no debe depender del LLM | **Correcto.** Ej.: Memory Intent Gate |
| Validar un contrato y emitir un estado tipado | **Correcto.** Ej.: `Validar fuentes y salida` |
| Armar un payload con lógica condicional | **Correcto** si son 20 líneas |
| Reimplementar un join entre tres fuentes | **Olor.** Eso es SQL |
| Un `switch` de 12 ramas que despacha a workflows | **Olor.** Eso es un router mal modelado |
| Llamadas HTTP a mano con `fetch` | **Olor.** Perdés las credenciales gestionadas y el registro del nodo |
| Más de ~80 líneas | **Olor.** Si es lógica de negocio va a la API; si es transformación, partila |

El olor no es el nodo `Code`: es el nodo `Code` **que crece**. Un nodo de 200 líneas dentro de un workflow es código sin tests, sin revisión y sin diff legible. Todo lo malo de escribir código sin nada de lo bueno.

En este sistema la línea se trazó así: las transformaciones y los gates viven en nodos `Code`; la lógica financiera vive en `api/server.mjs` (~70 KB, Node.js ESM sin framework) con 606 tests que la cubren. n8n llama a la API; no la reimplementa.

### Los límites que este sistema efectivamente pegó

Estos no son límites teóricos. Están documentados como riesgos abiertos.

**1. n8n guarda su propio estado en SQLite.**
El runtime usa SQLite para workflows, credenciales y ejecuciones. PostgreSQL está aparte, para memoria y finanzas. Consecuencia: el backup de n8n es el backup de un archivo, y la recuperación es un procedimiento propio — construido el 2026-07-15 junto con `RECOVERY.md`. No es un problema mientras esté asumido; sería un problema si alguien supusiera que "está en la base".

**2. Producción se usó como laboratorio.**
Textual de la línea base de gobernanza:

> *"El entorno de producción también ha sido utilizado como laboratorio y archivo histórico, porque conserva numerosos workflows de prueba, candidatos y respaldos."*

125 de 217 workflows tienen nomenclatura de laboratorio. El 2026-07-25 se hizo el inventario: 79 workflows de laboratorio clasificados en **clase A = 73** (borrables), **clase B = 4**, **clase C = 2** (activos, con tráfico). Inventariar antes de borrar es lo correcto; haber llegado a 79 es la deuda.

La causa raíz es que n8n hace **muy barato** duplicar un workflow para probar algo, y **nada barato** distinguir después cuál era el bueno. Sin ambientes separados, el laboratorio se acumula donde vive producción.

**3. Los diffs de JSON son ilegibles.**
Un workflow exportado es un JSON con posiciones de nodos, IDs generados y parámetros anidados. Mover un nodo dos píxeles produce un diff. Esto rompe la revisión de código tal como la conocemos: no se puede aprobar un cambio leyendo el diff.

La respuesta del proyecto es el **manifiesto mínimo de versionado de workflows no-code**: nombre lógico estable, owner, entorno, estado de ciclo de vida, contrato de entrada y salida, dependencias, credenciales por referencia simbólica, clasificación de datos, revisión de origen, evidencia de test, artefacto de rollback. Ciclo de vida `draft → test → staging → production → deprecated → archived`.

Y el pipeline de 10 pasos: exportar → normalizar → escanear secretos → validar estructura → probar contratos con fixtures ficticios → importar en staging aislado como inactivo → **revisar el grafo visual** → publicar tras aprobación → registrar hash desplegado → verificar y conservar rollback.

El paso 7 es la clave: si el diff no se puede revisar, se revisa el grafo. Se cambia la unidad de revisión, no se abandona la revisión.

**4. No hay separación de ambientes.**
Riesgo abierto declarado. La consecuencia práctica está en el TO-BE:

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Hoy es al revés: el runtime es la fuente de verdad y el repo es una copia. Todo lo demás —el drift del 2026-08-05, los 125 workflows de laboratorio, los `[TEST]` en producción— se deriva de esa inversión.

## Regla

n8n es tejido conectivo, no órgano. Si un nodo `Code` crece o un workflow acumula ramas, la lógica se está fugando del lugar donde se puede testear: bajala a SQL o a la API. Y asumí desde el día uno que el runtime no versiona: el pipeline de exportación y el artefacto de rollback son tuyos.

> Última verificación: 2026-08-05
