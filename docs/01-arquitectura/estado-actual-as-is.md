# Estado actual (AS-IS)

Lo que hay hoy, medido y sin maquillar: un sistema en producción que funciona todos los días y que arrastra las marcas de haberse construido rápido.

Este documento existe porque la alternativa —describir el sistema como uno querría que fuera— es la forma más eficiente de no arreglarlo nunca. La regla de la línea base de gobernanza del 2026-08-03 fue explícita:

> *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

---

## Resumen ejecutivo

| Dimensión | Estado |
|---|---|
| **Funcionalidad** | Alta. Agente multimodal 24/7, memoria persistente, finanzas con núcleo fiscal, agente fiscal de solo lectura, 606 tests |
| **Fiabilidad operativa** | Buena. 343/362 ejecuciones exitosas en la ventana de 7 días; errores capturados y notificados |
| **Disciplina de ingeniería** | Buena en lo nuevo, débil en lo heredado. Migraciones versionadas y testeadas; workflows sin ambientes ni releases trazables |
| **Higiene del runtime** | **Mala.** Producción se usó como laboratorio y archivo histórico |
| **Continuidad ante desastre** | **No demostrada.** Hay backups; no hay off-site ni ensayo de restauración |

---

## Lo que hay, en números (corte 2026-08-03 / 2026-08-05)

| Métrica | Valor | Fuente |
|---|---|---|
| Workflows n8n registrados | 217 | Inventario de runtime 2026-08-03 |
| Workflows activos | 25 | Inventario de runtime 2026-08-03 |
| Workflows archivados | 25 | Inventario de runtime 2026-08-03 |
| **Workflows con nomenclatura de laboratorio** | **125** | Inventario de runtime 2026-08-03 |
| Nodos del orquestador | 51 (eran 47 el 2026-07-27, 37 el 2026-07-23) | Corte 2026-08-03 |
| Ejecuciones conservadas | 377 | Corte 2026-08-03 |
| Ejecuciones últimos 7 días | 343 exitosas / 19 fallidas | Corte 2026-08-03 |
| Tablas en producción | 39 (eran 25 antes de la puesta al día del 05/08, y 35 tras ella) | Serie v4.9 → v4.13, 2026-08-06 |
| Casos de test automatizados | 606 en verde, 0 salteados | `node --test` + PGlite |
| Último export de memoria verificado | 2026-08-05 02:30 UTC — 2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, **0 secretos omitidos** | PraxIA Sync |

---

## Qué funciona

Esto no es aspiracional: corre y hay evidencia.

### Oppenheimer

- Canal Telegram único con filtro de dueño en el primer nodo.
- Multimodal real: texto, voz de entrada (Whisper), voz de salida (TTS "Jarvis"), imagen (`Analyze Image`) y PDF con máquina de estados.
- Orquestador activo desde el **2026-07-14 23:05**.
- Quince subagentes y workflows especializados invocados por contrato.
- `Memory Intent Gate` determinístico previo al modelo.
- Rutinas programadas estables: briefing de noticias 06:30, briefing diario 07:00, export de memoria 23:30 ART.

### Memoria

- PostgreSQL 16 en contenedor propio, expuesto **sólo a loopback**.
- Consulta de memoria en transacción `BEGIN TRANSACTION READ ONLY`, con normalización de acentos, stop-words en español, `to_tsvector('spanish')` y dos niveles de match.
- Guardado con deduplicación por normalización y auto-clasificación de reglas de seguridad.
- Gate de secretos en el router: *"¿Tiene secreto?"* → `Rechazo Secreto`. Verificado: 0 secretos omitidos en el último export porque no llegó ninguno a intentar entrar.
- Espejo Markdown con export nocturno + rclone a la nube.

### Finanzas

- Un solo camino de alta (`POST /api/ingesta`) para seis orígenes distintos.
- Invariantes en la base, no en el prompt: `prohibir_delete_fisico`, `deuda_pago_validar`, `movimiento_respaldo_deuda_guard`, `propuesta_contenido_inmutable`, `propuesta_transicion_valida`.
- Rol de base `praxia_finanzas_rw` **sin permiso DELETE**. Ningún endpoint `DELETE` en toda la API.
- Esquema en v4.13, con `schema_migrations` y despliegue en transacción con `ON_ERROR_STOP=1`.
- 606 casos de test contra el esquema real vía PGlite.
- Servidor MCP con OAuth/JWT/PKCE y cuatro scopes separados.

### Errores

- `errorWorkflow` global enlazado desde el 2026-07-22, con integración productiva aprobada el 2026-07-23.
- Deduplicación y anti-spam validados.
- Registro en `praxia.agent_errors` y alerta por Telegram.

---

## Qué está mezclado

Acá empieza la parte incómoda. La cita textual de la línea base de gobernanza del 2026-08-03:

> *"El entorno de producción también ha sido utilizado como laboratorio y archivo histórico, porque conserva numerosos workflows de prueba, candidatos y respaldos."*

### 1. Producción como laboratorio — 125 workflows

De 217 workflows registrados, **125 tienen nomenclatura de laboratorio**: pruebas, candidatos, harnesses, respaldos "antes de X", fases numeradas. Conviven en el mismo runtime que los 25 activos.

