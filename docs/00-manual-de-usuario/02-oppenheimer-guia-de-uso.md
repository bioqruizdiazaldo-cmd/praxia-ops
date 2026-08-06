# Oppenheimer — guía de uso

Cómo se usa Oppenheimer todos los días desde Telegram: qué le podés mandar, con qué palabras, qué pasa por detrás y dónde están los límites reales.

## Lo primero que tenés que saber

**No hay comandos.** No hay `/agenda`, no hay `/gasto`, no hay menú. Le escribís en castellano como le escribirías a una persona y el orquestador decide qué herramienta usar.

**Solo responde al dueño.** El primer nodo después de recibir el mensaje es un filtro (`If - Owner Only`) que compara la identidad de Telegram. Si el mensaje viene de cualquier otra cuenta, el flujo se corta ahí. No hay respuesta, no hay error visible del otro lado.

**Es un canal único.** Todo entra y sale por Telegram. No hay app web para conversar, no hay WhatsApp, no hay interfaz de escritorio. El dashboard de Finanzas es lo único que se opera fuera de Telegram, y es para finanzas nada más.

**Está siempre prendido.** Corre en un VPS con Docker, 24/7. Si no responde, es una falla, no un horario.

## Sobre los ejemplos de este documento

Las frases de ejemplo que aparecen abajo son **sintéticas**: ilustran el tipo de pedido, no son una lista cerrada de disparadores verificados. El orquestador interpreta lenguaje natural con un modelo, no con una tabla de palabras clave.

`[PENDIENTE DE VERIFICAR]`: no existe un inventario documentado de las frases exactas que activan cada subagente. Si necesitás garantía de que un pedido cae en el subagente correcto, probalo y verificá la respuesta.

## Los cuatro tipos de entrada

| Entrada | Qué acepta | Qué devuelve |
|---|---|---|
| Texto | Cualquier mensaje escrito | Texto |
| Voz | Nota de voz de Telegram | Texto y/o audio hablado |
| Imagen | Foto o imagen enviada al chat | Texto describiendo o interpretando la imagen |
| PDF | Documento PDF adjunto | Texto extraído + archivado en Drive |

---

## Texto

El modo por defecto. Escribís, responde.

### Qué le podés pedir

**Agenda y calendario.**

- "¿Qué tengo mañana?"
- "Agendame reunión con el contador el jueves a las 15."
- "Movele la reunión del martes a las 17."
- "Cancelá el turno del viernes."

