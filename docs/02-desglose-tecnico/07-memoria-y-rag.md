# Memoria y RAG

El modelo de memoria en capas de este sistema, y por qué no hay una base vectorial en ninguna parte.

## Criterio

"Memoria" es una palabra que tapa cuatro problemas distintos. Tratarlos como uno solo es el origen de la mayoría de las arquitecturas de memoria que no funcionan.

### Las cuatro capas

| Capa | Qué guarda | Vida útil | Cómo se recupera |
|---|---|---|---|
| **Corta** | Los últimos turnos de la conversación | Minutos | Va entera en el contexto |
| **Estructurada** | Hechos, preferencias, decisiones, tareas, proyectos | Indefinida | Consulta dirigida por intención |
| **Documental** | PDFs, papers, manuales, notas largas | Indefinida | Búsqueda por contenido |
| **Auditada** | Qué hizo el agente, cuándo, con qué permiso | Indefinida, inmutable | Consulta por entidad o fecha |

Cada una tiene un mecanismo distinto y **mezclarlas es el error**. Meter hechos estructurados en un índice vectorial junto con documentos hace que un dato de una línea compita en similitud con un párrafo de un PDF. Y al revés: guardar documentos como filas de texto en una tabla relacional te deja sin forma decente de buscarlos.

### Dónde RAG vectorial es la respuesta correcta

- **Volumen alto de texto no estructurado.** Cientos o miles de documentos largos.
- **Consultas conceptuales.** El usuario pregunta por una idea que el documento expresa con otras palabras.
- **Vocabulario abierto.** No sabés de antemano qué términos van a aparecer.
- **Recuperación aproximada aceptable.** Traer 5 fragmentos parecidos y dejar que el modelo elija es suficiente.

### Dónde es sobreingeniería

- **Pocos ítems.** Con decenas de hechos cortos, un `LIKE` bien hecho tiene mejor precisión que un vector.
- **Los hechos son cortos y precisos.** "El presupuesto techo es X" no gana nada convertido en 1.536 dimensiones.
- **Necesitás exactitud, no similitud.** Si la respuesta correcta es una fila específica, la búsqueda aproximada es un downgrade.
- **Necesitás editar y borrar.** Corregir un hecho en una tabla es un `UPDATE`. En un índice vectorial es reembeber y reindexar.
- **Necesitás saber por qué se recuperó algo.** Una distancia coseno de 0,83 no es una explicación. Un match de `to_tsquery` sí.

### El costo escondido de una base vectorial

Lo que se subestima no es el motor —hoy `pgvector` es un `CREATE EXTENSION`— sino el **pipeline**: elegir estrategia de chunking, elegir modelo de embeddings, versionar ese modelo, reembeber todo cuando cambia, sincronizar altas y bajas entre la fuente y el índice, y evaluar la calidad de recuperación con algo mejor que la intuición.

Esa cadena es la que se rompe. Un índice vectorial desincronizado de su fuente es peor que no tener índice: devuelve información obsoleta con la misma confianza que la actual.

## En este sistema

**Sin RAG vectorial.** Tres capas reales más una de auditoría.

### 1. Memoria corta

`Memory Buffer` de n8n. La conversación reciente, en el runtime, sin persistencia propia. Nada que decidir: es lo que el nodo hace.

### 2. Memoria estructurada — PraxIA Memory Core

PostgreSQL 16 en un contenedor propio (`praxia-memory-db`), base `praxia_memory`, esquema `praxia`. Puerto expuesto **sólo a `127.0.0.1:5433`**, red interna de Docker.

Tablas:

- **`memory_facts`** — `id`, `fact`, `category`, `project`, `confidence`, `active`, `updated_at`. Categorías observadas: `decision`, `recordar`, `preferencia`, `regla`, `seguridad`, `familia`.
- **`memory_events`** — `agent`, `source`, `device`, `user_message`, `assistant_response`, `intent`, `project`, `importance`, `tags` (jsonb), `raw_json` (jsonb).
- **`tasks`**, **`projects`** — `id`, `proyecto`, `status`, `priority`, `owner`, `next_action`, `updated_at`.
- Previstas en el esquema original y todavía sin uso: `papers`, `content_calendar`.

Volumen al último export verificado (**2026-08-05 02:30 UTC**): **2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, 0 secretos omitidos**.

