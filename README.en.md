# PraxIA Ops — English summary

**Production AI agent systems, engineered without hand-writing application code.**

Aldo Cáceres Ruiz Díaz · Microbiology, biosafety and CBRN governance · Argentina

---

PraxIA Ops is a 24/7 agentic platform running on a self-hosted VPS: one orchestrator, fifteen specialised subagents, persistent PostgreSQL memory, human approval gates on consequential actions, global error routing and versioned releases with rollback.

It was built with **AI-assisted no-code/low-code engineering** — n8n as the orchestration engine, SQL as the data contract, coding agents as supervised implementers — under an explicit delivery discipline: plan, evidence, test, release, rollback.

This repository is the sanitised, verifiable documentation of that work. The runtime, credentials and real data stay private.

## System at a glance (2026-08-06)

| Metric | Value |
|---|---|
| Agents in production | 1 orchestrator + 15 subagents/workflows |
| n8n workflows registered / active | 217 / 25 |
| Executions retained (7-day window) | 377 — 343 succeeded, 19 failed |
| Versioned SQL migrations | 40+ (fiscal schema at v4.13) |
| Tables in production | 39 |
| Automated test cases | 606 passing, 0 skipped (`node --test` + PGlite) |
| HTTP endpoints on the finance API | 60+, zero `DELETE` |
| MCP tools exposed | 22, across 4 OAuth scopes |
| Days from first workflow to current system | 22 |

## Where to look

- [User manual](docs/00-manual-de-usuario/) — what the system does and how it is operated
- [Architecture](docs/01-arquitectura/) — current state, target state, data model
- [Technical breakdown](docs/02-desglose-tecnico/) — when to use SQL, n8n, a subagent, an MCP, a front-end
- [Timeline](docs/03-cronologia/) — how it was built, day by day
- [Decisions](docs/04-decisiones/) — architecture decision records
- [Governance](docs/05-gobernanza/) — the AI-assisted delivery lifecycle, templates and checklists
- [Runbooks](docs/06-runbooks/) — operations, incidents, post-mortems
- [Fiscal agent](systems/praxia-agente-fiscal/) — a read-only contract, precedent-based proposals and a hard 403: the agent proposes, it never applies, and the separation is a credential it does not hold

Documentation is written in Spanish (Argentina); the governance guides in `docs/05-gobernanza` are available in English.

## Stack

n8n 2.31.5 self-hosted · PostgreSQL 16 · Docker + Traefik (TLS) · OpenAI (chat, Whisper, TTS) · Node.js ESM (no framework) · Model Context Protocol (SSE + OAuth/PKCE) · Telegram · Google Workspace · Tavily · Europe PMC · OpenAlex

## Licence

[Apache 2.0](LICENSE).