Por detrás: el orquestador llama al [Agente de Calendario](03-subagentes.md#agente-de-calendario), que hace Get, Create, Update o Delete contra Google Calendar.

**Mails.**

- "¿Tengo algo importante en el mail?"
- "Buscá los mails de la aseguradora de esta semana."
- "Escribile a X confirmando la reunión del jueves."

Por detrás: el [Agente de Email](03-subagentes.md#agente-de-email) busca, lee o redacta. **Si el pedido implica enviar, no envía**: te muestra el borrador y espera que aprietes aprobar en Telegram.

**Memoria.**

- "Acordate de que el proveedor nuevo cobra a 30 días."
- "¿Qué habíamos decidido sobre el tema de los backups?"
- "¿Cuáles son mis tareas pendientes del proyecto X?"

Por detrás: el [Router de memoria](03-subagentes.md#praxia-memory--router) despacha a Guardar, Consultar, Tareas o Proyectos según la intención, y antes de escribir pasa por un gate que revisa si hay secretos.

**Búsqueda web.**

- "Buscame qué se dijo esta semana sobre X."
- "¿Cuánto está el dólar hoy?" (esto puede caer en búsqueda web o en finanzas según cómo lo pidas)

Por detrás: el [Buscador Web Tavily](03-subagentes.md#buscador-web-tavily-v1), que no devuelve una respuesta suelta: devuelve un contrato con estado. Si no encontró fuente confiable, lo dice.

**Papers científicos.**

- "Buscame papers sobre resistencia a carbapenemes de los últimos dos años."

Por detrás: el [Agente Papers Científicos v2.1](03-subagentes.md#agente-papers-científicos-v21) arma la query, consulta Europe PMC y OpenAlex, rankea, escribe un resumen y lo deja en Google Sheets.

**Clima.**

- "¿Cómo va a estar el clima mañana?"

Por detrás: nodo `HTTP CLIMA` contra Open-Meteo.

**Planillas.**

- "Guardá en la planilla de gastos: nafta 45000."
- "¿Cuánto llevo gastado este mes según la planilla?"

Por detrás: el [Agente de Planillas](03-subagentes.md#agente-de-planillas) clasifica entre `GUARDAR:` y `CONSULTA:` y deriva las consultas a un subagente separado.

**Finanzas.**

- "Anotá 45000 de nafta."
- "¿Cuánto tengo en pesos?"

Por detrás: enrutamiento a PraxIA Finanzas. Ver [la guía de Finanzas](04-praxia-finanzas-guia-de-uso.md) — es un sistema aparte con reglas propias.

**Cuentas y razonamiento.**

El orquestador tiene dos nodos auxiliares: `Calculator` para hacer cuentas sin que el modelo las invente, y `Think` para razonar en pasos antes de contestar.

**Recordatorios.**

- "Recordame en dos horas llamar al taller."

Por detrás: webhook + nodo de espera + mensaje de Telegram.

### Qué pasa cuando el pedido toca memoria

Antes de que el modelo escriba una sola palabra, corre el **Memory Intent Gate**: un nodo de código —no un LLM— que decide de forma determinística si hay que consultar la base de memoria.

La regla del prompt de sistema es textual y es dura:

> *"Está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con action=consultar y haber recibido facts=[]"*

Traducción: si te dice que no sabe algo, es porque fue a fijarse y no había nada. No porque no se le ocurrió.

---

## Voz

Le mandás una nota de voz y te contesta. Es el modo más rápido para cargar cosas mientras hacés otra cosa.

### El circuito

1. Telegram entrega el archivo de audio.
2. Se transcribe con **OpenAI Whisper**.
3. El texto transcripto entra al orquestador como si lo hubieras escrito.
4. La respuesta puede volver hablada, con **TTS** y la voz configurada como **"Jarvis"**.

### Qué conviene y qué no

**Funciona bien** para cargar gastos, dictar recordatorios, guardar hechos en memoria y preguntas cortas de agenda.

**Funciona peor** para nombres propios raros, números largos con decimales y direcciones de mail. La transcripción es buena, no es perfecta. Si dictás un monto, verificá lo que quedó cargado.

`[PENDIENTE DE VERIFICAR]`: no hay un límite de duración de audio documentado en la fuente. Los límites que apliquen son los de la API de Telegram y los de Whisper, no un límite propio del sistema.

---

## Imagen

Le mandás una foto y la interpreta.

### El circuito

Telegram entrega la imagen, el nodo `Analyze Image` la procesa contra el modelo multimodal, y la respuesta vuelve como texto.

### Para qué sirve

- Leer un ticket, una factura, una etiqueta.
- Describir una foto.
- Sacar el texto de una captura de pantalla.

### Qué esperar

La lectura es del modelo, no de un OCR dedicado. Para un ticket arrugado o una foto movida, va a fallar o va a inventar dígitos.

**Regla práctica**: si de esa imagen sale un número que va a la base financiera, leé lo que te devuelve antes de confirmar. En Finanzas todo movimiento nace pendiente justamente por esto.

`[PENDIENTE DE VERIFICAR]`: no está documentado el límite de tamaño ni de resolución de imagen.

---

## PDF

Este es el flujo más trabajado de todos, y tiene una historia detrás.

### La historia

El 2026-07-25 a las 18:25 ART, la ejecución 1292 falló en el nodo `Telegram - Get Documento` con el error `Bad Request: file is too big`. Era un PDF de 21,9 MB.

Ese mismo día se publicó la reparación: validación previa, límite explícito, verificación de firma, extracción real y una máquina de estados. Se probó con 6 casos, 6 PASS.

### El circuito, paso a paso

1. **Recepción**: Telegram entrega el documento.
2. **Validación previa**: se chequea tamaño antes de intentar descargar.
3. **Verificación de firma**: se confirma que el archivo empiece con `%PDF-`. Un archivo renombrado a `.pdf` que no es un PDF se rechaza acá.
4. **Extracción**: se saca el texto real del documento.
5. **Revisión**: el contenido pasa al orquestador.
6. **Archivado**: el PDF va a Google Drive por el nodo `Drive - Subir PDF`.

### La máquina de estados

```
received → validated → text_extracted → reviewed → archived
                    ↘ failed
```

Cualquier paso puede terminar en `failed`. Si eso pasa, el estado te dice dónde se cortó.

### Los límites reales

| Límite | Valor | Qué pasa si lo cruzás |
|---|---|---|
| Tamaño máximo | **20 MiB** | Se rechaza en la validación previa, con mensaje. No intenta descargar |
| Firma de archivo | Debe empezar con `%PDF-` | Se rechaza como archivo inválido |
| PDF escaneado sin texto | No hay OCR documentado en este flujo | La extracción devuelve poco o nada |

Si tenés un PDF de más de 20 MiB: partilo, comprimilo, o subilo a Drive por tu cuenta y pedile que lo busque desde ahí (el orquestador tiene el nodo `Buscar en Drive`).

### PDF financiero

Un resumen de tarjeta o un extracto bancario en PDF **no** se carga por este flujo. Va por el flujo de documentos de PraxIA Finanzas, que tiene deduplicación por SHA-256 y un paso de análisis antes de importar. Ver [Importar un documento](04-praxia-finanzas-guia-de-uso.md#importar-un-documento).

---

## Las herramientas que tiene conectadas

Esto es lo que hay enchufado al orquestador, al corte del 2026-08-03.

| Herramienta | Para qué |
|---|---|
| Telegram | Canal de entrada y salida |
| OpenAI | Chat, transcripción (Whisper) y voz (TTS) |
| Google Drive | Buscar archivos, subir PDFs |
| Google Calendar | Agenda |
| Gmail | Leer, buscar, redactar, enviar (con aprobación) |
| Google Sheets | Planillas |
| Tavily | Búsqueda web con contrato de evidencia |
| Open-Meteo | Clima (`HTTP CLIMA`) |
| Europe PMC + OpenAlex | Papers científicos |
| PostgreSQL | Memoria estructurada |
| Webhook de recordatorios | Avisos programados |
| `Calculator` | Cuentas exactas |
| `Think` | Razonamiento en pasos |
| `Memory Buffer` | Contexto de la conversación reciente |

## Los límites, todos juntos

Para no buscarlos por el documento.

| Límite | Detalle |
|---|---|
| **Solo el dueño** | El filtro `If - Owner Only` descarta todo lo que no venga de la cuenta autorizada |
| **Un solo canal** | Telegram. No hay web, ni WhatsApp, ni mail de entrada |
| **PDF: 20 MiB** | Validado antes de descargar |
| **PDF: firma obligatoria** | Debe empezar con `%PDF-` |
| **Mails: no envía solo** | Requiere aprobación por Telegram |
| **Búsqueda web: puede decir que no** | Estados como `no_reliable_source` o `insufficient_evidence` son respuestas válidas |
| **Memoria: no guarda secretos** | Hay un gate que rechaza contraseñas, tokens, claves y datos bancarios completos |
| **Finanzas: nada se borra** | Solo baja lógica con auditoría |
| **Finanzas: cambios con confirmación** | Corregir, confirmar, anular e importar requieren un sí explícito |

## Qué no hace

- No inicia conversaciones por su cuenta salvo por las [rutinas programadas](06-rutinas-automaticas.md).
- No accede a nada que no esté en su lista de herramientas.
- No publica en redes sociales. Eso está planificado en otro proyecto, en fase cero.
- No maneja usuarios distintos del dueño. El agente para una segunda persona está decidido en arquitectura pero no construido.
- No borra información financiera.
- No inventa cotizaciones ni datos ausentes.

## Cómo darte cuenta de que algo salió mal

Tres señales.

**Silencio.** Si mandás algo y no vuelve nada en un rato, el flujo se cortó. Puede ser el filtro de dueño, un nodo caído o el runtime.

**Un mensaje de error del avisador.** Existe un workflow global (`PraxIA — Avisador de Errores v1`) que está enganchado como `errorWorkflow` de todo el sistema: registra la falla en `praxia.agent_errors` y te avisa por Telegram. Tiene deduplicación y anti-spam validados, así que si te llega, es real y no es repetido.

**Una respuesta con estado.** Especialmente en búsqueda web. `clarification_required` significa que tu pedido era ambiguo; `no_reliable_source` significa que buscó y no encontró nada que sostenga la respuesta.

Qué hacer con cada caso: [cuando algo falla](07-cuando-algo-falla.md).

## Un detalle de contexto sobre el runtime

Al 2026-08-03 el runtime tenía **217 workflows registrados, 25 activos, 25 archivados y 125 con nomenclatura de laboratorio**. En siete días hubo 377 ejecuciones conservadas: 343 exitosas y 19 fallidas.

Esos 125 workflows de laboratorio conviviendo con producción son una deuda técnica reconocida. Para vos como usuario no cambia nada —los que están activos son 25— pero explica por qué el equipo trata la separación de ambientes como la próxima prioridad.

> Última verificación: 2026-08-05
