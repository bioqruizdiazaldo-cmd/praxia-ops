# Glosario

Los términos que aparecen en todo el repositorio, explicados en criollo y con un ejemplo del propio sistema cuando aplica.

## Cómo está armado

Orden alfabético, definición de una a tres líneas, y ejemplo concreto de PraxIA Ops cuando existe.

Si un término te aparece en otro documento y no está acá, es un hueco: anotalo.

---

## A

**ADR** — *Architecture Decision Record*. Un documento corto que registra una decisión de arquitectura, por qué se tomó y qué alternativas se descartaron. Sirve para que dentro de seis meses nadie pregunte "¿por qué está hecho así?".

*Ejemplo:* el ADR definitivo rev.2 de PraxIA Finanzas, cerrado el 2026-08-02/03, y los cinco ADRs de AI-Command-Center del 2026-07-20.

**Adaptador** — Pieza de código que traduce un formato de entrada al formato interno del sistema. Cada origen tiene el suyo.

*Ejemplo:* PraxIA Finanzas tiene cuatro adaptadores —PDF, CSV, Excel y email— y los cuatro producen el mismo contrato universal.

**Auditoría** — El registro de qué se cambió, cuándo y quién lo cambió. No es un log de errores: es la historia de las modificaciones.

*Ejemplo:* la tabla `movimientos_auditoria` guarda cada cambio de cada movimiento, y `fiscal_auditoria` es directamente inmutable.

## B

**Baja lógica** — Marcar un registro como inactivo o anulado en vez de borrarlo de la base. El dato deja de contar pero sigue existiendo, y su historia se puede reconstruir.

*Ejemplo:* anular un movimiento en Finanzas, o poner `active = false` en un hecho de memoria. En Finanzas está reforzado por un trigger que directamente prohíbe el borrado físico.

## C

**Canary** — Una prueba en producción con alcance mínimo y controlado, antes de habilitar algo para todo el mundo. Si el canario se muere, no seguís bajando a la mina.

*Ejemplo:* el "canary Telegram aprobado" del 2026-07-27, que validó la carga de movimientos por Telegram antes de dar por completada la Fase 2.

**Contrato universal** — El formato único al que se traduce toda entrada, sin importar por dónde llegó. Garantiza que no haya dos formas distintas de representar la misma cosa.

*Ejemplo:* textual — *"Toda entrada —Telegram, dashboard, PDF, CSV, email o un agente— produce el mismo contrato universal y termina en la misma base."*

**Cron** — El programador de tareas del sistema operativo. Ejecuta un comando a una hora fija, todos los días, sin intervención.

*Ejemplo:* el cron de las 23:35 que sube con rclone el export de memoria a OneDrive. Ojo: es cron del servidor, no un workflow de n8n, y por eso no lo cubre el avisador de errores.

## D

**DDL** — *Data Definition Language*. La parte de SQL que crea y modifica la estructura de la base: tablas, columnas, índices, vistas. Es lo distinto de las consultas, que solo leen o escriben datos.

*Ejemplo:* el "DDL v3.1 aplicado al VPS con backups y SHA-256 verificados" del 2026-07-27, que creó el esquema base de Finanzas.

**Deduplicación** — Detectar que algo ya existe y no volver a crearlo. Es lo que impide que el mismo gasto se cargue dos veces o que la misma alerta te llegue cien veces.

*Ejemplo:* tres lugares distintos la usan — `Guardar Hecho` deduplica por normalización de texto, `documentos` deduplica por SHA-256, y `praxia.upsert_agent_error` deduplica alertas.

**Drift** — La diferencia entre lo que dice el código versionado y lo que está corriendo de verdad en el servidor. Un sistema con drift documenta una cosa y hace otra.

*Ejemplo:* el 2026-08-05 se descubrió que producción estaba tres migraciones atrás desde el 31/07, porque *"nadie había mirado el servidor, solo el repositorio"*.

## E

**Embedding** — Una representación numérica de un texto que permite buscar por significado en vez de por palabras. Es la base de la búsqueda semántica.

*Ejemplo:* **PraxIA Memory no usa embeddings.** La búsqueda es SQL con texto completo en español. Es una decisión, no un olvido: más simple, más barato y auditable, a cambio de no encontrar sinónimos lejanos.

**Endpoint** — Una dirección de la API que hace una cosa específica. El punto donde un programa le pide algo a otro.

*Ejemplo:* `POST /api/ingesta` es el único endpoint de alta de movimientos. Y en toda la API de Finanzas **no existe ningún endpoint DELETE**.

**errorWorkflow** — En n8n, el workflow que se ejecuta automáticamente cuando otro falla. Configurado a nivel global, atrapa las fallas de todo el sistema.

*Ejemplo:* `PraxIA — Avisador de Errores v1` está enganchado como errorWorkflow global desde el 2026-07-22.

## F

