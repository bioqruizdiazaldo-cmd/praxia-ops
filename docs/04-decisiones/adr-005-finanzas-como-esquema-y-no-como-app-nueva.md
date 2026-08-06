# ADR-005 — Finanzas como esquema, no como aplicación nueva

La pregunta no era si valía la pena construir un sistema financiero, sino si eso era un sistema nuevo o un esquema más dentro del que ya existía.

## Estado

Aceptada.

## Fecha

2026-07-26 — evaluación crítica y decisión fundacional de PraxIA Finanzas.

## Contexto

El 26 de julio el sistema ya tenía doce días de vida: orquestador, subagentes, memoria en PostgreSQL, avisador de errores, buscador web, backups y un VPS con Docker y Traefik andando. Apareció entonces una necesidad concreta y grande: registrar movimientos, saldos, deudas, comprobantes y obligaciones fiscales.

El reflejo natural frente a un dominio de ese tamaño es tratarlo como un producto aparte: repositorio nuevo, base nueva, framework, ORM, autenticación propia, panel propio. Es un dominio que lo justifica sin esfuerzo — al 5 de agosto tiene más de 35 tablas.

La evaluación fue en la dirección contraria y quedó escrita textualmente:

> *"Sí tiene sentido y sí vale la pena — pero NO como sistema nuevo. PraxIA Contable debe construirse como un esquema adicional (`praxia_finanzas`) dentro del PostgreSQL que ya corre en el VPS. Reutiliza ~80% de infraestructura existente. Construir una app aparte sería tirar a la basura el Memory Core."*

Vale la pena desarmar el argumento, porque no es una decisión de comodidad.

**Qué había ya construido y probado el 26 de julio:** PostgreSQL 16 en contenedor con puerto sólo en loopback; Docker Compose con Traefik y TLS; backups diarios con lock, manifiesto y script de chequeo; n8n con captura global de errores; Telegram como canal con filtro de remitente; un patrón de escritura con verificación posterior; y un método de trabajo con backup, hash y verificación antes de tocar producción.

**Qué habría que rehacer con una aplicación aparte:** todo eso.

Y un costo peor que rehacer: **dos fuentes de verdad**. Un sistema con memoria de decisiones por un lado y datos financieros por otro obliga a sincronizarlos, y esa sincronización es exactamente la clase de complejidad que después nadie sabe depurar. La frase "tirar a la basura el Memory Core" apunta a eso: no al código perdido, sino a la coherencia perdida.

## Decisión

**PraxIA Finanzas se construye como el esquema `praxia_finanzas` dentro de la misma instancia de PostgreSQL que aloja la memoria, reutilizando la infraestructura existente.**

Cuatro reglas derivadas, que se sostuvieron en las diez migraciones posteriores:

### 1. Una sola base, dos esquemas

Los esquemas `praxia` y `praxia_finanzas` conviven en la base `praxia_memory`. Mismo contenedor, mismos backups, mismo procedimiento de migración, misma superficie de red.

### 2. Un único camino de alta

> *"Toda entrada — Telegram, dashboard, PDF, CSV, email o un agente — produce el mismo contrato universal y termina en la misma base."*

En la práctica: `POST /api/ingesta` es el único camino de alta. Los adaptadores de PDF, CSV, Excel y correo no escriben en tablas: **normalizan hacia el contrato y lo entregan a la misma puerta**. Es el mismo principio del esquema único, aplicado a la entrada.

### 3. Rol separado, aislamiento dentro de la base

Que compartan instancia no significa que compartan permisos. El rol `praxia_finanzas_rw` es propio y no tiene permiso `DELETE`.

### 4. Stack mínimo, coherente con lo que ya había

| Capa | Elección | Por qué |
|---|---|---|
| Backend | Node.js ESM **sin framework**, `node:http` puro, router por regex | Una sola dependencia de runtime (`pg`). Menos superficie que mantener y actualizar |
| Frontend | HTML/JS vanilla en **un solo archivo** de 1.911 líneas | Sin build, sin cadena de herramientas, sin dependencias que caduquen |
| Tests | `node --test` + PGlite con el DDL real | El runner nativo, coherente con la API sin framework |
| Orquestación | n8n, 9 workflows | El motor que ya estaba |
| Despliegue | Docker Compose + Traefik, **sin puertos publicados al host** | La misma infraestructura del resto |

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Esquema adicional en la base existente** | ~80% de infraestructura reutilizada; una sola fuente de verdad; backups, TLS y migraciones ya resueltos; consultas entre dominios sin integración | Acoplamiento operativo: un problema de la base afecta a los dos dominios; el esquema crece dentro de una instancia compartida | **Elegida** |
| Aplicación nueva con base propia | Aislamiento total de fallas; libertad de stack; escalable por separado | Rehacer backups, TLS, despliegue, monitoreo y errores; **dos fuentes de verdad**; sincronización permanente | Rechazada |
| Servicio gestionado de contabilidad de terceros | Cero desarrollo; cumplimiento normativo resuelto | Datos financieros personales en un tercero; sin control del modelo de datos; sin integración con el agente; ver también [ADR-002](adr-002-postgres-propio-en-vez-de-supabase.md) | Rechazada |
| Planilla de cálculo con automatización | Rapidísimo de arrancar | Sin invariantes, sin auditoría, sin tipos, sin transacciones. No aguanta la regla de no borrar | Rechazada |
| Base nueva en la **misma** instancia | Algo de aislamiento lógico | Pierde las consultas entre dominios y gana poco: si la instancia cae, caen las dos igual | Rechazada |

