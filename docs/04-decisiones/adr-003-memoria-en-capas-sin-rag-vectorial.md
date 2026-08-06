# ADR-003 — Memoria en capas, sin RAG vectorial

Cuatro capas de memoria con responsabilidades distintas, un gate determinístico que decide cuándo consultarla, y cero embeddings.

## Estado

Vigente.

## Fecha

2026-07-18 — nace PraxIA Memory Core sobre PostgreSQL propio.
2026-07-20 — se agrega el Memory Intent Gate al orquestador, que completa el diseño.

## Contexto

Un agente que no recuerda nada entre conversaciones es un buscador con buenos modales. La memoria era un requisito, no una mejora.

El camino por default en 2026 para "memoria de agente" es un almacén vectorial: embeber cada mensaje, indexarlo y recuperar por similitud antes de responder. Es lo que recomienda casi todo el material disponible, y para grandes volúmenes de documentos no estructurados es la respuesta correcta.

Este caso no era ése. Al mirar qué había que recordar de verdad, aparecieron cuatro clases de información con requisitos incompatibles entre sí:

| Qué hay que recordar | Volumen | Requisito dominante |
|---|---|---|
| Lo que se dijo hace tres mensajes | Chico | Latencia cero, se descarta solo |
| Decisiones, preferencias, reglas, tareas, proyectos | **Muy chico** (26 hechos a los 17 días) | **Exactitud y corregibilidad a mano** |
| Documentos, notas, papers | Medio | Lectura humana, edición fuera del sistema |
| Qué hizo el agente y cuándo | Creciente | Inmutabilidad y trazabilidad |

La segunda fila es la que decide todo. **Veintiséis hechos no son un problema de recuperación.** Son un problema de precisión: cuando el usuario pregunta "¿qué habíamos decidido sobre las credenciales?", la respuesta correcta es un hecho específico, no los tres fragmentos más parecidos según una distancia coseno.

Había además un problema más grave que la recuperación, y que ninguna arquitectura de memoria resuelve sola: **el agente respondía "no tengo registrado" sin haber consultado la memoria**. Es la falla más molesta que puede tener un asistente con memoria, porque destruye la confianza de golpe. Y la causa no era la base: era que la decisión de consultar quedaba en manos del modelo.

## Decisión

**Memoria en cuatro capas, cada una con una tecnología distinta y una responsabilidad clara, con un gate determinístico que decide cuándo consultar la capa estructurada. Sin embeddings ni almacén vectorial.**

### Las cuatro capas

| # | Capa | Implementación | Qué guarda | Vida útil |
|---|---|---|---|---|
| 1 | Corta | `Memory Buffer` de n8n | Conversación reciente | Efímera |
| 2 | Estructurada | PostgreSQL 16, esquema `praxia` | Hechos, eventos, tareas, proyectos | Permanente, corregible |
| 3 | Documental | Espejo Markdown en el vault | Notas, documentos, decisiones legibles | Permanente, editable por una persona |
| 4 | Auditada | `praxia.agent_errors` + logs de ejecución | Qué hizo el agente, cuándo y con qué resultado | Permanente, no se corrige |

### Cómo se recupera, sin vectores

La capa estructurada se consulta con búsqueda de texto completo de PostgreSQL en español:

- Transacción `BEGIN TRANSACTION READ ONLY` — la consulta **no puede** escribir, por construcción.
- Normalización de acentos y stop-words en español.
- `to_tsvector('spanish')` para la indexación.
- **Dos niveles de coincidencia**: un nivel estricto y uno laxo, en ese orden.

El nivel doble es la parte que reemplaza funcionalmente a la similitud semántica: si la coincidencia exacta no devuelve nada, se afloja el criterio antes de rendirse.

### El gate determinístico

Tres piezas resuelven el problema del "no tengo registrado":

- `Code - Memory Intent Gate` — **código, no LLM**. Decide si la consulta requiere memoria.
- `IF Memory Required` — bifurca el flujo.
- `PraxIA Memory Preflight` — consulta la memoria **antes** de que el modelo redacte la respuesta.

Y una regla explícita en el prompt de sistema:

> *"Está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con action=consultar y haber recibido facts=[]"*

La combinación importa: el gate garantiza que la consulta ocurra, y la regla del prompt cubre el caso en que el modelo, aun teniendo los datos, quiera improvisar una negativa.

### Escritura verificada y con gate de secretos

- El Router de memoria tiene un gate **"¿Tiene secreto?"** con salida a `Rechazo Secreto`.
- El guardado deduplica por normalización y autoclasifica reglas de seguridad.
- Cada escritura verifica después de escribir, no confía en el retorno del nodo.
- Regla grabada como hecho #14 dentro del propio sistema: nunca guardar contraseñas, tokens, claves de API, claves privadas, credenciales ni datos bancarios completos; si se intenta, advertir y sugerir guardar sólo una referencia segura.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Capas + texto completo en español + gate determinístico** | Inspeccionable con un `SELECT`; corregible a mano; costo cero por consulta; sin latencia de red; se testea con SQL | No captura similitud semántica; depende de que las palabras coincidan | **Elegida** |
| Almacén vectorial con embeddings | Recuperación semántica; escala a volúmenes grandes | Infraestructura extra; costo por embedding; **no inspeccionable**: no se puede leer ni corregir un vector a mano; sobredimensionado para 26 hechos | Rechazada |
| Híbrido texto completo + vectores | Lo mejor de los dos | Dos caminos de recuperación que hay que mantener sincronizados y depurar juntos, sin un problema que lo justifique todavía | Postergada |
| Sólo ventana de contexto larga | Cero infraestructura | No persiste entre sesiones; el costo crece con cada turno; no es corregible ni auditable | Rechazada |
| Que el modelo decida cuándo consultar memoria | Menos código | **Es exactamente la falla que había que resolver.** Un gate probabilístico sobre una garantía requerida | Rechazada |