**26 hechos.** Ese número es el argumento entero contra los embeddings acá. Con 26 filas de una o dos líneas, un índice vectorial no mejora la recuperación: agrega un modelo de embeddings, un pipeline de reindexado y una fuente de error. `to_tsvector('spanish')` sobre 26 filas es instantáneo y explicable.

La separación `memory_facts` / `memory_events` también es deliberada: los hechos son **curados** (pocos, precisos, editables); los eventos son **crudos** (muchos, sin depurar). Si estuvieran en una sola tabla, el ruido de los eventos ahogaría los hechos en cualquier búsqueda.

Y hay una decisión que ninguna base vectorial permite: `confidence` y `active` son **columnas**. Bajar la confianza de un hecho o desactivarlo es un `UPDATE`. Es la operación más frecuente en una memoria que se usa de verdad.

### 3. Memoria documental

Espejo Markdown en la bóveda Obsidian. El workflow `PraxIA Sync — Export MD` exporta a las **23:30 ART**; un cron con rclone sube a OneDrive a las **23:35**.

La decisión maestra, grabada como hecho #1 (2026-07-18):

> *"La memoria viva vive en PostgreSQL (esquema praxia) en el VPS; MiBoveda es el espejo humano editable."*

Esa frase resuelve la pregunta más difícil de cualquier sistema de memoria: **¿cuál es la fuente de verdad?** PostgreSQL. El Markdown es un espejo. Sin esa definición, dos representaciones divergen y nadie sabe cuál mirar.

El caso es un buen recordatorio de por qué esto importa: el 2026-07-10 se resolvió un problema huevo-gallina donde **la regla de guardado vivía dentro del vault que no estaba montado**. El sistema no podía saber cómo guardar porque la instrucción estaba del otro lado de la puerta cerrada. La conclusión es general: las reglas operativas no pueden vivir dentro del recurso que gobiernan.

Estado hoy: la capa documental es Markdown legible por un humano y por búsqueda de texto. **No hay indexación semántica.** Es adecuado para el volumen actual e insuficiente para lo que viene.

### 4. Memoria auditada

`praxia.agent_errors` más los logs de ejecución de n8n. La función `praxia.upsert_agent_error` hace deduplicación y reserva de alertas **en la base**, no en el workflow: el estado de "ya avisé de esto" tiene que sobrevivir a un reinicio del runtime.

Del lado financiero, el equivalente son `movimientos_auditoria`, `deuda_auditoria` y `fiscal_auditoria` (inmutable).

Esta capa suele ser la que falta. Sin ella no podés responder "¿por qué el agente hizo esto?", que es la primera pregunta cuando algo sale mal.

### El Memory Intent Gate

El problema clásico: **¿cuándo consulta la memoria el agente?**

Las dos respuestas fáciles son malas. Consultar siempre gasta tokens y latencia en cada "hola". Dejar que el modelo decida produce el peor modo de falla posible: el agente responde *"no tengo eso registrado"* sin haber consultado nada.

La solución acá son tres nodos: **`Code - Memory Intent Gate`** → **`IF Memory Required`** → **`PraxIA Memory Preflight`**. La decisión es **determinística, en código, no en el LLM**.

```js
// SINTÉTICO — la forma del gate, no la implementación real
const DISPARADORES = [
  /\b(record[aá]|acord[aá]|guard[aá]|anot[aá])\b/i,
  /\b(qu[eé] sab[eé]s|te dije|hab[ií]amos|qued[oó] en)\b/i,
  /\b(mi|mis)\s+(preferencia|regla|proyecto|tarea)/i,
  /\b(proyecto|tarea|pendiente|decisi[oó]n)\b/i,
];

function memoryRequired(texto) {
  const t = texto.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  return DISPARADORES.some((re) => re.test(t));
}
```

Cuatro razones por las que el gate es código y no un modelo:

1. **Costo cero.** Una regex no gasta tokens.
2. **Latencia cero.** No hay inferencia extra antes de la inferencia.
3. **Testeable.** Entrada → booleano. Un test por caso, sin red.
4. **Auditable.** Cuando falla, se ve exactamente qué patrón faltó y se agrega uno.

El trade-off honesto: un gate por reglas tiene falsos negativos. Una frase que pide memoria con palabras que no están en la lista no dispara la consulta. Se mitiga con un preflight amplio —ante la duda, consultar— y con la regla de sistema:

> *"Está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con action=consultar y haber recibido facts=[]"*

