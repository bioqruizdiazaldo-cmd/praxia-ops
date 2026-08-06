# Memoria: qué recuerda y qué no

Las cuatro capas de memoria explicadas en criollo, qué está prohibido guardar, y cómo pedirle que recuerde o que olvide algo.

## El problema que resuelve

Un modelo de lenguaje no recuerda nada entre conversaciones. Cada mensaje arranca de cero salvo por lo que le vuelvas a contar.

PraxIA Memory Core es lo que hace que Oppenheimer se acuerde de una decisión que tomaste hace tres semanas. No es magia del modelo: es una base de datos PostgreSQL con búsqueda de texto y un conjunto de workflows que la leen y la escriben.

**Importante**: no hay RAG vectorial. No hay embeddings, no hay búsqueda semántica. Es SQL con búsqueda de texto completo en español. Es más simple, más barato y más auditable — y tiene el límite de que si preguntás con palabras muy distintas a las que usaste al guardar, puede no encontrarlo.

## Las cuatro capas

### 1. Memoria corta — la conversación

**Qué es.** Lo que dijiste hace tres mensajes.

**Dónde vive.** El nodo `Memory Buffer` de n8n, dentro del orquestador.

**Cuánto dura.** Lo que dure el hilo de conversación. Es volátil.

**Para qué sirve.** Que puedas decir "cambialo a las 17" sin repetir de qué reunión estabas hablando.

**Lo que no hace.** No sobrevive a un reinicio del sistema ni a una pausa larga. Si necesitás que algo persista, tiene que ir a la capa 2.

### 2. Memoria estructurada — los hechos

**Qué es.** El corazón del sistema. Hechos, decisiones, preferencias, reglas, tareas y proyectos, guardados en filas de una base.

**Dónde vive.** PostgreSQL 16, en un contenedor propio llamado `praxia-memory-db`, base `praxia_memory`, esquema `praxia`. El puerto está expuesto **solo a 127.0.0.1:5433** dentro de la red `n8n_default`: no hay forma de llegar desde internet.

**Qué se guarda.**

| Tabla | Contenido |
|---|---|
| `memory_facts` | Hechos: el texto, su categoría, su proyecto, un nivel de confianza, si está activo y cuándo se actualizó |
| `memory_events` | El registro de las interacciones: agente, canal, dispositivo, tu mensaje, la respuesta, la intención detectada, importancia y etiquetas |
| `tasks` | Tareas |
| `projects` | Proyectos, con estado, prioridad, dueño y próxima acción |
| `agent_errors` | Errores del sistema (es la capa 4) |

**Las categorías de hechos** que se usan en la práctica: `decision`, `recordar`, `preferencia`, `regla`, `seguridad`, `familia`.

**El tamaño real.** El último export verificado (2026-08-05) contaba **26 hechos, 4 tareas y 2 proyectos**. Es una memoria chica y curada, no un depósito. Eso es intencional: memoria útil, no acumulación.

**Cómo busca.** El workflow `Consultar Memoria` corre dentro de `BEGIN TRANSACTION READ ONLY` —físicamente no puede escribir— y hace lo siguiente:

1. Normaliza acentos, para que "decisión" encuentre "decision".
2. Saca stop-words en español ("el", "de", "que").
3. Usa `to_tsvector('spanish')`, que entiende raíces de palabras.
4. Prueba primero un **tier estricto**; si no encuentra nada, un **tier laxo**.

**Cómo guarda.** El workflow `Guardar Hecho` deduplica por normalización —si ya existe algo equivalente no lo repite— y auto-clasifica las reglas de seguridad. Después de escribir, **vuelve a leer para verificar** que quedó.

### 3. Memoria documental — el espejo

**Qué es.** Todo lo anterior volcado a archivos Markdown que podés abrir, leer y editar como cualquier nota.

**Dónde vive.** En la bóveda de Obsidian, sincronizada a OneDrive.

**Cómo se actualiza.** El workflow `PraxIA Sync — Export MD` corre todas las noches a las **23:30 ART** y escribe los archivos. A las **23:35** un cron con rclone los sube a OneDrive.

