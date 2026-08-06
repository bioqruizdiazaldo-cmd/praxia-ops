# Cronología

Esta sección reconstruye, día por día, cómo se construyó PraxIA Ops entre el 10 de julio y el 5 de agosto de 2026 — con las fechas, los incidentes y las cosas que no funcionaron.

## Por qué existe esta sección

Un repositorio de portafolio suele mostrar el estado final: la arquitectura ya ordenada, los tests en verde, el diagrama prolijo. Eso oculta lo único que realmente demuestra experiencia, que es **la secuencia de decisiones y correcciones** que llevó hasta ahí.

Acá está la secuencia completa. Incluye el PDF que rompió el pipeline, el buscador que no se publicó, las 33 migraciones SQL que estuvieron sin control de versiones durante once días y los cinco días en los que producción corrió tres migraciones atrás sin que nadie lo notara.

## Las cuatro etapas

El proyecto tiene 27 días de calendario y cuatro etapas con carácter propio. La división no es arbitraria: cada corte coincide con un cambio en el tipo de problema que se estaba resolviendo.

| Etapa | Fechas | Pregunta que dominaba | Resultado |
|---|---|---|---|
| **1. Laboratorio** | 10 – 14/07 | ¿Cómo ordeno esto antes de construir? | Método, taxonomía y las decisiones D-1 a D-8 |
| **2. Núcleo** | 14 – 20/07 | ¿Puedo hacer que funcione? | Orquestador, subagentes, memoria en PostgreSQL |
| **3. Endurecimiento** | 20 – 28/07 | ¿Puedo confiar en que siga funcionando? | Errores centralizados, aprobación humana, incidentes reparados, tests |
| **4. Producto** | 28/07 – 05/08 | ¿Puedo operar esto como un sistema y no como un experimento? | Git, migraciones versionadas, MCP, gobernanza, post-mortem |

### Etapa 1 — Laboratorio (10 al 14 de julio)

Cuatro días sin escribir un solo workflow productivo. Se resolvió el problema huevo-gallina de la memoria documental, se armó un PKM de IA con reglas anti-caos y se cerró una planificación maestra con ocho decisiones fundacionales. La regla que salió de acá ordena todo lo demás: *"Sin orden no hay sistema, solo experimentos. El error a evitar no es técnico, es de secuencia."*

### Etapa 2 — Núcleo (14 al 20 de julio)

Seis días de construcción intensa. Nace el orquestador Oppenheimer y sus subagentes base, después el Agente de Papers, después PraxIA Memory Core sobre PostgreSQL propio. Al final de la etapa hay un agente que recuerda entre conversaciones y exporta su memoria a Markdown todas las noches.

### Etapa 3 — Endurecimiento (20 al 28 de julio)

La etapa más larga y la que más se parece a ingeniería de verdad. Se centraliza el manejo de errores, se valida la aprobación humana en el envío de mails, se rompe el pipeline con un PDF de 21,9 MB y se repara con una máquina de estados, se inventarían 79 workflows de laboratorio antes de tocar nada, se construye un buscador web y se decide **no publicarlo** porque pasó 2 de 7 pruebas. Cierra con el checkpoint que descubre que no había repositorio git.

### Etapa 4 — Producto (28 de julio al 6 de agosto)

Diez días de consolidación: commit inicial, migraciones v4.0 a v4.13, servidor MCP versionado, contrato Finanzas↔Fiscal, línea base de gobernanza en 18 documentos y un post-mortem de drift entre repositorio y servidor. Termina con un agente que propone clasificaciones fiscales a partir de precedentes del propio dueño.

## Índice

| Documento | Qué contiene |
|---|---|
| [Línea de tiempo](linea-de-tiempo.md) | La tabla cronológica completa, día por día, agrupada por etapa |
| [Hitos por componente](hitos-por-componente.md) | La misma historia reorganizada por subsistema, para ver la evolución de cada pieza |
| [Métricas de avance](metricas-de-avance.md) | Los números duros con fecha de corte, y qué no miden |

## Cómo leer las tablas

Cada hito de la línea de tiempo tiene una columna **Estado de evidencia** con el vocabulario que se usa en todo el repositorio:

| Etiqueta | Significa |
|---|---|
| `Verificado` | Sale de una inspección directa de artefactos: workflows, esquemas, archivos, logs o exports |
| `Inferido` | Se deduce de artefactos verificados, pero no hay un registro directo del hecho en sí |
| `Pendiente de verificar` | Se afirma, no está comprobado, y se declara como vacío en lugar de completarlo con una narración |

La regla de fondo, tomada de la línea base de gobernanza: *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

## Advertencia de alcance

Las fechas y los hitos son reales. Los identificadores de infraestructura no se publican: no vas a encontrar IPs, hostnames, chat_ids, IDs de credenciales ni datos financieros. Cualquier ejemplo de comando o de dato es sintético y está marcado como tal.

> Última verificación: 2026-08-05
