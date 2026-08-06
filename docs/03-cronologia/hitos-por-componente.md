# Hitos por componente

La misma historia de la [línea de tiempo](linea-de-tiempo.md), reorganizada por subsistema, para que se vea la evolución de cada pieza sin el ruido de las demás.

Sirve para responder una pregunta distinta. La línea de tiempo contesta *"¿qué pasó el 25 de julio?"*; esta página contesta *"¿cómo llegó la memoria a ser lo que es?"*.

## Mapa rápido

| Componente | Nace | Estado al 2026-08-06 | Versión o fase |
|---|---|---|---|
| [Oppenheimer](#oppenheimer--orquestador-y-subagentes) | 14/07 23:05 | Producción | Orquestador con 51 nodos |
| [PraxIA Memory Core](#praxia-memory-core--memoria-persistente) | 18/07 | Producción | 4 capas, sin RAG vectorial |
| [PraxIA Finanzas](#praxia-finanzas--esquema-financiero-y-fiscal) | 26/07 | Producción | Esquema DB v4.13 · API 3.6.0 · MCP 1.0.0 |
| [Agente Fiscal](#agente-fiscal--el-que-propone-y-nunca-aplica) | 04/08 | Producción | Contrato v1.0 · motor v4.8 · esquema v4.13 |
| [Buscador web](#buscador-web--el-que-sí-y-el-que-no) | 25/07 23:18 | Tavily V1 en producción · General **no publicado** | V1 activo · General rechazado |
| [Gobernanza](#gobernanza--método-evidencia-y-publicación) | 13/07 | Línea base cerrada | 18 documentos (03/08) |
| [Contenido](#contenido--ai-command-center-y-arquitecto-ia-redes) | 20/07 | **Fase 0, nada desplegado** | Cero commits |

---

## Oppenheimer — orquestador y subagentes

El agente personal. Canal único Telegram, orquestador central, subagentes invocados como `toolWorkflow`. Es la pieza más antigua y la que más cambió sin romper compatibilidad hacia afuera: para el usuario final, la interfaz nunca dejó de ser un chat.

| Fase | Fecha | Qué cambió |
|---|---|---|
| Nacimiento | 2026-07-14 23:05 | Orquestador creado con seis subagentes base: Email, Calendario, Planillas, Recordatorios, Enviar Gmail y Briefing Diario |
| Ampliación de canales | 2026-07-15 | Briefing de Noticias (06:30, RSS → síntesis → Telegram), Alertas TradingView por webhook, primera versión del Agente de Papers |
| v2.1 | 2026-07-16/17 | Agente de Papers Científicos v2.1 con pipeline explícito: query-builder → Europe PMC + OpenAlex → ranker → writer → planilla. Resumen técnico consolidado |
| Multimodalidad | 2026-07-17 | Voz "Jarvis" (Whisper para entrada, TTS para salida) y arquitectura de subagentes formalizada |
| Memoria conectada | 2026-07-20 | **Memory Gate** en el orquestador: decisión determinística de consultar memoria antes de responder, con rollback previo guardado |
| Errores centralizados | 2026-07-22 → 07-23 | `PraxIA — Avisador de Errores v1` creado y enlazado como `errorWorkflow` global. Integración productiva aprobada con 37 nodos en el orquestador y la tabla de errores en cero filas |
| Email V3 | 2026-07-23/24 | Harnesses, candidatos, gates y canarios. Publicado con 5 pruebas aisladas OK y cierre declarado **provisional**: faltaban reinicio controlado y validación desde Telegram |
| Incidente y reparación de PDF | 2026-07-25 | Descarga de documentos con validación previa, límite de 20 MiB, verificación de firma `%PDF-`, extracción real y máquina de estados con `failed` terminal. 6/6 PASS |
| Búsqueda web | 2026-07-25 23:18 | Buscador Web Tavily V1 incorporado como subagente con contrato de evidencia |
| Integración financiera | 2026-08-02/03 | Enrutamiento de consultas financieras hacia PraxIA Finanzas mediante un workflow de **solo lectura** |
| Corte de inventario | 2026-08-03 | 51 nodos en el orquestador. 217 workflows registrados, 25 activos. 377 ejecuciones conservadas en la ventana de 7 días |

**Herramientas conectadas al orquestador al corte:** Telegram · OpenAI (chat, Whisper, TTS) · Google Drive · Google Calendar · Gmail · Google Sheets · Tavily · Open-Meteo · Europe PMC + OpenAlex · PostgreSQL · webhook de recordatorios · `Calculator` · `Think` · `Memory Buffer`.

**Deuda abierta:** el `errorWorkflow` global sigue nombrado con el prefijo `[TEST]` aunque está activo desde el 22/07.

---

## PraxIA Memory Core — memoria persistente

Cuatro capas y ningún embedding. La decisión de no usar RAG vectorial está documentada en el [ADR-003](../04-decisiones/adr-003-memoria-en-capas-sin-rag-vectorial.md) y sigue vigente.

| Fase | Fecha | Qué cambió |
|---|---|---|
| Prehistoria documental | 2026-07-10 | Guía de replicación de la memoria Obsidian. Se resuelve el problema huevo-gallina de la regla de guardado |
| Esquema v1 | 2026-07-16 | Primer esquema de datos y memoria, todavía en papel |
| Roles definidos | 2026-07-17 | Visión de dos memorias con roles diferenciados y un puente entre ellas, antes de implementar ninguna |
| Núcleo en PostgreSQL | 2026-07-18 | Nacen Guardar, Consultar, Router, Tareas y Proyectos sobre PostgreSQL 16 propio, base `praxia_memory`, esquema `praxia`. Hecho #1: *"La memoria viva vive en PostgreSQL; el vault es el espejo humano editable"* |
| Primer export | 2026-07-19 | Export a Markdown verificado con 7 hechos, 1 proyecto y 1 tarea |
| Sincronización | 2026-07-19/20 | PraxIA Sync operativo: export desde n8n a las 23:30 ART, cron con rclone a las 23:35 |
| Gate determinístico | 2026-07-20 | `Code - Memory Intent Gate` + `IF Memory Required` + `PraxIA Memory Preflight`. Regla del prompt de sistema: prohibido responder "no tengo registrado" sin haber consultado primero y recibido `facts=[]` |
| Capa de auditoría | 2026-07-22 | `praxia.agent_errors` y la función `praxia.upsert_agent_error` con deduplicación y reserva de alertas |
| Auditoría de volumen | 2026-07-24 | Export de auditoría con 44 workflows |
| Estado al corte | 2026-08-05 02:30 UTC | Export verificado: 2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, **0 secretos omitidos** |

**Las cuatro capas:**

1. **Corta** — `Memory Buffer` de n8n, conversación reciente.
2. **Estructurada** — PostgreSQL 16 en contenedor propio, expuesto sólo a loopback. Tablas `memory_facts`, `memory_events`, `tasks`, `projects`.
3. **Documental** — espejo Markdown en el vault, sincronizado todas las noches.
4. **Auditada** — `agent_errors` y logs de ejecución.

**Regla de seguridad grabada como hecho #14:** nunca guardar contraseñas, tokens, API keys, claves privadas, credenciales ni datos bancarios completos; si se intenta, advertir y sugerir guardar sólo una referencia segura. El Router implementa el gate "¿Tiene secreto?" con salida a `Rechazo Secreto`.

---

## PraxIA Finanzas — esquema financiero y fiscal

El componente más grande y el de evolución más rápida: de una decisión de diseño el 26 de julio a un esquema en v4.8, con API, dashboard, servidor MCP y 606 tests, en diez días — y a v4.13 con 39 tablas al día siguiente. Nació con una restricción que definió todo: no ser un sistema nuevo.

### Base y contrato

| Versión | Fecha | Qué cambió |
|---|---|---|
| Decisión fundacional | 2026-07-26 | *"NO como sistema nuevo"*. Se construye como esquema `praxia_finanzas` dentro del PostgreSQL existente, reutilizando ~80% de la infraestructura |
| DDL v3.1 | 2026-07-27 | Esquema base aplicado al VPS con backups y SHA-256 verificados: `perfiles`, `proyectos`, `cuentas`, `categorias`, `fx_rates`, `movimientos`, `transferencias`, `valuaciones`, `cuotas_movimientos`, `ingesta_raw`, `datos_sensibles`, `movimientos_auditoria`, `schema_migrations`. Trigger `prohibir_delete_fisico` |
| v3.2 → v3.5 | 2026-07-27 | Cifrado server-side, contrato universal de ingesta, clave fuera del volumen, cierre de seguridad |
| v3.6 | 2026-07-27 | Tabla `documentos` con `sha256`, `mime` y deduplicación. **Canary de Telegram aprobado, Fase 2 completada** |
| Adaptadores | 2026-07-28 | Fase 3: adaptadores PDF/CSV/Excel/email y conexión a clientes LLM externos. 141/141 tests |
| Control de versiones | 2026-07-28 | **Commit inicial.** Hasta ese día: 3275 líneas de JS y 33 migraciones SQL sin git |

### Núcleo fiscal

| Versión | Fecha | Qué cambió |
|---|---|---|
| v4.0 | 2026-07-28 | Núcleo fiscal escrito y **puesto en pausa**: `comprobantes`, `comprobante_iva`, `fiscal_perfiles`, `fiscal_reglas`, `fiscal_obligaciones`, `fiscal_cierres`, `fiscal_borradores`, `fiscal_auditoria` (inmutable), función `cierre_chequeos()` |
| v4.2 | 2026-07-29/30 | `fiscal_exportaciones` |
| v4.3 | 2026-07-29/30 | `deudas_pendientes` |
| v4.4 | 2026-07-31 | Deudas administrables: `deuda_auditoria`, vistas `v_deudas` y `v_deuda_resumen`. Tag `v4.3-pre-fase2`. **Última versión que llegó a producción antes del drift** |
| v4.5 | 2026-08-01 | `deuda_pagos` con guards `deuda_pago_validar` (misma moneda), `recalcular_saldo_deuda` y `movimiento_respaldo_deuda_guard`. Pagos totales y parciales sin duplicar movimientos |
| v4.6 | 2026-08-02/03 | Obligaciones recurrentes: `plantillas_recurrentes`, `plantilla_precios`, `planes_pago`, `plan_pago_origenes`, `plan_pago_documentos`, `obligacion_documentos`, `obligacion_cargos`, `generacion_ejecuciones`. Identidad de ocurrencia `(plantilla_id, occurrence_key)` |
| Contrato v1.0 | 2026-08-04 | Contrato Finanzas↔Fiscal aprobado. Capa de lectura fiscal con 9 operaciones solo-GET. Adenda del ADR para el tratamiento USD/ARS |
| v4.7 | 2026-08-05 | `movimiento_estado_fiscal_derivado` y `cierre_transicion_valida`: `estado_fiscal` ya no puede divergir de `ambito` + `deducible` |
| v4.8 | 2026-08-05 | `fiscal_propuestas` con triggers `propuesta_nace_pendiente`, `propuesta_contenido_inmutable` y `propuesta_transicion_valida`. Campos `huella` y `huella_evidencia`. `fiscal_motor.mjs`: propuestas por precedente del dueño. Dos detectores nuevos (11 → 13) |
| v4.9 | 2026-08-05/06 | Contribuyentes con FK obligatoria: `regimen_vigente()`, `perfil_fiscal_sin_solapamiento()`, `imputacion_mismo_contribuyente()`. Aislamiento entre contribuyentes garantizado en la base |
| v4.10 | 2026-08-05/06 | Plantillas recurrentes completas, con máquina de estados propia: reactivar una plantilla exige `vigente_desde` |
| v4.11 | 2026-08-05/06 | `catalogo_obligaciones`, `dias_no_habiles`, `terminacion_cuit`, `vencimiento_habil()` y `vencimiento_de_obligacion()` |
| v4.12 | 2026-08-05/06 | Feriados 2026 cargados |
| v4.13 | 2026-08-05/06 | Un régimen `historico` sigue siendo válido: `regimen_vigente()` deja de exigir `estado='vigente'` y sólo descarta `baja` y `observado` |

### Superficie e infraestructura del componente

| Aspecto | Fecha de corte | Estado |
|---|---|---|
| Servidor MCP | 2026-08-02/03 | Recuperado y versionado. 22 herramientas en 4 scopes OAuth: `praxia.read` (8), `praxia.fiscal.read` (10), `praxia.write` (1), `praxia.modify` (4) |
| Dashboard | 2026-08-02/03 | SPA vanilla de un archivo con 7 secciones. Prototipo UI v3 **aprobado en diseño, no migrado** |
| Puesta al día de producción | 2026-08-05 | v4.4 → v4.6 aplicadas. Verificación de no-regresión: 25 → 35 tablas, valores idénticos |
| Serie final desplegada | 2026-08-05/06 | v4.9 → v4.13 aplicadas. Producción en **v4.13**, **39 tablas**. Hubo un incidente de despliegue por un Dockerfile con la lista de archivos escrita a mano, resuelto con rollback |

**Invariantes que no cambiaron nunca:** único camino de alta (`POST /api/ingesta`), cero endpoints `DELETE`, rol de base de datos sin permiso `DELETE`, baja lógica con auditoría.

---

## Agente Fiscal — el que propone y nunca aplica

Nace como contrato antes que como código, y ése es el dato que lo distingue del resto de los componentes: el 4 de agosto se aprueba un documento de 21 secciones que declara qué puede leer, qué no puede tocar y qué tiene que hacer cuando no sabe. La implementación llega después y se limita a lo que el contrato ya permitía. Ficha completa en [`systems/praxia-agente-fiscal`](../../systems/praxia-agente-fiscal/).

| Fase | Fecha | Qué cambió |
|---|---|---|
| Contrato v1.0 aprobado | 2026-08-04 | 21 secciones + Anexo A. *"Contrato lógico y técnico de solo lectura"*, con principios no negociables, envelope de respuesta, 9 códigos de abstención y matriz de permisos. Ver [contrato-finanzas-fiscal.md](../../systems/praxia-agente-fiscal/contrato-finanzas-fiscal.md) |
| Capa de lectura | 2026-08-04 | Nueve operaciones solo-GET con guardia que rechaza todo lo que no empiece con `SELECT` o `WITH`, paginación por cursor y auditoría de consulta al log. Tercer token de API y 9 herramientas MCP bajo `praxia.fiscal.read`. **472 tests** |
| Anexo A | 2026-08-04 | Verificación del contrato contra el esquema real levantando PGlite con el DDL y 11 migraciones: 55 objetos. Registra dónde el cuerpo del contrato describía estados y columnas que la base no confirma |
| Incidente y v4.7 | 2026-08-05 | 22 movimientos clasificados y sin clasificar a la vez. `estado_fiscal` pasa a derivarse en la base y la máquina de estados del cierre deja de ser una función que nunca se ejecutaba. **492 tests**. Ver [post-mortem](../06-runbooks/postmortem-estado-fiscal-divergente.md) |
| v4.8 — propuestas y motor | 2026-08-05 | `fiscal_propuestas` con sus tres triggers y sus dos huellas, `fiscal_motor.mjs` con `diagnosticarPeriodo()`, y dos detectores nuevos (11 → 13). **606 tests verdes, 0 salteados** |
| Serie v4.9 → v4.13 | 2026-08-05/06 | Contribuyentes, plantillas recurrentes, catálogo de obligaciones con días no hábiles, feriados y régimen histórico válido. Producción en v4.13 |
| Publicación | 2026-08-06 | Ficha de subsistema en 8 documentos, ADR-010 a ADR-013, capítulo 09 del manual, runbook de cierre mensual y post-mortem |

**Umbrales del motor, tal como están en el código:** descripción mínima de 5 caracteres · sin precedente, abstención · precedentes contradictorios, abstención (no gana la mayoría) · confianza 0,60 / 0,75 / 0,85 según cuántos precedentes haya, **nunca 1** · el precedente no caduca por antigüedad, se informa la fecha de la última vez.

**Deuda abierta del componente:** el disparo mensual automático en n8n sigue siendo un esqueleto de cuatro nodos con trigger manual y el período hardcodeado; el rol de PostgreSQL de solo lectura —la segunda barrera— es tarea de despliegue pendiente; la auditoría de consultas no se persiste; y `cierre_chequeos()` arrastra a propósito el filtro que corrigió la v4.13. Inventario completo en [límites y deudas](../../systems/praxia-agente-fiscal/limites-y-deudas.md).

---

## Buscador web — el que sí y el que no

Dos componentes con el mismo propósito y destinos opuestos. Vale la pena verlos juntos: uno se publicó en horas y el otro no se publicó nunca, y la diferencia no fue el esfuerzo invertido.

### Buscador Web Tavily V1 — publicado

| Fase | Fecha | Qué cambió |
|---|---|---|
| V1 | 2026-07-25 23:18 | Nace, se publica y se verifica. Nueve nodos: validación de consulta → IF → preparación → HTTP a Tavily (Header Auth, `neverError=true`, timeout 20 s) → validación de fuentes → contexto / envoltura / merge |
| Corrección de fechas | 2026-07-26 | Manejo de hoy/ayer/temporada, `target_date` y `date_scope`. 8/8 |
| Corrección de contexto | 2026-07-26 | Corrección estructural del uso de `tavily_response`. 8/8 |
| Cobertura temática | 2026-07-26/27 | Etiquetas por resultado y fallback de 72 horas |

**Estados de salida tipados:** `ok`, `clarification_required`, `no_reliable_source`, `search_not_configured`, `technical_error`, `stable_knowledge_handoff`, `insufficient_evidence`. Un buscador que puede declarar que no encontró evidencia suficiente es más útil que uno que siempre responde algo.

### Buscador General — rechazado

| Fase | Fecha | Qué cambió |
|---|---|---|
| Fases 3B → 3E1 | 2026-07-27 | Relevancia, validador consolidado, métrica de alcance, fallback |
| Matriz fija | 2026-07-27 | Auditoría de ejecuciones y matriz de casos congelada **antes** de la revalidación |
| Revalidación | 2026-07-27 | **2/7 PASS contra una exigencia de 7/7 → NO PUBLICADO** |

Los fixtures no se ajustaron: *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."* Ver [ADR-006](../04-decisiones/adr-006-buscador-general-no-publicado.md).

---

## Gobernanza — método, evidencia y publicación

La capa que no se ve en ninguna demo y es la que hace publicable a todo el resto.

| Fase | Fecha | Qué cambió |
|---|---|---|
| PKM y reglas anti-caos | 2026-07-13 | IA_KNOWLEDGE_HUB: modelo de 5 niveles, 12 reglas anti-caos, taxonomía, ADR liviano. **Congelado desde el 17/07** |
| Decisiones fundacionales | 2026-07-14 | D-1 a D-8 cerradas junto con la arquitectura en 7 capas |
| ADRs de contenido | 2026-07-20 | Cinco ADRs de AI-Command-Center |
| Backup y recuperación | 2026-07-15 → 07-23 | Backup de n8n/SQLite con `RECOVERY.md`. Backups diarios con lock, `manifest.json` y `restore_check.sh`. SSH cerrado tras el despliegue verificado del 23/07 |
| Línea base AS-IS / TO-BE | 2026-08-03 | Inspección global de solo lectura y 18 documentos: AS-IS, TO-BE, inventarios, riesgos, estándares y política de saneamiento. *"Inspección no equivale a autorización de cambio"* |
| SDLC asistido por IA | 2026-08-03 | Nueve etapas con compuerta: intake, evidencia, diseño, implementación, verificación, staging, release, operación, incidente y aprendizaje |
| Versionado no-code | 2026-08-03 | Manifiesto mínimo de 11 campos y pipeline de 10 pasos para publicar un workflow. Ver [runbook](../06-runbooks/publicar-un-workflow-n8n.md) |
| ADR definitivo rev.2 | 2026-08-02/03 | Consolidación del ADR de finanzas |
| Post-mortem de drift | 2026-08-05 | Detección y remediación del atraso de producción. Ver [post-mortem](../06-runbooks/postmortem-drift-produccion.md) |

**Vocabulario de evidencia establecido:** `Verificado` · `Confirmado por el responsable` · `Inferido` · `Pendiente de verificar` · `Historia incompleta`.

**Regla raíz de publicación:** *"Los artefactos públicos deben enseñar un principio reutilizable sin exponer el sistema privado del que salió la lección."* Ver [ADR-009](../04-decisiones/adr-009-publicar-el-metodo-no-el-sistema.md).

---

## Contenido — AI-Command-Center y Arquitecto-IA-Redes

Se incluye por honestidad de inventario: es el componente que **no avanzó**, y su historia es tan informativa como la de los que sí.

| Fase | Fecha | Qué cambió |
|---|---|---|
| AI-Command-Center, Fase 0 | 2026-07-20 | Cinco ADRs. Stack elegido: n8n self-host + agente de código + vault, verificación con MCP de literatura científica, publicación vía herramienta de terceros, voz sintética, contenido sensible con modelo local. Pipeline por carpetas `00_ideas → 01_borradores → 02_en_revision → 03_aprobado → 04_publicado` |
| Arquitecto-IA-Redes | 2026-07-24 | Nace como mapa real de APIs de redes sociales para cuatro marcas |
| Mapa de APIs | 2026-07-24/29 | Hallazgo verificado: hay plataformas automatizables ya, una requiere revisión de app de semanas, otra publica sólo en modo privado sin auditoría, y la variante empresarial está bloqueada sin entidad legal |
| Estado al corte | 2026-08-05 | **Cero commits. Fase 0. USD 0. Nada instalado ni contratado.** Las cinco carpetas del pipeline están vacías |

**Deuda declarada:** AI-Command-Center y Arquitecto-IA-Redes resuelven el mismo problema con stacks distintos y el solapamiento **no está resuelto**. Plan de costos proyectado: Fase 0 en USD 0, Fase 1 alrededor de USD 27, Fase 2 entre USD 70 y 100 — son proyecciones, no gasto ejecutado.

La lección de este componente es la misma del IA_KNOWLEDGE_HUB: **el andamiaje se construyó antes que el material**. Cinco ADRs y un pipeline de cinco etapas para cero publicaciones.

---

## Qué muestra esta vista que la cronología no

Tres patrones sólo se ven cuando se separan los componentes:

1. **Los componentes que arrancaron con una restricción fuerte avanzaron más rápido.** Finanzas nació con "no es un sistema nuevo" y llegó a v4.8 en diez días. Contenido nació con un stack elegido y sigue en cero.
2. **Las correcciones se concentran.** El buscador Tavily recibió cuatro correcciones en 48 horas después de publicarse. Publicar temprano funciona si cada corrección viene con su lote de casos.
3. **La gobernanza llegó última y explica lo anterior.** La línea base es del 3 de agosto, es decir, veinte días después del primer workflow. Se documentó un sistema que ya existía, y por eso el AS-IS registra deudas en vez de negarlas.

> Última verificación: 2026-08-06