## Consecuencias

### Positivas

- **De la decisión a v4.8 en diez días**, con núcleo fiscal, deudas, pagos, obligaciones recurrentes y propuestas. Esa velocidad es el 80% reutilizado hecho tiempo.
- **Una sola fuente de verdad.** La regla del contrato es explícita: *"PraxIA Finanzas es la única fuente de verdad financiera. No existen sistemas paralelos. La ausencia de datos no debe convertirse en un dato inventado."*
- **Los procedimientos se heredaron.** Backup verificado con SHA-256, migración transaccional, verificación de no-regresión: no hubo que inventarlos, ya se usaban.
- **Un dominio nuevo agregó una dependencia de runtime.** Una: `pg`.
- **La integración con el agente fue barata.** Conectar Oppenheimer a las finanzas el 2/8 fue un workflow de solo lectura, no un proyecto de integración.
- **Los tests pueden replicar producción** porque el esquema es propio y su DDL está versionado.

### Negativas

- **Acoplamiento operativo real.** Un incidente en la instancia de PostgreSQL afecta a memoria y finanzas a la vez. No hay aislamiento de fallas entre dominios.
- **El esquema creció más rápido que la disciplina de despliegue.** Diez migraciones en diez días es también lo que hizo posible el drift del 05/08: v4.4 en producción y v4.6 en el repositorio.
- **Sin framework significa escribir cosas a mano.** El router por regex en un archivo de unos 70 KB es mantenible hoy y es un punto de atención hacia adelante.
- **El frontend en un solo archivo tiene techo.** El prototipo Dashboard UI v3, con obligaciones recurrentes y 17 estados, está aprobado en diseño y **no migrado**; es una fase pendiente.

### Operativas

- Backups, migraciones y monitoreo son compartidos: mejora la economía y concentra el riesgo.
- Cualquier migración del esquema financiero debe seguir el [runbook de despliegue](../06-runbooks/despliegue-de-una-migracion.md), porque toca la misma base que la memoria.
- La verificación de no-regresión del 05/08 —25 → 35 tablas con valores idénticos— cuenta tablas de **ambos** esquemas. Es la contracara concreta de compartir instancia.
- Sin integración continua: los 606 tests se corren a mano antes de publicar.

### De seguridad

- **Rol propio sin `DELETE`.** Compartir instancia no significa compartir permisos.
- **Datos sensibles cifrados del lado del servidor**, con token de reemplazo del tipo `⟦S1⟧` sustituido **antes** de mandar nada al modelo. Esa es la diferencia práctica entre tener el esquema bajo control propio y no tenerlo.
- La clave de cifrado se movió fuera del volumen de datos en la migración v3.4.
- **Sin puertos publicados al host**; todo detrás de Traefik con TLS.
- El texto original de cada ingesta se guarda cifrado en `ingesta_raw`, con canal, actor y clave de idempotencia.
- Riesgo concentrado, dicho claro: **una escalada de privilegios dentro de la instancia alcanza los dos esquemas**. La separación por rol mitiga, no elimina. Es el precio explícito de esta decisión.

## Evidencia

| Afirmación | Estado |
|---|---|
| Cita textual de la evaluación crítica del 2026-07-26 | `Verificado` |
| Esquema `praxia_finanzas` dentro de la base `praxia_memory` | `Verificado` |
| Rol `praxia_finanzas_rw` sin permiso `DELETE` | `Verificado` |
| Backend Node.js ESM sin framework, `node:http`, router por regex, única dependencia `pg` | `Verificado` |
| Frontend vanilla en un archivo de 1.911 líneas, 7 secciones | `Verificado` |
| 606 casos de test en verde, 0 salteados, con `node --test` y PGlite sobre el esquema real | `Verificado` |
| Único camino de alta `POST /api/ingesta`; cita textual del contrato universal | `Verificado` |
| Esquema en v4.8 al 2026-08-05, diez días después de la decisión | `Verificado` |
| Datos sensibles cifrados con token de reemplazo antes del modelo | `Verificado` |
| Prototipo Dashboard UI v3 aprobado en diseño y no migrado | `Verificado` |
| **La cifra de ~80% de infraestructura reutilizada** | `Confirmado por el responsable` — es la estimación textual de la evaluación, no una medición |
| Comparación de esfuerzo contra la alternativa de aplicación nueva | `Pendiente de verificar` — no se midió |

## Disparador de revisión

Revisar cuando:

- **El acoplamiento operativo cueste caro de verdad**: si una migración de finanzas provoca una interrupción de la memoria, o al revés, corresponde separar instancias.
- **Aparezca un segundo usuario con datos financieros.** El esquema tiene perfiles, pero el aislamiento entre personas dentro de una misma instancia es un problema distinto al de separar dominios.
- **El volumen justifique dimensionar por separado.** Hoy no: es un sistema chico en datos y denso en reglas.
- **El router por regex empiece a fallar** por cantidad de rutas o por casos de borde. Sería el momento de evaluar un framework mínimo, no de rehacer el sistema.
- **Haya que migrar el dashboard a la UI v3.** Es la Fase 6 pendiente y toca el archivo único.

> Última verificación: 2026-08-05
