# Línea de tiempo

Reconstrucción día por día de la construcción de PraxIA Ops, del 10 de julio al 6 de agosto de 2026, agrupada por las cuatro etapas del proyecto.

Cada fila declara el estado de su evidencia. Ver [cómo leer las tablas](README.md#cómo-leer-las-tablas) si venís directo a este archivo.

> **In English** — A day-by-day reconstruction of how the system was built between 10 July and 6 August 2026,
> grouped into four stages, with an evidence status on every row. The orchestrator was created on 2026-07-14
> at 23:05; persistent PostgreSQL memory replaced Supabase in practice four days later; the global error
> workflow was linked on 2026-07-22. Three episodes that recur throughout the repository all appear here: a
> 21.9 MB PDF broke execution 1292 on 2026-07-25 and exposed a pipeline that modelled only success; the
> general search agent scored 2 of 7 against a declared 7/7 threshold on 2026-07-27 and was not published; and
> on 2026-07-28 a checkpoint found 3275 lines of JavaScript and 33 SQL migrations running in production with
> no version control at all. The final stage covers five days of silent drift between repository and server,
> found on 2026-08-05. Nothing across these 28 days happened outside production.

<!-- fin del resumen en inglés -->

---

## Etapa 1 — Laboratorio (10 al 14 de julio)

Cuatro días sin construir nada productivo. Suena a pérdida de tiempo y es exactamente lo contrario: es la etapa que evitó que el proyecto terminara siendo una carpeta de experimentos sueltos. Lo que se resolvió acá fue el método — dónde vive el conocimiento, cómo se nombra, qué se decide antes de empezar — y las ocho decisiones fundacionales que después no hubo que rediscutir.

El hallazgo más útil de la etapa fue un problema circular: la regla que decía dónde guardar las cosas vivía dentro del vault que todavía no estaba montado. Es el tipo de bug de método que después se repite a escala en cualquier sistema de documentación.

| Fecha | Hito | Qué se aprendió | Estado de evidencia |
|---|---|---|---|
| 2026-07-10 | Guía para replicar la memoria Obsidian↔Cowork. Se resuelve el problema huevo-gallina: la regla de guardado vivía dentro del vault que no estaba montado | Las reglas de operación no pueden vivir sólo adentro del sistema que gobiernan. Hace falta un punto de entrada externo | `Verificado` |
| 2026-07-13 | Se crea el IA_KNOWLEDGE_HUB: PKM de IA con modelo de 5 niveles, 12 reglas anti-caos, taxonomía y ADR liviano | Un andamiaje bueno no genera contenido por sí solo. Este hub quedó congelado cuatro días después con 57 carpetas vacías — la lección está documentada como tal | `Verificado` |
| 2026-07-14 | **Planificación maestra PraxIA Ops**: arquitectura en 7 capas y decisiones **D-1 a D-8** cerradas | Cerrar ocho decisiones antes de escribir el primer workflow eliminó semanas de rediscusión. Una de ellas (D-2, Supabase) se revirtió a los cuatro días, y aun así el ejercicio valió | `Verificado` |

**Cierre de la etapa.** Queda escrita la regla que ordena todo el proyecto: *"Sin orden no hay sistema, solo experimentos. El error a evitar no es técnico, es de secuencia. Hay que construir un agente excelente (Oppenheimer) sobre una arquitectura de datos que ya contemple multiusuario."* Y el orden de construcción: Oppenheimer → PraxIA Ops → Ciencia Aplicada → agente familiar → marca outdoor → clientes.

---

## Etapa 2 — Núcleo (14 al 20 de julio)

Seis días de construcción densa. El 14 a las 23:05 nace el orquestador y, con él, el sistema. En una semana pasa de no existir a tener canal Telegram, seis subagentes, voz, análisis de imágenes, briefings automáticos y memoria persistente en PostgreSQL con espejo en Markdown.

El punto de inflexión de la etapa es el 18 de julio: la memoria deja de ser un buffer de conversación y pasa a ser una base de datos con esquema, categorías y verificación posterior a la escritura. Ese día también se abandona en la práctica la decisión D-2 (Supabase) y se va directo a PostgreSQL propio.

| Fecha | Hito | Qué se aprendió | Estado de evidencia |
|---|---|---|---|
| 2026-07-14 23:05 | **Nace el orquestador Oppenheimer** con los subagentes base: Email, Calendario, Planillas, Recordatorios, Enviar Gmail, Briefing Diario | Arrancar con un orquestador y subagentes desde el día uno, en vez de un workflow monolítico, evitó la reescritura que llega cuando el prompt central se vuelve inmanejable | `Verificado` |
| 2026-07-15 | Briefing de Noticias, Alertas TradingView y primera versión del Agente de Papers. Sistema de backup de n8n/SQLite + `RECOVERY.md` | El backup se armó el segundo día de vida del sistema, no después del primer susto. Es la decisión de infraestructura más barata y la que más se posterga | `Verificado` |
| 2026-07-16 | Esquema de datos y memoria v1. Backup del orquestador rotulado "antes de Agente Papers" | Un backup nombrado por el cambio que va a venir, y no por la fecha, es un artefacto de rollback usable | `Verificado` |
| 2026-07-16/17 | **Agente Papers Científicos v2.1** documentado y validado. Resumen técnico de Oppenheimer v2.1 | Un subagente con pipeline explícito (query-builder → fuentes → ranker → writer → planilla) es testeable por etapas; un prompt largo que "busca papers" no lo es | `Verificado` |
| 2026-07-17 | Índice maestro del vault. Visión de ecosistema integrado: dos memorias con roles diferenciados y un puente entre ellas. Voz "Jarvis" y arquitectura de subagentes | Definir *roles* de memoria (viva vs. espejo humano) antes de implementarlas evitó tener dos fuentes de verdad compitiendo | `Verificado` |
| 2026-07-18 | **Nace PraxIA Memory Core**: Guardar, Consultar, Router, Tareas y Proyectos sobre PostgreSQL propio. Memory Hub y captura universal | Se abandona Supabase en la práctica sin declararlo formalmente. La decisión maestra queda grabada como hecho #1: *"La memoria viva vive en PostgreSQL (esquema praxia) en el VPS; MiBoveda es el espejo humano editable"* | `Verificado` |
| 2026-07-19 | **Primer export de memoria a Markdown**: 7 hechos, 1 proyecto, 1 tarea | Un export chico y verificable el primer día vale más que un export completo sin verificar. Los números del export son la prueba de que el pipeline corrió entero | `Verificado` |
| 2026-07-19/20 | **PraxIA Sync operativo**: n8n exporta 23:30 ART, cron + rclone empuja a la nube 23:35 | Separar el export (n8n) de la sincronización (cron + rclone) permite que falle uno sin arrastrar al otro | `Verificado` |

**Cierre de la etapa.** Al 20 de julio hay un agente que responde por Telegram con texto, voz e imagen, ejecuta acciones en Gmail, Calendar, Sheets y Drive, y recuerda entre conversaciones. Lo que todavía no hay es ninguna garantía de que siga funcionando mañana.

---

## Etapa 3 — Endurecimiento (20 al 28 de julio)

La etapa más larga y la que más define el carácter del proyecto. Acá el trabajo deja de ser "hacer que funcione" y pasa a ser "hacer que no se rompa en silencio": captura centralizada de errores, aprobación humana verificada, contratos de salida con estados tipados, inventario antes de borrar, y pruebas con umbral declarado de antemano.

Es también la etapa con los dos episodios más citados del repositorio. El 25 de julio un PDF de 21,9 MB rompe el pipeline de Telegram y expone un problema estructural mayor que el bug: no existía un camino de archivado desde una descarga fallida. El 27 de julio el Buscador General pasa 2 de 7 pruebas reales contra una exigencia de 7/7 y **no se publica**.

| Fecha | Hito | Qué se aprendió | Estado de evidencia |
|---|---|---|---|
| 2026-07-20 | **Memory Gate** en el orquestador, con rollback previo guardado. Nace AI-Command-Center (ADR-001 a 005, Fase 0, USD 0) | La decisión de consultar memoria se sacó del modelo y se puso en código determinístico. Una regla que sale del prompt pasa de "hay que evaluarla" a "hay que testearla" | `Verificado` |
| 2026-07-22 | **Avisador de Errores v1** creado y enlazado como `errorWorkflow` global | Un punto único de captura de errores vale más que manejo de errores repartido en 200 workflows. El nombre de ese workflow todavía dice `[TEST]` — deuda técnica conocida y publicada | `Verificado` |
| 2026-07-23 | Avisador de Errores: **integración productiva aprobada**. 44 workflows, orquestador con 37 nodos, `praxia.agent_errors` en 0 filas, Traefik OK, SSH cerrado tras el despliegue | Aprobar una integración con la tabla de errores en cero filas es un criterio de aceptación honesto: se verifica que el camino feliz no genere ruido antes de confiar en las alertas | `Verificado` |
| 2026-07-23/24 | Ola de harnesses y candidatos de Email V3 y de memoria: gates, preflight router, single-path, canarios, fases 3d–3h | Construir el harness antes que el candidato. La cantidad de fases intermedias muestra que el camino real no fue lineal | `Verificado` |
| 2026-07-24 | **Email V3 publicado y validado** con 5 pruebas aisladas OK. Cierre declarado como provisional: faltaba reinicio controlado y validación desde Telegram. Auditoría de memoria con export de 44 workflows. Nace Arquitecto-IA-Redes | Declarar un cierre como provisional y listar lo que falta es más útil que declararlo completo. El solapamiento entre Arquitecto-IA-Redes y AI-Command-Center nunca se resolvió y está publicado como deuda | `Verificado` |
| 2026-07-25 18:25 ART | **Incidente**: la ejecución 1292 falla en el nodo de descarga de documentos de Telegram con `Bad Request: file is too big` ante un PDF de 21,9 MB | El bug era el límite de la API. El hallazgo real fue estructural: no existía camino de archivado desde una descarga, extracción o revisión fallida — el pipeline sólo modelaba el éxito | `Verificado` |
| 2026-07-25 | **Reparación de PDF publicada**: validación previa, límite de 20 MiB, verificación de firma `%PDF-`, extracción real y máquina de estados `received → validated → text_extracted → reviewed → archived \| failed`. 6/6 pruebas PASS | `failed` como estado terminal legítimo, y no como ausencia de estado, es la diferencia entre un pipeline que se cuelga y uno que cierra el caso. Detalle completo en el [runbook](../06-runbooks/incidente-pdf-telegram.md) | `Verificado` |
| 2026-07-25 | Limpieza de runtime: inventario de 79 workflows de laboratorio — **clase A = 73** (borrables), clase B = 4, clase C = 2 activos con tráfico | No se borró nada sin inventario previo. Dos de los 79 estaban activos y recibiendo tráfico: un borrado "obvio" habría cortado producción. Ver [runbook](../06-runbooks/limpieza-de-runtime.md) | `Verificado` |
| 2026-07-25 23:18 | **Nace el Buscador Web Tavily V1**, publicado y verificado. Nueve nodos con contrato de evidencia y siete estados de salida tipados | Un buscador que puede responder `no_reliable_source` o `insufficient_evidence` es más útil que uno que siempre contesta algo | `Verificado` |
| 2026-07-26 | Auditoría correctiva de fechas del buscador (hoy/ayer/temporada, `target_date`, `date_scope`): 8/8. Corrección estructural del contexto (`tavily_response`): 8/8 | Dos correcciones en un día sobre un workflow publicado el día anterior. Publicar temprano y corregir con pruebas es viable si cada corrección tiene su lote de casos | `Verificado` |
| 2026-07-26 | **Nace PraxIA Contable** con la evaluación crítica: *"Sí tiene sentido y sí vale la pena — pero NO como sistema nuevo"*. Se decide construirlo como esquema `praxia_finanzas` dentro del PostgreSQL existente, reutilizando ~80% de la infraestructura | La pregunta correcta no era "¿hago finanzas?" sino "¿esto es un sistema nuevo o un esquema más?". Ver [ADR-005](../04-decisiones/adr-005-finanzas-como-esquema-y-no-como-app-nueva.md) | `Verificado` |
| 2026-07-26/27 | Corrección de cobertura temática del buscador: etiquetas por resultado y fallback de 72 horas | Tercera y cuarta corrección del mismo componente en dos días. La señal de que algo no cierra ya estaba disponible antes de la revalidación | `Inferido` |
| 2026-07-27 | Fases 3B→3E1 del "Buscador General": relevancia, validador consolidado, métrica de alcance, fallback. Auditoría de ejecuciones y matriz fija de casos | Fijar la matriz de casos *antes* de la revalidación es lo que hizo posible el resultado del renglón siguiente. Si el umbral se define después de ver los resultados, siempre se cumple | `Verificado` |
| 2026-07-27 | **Revalidación real acotada del Buscador General: 2/7 PASS con exigencia de 7/7 → NO PUBLICADO** | El resultado se aceptó sin ajustar los fixtures: *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded"*. Ver [ADR-006](../04-decisiones/adr-006-buscador-general-no-publicado.md) | `Verificado` |
| 2026-07-27 | PraxIA Finanzas: DDL v3.1 aplicado al VPS con backups y SHA-256 verificados. Fases 1A–1E. Migraciones v3.2 a v3.6: cifrado server-side, contrato universal, clave fuera del volumen, cierre de seguridad, documentos y dedup. **Canary Telegram aprobado, Fase 2 completada** | Cinco migraciones en un día sobre una base que ya tenía datos, con backup y hash verificados en cada paso. El canary con tráfico real acotado cerró la fase, no los tests | `Verificado` |

**Cierre de la etapa.** El sistema ya se recupera de sus propios errores, avisa cuando falla y tiene decisiones documentadas sobre lo que no se publica. Lo que todavía no tiene es control de versiones.

---

## Etapa 4 — Producto (28 de julio al 6 de agosto)

Diez días de consolidación. La etapa arranca con un checkpoint incómodo: había 3275 líneas de JavaScript y 33 migraciones SQL en producción **sin ningún control de versiones**. El commit inicial de PraxIA Finanzas es del 28 de julio, once días después de que empezara a existir código.

A partir de ahí el trabajo cambia de naturaleza: migraciones numeradas y probadas, servidor MCP recuperado y versionado, contrato formal entre módulos, línea base de gobernanza en 18 documentos, y un post-mortem por drift entre repositorio y servidor. La etapa cierra con un agente que propone clasificaciones fiscales aprendiendo exclusivamente de las decisiones previas de su dueño.

| Fecha | Hito | Qué se aprendió | Estado de evidencia |
|---|---|---|---|
| 2026-07-28 | **Fase 3 completada**: adaptadores PDF/CSV/Excel/email y conexión a clientes LLM externos, 141/141 tests. Migración v4.0 del núcleo fiscal escrita y puesta en pausa | Escribir una migración y pausarla antes de aplicarla es una decisión válida. El código existe, el riesgo no se toma todavía | `Verificado` |
| 2026-07-28 | **Checkpoint crítico**: *"No hay repo git. 3275 líneas de JS + 33 migraciones SQL, sin control de versiones"*. Se hace el **commit inicial** | Once días de código en producción sin git. El checkpoint que lo detectó fue una revisión deliberada, no un accidente — pero la deuda existió y se publica tal cual. Motiva el [ADR-008](../04-decisiones/adr-008-el-repositorio-como-fuente-de-verdad.md) | `Verificado` |
| 2026-07-29/30 | Migración v4.2: exportaciones fiscales. Migración v4.3: `deudas_pendientes` | Con git, las migraciones pasan a ser incrementos numerados y revisables en vez de scripts sueltos | `Verificado` |
| 2026-07-31 | Migración v4.4: deudas administrables. Tag `v4.3-pre-fase2`. Fix de tickets de Telegram hacia ingesta. Auditoría de webhooks de n8n | Un tag `pre-fase` antes de un cambio grande es el rollback más barato que existe. **Ésta es la última migración que llegó a producción antes del drift de cinco días** | `Verificado` |
| 2026-08-01 | Migración v4.5: `deuda_pagos` — pagos totales y parciales sin duplicar movimientos, con guards de moneda y recálculo de saldo | *"Registrar una deuda, una cuota, un vencimiento o un gasto esperado no modifica saldos. El impacto financiero ocurre únicamente al registrar o vincular un pago real, y un pago se contabiliza exactamente una vez"* | `Verificado` |
| 2026-08-02/03 | Enrutamiento de las consultas financieras de Oppenheimer hacia PraxIA mediante un workflow de **solo lectura**. **Servidor MCP remoto recuperado y versionado**. **ADR definitivo rev.2**. Dashboard UI v3 revisado | Conectar el agente conversacional a las finanzas por un camino de solo lectura es la forma barata de integrar dos sistemas sin heredar el riesgo de escritura de uno en el otro | `Verificado` |
| 2026-08-03 | **Inspección global de solo lectura** y línea base de gobernanza de Oppenheimer: 18 documentos con AS-IS, TO-BE, inventarios, riesgos, estándares y política de saneamiento. Se inicia el repo de gobernanza asistida por IA | *"Inspección no equivale a autorización de cambio."* Se miró todo el runtime y no se tocó nada. El AS-IS registró que producción también se usó como laboratorio y archivo histórico | `Verificado` |
| 2026-08-03 | Corte de runtime: 217 workflows registrados, 25 activos, 25 archivados, 125 con nomenclatura de laboratorio. Orquestador en 51 nodos. 377 ejecuciones conservadas, 343 exitosas y 19 fallidas en 7 días | Los números del corte son el argumento del TO-BE: un runtime donde el 58% de los workflows son de laboratorio no puede ser la fuente de verdad | `Verificado` |
| 2026-08-04 | **Contrato Finanzas↔Fiscal v1.0 aprobado**. Capa de lectura fiscal con 9 operaciones. Adenda del ADR que resuelve el tratamiento USD/ARS | Formalizar el contrato entre dos módulos del mismo sistema, con versión propia, permite cambiar un lado sin adivinar qué rompe del otro | `Verificado` |
| 2026-08-05 | **Puesta al día de producción v4.4 → v4.6**. Se descubre que producción estaba **tres migraciones atrás desde el 31/07** porque *"nadie había mirado el servidor, solo el repositorio"*. Backup verificado, migraciones con `ON_ERROR_STOP=1` en transacción, verificación de no-regresión 25 → 35 tablas | Cinco días de drift silencioso. El repositorio estaba impecable y producción atrasada: la disciplina de versionado no reemplaza la verificación del estado desplegado. Ver [post-mortem](../06-runbooks/postmortem-drift-produccion.md) | `Verificado` |
| 2026-08-05 | **Incidente `estado_fiscal` divergente**: 22 movimientos quedan con `ambito` y `deducible` correctos y `estado_fiscal='sin_clasificar'`. El agente los ve clasificados y el cierre los sigue marcando como bloqueantes. El mismo día se verifica que una ruta HTTP aceptaba marcar como `presentado` un período recién abierto | *"Dos partes del sistema, dos respuestas distintas a la misma pregunta, sin que nada avisara de la contradicción."* Ver [post-mortem](../06-runbooks/postmortem-estado-fiscal-divergente.md) | `Verificado` |
| 2026-08-05 | Migración v4.7: `estado_fiscal` derivado — `movimiento_estado_fiscal_derivado` y `cierre_transicion_valida` impiden que el estado fiscal diverja de `ambito` + `deducible`. **492 tests** | Un campo que puede divergir de los campos que lo determinan es un bug esperando fecha. La solución fue derivarlo en la base, no recordarlo en la aplicación | `Verificado` |
| 2026-08-05 | **Migración v4.8: propuestas fiscales**. Tabla `fiscal_propuestas` con triggers `propuesta_nace_pendiente`, `propuesta_contenido_inmutable` y `propuesta_transicion_valida`. Campos `huella` y `huella_evidencia`. Dos detectores nuevos (11 → 13). **606 tests verdes, 0 salteados** | *"Un agente que puede repreguntar sin límite termina consiguiendo el 'sí' por cansancio."* La huella impide insistir con lo mismo; la huella de evidencia impide aprobar algo caducado | `Verificado` |
| 2026-08-05 | `fiscal_motor.mjs`: el agente propone clasificaciones a partir de precedentes del propio dueño — *"de las decisiones anteriores de Aldo. De ningún otro lado. El agente mejora a medida que Aldo decide, sin que nadie lo reentrene. Y el primer mes propone poco, que es lo correcto — todavía no sabe nada"* | Aprendizaje por precedente explícito y auditable, sin reentrenamiento y sin embeddings. Que el sistema proponga poco al principio es la conducta correcta, no una limitación | `Verificado` |
| 2026-08-05 | Último export de memoria verificado (02:30 UTC): 2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, 0 secretos omitidos | El contador de secretos omitidos en el export es una métrica de seguridad, no de volumen: cero significa que el gate no tuvo que actuar, no que no exista | `Verificado` |
| 2026-08-05/06 | **Serie v4.9 → v4.13 aplicada y desplegada**: contribuyentes con FK real y aislamiento entre ellos (v4.9), plantillas recurrentes completas (v4.10), catálogo de obligaciones con días no hábiles y vencimiento por terminación de CUIT (v4.11), feriados 2026 (v4.12) y un régimen `historico` que sigue siendo válido (v4.13). Producción queda en **v4.13**, **39 tablas**. Incidente de despliegue por un Dockerfile con la lista de archivos escrita a mano, y rollback | La v4.13 corrige un filtro que descartaba regímenes históricos: el sistema respondía *"no hay condición fiscal vigente"* para un período en el que sí la había. Es el patrón de la falla silenciosa — una respuesta plausible y equivocada. Ver [límites y deudas](../../systems/praxia-agente-fiscal/limites-y-deudas.md) | `Verificado` |
| 2026-08-06 | Publicación del subsistema [Agente Fiscal](../../systems/praxia-agente-fiscal/): contrato de solo lectura, motor de precedentes, propuestas con doble huella y separación de credenciales | *"La separación no descansa en que el agente se porte bien, descansa en que no tenga la credencial."* El disparo mensual automático en n8n sigue pendiente: el workflow es un stub con trigger manual | `Verificado` |

---

## Lo que la línea de tiempo no muestra

Tres cosas que conviene decir explícitamente:

- **No hay separación de ambientes en ningún punto de estos 28 días.** Todo pasó en producción. Los inventarios, canaries y backups fueron la mitigación; no son un reemplazo.
- **Las horas exactas sólo están donde quedaron registradas** (14/07 23:05, 25/07 18:25 ART, 25/07 23:18, 05/08 02:30 UTC). Para el resto la granularidad es el día, y no se inventaron horarios.
- **Los proyectos paralelos avanzaron poco y se declara así.** AI-Command-Center sigue en Fase 0 con cero commits; Arquitecto-IA-Redes son notas; IA_KNOWLEDGE_HUB está congelado desde el 17/07.

> Última verificación: 2026-08-06
