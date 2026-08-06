# Registro de cambios

Cambios de este repositorio de documentación. El registro de cambios del sistema en sí está en [`docs/03-cronologia`](docs/03-cronologia/).

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Las versiones son de la documentación, no del sistema.

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