**Fixture** — Un dato de prueba fijo y ficticio que se usa para testear siempre contra lo mismo. Si el test pasa hoy y falla mañana, el cambio está en el código, no en los datos.

*Ejemplo:* del cierre del buscador — *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."*

## G

**Gate** — Una compuerta: un punto del flujo donde se decide si se sigue o se corta. La diferencia con una instrucción en un prompt es que un gate es estructura, no sugerencia.

*Ejemplo:* el gate "¿Tiene secreto?" del Memory Router, que deriva a `Rechazo Secreto`; y el `Memory Intent Gate`, que es código y decide determinísticamente si hay que consultar la memoria.

## H

**Harness** — El andamiaje que permite correr pruebas de forma repetible, con una base o un entorno simulados.

*Ejemplo:* los 554 tests de Finanzas corren con un harness basado en **PGlite**, que replica el esquema real de PostgreSQL sin necesidad de levantar el servidor.

**Huella** — Un identificador derivado del contenido, que cambia si el contenido cambia. Sirve para detectar repeticiones y detectar modificaciones.

*Ejemplo:* las propuestas fiscales tienen `huella` —para no volver a proponer lo mismo que ya rechazaste— y `huella_evidencia` —para que no apruebes algo cuya evidencia cambió—.

## I

**Idempotencia** — Propiedad de una operación que, repetida, da el mismo resultado que ejecutada una sola vez. Es lo que hace seguro reintentar sin duplicar.

*Ejemplo:* la `idempotency_key` de `ingesta_raw`. Si el mismo mensaje de Telegram se procesa dos veces por un reintento de red, el gasto se carga una sola vez.

**Ingesta** — El acto de meter un dato al sistema desde afuera, con su validación y su registro de origen.

*Ejemplo:* `POST /api/ingesta` es el único camino de alta en Finanzas, y guarda el texto original cifrado junto con el canal y el actor.

## L

**LLM** — *Large Language Model*, el modelo de lenguaje que genera las respuestas. Es una pieza del sistema, no el sistema.

*Ejemplo:* el orquestador usa OpenAI para redactar, pero las decisiones críticas —consultar memoria, rechazar secretos, validar evidencia— las toma código determinístico, no el LLM.

## M

**Máquina de estados** — Un conjunto cerrado de estados posibles y de transiciones permitidas entre ellos. Impide que algo salte de un estado a otro sin pasar por el camino correcto.

*Ejemplo:* el flujo de PDF (`received → validated → text_extracted → reviewed → archived | failed`) y el ciclo de un movimiento (pendiente → confirmado → anulado).

**MCP** — *Model Context Protocol*. Un estándar para que un asistente de IA use herramientas externas de forma controlada, con permisos declarados.

*Ejemplo:* `praxia-finanzas-mcp@1.0.0` expone 22 herramientas en 4 scopes, y es lo que permite que ChatGPT, Claude o Cowork consulten las finanzas sin acceso directo a la base.

**Migración** — Un cambio versionado de la estructura de la base. Se aplica en orden, queda registrado y se puede auditar.

*Ejemplo:* el esquema de Finanzas va por la v4.8. Se aplican con `ON_ERROR_STOP=1` dentro de una transacción: si algo falla, no queda a medio camino.

## N

**n8n** — La plataforma de automatización donde viven los workflows. Se programa conectando nodos en un lienzo, y en este sistema corre autohospedada en un VPS.

*Ejemplo:* el orquestador de Oppenheimer es un workflow de n8n con 51 nodos.

**Nodo** — Cada cajita de un workflow: hace una cosa —llamar una API, decidir, transformar datos— y le pasa el resultado a la siguiente.

*Ejemplo:* `If - Owner Only`, `Analyze Image`, `HTTP CLIMA` y `Telegram - Approve Send` son nodos del orquestador.

## O

**Orquestador** — El workflow central que recibe todo, interpreta qué se pide y decide qué herramienta o subagente usar. Es el que coordina; los subagentes ejecutan.

*Ejemplo:* `Oppenheimer - Orquestador`, activo desde el 2026-07-14 23:05, con 51 nodos al 2026-08-03.

## P

**Placeholder token** — Un marcador que reemplaza un dato sensible antes de mandarlo a un tercero. El dato real queda cifrado del lado del servidor; afuera viaja el marcador.

*Ejemplo:* los tokens del tipo `⟦S1⟧` que PraxIA Finanzas usa para que el LLM nunca vea el dato sensible original.

**Prompt de sistema** — Las instrucciones fijas que recibe el modelo en cada conversación. Definen su rol, sus límites y sus prohibiciones.

*Ejemplo:* el del orquestador incluye — *"Está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con action=consultar y haber recibido facts=[]"*.

## R

**RAG** — *Retrieval Augmented Generation*: buscar documentos relevantes y pasárselos al modelo para que responda sobre ellos en vez de sobre lo que "recuerda".

