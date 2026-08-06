# ADR-002 — PostgreSQL propio en vez de Supabase

La decisión original era usar Supabase en las fases 1 y 2 con PostgreSQL propio como repliegue; cuatro días después se fue directo a PostgreSQL propio y nunca se volvió.

## Estado

Aceptada y superada.

La decisión original (D-2) fue **Aceptada** el 2026-07-14 y quedó **superada** por la práctica el 2026-07-18, sin que en su momento se escribiera un ADR de reemplazo. Este documento registra las dos cosas: lo que se decidió y lo que efectivamente pasó.

## Fecha

- **2026-07-14** — D-2: Supabase para las fases 1-2, PostgreSQL propio como repliegue.
- **2026-07-18** — Nace PraxIA Memory Core directamente sobre PostgreSQL propio en el VPS. El repliegue se convierte en la opción principal sin declaración formal.
- **2026-08-05** — Se escribe este ADR para cerrar la brecha entre la decisión y el hecho.

## Contexto

En la planificación maestra del 14 de julio, la elección de base de datos se resolvió con el razonamiento habitual: un servicio gestionado reduce el trabajo de operación, trae autenticación, API automática, panel de administración y copias de seguridad sin que haya que montar nada. Para un proyecto de una sola persona que necesita llegar rápido a algo usable, es el default sensato. PostgreSQL propio quedó anotado como repliegue para el caso de que el servicio gestionado no alcanzara.

Lo que cambió el cálculo fue algo que no estaba sobre la mesa el día 14: para el 18 de julio ya existía un VPS con Docker, Traefik y n8n corriendo, decidido en D-3 y ejecutado en los días intermedios. **La infraestructura que hacía "caro" a PostgreSQL propio ya estaba paga y andando.**

A eso se sumaron tres cosas concretas que aparecieron al empezar a escribir la memoria de verdad:

1. **La lógica de memoria terminó siendo SQL denso, no CRUD.** La consulta de memoria corre en `BEGIN TRANSACTION READ ONLY`, normaliza acentos, aplica stop-words en español, usa `to_tsvector('spanish')` y resuelve dos niveles de coincidencia. El guardado deduplica por normalización y autoclasifica reglas de seguridad. Nada de eso se beneficia de una API REST generada: se beneficia de escribir SQL y ejecutarlo.
2. **El consumidor principal es n8n, que ya estaba en el mismo host.** El nodo de PostgreSQL de n8n habla directo con la base. Un servicio externo agregaba una llamada de red, una capa de autenticación y una dependencia de disponibilidad a cambio de nada.
3. **Los datos son personales y sensibles por definición.** Memoria de decisiones, agenda, correo, y más adelante finanzas. Mantenerlos en un contenedor propio, con el puerto expuesto **sólo a loopback**, es una superficie de ataque materialmente más chica que un endpoint público con claves.

## Decisión

**Toda la memoria estructurada vive en un PostgreSQL 16 propio, en un contenedor del VPS, con el puerto expuesto exclusivamente a la interfaz de loopback y sin publicación al host.**

La decisión maestra quedó grabada dentro del propio sistema como hecho #1 de la memoria, el 2026-07-18:

> *"La memoria viva vive en PostgreSQL (esquema praxia) en el VPS; MiBoveda es el espejo humano editable."*

Cuando el 26 de julio apareció la necesidad de finanzas, la misma decisión se aplicó por extensión: un esquema más (`praxia_finanzas`) en la misma base, no un servicio nuevo. Eso está en el [ADR-005](adr-005-finanzas-como-esquema-y-no-como-app-nueva.md).

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **PostgreSQL propio en el VPS** | Sin costo marginal (el VPS ya estaba); SQL sin capas intermedias; sólo en loopback; extensiones y funciones sin restricción; misma base para memoria y finanzas | Backups, actualizaciones y monitoreo quedan a cargo propio; no hay panel de administración regalado | **Elegida en la práctica el 18/07** |
| Supabase gestionado (D-2 original) | Operación resuelta; panel, autenticación y API automática; copias de seguridad incluidas | Latencia y dependencia de red para el consumidor principal; datos personales en un tercero; el valor agregado no aplicaba a este caso de uso | Superada |
| Los dos: Supabase para la aplicación y PostgreSQL propio para la memoria | Cada uno donde rinde | **Dos fuentes de verdad.** El problema que el proyecto más quería evitar | Rechazada |
| SQLite, aprovechando el que ya usa n8n | Cero infraestructura adicional | Sin búsqueda de texto en español decente; concurrencia limitada; mezcla el estado del runtime con los datos del dominio | Rechazada |

## Consecuencias

### Positivas

