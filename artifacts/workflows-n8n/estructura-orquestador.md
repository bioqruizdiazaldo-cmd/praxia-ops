# Estructura del orquestador y del buscador

Descripción nodo por nodo del orquestador de Oppenheimer y del subagente de búsqueda web, sin exportar el JSON y sin un solo ID de credencial.

> **Reconstrucción didáctica.** Los nombres de nodo son los verificados; la descripción de entradas y salidas es una reconstrucción fiel al comportamiento documentado. Las credenciales aparecen como referencias simbólicas. Al corte del 2026-08-03 el orquestador tenía **51 nodos**; acá se describen los que definen la arquitectura, no los 51.

---

## Oppenheimer — Orquestador

Creado el 2026-07-14 23:05. Estado: activo, producción. Evolución de nodos: 37 (23/07) → 47 (27/07) → 51 (03/08).

### Entrada y control de acceso

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Telegram Trigger` | Trigger | Recibe todo mensaje entrante del bot: texto, voz, imagen, documento | Update de Telegram (`CRED_TELEGRAM_BOT`) | Mensaje crudo con remitente, tipo y adjunto |
| `If - Owner Only` | IF | Filtra por identidad del remitente. **Corta antes de cualquier nodo de IA** | Mensaje crudo | Rama verdadera: mensaje autorizado. Rama falsa: descarte silencioso |

Que el filtro esté en el segundo nodo no es casualidad: un mensaje no autorizado no debe consumir ni un token ni una llamada a una API paga.

### Rama multimodal

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Switch - Tipo de mensaje` | Switch | Deriva según sea texto, voz, imagen o documento | Mensaje autorizado | Una de cuatro ramas |
| `OpenAI - Transcribir` | OpenAI (Whisper) | Convierte la nota de voz a texto | Archivo de audio (`CRED_OPENAI`) | Texto transcripto + marca `entro_por_voz = true` |
| `Analyze Image` | OpenAI (visión) | Describe o interpreta la imagen | Archivo de imagen | Descripción textual |
| `Validar PDF` | Code | Verifica tamaño (**límite 20 MiB**) y firma `%PDF-` antes de descargar | Metadatos del documento | `validated` o `failed` con motivo |
| `Telegram - Get Documento` | Telegram | Descarga el archivo | Referencia del documento | Binario |
| `Extraer texto PDF` | Extract from File | Extrae el texto real del PDF | Binario | Texto + estado `text_extracted` |
| `Drive - Subir PDF` | Google Drive | Archiva el documento (`CRED_GOOGLE_OAUTH`) | Binario + metadatos | Referencia en Drive + estado `archived` |

La validación **antes** de la descarga es la corrección del incidente del 2026-07-25: la ejecución 1292 murió en `Telegram - Get Documento` con `Bad Request: file is too big` frente a un PDF de 21,9 MB. La máquina de estados resultante es `received → validated → text_extracted → reviewed → archived | failed`, con 6/6 pruebas PASS.

### Gate de memoria

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Code - Memory Intent Gate` | Code | Decide **en código, sin LLM**, si la consulta requiere memoria previa | Texto del mensaje | `{ memory_required: boolean, motivo: string, consulta_sugerida: string }` |
| `IF Memory Required` | IF | Bifurca según la decisión del gate | Salida del gate | Rama con preflight / rama directa |
| `PraxIA Memory Preflight` | Execute Workflow | Consulta la memoria **antes** de que el modelo hable | `{ action: "consultar", consulta }` | `{ facts: [...] }`, posiblemente vacío |

El punto entero del gate: la decisión es determinística, barata y auditable. Y habilita la regla dura del prompt de sistema — *"está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con `action=consultar` y haber recibido `facts=[]`"*.

### Núcleo

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Orquestador Oppenheimer` | AI Agent | El agente central: recibe el mensaje y los hechos del preflight, elige herramientas y compone la respuesta | Texto + `facts` + historial | Respuesta en texto + llamadas a herramientas |
| `OpenAI Chat Model` | Modelo | Modelo de lenguaje del agente (`CRED_OPENAI`) | Prompt del agente | Completado |
| `Memory Buffer` | Memoria | Conversación reciente (capa 1 de la memoria) | Turnos previos | Contexto de sesión |
| `Think` | Herramienta | Espacio de razonamiento explícito antes de actuar | Estado del agente | Nota de razonamiento |
| `Calculator` | Herramienta | Aritmética exacta, para no delegarla al modelo | Expresión | Resultado numérico |