División de trabajo clara: **el código garantiza que la llamada ocurra; el prompt garantiza cómo se interpreta el resultado.** La garantía dura está en el código.

Cronología: el Memory Gate entró en el orquestador el **2026-07-20**, con rollback previo guardado antes de tocar nada.

### Recuperación: full-text en español, no vectores

`Consultar Memoria` corre en `BEGIN TRANSACTION READ ONLY`, con normalización de acentos, stop-words en español, `to_tsvector('spanish')` y **dos niveles de match**: un tier estricto (full-text) y un tier laxo (substring). El detalle del SQL está en [01](01-cuando-uso-sql.md).

Los dos tiers cumplen la función que en un RAG cumpliría el score de similitud, pero de forma **discreta y explicable**. El agente sabe si el match fue exacto o aproximado; no recibe un número flotante que no puede interpretar.

### Deduplicación y normalización

`Guardar Hecho` **deduplica por normalización** y **auto-clasifica reglas de seguridad**. El export del 2026-08-05 reporta 1 hecho deduplicado sobre 26.

La deduplicación en el momento de la escritura, y no en el de la lectura, es la decisión correcta y suele hacerse al revés. Sin ella, un agente que guarda cosas termina con cinco versiones del mismo hecho con distinta redacción, y en la consulta las cinco matchean. La memoria se degrada sola.

El pipeline de normalización —minúsculas, sin acentos, sin puntuación, espacios colapsados— es el mismo que se usa en la consulta. **Tiene que ser el mismo**: si normalizás distinto al escribir y al leer, la dedup no encuentra lo que la consulta sí encontraría.

Encima está el gate de seguridad del Router (`¿Tiene secreto?` → `Rechazo Secreto`), respaldado por el hecho #14:

> *"Nunca guardar contraseñas, tokens, API keys, claves privadas, credenciales ni datos bancarios completos. Si Aldo intenta guardar algo sensible, advertirle y sugerir guardar solo una referencia segura."*

Que la regla esté guardada **como un hecho** dentro de la propia memoria es coherente con el diseño: las reglas del sistema son datos, se consultan igual que todo lo demás, y se pueden auditar.

### Qué se hará distinto cuando entren papers y PDFs a escala

Acá el criterio se invierte, y conviene decirlo antes de que pase.

Hoy la capa documental son archivos Markdown y PDFs archivados en Drive. El Agente Papers Científicos v2.1 consulta Europe PMC y OpenAlex **en vivo** y escribe resultados a Sheets: no hay corpus local. Por eso no hace falta índice semántico.

Cuando el corpus sea local y grande —papers guardados, PDFs de manuales, documentación técnica acumulada— las cuatro condiciones que hacen a un RAG la respuesta correcta se cumplen todas: volumen alto, texto no estructurado, consultas conceptuales, vocabulario abierto.

Cómo lo encararía, y qué me obligaría a resolver primero:

| Decisión | Criterio |
|---|---|
| Motor | `pgvector` en el PostgreSQL que ya existe. Un servicio nuevo sólo si el volumen lo obliga |
| Alcance | **Sólo la capa documental.** `memory_facts` sigue en full-text. No mezclar |
| Chunking | Por sección con solapamiento, no por cantidad fija de caracteres |
| Metadatos | Fuente, fecha, DOI, sección. Filtrar por metadato antes de buscar por vector |
| Sincronización | El chunk apunta a `documentos.sha256`. Si el documento cambia, el chunk se invalida |
| Evaluación | Un set de preguntas con respuesta conocida, corriendo en el mismo harness que el resto. Sin eso, "mejoró" es una impresión |
| Fallback | Si la recuperación no supera un umbral, `insufficient_evidence`. Nunca inventar |

Las tablas `papers` y `documentos` (con `sha256`, `mime`, `bucket_url` y dedup, de v3.6) son la base sobre la que iría. La deduplicación por hash ya existe, que es la mitad del problema de sincronización resuelto.

El resto es `[PENDIENTE DE VERIFICAR]`: no hay fecha, no hay diseño escrito y no hay corpus todavía. Anticiparlo como criterio es útil; presentarlo como plan sería inventar.

## Regla

Separá las cuatro capas y elegí el mecanismo de cada una por separado. Un RAG vectorial se justifica por volumen de texto no estructurado, no por tener un agente: con decenas de hechos cortos, `to_tsvector('spanish')` es más preciso, más barato y explicable.

> Última verificación: 2026-08-05
