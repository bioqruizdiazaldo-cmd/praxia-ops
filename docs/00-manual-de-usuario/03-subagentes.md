# Subagentes

Ficha de cada uno de los catorce subagentes que el orquestador puede llamar: qué hace, cómo se lo invoca, qué devuelve, qué permisos tiene y qué no hace.

## Cómo leer estas fichas

Todos los subagentes son workflows de n8n invocados desde el orquestador como `toolWorkflow` / `executeWorkflow`. Vos nunca los llamás directo: le hablás a Oppenheimer en Telegram y él decide cuál usar.

Cada ficha tiene los mismos siete campos:

- **Para qué sirve** — el trabajo concreto.
- **Cómo se lo invoca** — ejemplos en lenguaje natural. Son **sintéticos**, ilustran el tipo de pedido y no son una lista cerrada de disparadores verificados.
- **Qué devuelve** — la forma de la respuesta.
- **Permisos** — a qué sistemas toca.
- **Qué NO hace** — el borde.
- **Aprobación humana** — si frena para pedirte un sí.

`[PENDIENTE DE VERIFICAR]` en la mayoría de las fichas: la fuente documenta la función y los nodos principales de cada subagente, no su contrato de entrada/salida campo por campo. Lo que está acá es lo verificado.

## Índice rápido