### Herramientas directas

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Buscar en Drive` | Google Drive Tool | Busca archivos por nombre o contenido (`CRED_GOOGLE_OAUTH`) | Criterio de búsqueda | Lista de archivos con referencia |
| `Google Calendar Tool` | Calendar Tool | Lectura rápida de agenda | Rango de fechas | Eventos |
| `Google Sheets Tool` | Sheets Tool | Lectura y escritura en planillas | Rango + valores | Filas |
| `Gmail Tool` | Gmail Tool | Búsqueda y lectura de correo | Consulta | Mensajes |
| `HTTP CLIMA` | HTTP Request | Clima vía Open-Meteo (API abierta, sin credencial) | Coordenadas + fecha | Pronóstico |
| `Europe PMC / OpenAlex` | HTTP Request | Búsqueda bibliográfica | Consulta estructurada | Resultados con metadatos |

### Subagentes invocados como herramienta

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Agente de Email` | Tool Workflow | Buscar, leer y redactar Gmail. **El envío pasa por aprobación** | `{ accion, criterio, destinatario, asunto, cuerpo }` | `{ estado, resultado }` |
| `Agente de Calendario` | Tool Workflow | Get / Create / Update / Delete de eventos | `{ accion, evento }` | `{ estado, evento_id }` |
| `Agente de Planillas` | Tool Workflow | Sheets; clasifica `GUARDAR:` vs `CONSULTA:` | `{ intencion, datos }` | `{ estado, filas }` |
| `Agente Papers v2.1` | Tool Workflow | query-builder → Europe PMC + OpenAlex → ranker → writer → Sheets | `{ tema, alcance }` | `{ estado, resumen, planilla }` |
| `Buscador Web Tavily V1` | Tool Workflow | Búsqueda con contrato de evidencia | `{ consulta, target_date, date_scope }` | `{ estado, respuesta, fuentes }` |
| `PraxIA Memory — Router` | Tool Workflow | Despacho de memoria con gate anti-secretos | `{ action, payload }` | `{ estado, facts \| id }` |

