# Manual de usuario — PraxIA Ops / Oppenheimer

Este manual explica cómo se usa el sistema desde afuera: qué se le puede pedir, qué devuelve, qué no hace y qué hacer cuando algo falla.

> **In English** — This is the index of the end-user manual: nine chapters on how the system is operated from
> the outside, not on how it is built. It covers what you can ask Oppenheimer over Telegram (text, voice,
> image, PDF), what each subagent does and with which permissions, how movements are recorded and queried in
> PraxIA Finanzas, what the memory layer may store and what it must refuse, which routines run unattended and
> at what time, and how the monthly fiscal diagnosis and its proposals are decided. Content is cut at
> 2026-08-05; anything that could not be checked against the running system is marked
> `[PENDIENTE DE VERIFICAR]` instead of being filled in with a guess. The page closes with a deliberate
> warning: production was also used as a laboratory, there is no real environment separation, backups have no
> off-site copy or proven restore, and on 2026-08-05 the server was found three migrations behind the repo.

<!-- fin del resumen en inglés -->

## Para quién es

Para la persona que **usa** el sistema, no para quien lo construye.

Si querés entender la arquitectura interna, los esquemas SQL, las migraciones o el ciclo de vida de los workflows, este no es el lugar: buscá en `docs/01-arquitectura`, `docs/02-desglose-tecnico` y `docs/05-gobernanza`.

Acá vas a encontrar:

- Qué es el sistema y qué problema resuelve.
- Cómo se habla con Oppenheimer por Telegram.
- Qué hace cada subagente y con qué permisos.
- Cómo se cargan y consultan movimientos en PraxIA Finanzas.
- Qué recuerda la memoria y qué tiene prohibido guardar.
- Qué corre solo, a qué hora.
- Qué hacer cuando algo no anda.
- Cómo se pide el diagnóstico fiscal de un mes y cómo se deciden las propuestas del Agente Fiscal.

## Cómo leerlo

Hay dos recorridos posibles.

**Si es tu primera vez**, leé en orden: `01` → `02` → `05` → `06`. Con eso ya podés operar el día a día.

**Si venís a resolver algo puntual**, andá directo a la tabla de abajo o al [glosario](08-glosario.md) si te trabó una palabra.

Todo el manual está escrito con corte al **2026-08-05**. Lo que no pudimos verificar contra el sistema real aparece marcado como `[PENDIENTE DE VERIFICAR]`. Preferimos dejar el hueco visible antes que rellenarlo con una suposición.

## Índice

| # | Archivo | De qué va |
|---|---|---|
| 01 | [Qué es PraxIA Ops](01-que-es-praxia-ops.md) | El sistema, el problema que resuelve, qué NO es, los principios y el mapa de piezas |
| 02 | [Oppenheimer — guía de uso](02-oppenheimer-guia-de-uso.md) | El día a día por Telegram: texto, voz, imagen, PDF y sus límites |
| 03 | [Subagentes](03-subagentes.md) | Ficha de cada subagente: qué hace, cómo se lo invoca, qué permisos tiene |
| 04 | [PraxIA Finanzas — guía de uso](04-praxia-finanzas-guia-de-uso.md) | Cargar y consultar movimientos, deudas, pagos y cierre fiscal |
| 05 | [Memoria: qué recuerda y qué no](05-memoria-que-recuerda-y-que-no.md) | Las cuatro capas de memoria y la regla anti-secretos |
| 06 | [Rutinas automáticas](06-rutinas-automaticas.md) | Lo que corre solo: briefings, exports, alertas y avisos |
| 07 | [Cuando algo falla](07-cuando-algo-falla.md) | Síntoma → causa probable → qué hacer |
| 08 | [Glosario](08-glosario.md) | Los términos que aparecen en todo el repo, en criollo |
| 09 | [El Agente Fiscal — guía de uso](09-agente-fiscal-guia-de-uso.md) | Diagnóstico de un mes, propuestas, aprobación y qué bloquea un cierre |

## Quiero hacer X → andá a Y