*Ejemplo:* **el sistema no usa RAG vectorial.** La memoria es SQL con búsqueda de texto en español, en dos niveles de coincidencia.

**rclone** — Herramienta de línea de comandos para sincronizar archivos con almacenamiento en la nube.

*Ejemplo:* el cron de las 23:35 que sube la bóveda exportada a OneDrive.

**Rollback** — Volver a la versión anterior que funcionaba. Un despliegue sin rollback preparado es una apuesta.

*Ejemplo:* antes de meter el Memory Gate en el orquestador (2026-07-20) se guardó el rollback. Y el manifiesto de versionado de workflows exige "artefacto de rollback" como campo obligatorio.

## S

**Scope OAuth** — Un permiso con nombre que limita qué puede hacer quien tiene el token. No es una promesa: si el scope no está, la llamada se rechaza.

*Ejemplo:* los cuatro scopes de Finanzas — `praxia.read` (8 herramientas), `praxia.fiscal.read` (10), `praxia.write` (1) y `praxia.modify` (4, con confirmación explícita). Un agente con `praxia.read` no puede anular un movimiento aunque se lo pidan.

**SHA-256** — Una función que produce una huella única de un archivo. Dos archivos idénticos dan la misma huella; cambiar un byte la cambia entera.

*Ejemplo:* la tabla `documentos` guarda el SHA-256 de cada archivo subido, y por eso subir dos veces el mismo resumen de tarjeta no lo procesa dos veces.

**Staging** — Un ambiente intermedio entre desarrollo y producción, donde se prueba con condiciones parecidas a las reales antes de publicar.

*Ejemplo:* está en el pipeline de 10 pasos del manifiesto de versionado, pero **no existe en la práctica**: la falta de separación de ambientes es una de las deudas técnicas abiertas.

**Subagente** — Un workflow especializado que el orquestador llama para una tarea concreta y que devuelve un resultado. Aísla el riesgo: si uno falla, los demás siguen.

*Ejemplo:* los catorce subagentes de Oppenheimer, invocados como `toolWorkflow` / `executeWorkflow`. Ver [subagentes](03-subagentes.md).

## T

**Trigger (n8n)** — El nodo que arranca un workflow: un mensaje que llega, un horario que se cumple, un webhook que se llama.

*Ejemplo:* `Telegram Trigger` en el orquestador; el trigger de horario de las 07:00 en el Briefing Diario.

**Trigger SQL** — Una regla que la base ejecuta sola cuando pasa algo, sin que la aplicación pueda evitarlo. Es la forma más fuerte de garantizar una regla.

*Ejemplo:* `prohibir_delete_fisico` impide borrar movimientos; `propuesta_contenido_inmutable` impide que una propuesta cambie después de creada; `recalcular_saldo_deuda` mantiene el saldo consistente.

**TTS** — *Text To Speech*: convertir texto en voz. Es lo que hace que Oppenheimer te conteste hablando.

*Ejemplo:* la voz configurada se llama "Jarvis" y se usa en las respuestas a notas de voz.

## V

**Vista** — Una consulta guardada en la base a la que se accede como si fuera una tabla. No duplica datos: los calcula cada vez.

*Ejemplo:* `v_saldos_por_moneda`, `v_pendientes_completables`, `v_deudas`, `v_fiscal_periodo`. Es lo que permite preguntar "¿cuánto tengo?" sin recalcular nada a mano.

## W

**Webhook** — Una URL que queda esperando a que un sistema externo la llame. Es la forma de que algo de afuera dispare un workflow.

*Ejemplo:* el webhook de recordatorios y el que recibe las alertas de TradingView.

**Whisper** — El modelo de OpenAI que transcribe audio a texto.

*Ejemplo:* transcribe tus notas de voz antes de que entren al orquestador como si las hubieras escrito.

**Workflow** — Un flujo automatizado completo, hecho de nodos conectados. En este sistema, cada subagente, cada rutina y el propio orquestador son workflows.

*Ejemplo:* al 2026-08-03 había 217 workflows registrados: 25 activos, 25 archivados y 125 con nomenclatura de laboratorio.

---

## Vocabulario de evidencia

Estas cinco etiquetas se usan en toda la documentación del proyecto para marcar cuánto respaldo tiene una afirmación. No son opinables: cada una significa algo distinto.

| Etiqueta | Significa |
|---|---|
| `Verificado` | Se inspeccionó el sistema real y se comprobó |
| `Confirmado por el responsable` | Lo afirma quien lo construyó, sin inspección independiente |
| `Inferido` | Se deduce de otras evidencias, no se observó directo |
| `Pendiente de verificar` | Falta comprobarlo |
| `Historia incompleta` | Hay un hueco reconocido en el relato |

La regla que las sostiene: *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

> Última verificación: 2026-08-05