**La regla de dirección.** Esta es clave y es textual, del hecho #1 grabado el 2026-07-18:

> *"La memoria viva vive en PostgreSQL (esquema praxia) en el VPS; MiBoveda es el espejo humano editable."*

El flujo va **de la base al Markdown**, nunca al revés. Si editás un archivo Markdown a mano, ese cambio no vuelve a la base y se va a perder en el próximo export. El Markdown es para leer, buscar y linkear en Obsidian.

**Por qué existe esta capa.** Porque una base de datos no se lee de noche en el celular. El espejo te da consulta humana sin depender de que el sistema esté andando.

### 4. Memoria auditada — qué pasó

**Qué es.** El registro de lo que el sistema ejecutó y de lo que falló.

**Dónde vive.** La tabla `praxia.agent_errors` más los logs de ejecución de n8n.

**Cómo se llena.** El workflow `PraxIA — Avisador de Errores v1` está enganchado como `errorWorkflow` global: cuando cualquier workflow falla, escribe la fila y te alerta por Telegram. Usa la función `praxia.upsert_agent_error`, que deduplica y reserva alertas para que no te llegue el mismo error cien veces.

**Para qué sirve.** Para poder responder "¿qué pasó el martes a las 18?" con datos y no con memoria humana.

---

## Qué está prohibido guardar

Esta es la regla más importante del sistema de memoria, y está grabada **dentro de la propia memoria** como el hecho #14:

> *"Nunca guardar contraseñas, tokens, API keys, claves privadas, credenciales ni datos bancarios completos. Si Aldo intenta guardar algo sensible, advertirle y sugerir guardar solo una referencia segura."*

### Cómo se hace cumplir

No depende de que el modelo se acuerde. El workflow `PraxIA Memory — Router` tiene un nodo de decisión explícito: **"¿Tiene secreto?"**. Si la respuesta es sí, el flujo se desvía a `Rechazo Secreto` y no se escribe nada.

Es una bifurcación en el grafo, no una instrucción en un prompt. Un prompt se puede convencer; una bifurcación no.

### La lista concreta

| Prohibido | Alternativa segura |
|---|---|
| Contraseñas | "La clave del router está en el gestor de contraseñas, entrada X" |
| Tokens y API keys | "El token de X vive en las credenciales de n8n" |
| Claves privadas | "La clave SSH está en la máquina Y, ruta gestionada aparte" |
| Credenciales de cualquier tipo | Una referencia al lugar donde están |
| Datos bancarios completos | Los últimos cuatro dígitos, o el alias |

El patrón es siempre el mismo: **guardá el puntero, no el secreto**.

### Qué sí conviene guardar

- Decisiones y su motivo. "Elegimos PostgreSQL propio en vez de Supabase porque…"
- Reglas de trabajo. "Los mails al contador se mandan siempre con copia a…"
- Preferencias. "Prefiero los briefings antes de las 7."
- Estado de proyectos y próxima acción.
- Datos de contexto que vas a necesitar y no querés volver a buscar.

### El caso real que hay que evitar

En la lista de riesgos abiertos del sistema figura este hallazgo: *"`.env` con un token real quedó dentro de una carpeta sincronizada a la nube — requiere rotación."*

O sea: la regla existe porque el problema es real, y el sistema lo detectó en su propia auditoría. La memoria estructurada tiene su gate. Los archivos sueltos no.

---

## Cómo pedirle que recuerde algo

Le hablás normal. Ejemplos **sintéticos**:

- "Acordate de que el proveedor nuevo cobra a 30 días."
- "Anotá como regla que los mails a clientes se revisan antes de mandar."
- "Decidimos usar PostgreSQL propio en lugar de Supabase."
- "Agregá a las tareas del proyecto X: pedir presupuesto."

Qué pasa por detrás: el Router clasifica la intención, pasa el gate de secretos, y `Guardar Hecho` escribe con deduplicación y verificación posterior.

**Cómo saber que quedó.** El sistema verifica después de escribir. Si querés estar seguro, preguntá: "¿Qué tenés guardado sobre el proveedor nuevo?"

