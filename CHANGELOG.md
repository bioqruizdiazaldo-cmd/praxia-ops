# Registro de cambios

Cambios de este repositorio de documentación. El registro de cambios del sistema en sí está en [`docs/03-cronologia`](docs/03-cronologia/).

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Las versiones son de la documentación, no del sistema.

---

## [0.3.0] — 2026-08-06

Seguridad y herramientas. Sale de una auditoría de la carpeta de trabajo privada que buscaba filtraciones y encontró algo distinto: no había secretos publicados, pero sí permisos de agente que en la práctica entregaban el servidor de producción.

### Agregado

- **`tools/n8n-versionado/`** — la herramienta que el bloqueante 2 de la hoja de ruta pedía y que hasta ahora sólo estaba descrita. Exporta desde la API de n8n con paginación, normaliza el JSON quitando los catorce campos de runtime que ensucian el diff, verifica secretos y datos personales antes de commitear, y genera y valida el manifiesto de 11 campos. Cero dependencias, 65 tests, dos fixtures — uno limpio y uno con problemas sembrados.
- **Gobernanza**: [auditar antes de publicar](docs/05-gobernanza/auditar-antes-de-publicar.md), los nueve controles con su triaje de falsos positivos; y [permisos de agente](docs/05-gobernanza/permisos-de-agente.md), la precedencia, las cuatro trampas de sintaxis y los límites reales del mecanismo.
- **Runbooks**: [rotar una credencial expuesta](docs/06-runbooks/rotar-una-credencial-expuesta.md) — ocho pasos, criterio de éxito 401 o 403 y no "ya lo moví"; [publicar una actualización](docs/06-runbooks/publicar-una-actualizacion.md) — el circuito completo con su tabla de fallas; y [sacar datos operativos de la bóveda](docs/06-runbooks/sacar-datos-operativos-de-la-boveda.md) — la limpieza de coordenadas y volcados de una carpeta de notas sincronizada.
- **Resúmenes en inglés** al principio de los documentos clave, para que el repositorio se pueda leer sin español.
- **CI**: un job nuevo que corre los tests del toolkit y comprueba que su verificador sigue detectando sus propios señuelos. Si dejara de hacerlo, la compuerta que protege cada publicación estaría rota sin que nadie se entere.
- **`tools/n8n-versionado/tests/senuelos.mjs`** — los valores con forma de secreto que prueban el verificador se arman en tiempo de ejecución, uniendo pedazos. Ningún archivo del repositorio contiene una cadena con forma de secreto, ni real ni falsa.

### Cambiado

- **Bloqueante 2 de la hoja de ruta: `No existe` → `Parcial`.** La herramienta existe y está probada; ningún workflow real está versionado todavía. Tener el exportador y no tener los workflows en git es la distancia entre una herramienta y una práctica, y la hoja de ruta ahora lo dice así.
- Los índices de gobernanza y de runbooks, con un principio nuevo: cada dato operativo vive en un solo lugar, y ese lugar no es la carpeta que sincroniza.

### Seguridad

Sin filtraciones en lo publicado: se verificó contra el remoto, clonando. Los hallazgos fueron todos del lado privado y se corrigieron ahí. El que importa, y que queda documentado porque le puede pasar a cualquiera que trabaje con agentes:

- **Reglas de permiso terminadas en comodín.** Aprobando comandos puntuales durante sesiones largas, el prefijo común se fue acortando hasta que quedaron reglas de la forma `Bash(ssh ... root@<host> ' *)`. Leída literalmente, esa regla autoriza cualquier comando como root en producción, sin preguntar. No se puso ahí con mala intención: se acumuló. La corrección está descrita en el runbook, y quitar una regla de la lista de permitidos no prohíbe nada — sólo devuelve la pregunta.
- **Cero excepciones en el escaneo de secretos.** La protección de push de GitHub rechazó esta misma versión por un token de Slack **falso** escrito literal en un test. Hizo bien: un escáner que distinguiera secretos de verdad de secretos de mentira no serviría de nada. En vez de pedir la excepción se cambió el código, y hoy ni el escaneo local, ni el del CI, ni el de GitHub tienen lista de exentos.

---

## [0.2.0] — 2026-08-06

Incorporación del subsistema Agente Fiscal y puesta al día de los números del repositorio contra el estado real de producción.

### Agregado