- **Una sola base para memoria y finanzas.** Los esquemas `praxia` y `praxia_finanzas` conviven en la misma instancia, y el ~80% de reutilización de infraestructura que hizo viable PraxIA Finanzas es consecuencia directa de esto.
- **SQL sin techo.** Transacciones de solo lectura, `to_tsvector('spanish')`, triggers, funciones y vistas se usaron sin pedirle permiso a ninguna capa intermedia. Buena parte de las invariantes del sistema vive ahí.
- **Superficie de red mínima.** El puerto de la base sólo escucha en loopback y no hay puertos publicados al host. Lo que no está expuesto no hay que defenderlo.
- **Costo marginal cero.** El VPS ya estaba pago por año.
- **Los tests pueden replicar producción.** El harness con PGlite aplica el mismo DDL real. Con un servicio gestionado y sus extensiones propias, esa equivalencia sería más difícil de sostener.

### Negativas

- **La operación es propia y se nota.** Los backups son diarios, con lock, manifiesto y script de chequeo, pero **sin copia fuera del sitio y sin ensayo de restauración demostrado**. Con un servicio gestionado eso venía resuelto. Es el costo real de esta decisión y está abierto.
- **No hay panel de administración regalado.** El dashboard financiero es una SPA vanilla de 1.911 líneas escrita a mano.
- **No hay alta disponibilidad.** Una instancia, un host. Si el VPS cae, cae todo.
- **La autenticación hubo que resolverla aparte:** tokens en la API propia y OAuth con JWT y PKCE en el servidor MCP.

### Operativas

- Actualizaciones de PostgreSQL, monitoreo y crecimiento de disco son responsabilidad propia.
- El procedimiento de migración tuvo que escribirse: backup verificado, aplicación transaccional con `ON_ERROR_STOP=1`, verificación de no-regresión. Está en el [runbook](../06-runbooks/despliegue-de-una-migracion.md).
- La ausencia de un panel gestionado contribuyó al drift del 05/08: no había ninguna vista que mostrara el estado del esquema desplegado sin entrar al servidor a mirarlo.

### De seguridad

- **Menos superficie.** Sin endpoint público de base de datos, sin claves de API de base circulando entre servicios.
- **Los datos personales no salen del host.** Memoria, agenda, correo y finanzas viven en una máquina bajo control propio.
- Contrapartida directa: **el parcheo de PostgreSQL es responsabilidad propia**, y una instancia sin actualizar es un riesgo que un servicio gestionado habría absorbido.
- La clave de cifrado de los datos sensibles se movió fuera del volumen de datos en la migración v3.4. Ese tipo de control es posible justamente por tener la base bajo control propio.

## Evidencia

| Afirmación | Estado |
|---|---|
| D-2 del 2026-07-14: Supabase para fases 1-2 con PostgreSQL propio de repliegue | `Verificado` |
| PraxIA Memory Core nace el 2026-07-18 sobre PostgreSQL propio | `Verificado` |
| Hecho #1 de la memoria con la decisión maestra, fechado 2026-07-18 | `Verificado` |
| PostgreSQL 16 en contenedor propio, base `praxia_memory`, esquema `praxia`, puerto sólo en loopback | `Verificado` |
| SQL de consulta con transacción de solo lectura, normalización, stop-words y dos niveles de coincidencia | `Verificado` |
| Backups diarios con lock, manifiesto y script de chequeo | `Verificado` |
| Ausencia de copia fuera del sitio y de ensayo de restauración | `Verificado` como riesgo abierto |
| Que la migración a Supabase se haya evaluado formalmente antes de descartarla | `Historia incompleta` — no hay registro de una evaluación explícita; el cambio fue de hecho |
| Comparación de costos entre las dos opciones | `Pendiente de verificar` — nunca se hizo |

## Por qué cambió, dicho sin vueltas

La decisión original no fue mala: fue tomada con la información del 14 de julio, cuando el VPS todavía era un plan. Cuatro días después el contexto ya era otro y la opción de repliegue era estrictamente mejor.

Lo que sí fue una falla de método es que **el cambio no se documentó cuando ocurrió**. Se cambió de base de datos y la decisión escrita siguió diciendo otra cosa durante dieciocho días. En un proyecto de una persona eso se sostiene porque la persona se acuerda. En cualquier proyecto con más de una persona, ese hueco entre la decisión escrita y la práctica es exactamente donde nacen los malentendidos caros.

Este ADR existe para cerrar ese hueco, no para embellecerlo.

## Disparador de revisión

Revisar cuando:

- Aparezca un segundo usuario o un cliente externo y la operación propia empiece a competir con el tiempo de construcción.
- Se necesite alta disponibilidad o recuperación ante desastre con objetivos declarados de tiempo y punto de recuperación. Es el escenario más probable de reversión parcial.
- La ausencia de copia fuera del sitio deje de ser aceptable — y eso ya debería resolverse ahora, sin esperar a cambiar de base.
- Se necesite acceso directo desde clientes que no estén en el host, lo que obligaría a exponer la base y anularía la ventaja principal.

> Última verificación: 2026-08-05