**Un consejo práctico.** Guardá con las palabras con las que después vas a preguntar. La búsqueda es por texto: si guardás "acuerdo comercial con la firma del norte" y después preguntás "¿qué pasa con el proveedor?", puede no encontrarlo.

---

## Cómo pedirle que olvide algo

Ejemplos **sintéticos**:

- "Olvidate de lo del proveedor nuevo."
- "Ese hecho ya no vale, dalo de baja."

Qué pasa por detrás: la tabla `memory_facts` tiene un campo `active`. Olvidar es poner ese campo en falso, no borrar la fila.

**Consecuencia**: el hecho deja de aparecer en las consultas, pero el registro sigue existiendo. Es la misma filosofía que en Finanzas — baja lógica, no borrado físico.

`[PENDIENTE DE VERIFICAR]`: la fuente confirma el campo `active` en `memory_facts` pero no documenta un flujo específico de "olvidar" invocado desde Telegram. Si el pedido no funciona, la baja se puede hacer editando el estado del hecho por los canales de administración.

---

## El Memory Intent Gate, sin jerga

### El problema que resuelve

Un asistente con memoria tiene una falla típica: te contesta "no tengo eso registrado" sin haber ido a fijarse. El modelo decide que no hace falta consultar, y decide mal.

### La solución

Antes de que el modelo genere una sola palabra, corre un **nodo de código** —`Code - Memory Intent Gate`— que evalúa tu mensaje y decide **determinísticamente** si hay que ir a la base. Después un `IF Memory Required` bifurca, y `PraxIA Memory Preflight` trae los datos antes de que el modelo redacte.

La palabra clave es **determinístico**: es código, no un LLM. Ante el mismo mensaje, siempre toma la misma decisión. No hay margen para que el modelo "sienta" que no hace falta consultar.

### La regla escrita

En el prompt de sistema del orquestador está esta prohibición, textual:

> *"Está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con action=consultar y haber recibido facts=[]"*

Leída al revés: **"no tengo registrado" es una afirmación con respaldo**. Significa que fue, buscó y volvió con las manos vacías. No significa que no se le ocurrió mirar.

### Cuándo nació

El Memory Gate se puso en el orquestador el 2026-07-20, con el rollback previo guardado antes de tocar nada. Fue una de las primeras aplicaciones concretas de la regla de gobernanza *"todo despliegue debe tener rollback"*.

---

## Dónde ver la memoria en Obsidian

La bóveda de Obsidian tiene el espejo Markdown que se genera todas las noches.

**Qué vas a encontrar ahí**: los hechos, las tareas y los proyectos exportados, en archivos de texto plano que Obsidian indexa y linkea.

**Qué NO vas a encontrar**: secretos (nunca entraron a la base), los `memory_events` crudos, ni los datos que estén marcados como inactivos.

**El resumen del último export** (2026-08-05 02:30 UTC) da la dimensión exacta: 2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, **0 secretos omitidos**. Ese último número es la métrica de salud del gate: si un día no es cero, alguien intentó guardar un secreto y el sistema lo frenó.

**Recordá la dirección del flujo**: leés el Markdown, escribís en la base por Telegram. Editar el Markdown no cambia nada.

`[PENDIENTE DE VERIFICAR]`: la ruta concreta dentro de la bóveda no se publica, por política de no exponer rutas del sistema privado.

---

## Los límites, en una tabla

| Límite | Consecuencia práctica |
|---|---|
| Sin RAG vectorial | Si preguntás con sinónimos muy distintos, puede no encontrar |
| Búsqueda en español | Optimizada para castellano, no para inglés |
| Memoria corta volátil | Lo que no se guarda explícitamente se pierde al cerrar el hilo |
| Gate de secretos | No podés guardar credenciales aunque insistas |
| Baja lógica | "Olvidar" oculta, no destruye |
| Espejo unidireccional | Editar el Markdown no actualiza la base |
| Export nocturno | Lo que guardás hoy aparece en Obsidian recién mañana |
| Un solo usuario | La memoria es del dueño. La separación por usuario está en la arquitectura, no en operación |

> Última verificación: 2026-08-05