- **Ficha de subsistema `systems/praxia-agente-fiscal`** (8 documentos): README con las cinco garantías de diseño y el diagrama de frontera, el contrato Finanzas↔Fiscal v1.0, la capa de lectura, el motor de precedentes, las propuestas y sus dos huellas, el ciclo del cierre fiscal, la seguridad y los permisos, y el inventario de límites y deudas.
- **Decisiones**: 4 registros nuevos — [ADR-010](docs/04-decisiones/adr-010-el-agente-propone-el-humano-decide.md) el agente propone y el humano decide, [ADR-011](docs/04-decisiones/adr-011-precedentes-verificables-en-vez-de-inferencia.md) precedentes verificables en vez de inferencia, [ADR-012](docs/04-decisiones/adr-012-la-invariante-vive-en-la-base.md) la invariante vive en la base, [ADR-013](docs/04-decisiones/adr-013-abstenerse-antes-que-devolver-un-resultado-parcial.md) abstenerse antes que devolver un resultado parcial.
- **Manual de usuario**: capítulo [09 — El Agente Fiscal, guía de uso](docs/00-manual-de-usuario/09-agente-fiscal-guia-de-uso.md).
- **Runbooks**: [cierre fiscal mensual](docs/06-runbooks/cierre-fiscal-mensual.md) y [post-mortem del `estado_fiscal` divergente](docs/06-runbooks/postmortem-estado-fiscal-divergente.md).
- **Artefactos SQL sanitizados**: [`07-nucleo-fiscal.sql`](artifacts/sql/07-nucleo-fiscal.sql), [`08-cierre-y-estado-derivado.sql`](artifacts/sql/08-cierre-y-estado-derivado.sql) y [`09-propuestas-fiscales.sql`](artifacts/sql/09-propuestas-fiscales.sql).
- Referencias cruzadas al subsistema fiscal desde el `README.md`, el `README.en.md`, la arquitectura, el desglose técnico, la cronología y la ficha de PraxIA Finanzas.
- **Hoja de ruta**: cuatro capacidades nuevas con evidencia `Verificado` y una sección de pendientes del lado fiscal — disparo mensual en n8n, rol de PostgreSQL de solo lectura, persistencia de la auditoría de consultas y carga de las plantillas de obligaciones reales.

### Corregido

Los números publicados el 2026-08-05 habían quedado atrás del sistema real. Al corte 2026-08-06:

- Versión del esquema `praxia_finanzas` en producción: **v4.8 → v4.13**.
- Tablas en producción: **35 → 39**.
- Casos de test: **554 → 606 verdes, 0 salteados**.
- Migraciones SQL versionadas: **33+ → 40+**.
- El conteo de archivos de test (27) se retiró de las tablas de métricas: quedó `[PENDIENTE DE VERIFICAR]` y se publica sólo el número de casos.

Las menciones históricas fechadas —por ejemplo "de 25 a 35 tablas" describiendo la puesta al día del 2026-08-05— se conservan tal como estaban: son hechos con fecha, no afirmaciones de estado actual.

---

## [0.1.0] — 2026-08-05

Primera publicación. Consolidación de todo el trabajo disperso en la bóveda de trabajo en un repositorio único, ordenado y sanitizado.

### Agregado

- **Manual de usuario** (9 documentos): qué es el sistema, guía de uso de Oppenheimer por Telegram, ficha de cada subagente, guía de PraxIA Finanzas, modelo de memoria, rutinas automáticas, diagnóstico de fallas y glosario.
- **Arquitectura** (7 documentos): visión general con diagramas, estado actual AS-IS, estado objetivo TO-BE con brechas priorizadas, modelo de datos, modelo de permisos y plan de escalamiento multiagente.
- **Desglose técnico** (10 documentos): criterios de decisión para SQL, n8n, subagentes, MCP, API propia, frontend, memoria y RAG, infraestructura y testing.
- **Cronología** (4 documentos): línea de tiempo del 2026-07-10 al 2026-08-05, hitos por componente y métricas de avance.
- **Decisiones**: 9 registros de decisión de arquitectura (ADR-001 a ADR-009).
- **Gobernanza** (19 documentos): ciclo de vida SDLC asistido por IA, acuerdo de trabajo con agentes, versionado de workflows no-code, política de publicación, 3 checklists, 7 plantillas y la versión en inglés de los cuatro documentos centrales.
- **Runbooks** (6 documentos): incidente del PDF de Telegram, post-mortem del drift de producción, despliegue de migraciones, publicación de workflows y limpieza de runtime.
- **Fichas de subsistema**: Oppenheimer, PraxIA Memory Core, PraxIA Finanzas y AI-Command-Center.
- **Artefactos sanitizados**: 6 archivos SQL sintéticos verificados contra PostgreSQL 16, manifiesto y contrato de workflows n8n, prompts de sistema reconstruidos y patrones de prompt reutilizables, descripción del contrato OpenAPI.
- **Hoja de ruta** (`ROADMAP.md`): estado de evidencia por capacidad, separando explícitamente lo construido de lo planeado, con la condición bajo la cual cada pendiente pasa a ser publicable.
- Archivos de repositorio: `README.md`, `README.en.md`, `SECURITY.md`, `CONTRIBUTING.md`, `LICENSE` (Apache 2.0), `.gitignore` endurecido contra secretos y exports crudos.
- Verificación automática en `.github/workflows/verificacion.yml`: escaneo de secretos y datos prohibidos, comprobación de enlaces internos y aplicación de los esquemas SQL sobre PostgreSQL 16 en cada push.

### Notas

- El material de origen es una auditoría de solo lectura de la bóveda de trabajo, realizada el 2026-08-05.
- Todo dato que no se pudo verificar quedó marcado como `[PENDIENTE DE VERIFICAR]` en vez de completarse con una suposición.
- Las deudas técnicas y los riesgos abiertos del sistema se publican tal como están, sin maquillar.
- Este repositorio reemplaza y absorbe el borrador local `ai-assisted-software-governance`, cuyo contenido vive ahora en [`docs/05-gobernanza`](docs/05-gobernanza/).
