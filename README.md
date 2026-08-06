# PraxIA Ops

**Ingeniería de sistemas agénticos de IA, construidos sin escribir una línea de código a mano.**

Aldo Cáceres Ruiz Díaz · Microbiología, bioseguridad y gobernanza QBRN · Argentina
[English summary](README.en.md)

---

## Qué es esto

PraxIA Ops es una plataforma de agentes de IA operativos, en producción 24/7, construida entre julio y agosto de 2026 sobre un VPS propio. No es un chatbot ni una demo: es un sistema con orquestador, subagentes especializados, memoria persistente en PostgreSQL, control humano en las acciones consecuentes, auditoría de errores y despliegue con rollback.

Está construido con **programación no-code / low-code asistida por IA**: n8n como motor de orquestación, SQL escrito y revisado como contrato de datos, agentes de código (Claude Code) como implementadores bajo supervisión, y una disciplina de ingeniería explícita — plan, evidencia, prueba, release, rollback — que es la parte que realmente hace la diferencia.

Este repositorio es la **documentación ordenada, sanitizada y verificable** de ese trabajo.

> **Nota de alcance:** el runtime, las credenciales y los datos reales viven en infraestructura privada. Acá se publica arquitectura, método, esquemas, contratos y artefactos sanitizados. Ver [`SECURITY.md`](SECURITY.md) y la [política de publicación](docs/05-gobernanza/politica-de-publicacion.md).

---

## Números del sistema (corte 2026-08-06)

| Métrica | Valor |
|---|---|
| Agentes en producción | 1 orquestador + 15 subagentes/workflows |
| Workflows n8n registrados / activos | 217 / 25 |
| Ejecuciones conservadas (ventana 7 días) | 377 — 343 exitosas, 19 fallidas |
| Migraciones SQL versionadas | 40+ (esquema fiscal en v4.13) |
| Tablas en producción | 39 |
| Casos de test automatizados | 606 verdes, 0 salteados (`node --test` + PGlite) |
| Endpoints HTTP en la API financiera | 60+, ninguno `DELETE` |
| Herramientas MCP expuestas | 22, en 4 scopes OAuth |
| Días desde el primer workflow al sistema actual | 22 |

---

## Mapa del repositorio

### Empezá por acá

| Si querés… | Leé |
|---|---|
| Entender qué hace el sistema y cómo se usa | **[Manual de usuario](docs/00-manual-de-usuario/)** |
| Ver la arquitectura | [Arquitectura](docs/01-arquitectura/) |
| Saber **cuándo uso SQL, cuándo n8n, cuándo un subagente** | **[Desglose técnico](docs/02-desglose-tecnico/)** |
| Ver cómo se le pone freno a un agente que opera sobre algo que importa | **[Agente Fiscal](systems/praxia-agente-fiscal/)** |
| Ver cómo se construyó, día por día | [Cronología](docs/03-cronologia/) |
| Ver las decisiones y por qué | [Decisiones (ADR)](docs/04-decisiones/) |
| Ver el método de trabajo con agentes de IA | [Gobernanza](docs/05-gobernanza/) |
| Operar o reparar el sistema | [Runbooks](docs/06-runbooks/) |
| Saber qué existe y qué todavía no | **[Hoja de ruta](ROADMAP.md)** |

### Subsistemas

| Subsistema | Qué es | Estado |
|---|---|---|
| [`systems/oppenheimer`](systems/oppenheimer/) | Agente personal: Telegram, voz, imagen, PDF, mail, agenda, papers, búsqueda web | Producción |
| [`systems/praxia-memory-core`](systems/praxia-memory-core/) | Memoria persistente en PostgreSQL + espejo Markdown | Producción |
| [`systems/praxia-finanzas`](systems/praxia-finanzas/) | Finanzas y núcleo fiscal: API, dashboard, MCP, 606 tests | Producción |
| [`systems/praxia-agente-fiscal`](systems/praxia-agente-fiscal/) | Agente fiscal: contrato de solo lectura, motor de precedentes, propuestas con aprobación humana | Producción |
| [`systems/ai-command-center`](systems/ai-command-center/) | Fábrica de contenido multimarca | Diseño (Fase 0) |

### Artefactos

| Carpeta | Contenido |
|---|---|
| [`artifacts/sql`](artifacts/sql/) | Esquemas y migraciones sanitizados |
| [`artifacts/workflows-n8n`](artifacts/workflows-n8n/) | Estructura de los workflows, sin credenciales |
| [`artifacts/prompts`](artifacts/prompts/) | Prompts de sistema de los agentes, sanitizados |
| [`artifacts/openapi`](artifacts/openapi/) | Contrato OpenAPI de la API financiera |

---

## Stack

**Orquestación** n8n 2.31.5 self-hosted · **Datos** PostgreSQL 16 · **Runtime** Docker + Traefik (TLS) en VPS Hostinger
**Modelos** OpenAI (chat, Whisper, TTS) · **Interfaz** Telegram, dashboard HTML, MCP (SSE + OAuth/PKCE)
**Backend** Node.js ESM sin framework · **Tests** `node --test` + PGlite · **Docs** Obsidian → Markdown versionado
**Integraciones** Gmail · Google Calendar · Drive · Sheets · Tavily · Europe PMC · OpenAlex · Open-Meteo · RSS

---

## Los cinco principios que ordenan todo

1. **Sin orden no hay sistema, solo experimentos.** Planificación antes de implementación, siempre.
2. **Inspección no equivale a autorización de cambio.** Un agente puede leer todo; escribir requiere un permiso explícito.
3. **La ausencia de dato no se convierte en un dato inventado.** Si no hay evidencia, se declara el vacío.
4. **La aprobación humana no es un trámite.** Mandar un mail, gastar plata, borrar o publicar pasan por una persona.
5. **Todo despliegue tiene rollback verificado.** Si no se puede volver atrás, no se sube.

Cada uno está desarrollado, con ejemplos reales, en [`docs/05-gobernanza`](docs/05-gobernanza/).

---

## Qué demuestra este repositorio

Este no es un portafolio de tutoriales terminados. Es el registro de un sistema real, con sus incidentes y sus fracasos documentados:

- Un PDF de 21,9 MB que rompió el pipeline de Telegram, y la reparación con estados explícitos ([incidente](docs/06-runbooks/incidente-pdf-telegram.md)).
- Un buscador web que pasó 2 de 7 pruebas reales y **no se publicó** ([decisión](docs/04-decisiones/adr-006-buscador-general-no-publicado.md)).
- Producción tres migraciones atrás durante cinco días, porque se miraba el repositorio y no el servidor ([post-mortem](docs/06-runbooks/postmortem-drift-produccion.md)).
- Veintidós movimientos bien clasificados y sin clasificar al mismo tiempo: `estado_fiscal` divergía de los campos que lo determinan, y la corrección fue derivarlo en la base en vez de recordarlo en la aplicación ([post-mortem](docs/06-runbooks/postmortem-estado-fiscal-divergente.md)).
- 73 workflows de laboratorio conviviendo con producción, inventariados y clasificados antes de tocar nada.

Un sistema que solo muestra sus éxitos no está documentado: está publicitado.

---

## Licencia

[Apache 2.0](LICENSE). La documentación y las plantillas son reutilizables con atribución.