El inventario del 2026-07-25 clasificó 79 de ellos en tres clases: **clase A = 73** (borrables sin consecuencia), **clase B = 4** (dudosos), **clase C = 2** (activos con tráfico real, pese al nombre de prueba). Esa clasificación es la razón por la que no se borró por patrón de nombre: dos workflows que parecían basura estaban sirviendo tráfico.

**Consecuencia real:** no se puede responder "¿qué está corriendo?" leyendo la lista. Hay que auditarla.

Ver el procedimiento que salió de esto: [limpieza de runtime](../06-runbooks/limpieza-de-runtime.md).

### 2. Sin separación de ambientes

No hay dev, no hay staging, no hay prod. Hay **un** runtime. Un workflow nuevo se prueba en el mismo lugar donde corren los que funcionan, y la única separación es el estado activo/inactivo y la disciplina de quien lo edita.

**Consecuencia real:** un error de configuración durante una prueba puede afectar a un flujo productivo. No pasó todavía; la ausencia de incidente no es un control.

### 3. Drift entre repositorio y servidor

El **2026-08-05** se descubrió que producción estaba **tres migraciones atrás desde el 31/07**. Cinco días. La causa, textual:

> *"nadie había mirado el servidor, solo el repositorio"*

Se corrigió con backup verificado, migraciones en transacción con `ON_ERROR_STOP=1` y verificación de no-regresión (25 → 35 tablas). Pero el mecanismo que permitió el drift sigue existiendo: **desplegar es un acto manual que alguien tiene que acordarse de hacer.**

Ver [post-mortem del drift](../06-runbooks/postmortem-drift-produccion.md).

### 4. Backups sin off-site ni restore drill

Hay backups diarios, semanales y mensuales en `<ruta-de-despliegue>/backups/`, con lock para evitar solapamiento, `manifest.json` y un `restore_check.sh`.

Lo que **no** hay: copia fuera del mismo servidor, y un ensayo de restauración completo ejecutado y documentado.

**Consecuencia real:** hoy el sistema está protegido contra el error humano y la corrupción de datos, pero **no está protegido contra la pérdida del VPS**. Un backup que nunca se restauró es una hipótesis, no un respaldo. Está anotado como riesgo abierto y no se disimula.

### 5. Deudas menores pero reales

| Deuda | Detalle |
|---|---|
| `errorWorkflow` llamado `[TEST]` | `PraxIA — Avisador de Errores v1` está activo y en producción desde el 2026-07-23, y su nombre todavía dice `[TEST]`. Es cosmético hasta que alguien lo borre por parecer una prueba |
| Solapamiento de proyectos | AI-Command-Center y Arquitecto-IA-Redes resuelven el mismo problema con stacks distintos. El solapamiento no está resuelto |
| `.env` con token real en carpeta sincronizada a la nube | Hallazgo de la auditoría del 2026-08-05. **Requiere rotación** |
| Defaults inseguros en el servidor MCP | `JWT_SECRET` y password de owner hardcodeados como fallback. Sólo aplican si faltan las variables de entorno, lo cual es exactamente el escenario de un despliegue apurado |
| Repositorio de gobernanza con cero commits | Tenía archivos en stage y ningún commit. Mismo patrón que el checkpoint del 2026-07-28 en finanzas: *"No hay repo git. 3275 líneas de JS + 33 migraciones SQL, sin control de versiones"* |

La lista completa y priorizada está en [estado objetivo (TO-BE)](estado-objetivo-to-be.md).

---

## El patrón detrás de todos estos problemas

No son cinco problemas distintos. Son **uno solo, en cinco lugares**: durante veintidós días el criterio fue *"que funcione hoy"*, y eso produjo un sistema que funciona hoy y una historia que no se puede reconstruir sin auditar el runtime.

Los tres síntomas del mismo patrón:

- El artefacto real vive en el servidor, no en el repositorio.
- El estado se conoce inspeccionando, no leyendo.
- La prueba y la producción comparten el mismo espacio.

Esto no es un accidente ni un descuido: es la consecuencia previsible de construir rápido, y por eso el diagnóstico está escrito antes que la lista de mejoras.

---

## El TO-BE, en las palabras de la fuente

La línea base de gobernanza del 2026-08-03 no propuso funcionalidades nuevas. Propuso exactamente lo contrario:

> *"La próxima mejora de mayor valor es convertir evidencia dispersa en fuentes de verdad, ambientes separados y releases trazables antes de expandir funcionalidades."*

Y la regla que lo resume:

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Hoy es al revés: el runtime **es** la fuente de verdad, y el repositorio es un reflejo parcial y atrasado de lo que hay en él. Esa inversión es el problema arquitectónico central del sistema, y el resto de las deudas son consecuencias suyas.

Ver [estado objetivo (TO-BE)](estado-objetivo-to-be.md) y [ADR-008](../04-decisiones/adr-008-el-repositorio-como-fuente-de-verdad.md).

---

## Nivel de evidencia de este documento

| Afirmación | Nivel |
|---|---|
| Métricas de runtime, tablas, tests, ejecuciones | Verificado (inspección de solo lectura, 2026-08-03 / 2026-08-05) |
| Deudas técnicas 1 a 10 | Verificado |
| "No pasó todavía" sobre el riesgo de ambientes | Confirmado por el responsable |
| Consecuencia proyectada de la pérdida del VPS | Inferido |
| Estado exacto de los 46 workflows de laboratorio no clasificados en el inventario del 2026-07-25 | Pendiente de verificar |

> Última verificación: 2026-08-05