| Familia | Subagentes |
|---|---|
| Productividad | [Email](#agente-de-email) · [Calendario](#agente-de-calendario) · [Planillas](#agente-de-planillas) · [Recordatorios](#recordatorios) · [Enviar Gmail](#enviar-gmail) |
| Investigación | [Papers Científicos](#agente-papers-científicos-v21) · [Buscador Web Tavily](#buscador-web-tavily-v1) |
| Memoria | [Router](#praxia-memory--router) · [Guardar / Consultar / Tareas / Proyectos](#praxia-memory--guardar--consultar--tareas--proyectos) · [Sync Export MD](#praxia-sync--export-md) |
| Operación | [Briefing Diario](#briefing-diario) · [Briefing Noticias](#briefing-noticias) · [Alertas TradingView](#alertas-tradingview) · [Avisador de Errores](#avisador-de-errores-v1) |

---

## Agente de Email

Nombre real del workflow: `Oppenheimer - Agente de Email`.

**Para qué sirve.** Buscar, leer y redactar correo en Gmail. Es el subagente con más historia de trabajo encima: su versión V3 se publicó y validó el 2026-07-24 con 5 pruebas aisladas OK.

**Cómo se lo invoca.**

- "¿Tengo algo importante en el mail?"
- "Buscá los mails del contador de esta semana."
- "Leeme el último mail de la aseguradora."
- "Contestale confirmando la reunión del jueves."

**Qué devuelve.** Un resumen de los mails encontrados, el contenido de un mail puntual, o un borrador redactado listo para revisar.

**Permisos.** Lectura y búsqueda en Gmail. Redacción de borradores. Envío **solo** después de aprobación.

**Qué NO hace.**

- No manda nada sin que aprietes aprobar.
- No borra correo.
- No toca etiquetas ni configuración de la cuenta.
- No accede a otras casillas que no sean la conectada.

**Aprobación humana.** **Sí, obligatoria para enviar.** El flujo tiene dos nodos explícitos: `Telegram - Approve Send` te muestra el borrador y espera, e `If - Approved` decide si sigue o se corta. Esto implementa la decisión D-7: *"Aprobación humana obligatoria para enviar mails, borrar, gastar y publicar."*

---

## Agente de Calendario

Nombre real del workflow: `Oppenheimer - Agente de Calendario`.

**Para qué sirve.** Manejar la agenda en Google Calendar: consultar, crear, modificar y eliminar eventos.

**Cómo se lo invoca.**

- "¿Qué tengo mañana?"
- "¿Estoy libre el jueves a la tarde?"
- "Agendame dentista el 12 a las 10."
- "Cambiá la reunión del martes para las 17."
- "Borrá el turno del viernes."

**Qué devuelve.** La lista de eventos del período pedido, o la confirmación de la operación hecha.

**Permisos.** Get, Create, Update y Delete sobre Google Calendar.

**Qué NO hace.**

- No invita a terceros por su cuenta `[PENDIENTE DE VERIFICAR]`: la fuente no detalla el manejo de invitados.
- No cruza la agenda con otros calendarios que no estén conectados.

**Aprobación humana.** No documentada como paso explícito del flujo. Ojo con esto: **Delete existe en este subagente** y la decisión D-7 lista "borrar" entre las acciones que requieren aprobación. La fuente no describe un nodo de aprobación en este workflow. Tratalo como un borde a verificar antes de pedirle borrados masivos.

---

## Agente de Planillas

Nombre real del workflow: `Oppenheimer - Agente de Planillas`.

**Para qué sirve.** Escribir y leer Google Sheets. Es el subagente más viejo del sistema junto con Email y Calendario: nació el 2026-07-14 con el orquestador.

**Cómo se lo invoca.**

- "Guardá en la planilla: nafta 45000."
- "Anotá en la hoja de contactos: [datos]."
- "¿Cuánto llevo cargado este mes en la planilla?"

**Qué devuelve.** Confirmación de escritura, o el resultado de la consulta.

**Cómo funciona por dentro.** Clasifica el pedido en dos ramas: `GUARDAR:` o `CONSULTA:`. Las consultas se derivan a un `Consulta Sub-Agent` separado, para que leer y escribir no compartan el mismo camino.

**Permisos.** Lectura y escritura sobre las hojas de Google Sheets conectadas.

**Qué NO hace.**

- No es el sistema financiero. Si el dato es plata de verdad, va a [PraxIA Finanzas](04-praxia-finanzas-guia-de-uso.md), que tiene auditoría, estados y prohibición de borrado. La planilla no tiene nada de eso.
- No crea hojas nuevas `[PENDIENTE DE VERIFICAR]`.

**Aprobación humana.** No documentada.

---

## Agente Papers Científicos v2.1

Nombre real del workflow: `Oppenheimer — Agente Papers Científicos v2.1`. Documentado y validado el 2026-07-16/17.

**Para qué sirve.** Buscar literatura científica en fuentes públicas, ordenarla por relevancia y dejar el resultado escrito.

**Cómo se lo invoca.**

- "Buscame papers sobre [tema] de los últimos tres años."
- "¿Qué hay publicado sobre [tema]?"
- "Armame una revisión rápida de [tema]."

**Qué devuelve.** Un texto con los hallazgos rankeados, y una fila por búsqueda en Google Sheets.

**Cómo funciona por dentro.** Pipeline de cinco pasos:

```
query-builder → Europe PMC + OpenAlex → ranker → writer → Google Sheets
```

El query-builder traduce tu pedido en castellano a una búsqueda estructurada. Después consulta dos bases distintas, rankea los resultados, redacta y persiste.

**Permisos.** Lectura de las APIs públicas de Europe PMC y OpenAlex. Escritura en la hoja de resultados.

**Qué NO hace.**

- No baja PDFs de papers pagos.
- No consulta PubMed directamente ni bases con suscripción.
- No escribe un paper por vos. Devuelve hallazgos, no manuscritos.

**Aprobación humana.** No.

---

## Buscador Web Tavily V1

Nombre real del workflow: `Oppenheimer — Buscador Web Tavily V1`. Nació el 2026-07-25 a las 23:18, publicado y verificado.

**Para qué sirve.** Buscar en internet y devolver una respuesta **con evidencia**, o decir explícitamente que no la encontró.

**Cómo se lo invoca.**

- "Buscá qué pasó con [tema] esta semana."
- "¿Qué se sabe de [tema]?"
- "Fijate en internet cuánto sale [cosa]."

**Qué devuelve.** Una respuesta con estado. Ese es el punto central del diseño: no siempre devuelve una respuesta, y eso es una feature.

| Estado | Qué significa |
|---|---|
| `ok` | Encontró y hay evidencia suficiente |
| `clarification_required` | Tu pedido era ambiguo, necesita que precises |
| `no_reliable_source` | Buscó y no encontró fuente confiable |
| `search_not_configured` | La búsqueda no está configurada |
| `technical_error` | Falló la llamada |
| `stable_knowledge_handoff` | Es conocimiento estable, no hace falta buscar en la web |
| `insufficient_evidence` | Encontró cosas pero no alcanzan para afirmar |

**Cómo funciona por dentro.** Nueve nodos:

```
Validar consulta web → IF Consulta válida → Preparar búsqueda
→ HTTP Request - Tavily Search → Validar fuentes y salida
→ Conservar contexto / Envolver respuesta / Merge
```

La llamada HTTP usa Header Auth, `neverError=true` y timeout de 20 segundos, y deja la salida en `tavily_response`.

**Permisos.** Solo lectura contra la API de Tavily. No escribe en ningún lado.

**Qué NO hace.**

- No navega páginas ni hace clic.
- No completa formularios.
- No inventa una respuesta cuando la evidencia no alcanza. Devuelve `insufficient_evidence` y se planta.

**Aprobación humana.** No.

**Nota honesta sobre el sucesor.** Hubo un intento de evolución llamado "Buscador General" (fases 3B→3E1: relevancia, validador consolidado, métrica de alcance, fallback). La revalidación real acotada del 2026-07-27 dio **2 de 7 PASS con exigencia de 7/7 → NO PUBLICADO**. El cierre de ese trabajo dice: *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."* Lo que corre hoy es la V1.

---

## PraxIA Memory — Router

**Para qué sirve.** Es el despachador de todo lo que tiene que ver con memoria. Decide si el pedido es guardar, consultar, manejar tareas o manejar proyectos, y llama al workflow que corresponda.

**Cómo se lo invoca.** No se lo invoca directo. Cualquier pedido de memoria pasa por acá.

**Qué devuelve.** Lo que devuelva el subagente al que despachó, o un rechazo.

**El gate de secretos.** El Router tiene un nodo de decisión: **"¿Tiene secreto?"**. Si detecta que lo que le estás pidiendo guardar es una contraseña, un token, una API key, una clave privada, una credencial o datos bancarios completos, deriva a `Rechazo Secreto` y no guarda nada.

Esto no es una sugerencia del prompt: es una bifurcación en el flujo. Y está respaldado por la regla de seguridad grabada como el hecho #14 de la propia memoria:

> *"Nunca guardar contraseñas, tokens, API keys, claves privadas, credenciales ni datos bancarios completos. Si Aldo intenta guardar algo sensible, advertirle y sugerir guardar solo una referencia segura."*

**Permisos.** Invoca a los workflows de memoria. No escribe directo en la base.

**Qué NO hace.** No guarda secretos, bajo ninguna forma de pedido.

**Aprobación humana.** No, pero sí rechazo automático.

---

## PraxIA Memory — Guardar / Consultar / Tareas / Proyectos

Son cuatro workflows hermanos que hacen el CRUD real sobre PostgreSQL, esquema `praxia`. Nacieron el 2026-07-18, el día que nació el Memory Core.

**Para qué sirve cada uno.**

| Workflow | Trabajo |
|---|---|
| Guardar | Escribe hechos en `memory_facts` |
| Consultar | Busca hechos por texto |
| Tareas | CRUD sobre `tasks` |
| Proyectos | CRUD sobre `projects` |

**Cómo se los invoca.**

- Guardar: "Acordate de que…", "Anotá como regla que…", "Decidimos que…"
- Consultar: "¿Qué sabés de…?", "¿Qué habíamos decidido sobre…?"
- Tareas: "Agregá a pendientes…", "¿Qué tengo pendiente?"
- Proyectos: "¿En qué está el proyecto X?", "El próximo paso del proyecto X es…"

**Qué devuelven.** Confirmación de escritura **con verificación posterior** —es decir, después de escribir vuelve a leer para confirmar que quedó— o la lista de hechos, tareas o proyectos encontrados.

**Cómo funciona la búsqueda.** `Consultar Memoria` corre dentro de `BEGIN TRANSACTION READ ONLY`. Normaliza acentos, saca stop-words en español, usa `to_tsvector('spanish')` y aplica dos niveles de coincidencia: un tier estricto y uno laxo. Si el estricto no trae nada, prueba el laxo.

**Cómo funciona el guardado.** `Guardar Hecho` deduplica por normalización —si ya guardaste algo equivalente, no lo duplica— y auto-clasifica las reglas de seguridad.

**Permisos.** Lectura y escritura sobre el esquema `praxia`. La base escucha **solo en 127.0.0.1:5433**, en la red `n8n_default`: no está expuesta a internet.

**Qué NO hacen.**

- No borran físicamente: los hechos tienen un campo `active`, se dan de baja lógica.
- No guardan secretos (el Router los frena antes).
- No hacen búsqueda semántica. No hay embeddings.

**Aprobación humana.** No.

---

## PraxIA Sync — Export MD

**Para qué sirve.** Volcar la memoria estructurada a archivos Markdown legibles, todas las noches, para que exista un espejo humano editable fuera de la base.

**Cómo se lo invoca.** No se lo invoca: corre solo a las **23:30 ART**. Después, a las 23:35, un cron con rclone sincroniza esos archivos a OneDrive.

**Qué devuelve.** Archivos Markdown en la bóveda Obsidian, más un resumen de lo exportado.

El último export verificado (2026-08-05 02:30 UTC) dice: **2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, 0 secretos omitidos**.

**Permisos.** Lectura de `praxia.*`, escritura de archivos.

**Qué NO hace.** No sincroniza para el otro lado. Si editás el Markdown a mano, ese cambio **no vuelve** a la base. La decisión maestra lo dice: *"La memoria viva vive en PostgreSQL (esquema praxia) en el VPS; MiBoveda es el espejo humano editable."* El espejo se lee, la base manda.

**Aprobación humana.** No.

---

## Briefing Diario

Nombre real del workflow: `Oppenheimer - Briefing Diario`. Nació el 2026-07-14 con el orquestador.

**Para qué sirve.** Mandarte un resumen del día antes de que arranques.

**Cómo se lo invoca.** Automático a las **07:00**.

**Qué devuelve.** Un mensaje de Telegram con cuatro bloques: agenda del día, tareas pendientes, mails y clima.

**Permisos.** Lectura de Google Calendar, de las tareas en `praxia`, de Gmail y de Open-Meteo. Escritura en Telegram.

**Qué NO hace.** No actúa sobre nada de lo que informa. Te avisa, no resuelve.

**Aprobación humana.** No aplica.

---

## Briefing Noticias

Nombre real del workflow: `Oppenheimer — Briefing Noticias`. Nació el 2026-07-15.

**Para qué sirve.** Un resumen de noticias antes del briefing personal.

**Cómo se lo invoca.** Automático a las **06:30**.

**Qué devuelve.** Una síntesis en Telegram.

**Cómo funciona por dentro.** Lee los RSS de **Infobae, Clarín, Olé y BBC**, sintetiza con OpenAI y manda por Telegram.

**Permisos.** Lectura de feeds RSS públicos. Llamada a OpenAI. Escritura en Telegram.

**Qué NO hace.** No verifica las noticias contra otras fuentes. Es un resumen de titulares, no periodismo verificado. Si algo importa, cruzalo con el [Buscador Web](#buscador-web-tavily-v1).

**Aprobación humana.** No aplica.

---

## Recordatorios

Nombre real del workflow: `Oppenheimer - Recordatorios`. Nació el 2026-07-14.

**Para qué sirve.** Avisarte algo más tarde.

**Cómo se lo invoca.**

- "Recordame en dos horas llamar al taller."
- "Avisame mañana a las 9 que tengo que mandar el formulario."

**Qué devuelve.** Un mensaje de Telegram en el momento pedido.

**Cómo funciona por dentro.** Webhook + nodo `Wait` + Telegram. Es simple a propósito.

**Permisos.** Escritura en Telegram.

**Qué NO hace.** No arma recurrencias complejas `[PENDIENTE DE VERIFICAR]`. No es un gestor de tareas: para eso está el subagente de Tareas de memoria, que persiste en base.

**Aprobación humana.** No.

---

## Enviar Gmail

Nombre real del workflow: `Oppenheimer - Enviar Gmail`. Nació el 2026-07-14.

**Para qué sirve.** Ejecutar el envío del mail, y nada más. Es la mano que aprieta el botón.

**Cómo se lo invoca.** No se lo invoca directo: se dispara **después de que confirmaste** el borrador que preparó el [Agente de Email](#agente-de-email).

**Qué devuelve.** Confirmación de envío.

**Permisos.** Envío por Gmail.

**Qué NO hace.** No redacta. No decide destinatario. No se ejecuta sin la confirmación previa.

**Aprobación humana.** Es el paso **posterior** a la aprobación. Sin el sí, no corre.

La separación entre "redactar" y "enviar" en dos workflows distintos es deliberada: hace imposible que un error del redactor mande un mail.

---

## Alertas TradingView

Nombre real del workflow: `Oppenheimer - Alertas TradingView`. Nació el 2026-07-15.

**Para qué sirve.** Recibir alertas de mercado configuradas en TradingView y reenviarlas a Telegram.

**Cómo se lo invoca.** No se lo invoca desde Telegram: **entra** por un webhook cuando TradingView dispara una alerta que configuraste allá.

**Qué devuelve.** Un mensaje de Telegram con la alerta.

**Permisos.** Recibir en un webhook. Escribir en Telegram.

**Qué NO hace.**

- No opera. No compra, no vende, no toca un broker.
- No genera las alertas: solo las transporta. La lógica de la alerta vive en TradingView.
- No las guarda en la base financiera.

**Aprobación humana.** No aplica: no ejecuta acciones, solo notifica.

---

## Avisador de Errores v1

Nombre real del workflow: `PraxIA — Avisador de Errores v1`. Creado el 2026-07-22, con integración productiva aprobada el 2026-07-23.

**Para qué sirve.** Es la red de seguridad de todo el sistema. Está enganchado como **`errorWorkflow` global**: cuando cualquier otro workflow falla, n8n lo llama a él.

**Cómo se lo invoca.** Nunca lo llamás vos. Lo llama el runtime cuando algo se rompe.

**Qué devuelve.** Dos cosas: una fila en la tabla `praxia.agent_errors` y un mensaje de alerta por Telegram.

**Cómo funciona por dentro.** Usa la función `praxia.upsert_agent_error`, que hace deduplicación y reserva de alertas. La deduplicación y el anti-spam están **validados**: si el mismo error se repite, no te bombardea.

**Permisos.** Escritura en `praxia.agent_errors`. Escritura en Telegram.

**Qué NO hace.**

- No repara nada. Avisa.
- No reintenta la ejecución fallida.

**Aprobación humana.** No aplica.

**Deuda técnica conocida.** El nombre del workflow **todavía dice `[TEST]`** aunque está activo y en producción desde el 2026-07-23. Está anotado como deuda abierta y aparece en la lista de riesgos del sistema. Si lo ves con ese prefijo en n8n, no es un workflow de prueba: es el avisador real.

---

## Resumen de permisos y aprobaciones

| Subagente | Escribe en sistemas externos | Requiere aprobación |
|---|---|---|
| Agente de Email | Gmail (solo borradores) | **Sí, para enviar** |
| Agente de Calendario | Google Calendar (incl. Delete) | No documentada — borde a verificar |
| Agente de Planillas | Google Sheets | No |
| Papers Científicos v2.1 | Google Sheets | No |
| Buscador Web Tavily V1 | Nada | No |
| Memory Router | Nada (despacha) | Rechazo automático de secretos |
| Memory Guardar/Consultar/Tareas/Proyectos | PostgreSQL `praxia` | No |
| Sync Export MD | Archivos + OneDrive | No |
| Briefing Diario | Telegram | No aplica |
| Briefing Noticias | Telegram | No aplica |
| Recordatorios | Telegram | No |
| Enviar Gmail | Gmail (envío real) | Es el paso posterior al sí |
| Alertas TradingView | Telegram | No aplica |
| Avisador de Errores v1 | PostgreSQL + Telegram | No aplica |

> Última verificación: 2026-08-05