## Consecuencias

### Positivas

- **La memoria se lee y se corrige a mano.** Un hecho equivocado se arregla con un `UPDATE`. Con embeddings hay que reindexar, y verificar el resultado es mucho más difícil.
- **Costo marginal cero por consulta.** Ninguna llamada a una API de embeddings.
- **La recuperación es determinística y testeable.** Las mismas palabras devuelven los mismos hechos, siempre.
- **El espejo Markdown hace la memoria legible sin herramientas.** Export a las 23:30 y sincronización a las 23:35, todas las noches.
- **El problema del "no tengo registrado" se resolvió en el lugar correcto**: en código, no pidiéndole al modelo que se acuerde de consultar.
- **Los secretos se filtran en la escritura, no en la lectura.** El último export verificado reporta 0 secretos omitidos.

### Negativas

- **No hay recuperación semántica.** Si el hecho dice "credenciales" y la pregunta dice "contraseñas", el nivel estricto falla. El nivel laxo mitiga pero no equivale.
- **No escala a documentos.** La capa documental es un espejo Markdown para lectura humana, **no un índice consultable por el agente**. Buscar dentro de un PDF archivado no está resuelto.
- **La búsqueda es monolingüe.** `to_tsvector('spanish')` funciona en español. Contenido en inglés se indexa peor.
- **El gate es una heurística en código.** Puede tener falsos negativos: una consulta que necesitaba memoria y no la disparó. No hay una medición de su tasa de acierto. Estado: `Pendiente de verificar`.

### Operativas

- Cuatro capas son cuatro cosas que pueden fallar por separado: buffer, base, export y auditoría.
- El export nocturno es un punto de falla silencioso. Los contadores del export (hechos, proyectos, tareas, deduplicadas, secretos omitidos) son la verificación de que corrió entero.
- Agregar una categoría nueva de hechos implica tocar SQL, no configuración.

### De seguridad

- **El gate de secretos actúa en la escritura**, que es el único momento en que se puede evitar que un secreto entre a la base. Filtrar en la lectura sería tarde.
- La consulta corre en transacción de solo lectura: una inyección en la ruta de consulta **no puede escribir**, por diseño de la transacción y no por validación de entrada.
- La base sólo escucha en loopback.
- No mandar el contenido de la memoria a un servicio de embeddings externo elimina una vía completa de exfiltración. Con un almacén vectorial gestionado, cada hecho personal viajaría a un tercero para ser indexado.
- Contrapartida honesta: los hechos se guardan en claro en la capa estructurada. El cifrado en reposo por campo existe en el esquema financiero (`datos_sensibles` con token de reemplazo antes de mandar nada al modelo), **no en la memoria general**. Estado: `Pendiente de verificar` si corresponde extenderlo.

## Evidencia

| Afirmación | Estado |
|---|---|
| Cuatro capas implementadas, sin RAG vectorial | `Verificado` |
| PostgreSQL 16, esquema `praxia`, tablas `memory_facts`, `memory_events`, `tasks`, `projects`, `agent_errors` | `Verificado` |
| Consulta en transacción de solo lectura con normalización, stop-words, `to_tsvector('spanish')` y dos niveles de coincidencia | `Verificado` |
| `Code - Memory Intent Gate` + `IF Memory Required` + `PraxIA Memory Preflight` | `Verificado` |
| Regla textual del prompt de sistema sobre "no tengo registrado" | `Verificado` |
| Gate "¿Tiene secreto?" con salida a `Rechazo Secreto` en el Router | `Verificado` |
| Hecho #14 con la regla de no guardar credenciales | `Verificado` |
| Export nocturno 23:30 ART + sincronización 23:35 | `Verificado` |
| Último export: 2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, 0 secretos omitidos | `Verificado` |
| Tasa de acierto del gate (falsos negativos) | `Pendiente de verificar` |
| Comparación medida contra una implementación vectorial | `Pendiente de verificar` — nunca se midió, la decisión fue de diseño |

## Cuándo se revisaría

Esta decisión **no es ideológica**. Sin embargo, cambiarla necesita un disparador medible, no una impresión. Los umbrales concretos:

| Disparador | Umbral | Qué haría |
|---|---|---|
| Volumen de hechos | El texto completo empieza a devolver demasiado ruido — orientativamente por encima del orden de los cientos de hechos | Evaluar híbrido, manteniendo el texto completo como camino primario |
| Búsqueda dentro de documentos | Que haya que consultar el contenido de PDFs y papers archivados, y no sólo sus metadatos | **Es el escenario más probable.** Un índice vectorial *sólo* para la capa documental, sin tocar la estructurada |
| Falsos negativos del gate | Que se mida y resulte alta | Primero mejorar el gate; recién después pensar en cambiar la recuperación |
| Multilingüe | Que entre volumen relevante en inglés | Configuración de idioma por fila, antes que embeddings |
| Segundo usuario | Que la separación por usuario multiplique el volumen | Revisar índices antes que arquitectura |

Y el criterio inverso, que también vale: **si en seis meses la memoria sigue teniendo decenas de hechos y se consulta bien, la decisión fue correcta y no hay nada que revisar.** Migrar a vectores porque es lo que se usa no es un disparador.

> Última verificación: 2026-08-05
