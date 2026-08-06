# Desglose técnico — cuándo uso cada herramienta y por qué

Esta sección no explica *qué hace* el sistema (eso está en el [manual de usuario](../00-manual-de-usuario/)) ni *cómo está armado* (eso está en [arquitectura](../01-arquitectura/)). Explica **el criterio de decisión**: frente a un problema concreto, por qué la solución terminó siendo una constraint de PostgreSQL y no un `if` en un prompt, por qué un subagente y no una herramienta más en el orquestador, por qué una API propia y no un BaaS.

## Para quién es

Para alguien que construye sistemas agénticos y necesita decidir lo mismo. Cada archivo tiene la misma estructura:

- **`## Criterio`** — el razonamiento general, aplicable a cualquier sistema. Es opinión de ingeniería, no un hecho del sistema.
- **`## En este sistema`** — cómo se resolvió acá, con nombres reales de tablas, funciones, workflows y endpoints.
- **`## Regla`** — una o dos líneas que resumen el criterio para que se pueda citar sin releer todo.

Los bloques de código son **sintéticos y sanitizados**: reproducen la forma de la solución real, no su contenido. No hay IPs, hostnames, tokens, identificadores de chat ni datos financieros reales en ninguna parte de este repo.

## La matriz de decisión

Esta tabla es el atajo. Si sólo vas a leer una cosa de esta sección, que sea esto.

| Necesidad | Herramienta elegida | Por qué | Ejemplo real en el sistema |
|---|---|---|---|
| Una invariante que **nunca** puede romperse, ni por bug ni por alucinación | **Constraint / trigger en PostgreSQL** | La base es el único punto por el que pasan todos los caminos de escritura. Un prompt no es una garantía | `prohibir_delete_fisico`, `propuesta_contenido_inmutable`, `deuda_pago_validar` ([01](01-cuando-uso-sql.md)) |
| Una regla de negocio con aritmética o derivación de estado | **Función SQL** | Determinística, testeable con SQL puro, imposible de saltear desde la aplicación | `fx_vigente()`, `cierre_chequeos()`, `movimiento_estado_fiscal_derivado` ([01](01-cuando-uso-sql.md)) |
| Lectura compleja que consumen varios clientes distintos | **Vista SQL como API de lectura** | Un solo lugar donde vive el join; los clientes no reimplementan la lógica | `v_saldos_por_moneda`, `v_deudas`, `v_fiscal_periodo` ([01](01-cuando-uso-sql.md)) |
| Búsqueda de texto en español sobre memoria estructurada | **`to_tsvector('spanish')` + transacción `READ ONLY`** | Sin infraestructura vectorial, sin costo por consulta, sin latencia de red | `Consultar Memoria` de PraxIA Memory ([07](07-memoria-y-rag.md)) |
| Conectar servicios externos con triggers, reintentos y ramas | **n8n** | El costo de mantener glue code entre 10 APIs es más alto que el costo de un runtime visual | Orquestador Oppenheimer, 51 nodos, 25 workflows activos ([02](02-cuando-uso-n8n.md)) |
| Capturar todos los errores del runtime en un solo lugar | **`errorWorkflow` global de n8n** | Un punto único de captura vale más que try/catch repartido en 200 workflows | `PraxIA — Avisador de Errores v1` ([02](02-cuando-uso-n8n.md)) |
| Un dominio con prompt propio, permisos propios y aprobación propia | **Subagente (`toolWorkflow`)** | Aísla el blast radius, achica el prompt del orquestador, se testea solo | 15 subagentes; el de Email tiene su propia aprobación humana ([03](03-cuando-construyo-un-subagente.md)) |
| Una capacidad puntual sin permisos especiales | **Herramienta en el orquestador, no subagente** | Un subagente cuesta latencia, contrato y versionado. Si no hay dominio que aislar, es burocracia | `Calculator`, `HTTP CLIMA`, `Buscar en Drive` ([03](03-cuando-construyo-un-subagente.md)) |
| Exponer el sistema a un cliente LLM que no controlo | **Servidor MCP** | Descubrimiento de herramientas + OAuth por scope, sin escribir un cliente por cada modelo | 22 herramientas en 4 scopes: `read`, `fiscal.read`, `write`, `modify` ([04](04-cuando-uso-un-mcp.md)) |
| Un contrato de escritura estable, idempotente y auditable | **API HTTP propia (Node.js, sin framework)** | El contrato de ingesta es el corazón del sistema; no quería que dependiera de una UI ni de un vendor | `POST /api/ingesta` como único camino de alta ([05](05-cuando-uso-una-api-propia.md)) |
| Revisar, corregir y confirmar muchos registros seguidos | **Dashboard web** | El chat es pésimo para trabajo tabular y para ver 40 pendientes de un vistazo | SPA vanilla de un archivo, 7 secciones ([06](06-cuando-uso-frontend.md)) |
| Que el agente recuerde hechos entre conversaciones | **Tabla `memory_facts` + gate determinístico** | Barato, inspeccionable, corregible a mano. Sin embeddings | `Code - Memory Intent Gate` + `PraxIA Memory Preflight` ([07](07-memoria-y-rag.md)) |
| Publicar servicios con TLS sin exponer la base | **Docker + Traefik, sin puertos publicados** | La superficie de ataque que no existe no se audita | PostgreSQL sólo en loopback, `127.0.0.1:5433` ([08](08-infra-y-despliegue.md)) |
| Verificar lógica que vive en SQL | **`node --test` + PGlite con el esquema real** | Mockear la base es testear el mock. PGlite corre el DDL de verdad | 606 casos en verde ([09](09-testing-y-evidencia.md)) |