| Quiero… | Andá a |
|---|---|
| Entender de qué se trata todo esto | [01 — Qué es PraxIA Ops](01-que-es-praxia-ops.md) |
| Mandarle un audio y que me conteste hablando | [02 — Voz](02-oppenheimer-guia-de-uso.md#voz) |
| Mandarle un PDF para que lo lea y lo archive | [02 — PDF](02-oppenheimer-guia-de-uso.md#pdf) |
| Que me busque algo en internet con fuentes | [03 — Buscador Web Tavily](03-subagentes.md#buscador-web-tavily-v1) |
| Que me redacte y mande un mail | [03 — Agente de Email](03-subagentes.md#agente-de-email) |
| Cargar o mover un evento de la agenda | [03 — Agente de Calendario](03-subagentes.md#agente-de-calendario) |
| Buscar papers científicos | [03 — Agente Papers Científicos](03-subagentes.md#agente-papers-científicos-v21) |
| Cargar un gasto o un ingreso | [04 — Cómo se carga un movimiento](04-praxia-finanzas-guia-de-uso.md#cómo-se-carga-un-movimiento) |
| Saber cuánta plata hay | [04 — Consultar saldos](04-praxia-finanzas-guia-de-uso.md#consultar-lo-que-ya-está-cargado) |
| Importar un resumen en PDF, CSV o Excel | [04 — Importar documentos](04-praxia-finanzas-guia-de-uso.md#importar-un-documento) |
| Anotar una deuda y después pagarla | [04 — Deudas y pagos](04-praxia-finanzas-guia-de-uso.md#deudas-y-pagos) |
| Cerrar un período fiscal | [04 — Cierre fiscal](04-praxia-finanzas-guia-de-uso.md#cierre-fiscal-y-propuestas-del-agente) |
| Pedir el diagnóstico fiscal de un mes | [09 — Pedirle el diagnóstico de un mes](09-agente-fiscal-guia-de-uso.md#pedirle-el-diagnóstico-de-un-mes) |
| Aprobar o rechazar una propuesta del Agente Fiscal | [09 — Las propuestas](09-agente-fiscal-guia-de-uso.md#las-propuestas) |
| Entender por qué un cierre no avanza | [09 — Qué bloquea un cierre](09-agente-fiscal-guia-de-uso.md#qué-bloquea-un-cierre-y-cómo-destrabarlo) |
| Que se acuerde de algo importante | [05 — Pedirle que recuerde](05-memoria-que-recuerda-y-que-no.md#cómo-pedirle-que-recuerde-algo) |
| Que se olvide de algo | [05 — Pedirle que olvide](05-memoria-que-recuerda-y-que-no.md#cómo-pedirle-que-olvide-algo) |
| Leer la memoria fuera de Telegram | [05 — Dónde ver la memoria](05-memoria-que-recuerda-y-que-no.md#dónde-ver-la-memoria-en-obsidian) |
| Cambiar el horario del briefing | [06 — Rutinas automáticas](06-rutinas-automaticas.md#tabla-de-rutinas) |
| Apagar una rutina que molesta | [06 — Cómo se apaga](06-rutinas-automaticas.md#cómo-se-apaga-o-se-cambia-una-rutina) |
| Entender por qué no me responde | [07 — No responde](07-cuando-algo-falla.md#síntoma-no-responde-nada) |
| Entender por qué dice "no tengo registrado" | [07 — No tengo registrado](07-cuando-algo-falla.md#síntoma-responde-no-tengo-registrado) |
| Saber qué significa "idempotencia" o "canary" | [08 — Glosario](08-glosario.md) |

## Una advertencia honesta

El sistema funciona y está en producción, pero tiene deudas técnicas conocidas y documentadas: producción se usó también como laboratorio, no hay separación real de ambientes, los backups no tienen off-site ni ensayo de restauración demostrado, y el 2026-08-05 se detectó que el servidor estaba tres migraciones atrás del repositorio.

No lo escondemos. Está en `docs/05-gobernanza` y afecta lo que podés esperar del sistema: es confiable para el uso diario, no es todavía una plataforma con garantías de nivel producto.

> Última verificación: 2026-08-05