### Aprobación humana

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Telegram - Approve Send` | Telegram (sendAndWait) | Muestra el borrador y espera confirmación explícita | Borrador de mail | Respuesta del usuario |
| `If - Approved` | IF | Bifurca según la respuesta | Respuesta | Rama de envío / rama de descarte |
| `Oppenheimer - Enviar Gmail` | Execute Workflow | Envío real, sólo después de la aprobación | Mail aprobado | Confirmación |

Decisión **D-7**: enviar mails, borrar, gastar y publicar pasan por una persona. La aprobación es un nodo del flujo, no una recomendación del prompt.

### Salida

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `Componer respuesta` | Set / Code | Arma el mensaje final y decide el formato | Salida del agente | Texto + bandera de voz |
| `IF Entró por voz` | IF | Si la entrada fue voz, la salida también | Bandera | Rama TTS / rama texto |
| `OpenAI - TTS` | OpenAI | Genera audio con la voz configurada (`CRED_OPENAI`) | Texto | Archivo de audio |
| `Telegram - Responder` | Telegram | Envía texto o audio al usuario | Mensaje final | Confirmación de envío |

### Manejo de errores

| Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|
| `PraxIA — Avisador de Errores v1` | Error Workflow | Configurado como `errorWorkflow` global. Registra y alerta | Objeto de error de n8n | Fila en `praxia.agent_errors` + alerta |
| `Postgres - upsert_agent_error` | Postgres | Llama a la función de deduplicación (`CRED_PG_MEMORIA`) | workflow, nodo, mensaje | `{ error_id, total_ocurrencias, debe_alertar }` |
| `IF Debe alertar` | IF | Anti-spam: una alerta por ventana | `debe_alertar` | Rama de alerta / silencio |
| `Telegram - Alerta` | Telegram | Notifica el error | Resumen del error | Mensaje enviado |

**Deuda conocida:** este workflow todavía se llama `[TEST]` en el runtime.

---

## Oppenheimer — Buscador Web Tavily V1

Nueve nodos. Publicado y verificado el 2026-07-25 23:18.

| # | Nodo | Tipo | Qué hace | Entrada | Salida |
|---|---|---|---|---|---|
| 1 | `Validar consulta web` | Code | Verifica que la consulta exista, tenga longitud razonable y no sea ambigua. Resuelve `target_date` y `date_scope` (hoy / ayer / temporada) | `{ consulta, target_date?, date_scope? }` | `{ valida: bool, consulta_normalizada, target_date, date_scope, motivo? }` |
| 2 | `IF Consulta válida` | IF | Bifurca. Una consulta ambigua no se busca: se devuelve pidiendo precisión | Salida de (1) | Rama válida / rama `clarification_required` |
| 3 | `Preparar búsqueda` | Set | Arma el cuerpo de la petición: términos, profundidad, ventana temporal, idioma | Consulta normalizada | Payload de búsqueda |
| 4 | `HTTP Request - Tavily Search` | HTTP Request | Llama al proveedor. **Header Auth** (`CRED_TAVILY_HEADER`), **`neverError=true`**, **timeout 20 s**. La respuesta cruda queda en `tavily_response` | Payload | `{ tavily_response, statusCode }` |
| 5 | `Validar fuentes y salida` | Code | Aplica el contrato de evidencia: descarta fuentes no confiables, etiqueta por resultado, aplica el fallback de 72 h y **determina el estado de salida** | `tavily_response` | `{ estado, respuesta, fuentes[], motivo }` |
| 6 | `Conservar contexto` | Set | Preserva la respuesta cruda y los parámetros de la búsqueda para que el orquestador pueda razonar sobre la evidencia | Salida de (4) y (5) | `{ contexto }` |
| 7 | `Envolver respuesta` | Set | Arma el objeto final con el estado tipado | Salidas de (5) y (6) | Contrato de salida completo |
| 8 | `Merge` | Merge | Une la rama válida con la rama de error o aclaración | Dos ramas | Una sola salida |
| 9 | *(salida del workflow)* | — | Devuelve al orquestador | Contrato completo | `{ estado, respuesta, fuentes, motivo, contexto }` |

### Por qué `neverError=true`

Sin esa opción, un timeout o un 500 del proveedor aborta la ejecución y el orquestador recibe un error genérico. Con ella, **la falla entra al flujo como dato** y el validador la convierte en `technical_error`, un estado que el orquestador sabe manejar: puede decir "no pude buscar" en vez de romperse.

Es el patrón general: **un error de infraestructura se traduce a un estado del contrato**.

### Los 7 estados de salida

| Estado | Cuándo |
|---|---|
| `ok` | Evidencia suficiente y fuentes válidas |
| `clarification_required` | Consulta ambigua: se pide precisión antes de gastar una búsqueda |
| `no_reliable_source` | Hubo resultados, ninguno pasó el validador |
| `search_not_configured` | Falta configuración del proveedor |
| `technical_error` | Falla técnica capturada |
| `stable_knowledge_handoff` | No requiere web: es conocimiento estable, vuelve al orquestador |
| `insufficient_evidence` | Hay fuentes, la evidencia no alcanza para una respuesta fundada |

Ninguno significa "respondé igual".

### Correcciones aplicadas

| Fecha | Corrección | Resultado |
|---|---|---|
| 2026-07-26 | Auditoría de fechas: hoy / ayer / temporada, `target_date`, `date_scope` | 8/8 PASS |
| 2026-07-26 | Corrección estructural del contexto (`tavily_response`) | 8/8 PASS |
| 2026-07-26/27 | Cobertura temática: etiquetas por resultado, fallback de 72 h | Aplicada |
| 2026-07-27 | Revalidación de la variante "Buscador General" | **2/7 PASS con exigencia de 7/7 → NO PUBLICADO** |

---

## Lo que esta descripción no incluye

- El JSON exportado de ambos workflows.
- Los parámetros exactos de cada nodo (modelos, temperaturas, profundidad de búsqueda, rangos).
- El texto completo de los nodos `Code`.
- IDs de nodo, de workflow, de credencial o de ejecución.
- URLs de webhook y endpoints internos.

Alcanza para reproducir la **arquitectura**. No alcanza para reproducir el sistema.

> Última verificación: 2026-08-05