## Índice

| # | Archivo | La pregunta que responde |
|---|---|---|
| 01 | [Cuándo uso SQL](01-cuando-uso-sql.md) | ¿Esta regla va en la base o en el agente? |
| 02 | [Cuándo uso n8n](02-cuando-uso-n8n.md) | ¿Qué resuelve bien un runtime visual y qué no? |
| 03 | [Cuándo construyo un subagente](03-cuando-construyo-un-subagente.md) | ¿Subagente nuevo o una herramienta más? |
| 04 | [Cuándo uso un MCP](04-cuando-uso-un-mcp.md) | ¿Cómo expongo capacidades a un LLM que no controlo? |
| 05 | [Cuándo uso una API propia](05-cuando-uso-una-api-propia.md) | ¿Por qué escribir HTTP a mano en 2026? |
| 06 | [Cuándo uso frontend](06-cuando-uso-frontend.md) | ¿Hace falta una pantalla o alcanza el chat? |
| 07 | [Memoria y RAG](07-memoria-y-rag.md) | ¿Por qué no hay base vectorial acá? |
| 08 | [Infra y despliegue](08-infra-y-despliegue.md) | ¿Cómo se sube algo sin poder volver atrás a mano? |
| 09 | [Testing y evidencia](09-testing-y-evidencia.md) | ¿Qué cuenta como "probado" en un sistema con LLMs? |

## Tres cosas que atraviesan toda la sección

**1. La capa más baja que pueda garantizar algo, lo garantiza.**
Si una regla puede vivir en la base, vive en la base. Si no, en la API. Si no, en el workflow. El prompt es la última capa, no la primera. Un modelo puede equivocarse; un `CHECK` no.

**2. Cada capa nueva se paga con latencia, contrato y versionado.**
No hay decisión arquitectónica gratis. Un subagente agrega un salto de red y un contrato que mantener. Un MCP agrega una superficie de autenticación. Una API propia agrega código que hay que testear. La pregunta no es "¿esto sería mejor?" sino "¿el problema justifica el costo?".

**3. Lo que no está verificado se declara vacío.**
El vocabulario de evidencia del proyecto — `Verificado`, `Confirmado por el responsable`, `Inferido`, `Pendiente de verificar`, `Historia incompleta` — se usa en toda esta sección. Donde no hay dato, dice `[PENDIENTE DE VERIFICAR]`. No se completa con una narración plausible.

## Los números que respaldan los ejemplos

Todos los casos que se citan en esta sección salen del mismo sistema, con corte al 2026-08-05. Para que se entienda la escala de la que estamos hablando —ni un juguete ni una plataforma corporativa:

