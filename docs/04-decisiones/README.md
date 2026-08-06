# Decisiones (ADR)

Las trece decisiones que explican por qué este sistema es como es — incluida la de no publicar un componente terminado.

> **In English** — Index of the thirteen architecture decision records that explain why the system is shaped
> the way it is, each with its status: accepted, superseded, rejected, or standing. If you read only one, read
> ADR-006 — the decision not to publish a component that was already built and working, because it scored 2 of
> 7 against a threshold of 7/7 declared in advance. It is the only one of the thirteen that produced no
> deliverable. The last four form a block around the fiscal subsystem and answer four versions of the same
> question — how to put a brake on an agent operating on something that matters: what it may write, what its
> claims rest on, where invariants are enforced, and what it does when it cannot fully answer.

<!-- fin del resumen en inglés -->

## Qué es un ADR y por qué están acá

Un ADR (*Architecture Decision Record*) es el registro de una decisión de diseño con su contexto, sus alternativas y sus consecuencias. No es documentación de la solución: es documentación **del momento en que se eligió**, con la información que había entonces.

Sirven para tres cosas concretas:

- Evitar rediscutir lo mismo cada dos semanas.
- Poder revertir con criterio, porque está escrito qué se estaba resolviendo.
- Distinguir una decisión de una costumbre. Todo lo que no está acá y sin embargo se hace siempre igual, es una costumbre no auditada.

Están en español, son cortos y ninguno afirma más de lo que se puede demostrar.

## Índice

| ID | Título | Fecha | Estado |
|---|---|---|---|
| [ADR-001](adr-001-un-agente-excelente-antes-que-muchos.md) | Un agente excelente antes que muchos | 2026-07-14 | Aceptada |
| [ADR-002](adr-002-postgres-propio-en-vez-de-supabase.md) | PostgreSQL propio en vez de Supabase | 2026-07-14 · superada 2026-07-18 | Aceptada y superada |
| [ADR-003](adr-003-memoria-en-capas-sin-rag-vectorial.md) | Memoria en capas, sin RAG vectorial | 2026-07-18 | Vigente |
| [ADR-004](adr-004-aprobacion-humana-en-acciones-consecuentes.md) | Aprobación humana en acciones consecuentes | 2026-07-14 | Vigente |
| [ADR-005](adr-005-finanzas-como-esquema-y-no-como-app-nueva.md) | Finanzas como esquema, no como aplicación nueva | 2026-07-26 | Aceptada |
| [ADR-006](adr-006-buscador-general-no-publicado.md) | **El Buscador General no se publica** | 2026-07-27 | **Rechazada** |
| [ADR-007](adr-007-sin-borrado-fisico.md) | Sin borrado físico | 2026-07-27 | Vigente |
| [ADR-008](adr-008-el-repositorio-como-fuente-de-verdad.md) | El repositorio como fuente de verdad | 2026-08-03 | Aceptada |
| [ADR-009](adr-009-publicar-el-metodo-no-el-sistema.md) | Publicar el método, no el sistema | 2026-08-05 | Vigente |
| [ADR-010](adr-010-el-agente-propone-el-humano-decide.md) | El agente propone, el humano decide | 2026-08-05 | Vigente |
| [ADR-011](adr-011-precedentes-verificables-en-vez-de-inferencia.md) | Precedentes verificables en vez de inferencia | 2026-08-05 | Vigente |
| [ADR-012](adr-012-la-invariante-vive-en-la-base.md) | La invariante vive en la base | 2026-08-05 | Vigente |
| [ADR-013](adr-013-abstenerse-antes-que-devolver-un-resultado-parcial.md) | Abstenerse antes que devolver un resultado parcial | 2026-08-04 | Vigente |

## Vocabulario de estados

| Estado | Significa |
|---|---|
| **Aceptada** | Se decidió y se implementó. Sigue en pie |
| **Aceptada y superada** | Se decidió, y después la práctica la reemplazó. Se conserva porque el cambio enseña algo |
| **Rechazada** | Se evaluó y se decidió no hacerlo, o no publicarlo |
| **Vigente** | Es una regla operativa activa que condiciona el diseño de todo lo nuevo |

## Si sólo vas a leer una

Leé el [ADR-006](adr-006-buscador-general-no-publicado.md). Es la decisión de no publicar un componente que ya estaba construido, porque pasó 2 de 7 pruebas contra una exigencia declarada de 7/7. Es la única de las trece que no produjo ningún entregable, y es la que mejor describe cómo se trabaja acá.

## El bloque fiscal: ADR-010 a ADR-013

Las cuatro últimas salieron del mismo subsistema —el [Agente Fiscal](../../systems/praxia-agente-fiscal/README.md)— y se leen mejor juntas, porque responden a cuatro versiones de la misma pregunta: **cómo se le pone freno a un agente que opera sobre algo que importa.**

| ADR | La pregunta que responde |
|---|---|
| [ADR-010](adr-010-el-agente-propone-el-humano-decide.md) | ¿Qué puede escribir el agente? Una tabla que no mueve un peso, y no tiene la credencial para aprobarla |
| [ADR-011](adr-011-precedentes-verificables-en-vez-de-inferencia.md) | ¿En qué se apoya lo que afirma? En decisiones anteriores del titular, no en inferencia |
| [ADR-012](adr-012-la-invariante-vive-en-la-base.md) | ¿Dónde se garantiza lo que tiene que ser siempre cierto? En la base, porque el código ya falló una vez |
| [ADR-013](adr-013-abstenerse-antes-que-devolver-un-resultado-parcial.md) | ¿Qué hace cuando no puede responder del todo? Se abstiene, con un código, en vez de entregar la mitad |

## Relación con el resto del repositorio

- La secuencia temporal de estas decisiones está en la [cronología](../03-cronologia/linea-de-tiempo.md).
- El razonamiento técnico detrás de varias de ellas está desarrollado en el [desglose técnico](../02-desglose-tecnico/).
- Los procedimientos que se derivan de las decisiones están en los [runbooks](../06-runbooks/).
- El método general de trabajo con agentes de IA está en [gobernanza](../05-gobernanza/).

> Última verificación: 2026-08-05