| Dato | Valor | Dónde se usa como evidencia |
|---|---|---|
| Workflows n8n registrados / activos / de laboratorio | 217 / 25 / 125 | [02](02-cuando-uso-n8n.md), [08](08-infra-y-despliegue.md) |
| Nodos del orquestador (27/07 → 03/08) | 47 → 51 | [02](02-cuando-uso-n8n.md), [03](03-cuando-construyo-un-subagente.md) |
| Ejecuciones en 7 días | 377 (343 OK / 19 fallidas) | [02](02-cuando-uso-n8n.md) |
| Versión del esquema fiscal | v4.13, 40+ migraciones, 39 tablas | [01](01-cuando-uso-sql.md), [08](08-infra-y-despliegue.md) |
| Endpoints HTTP | 60+, ninguno `DELETE` | [05](05-cuando-uso-una-api-propia.md) |
| Herramientas MCP | 22 en 4 scopes | [04](04-cuando-uso-un-mcp.md) |
| Casos de test | 606 en verde, 0 salteados | [09](09-testing-y-evidencia.md) |
| Hechos en la memoria estructurada | 26 | [07](07-memoria-y-rag.md) |
| Líneas del dashboard | 1.911, en un archivo | [06](06-cuando-uso-frontend.md) |

El de 26 hechos es el que más discusión genera y es el más importante: es la razón por la que acá no hay base vectorial. La escala manda sobre la moda.

## Vocabulario de evidencia

Se usa en toda la sección, con el mismo significado que en [`docs/05-gobernanza`](../05-gobernanza/):

- **`Verificado`** — se inspeccionó el sistema y se registró el resultado.
- **`Confirmado por el responsable`** — lo afirma quien lo hizo, sin inspección independiente.
- **`Inferido`** — se deduce de otra cosa; es razonable y no está comprobado.
- **`Pendiente de verificar`** — hueco explícito, marcado `[PENDIENTE DE VERIFICAR]`.
- **`Historia incompleta`** — hay evidencia parcial y falta el resto.

La regla que lo sostiene, textual del proyecto: *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

## Qué no cubre esta sección

Para no hacerte buscar de más:

- **Cómo se usa el sistema** → [manual de usuario](../00-manual-de-usuario/).
- **Diagramas y vista general de componentes** → [arquitectura](../01-arquitectura/).
- **Por qué se tomó cada decisión, con fecha y contexto** → [decisiones (ADR)](../04-decisiones/).
- **El método de trabajo con agentes de IA, las compuertas y las plantillas** → [gobernanza](../05-gobernanza/).
- **Qué hacer cuando algo se rompe** → [runbooks](../06-runbooks/).
- **Esquemas, workflows y prompts sanitizados** → [`artifacts/`](../../artifacts/).

## Los cinco antipatrones que esta sección intenta evitar

Cada archivo desarrolla al menos uno. Están acá juntos porque son la forma más rápida de saber si algo de esto te sirve.

| Antipatrón | Cómo se ve | Dónde está tratado |
|---|---|---|
| **La regla vive sólo en el prompt** | "El agente sabe que no tiene que borrar" | [01](01-cuando-uso-sql.md) — la garantía va en la base |
| **El nodo Code que crece** | 200 líneas de lógica de negocio dentro de un workflow | [02](02-cuando-uso-n8n.md) — sin tests, sin diff, sin revisión |
| **Un subagente por prolijidad** | Cinco agentes que podrían ser tres nodos | [03](03-cuando-construyo-un-subagente.md) — latencia y contratos que nadie pidió |
| **RAG por default** | Base vectorial para 26 hechos de una línea | [07](07-memoria-y-rag.md) — pipeline caro, recuperación peor |
| **El umbral se fija después** | "Dio 2 de 7, pero se ve prometedor" | [09](09-testing-y-evidencia.md) — el criterio se declara antes |

## Cómo leer esta sección

- **Si venís a decidir algo puntual**, andá a la matriz de arriba y de ahí al archivo.
- **Si querés el criterio central del repo**, leé [03 — Cuándo construyo un subagente](03-cuando-construyo-un-subagente.md). Es el que más se aplica a cualquier sistema agéntico, más allá de este stack.
- **Si te interesa el método antes que la tecnología**, leé [09 — Testing y evidencia](09-testing-y-evidencia.md) y después [`docs/05-gobernanza`](../05-gobernanza/).
- **Si querés ver dónde falló esto**, están declarados: el drift de producción en [08](08-infra-y-despliegue.md), el buscador que no se publicó en [09](09-testing-y-evidencia.md), los defaults inseguros del MCP en [04](04-cuando-uso-un-mcp.md).

## Regla

El criterio importa más que la herramienta. Una decisión bien fundamentada con la herramienta equivocada se corrige; una decisión sin fundamento con la herramienta correcta se repite mal en el próximo sistema.

> Última verificación: 2026-08-05
