# Desplegar una migración

Procedimiento paso a paso para aplicar un cambio de esquema a producción sin romper nada y con forma de volver atrás.

Salió del [post-mortem del drift del 5 de agosto](postmortem-drift-produccion.md). Antes de eso era un conjunto de cuidados personales; ahora es un procedimiento con casillas.

## Cuándo usarlo

Siempre que se aplique SQL que modifique el esquema de producción: tablas, columnas, índices, vistas, funciones, triggers o constraints.

También aplica a migraciones que sólo agregan cosas. Una migración "que sólo agrega una tabla" puede fallar por un nombre repetido, por permisos del rol, o por un `DEFAULT` que dispara una reescritura completa de la tabla.

**No aplica** a consultas de solo lectura ni a inserciones de datos por los caminos normales de la aplicación.

## Antes de empezar

Tres cosas tienen que ser ciertas. Si alguna no lo es, no se avanza.

- [ ] La migración está **versionada** en el repositorio, con número de versión y nombre descriptivo.
- [ ] La migración **pasó los tests** contra una base con el DDL real (acá: `node --test` con PGlite).
- [ ] Existe una **ventana** donde una interrupción breve no molesta a nadie.

## Paso 0 — Verificar el estado real del servidor

**Es el paso que faltaba el 5 de agosto y por eso hubo cinco días de drift.** No se salta nunca.

- [ ] Consultar `schema_migrations` **en el servidor**, no en el repositorio.
- [ ] Comparar contra las migraciones versionadas.
- [ ] Confirmar que la brecha es la esperada.

```bash
# Ejemplo sintético y genérico.
psql "postgresql://usuario_ejemplo@localhost:5432/base_ejemplo" \
  -c "SELECT version, applied_at FROM esquema_ejemplo.schema_migrations ORDER BY applied_at DESC LIMIT 5;"
```

**Criterio de parada:** si el servidor está más de una migración atrás de lo esperado, **no sigas con el plan original**. Estás frente a un drift. Aplicá las pendientes de a una, en orden, cada una con su ciclo completo de este runbook.

## Paso 1 — Precondiciones

- [ ] Leer la migración completa. Entera, no en diagonal.
- [ ] Identificar qué **destruye o transforma** datos existentes: `ALTER ... TYPE`, `DROP COLUMN`, constraints nuevas sobre tablas con filas, `NOT NULL` sin `DEFAULT`.
- [ ] Verificar que el **rol** con el que se va a aplicar tenga los permisos necesarios.
- [ ] Estimar cuánto tarda. Un índice sobre una tabla grande bloquea.
- [ ] Confirmar que la migración es **idempotente o está protegida**: `IF NOT EXISTS` donde corresponda, o certeza de que no se aplicó antes.
- [ ] Anotar el **estado esperado después**: cuántas tablas, cuáles nuevas, qué cambia.

**Criterio de parada:** si no podés describir en una frase qué hace la migración y qué toca, no la apliques todavía.

## Paso 2 — Backup y verificación del backup

Un backup no verificado es una hipótesis, no un respaldo.

- [ ] Tomar un backup completo de la base.
- [ ] **Verificar la integridad** del archivo, no sólo que exista.
- [ ] Registrar hash y tamaño.
- [ ] Anotar dónde quedó y cómo se restauraría.

```bash
# Ejemplo sintético y genérico.
FECHA=$(date +%Y%m%d-%H%M%S)
ARCHIVO="/ruta/ejemplo/backups/pre-migracion-${FECHA}.dump"

pg_dump --format=custom --file="${ARCHIVO}" \
  "postgresql://usuario_ejemplo@localhost:5432/base_ejemplo"

# Verificación: si el volcado está corrupto, esto falla.
pg_restore --list "${ARCHIVO}" > /dev/null && echo "backup legible"

sha256sum "${ARCHIVO}"
ls -lh "${ARCHIVO}"
```

- [ ] Confirmar que el tamaño es **coherente con el backup anterior**. Un backup diez veces más chico que el de ayer es una alarma, no un ahorro de espacio.

**Criterio de parada:** sin backup verificado, no se toca producción. Nunca.

## Paso 3 — Capturar la línea base

Necesitás el estado *antes* para poder comparar el estado *después*. Sin esto, el paso 5 no se puede hacer.

- [ ] Contar tablas del esquema.
- [ ] Contar filas de las tablas que la migración toca.
- [ ] Guardar valores agregados de control: saldos, totales, cantidades por estado — lo que corresponda al dominio.
- [ ] Guardar todo en un archivo, no en la cabeza.

```bash
# Ejemplo sintético y genérico.
psql "postgresql://usuario_ejemplo@localhost:5432/base_ejemplo" <<'SQL' > /tmp/linea-base.txt
SELECT count(*) AS tablas
  FROM information_schema.tables
 WHERE table_schema = 'esquema_ejemplo';

SELECT 'tabla_ejemplo' AS t, count(*) FROM esquema_ejemplo.tabla_ejemplo;

SELECT estado_ejemplo, count(*), sum(monto_ejemplo)
  FROM esquema_ejemplo.tabla_ejemplo
 GROUP BY estado_ejemplo
 ORDER BY estado_ejemplo;
SQL
```

## Paso 4 — Aplicación transaccional

Una migración a medias es peor que ninguna migración: deja el esquema en un estado que nadie diseñó.

- [ ] Aplicar **una sola migración por vez**, en orden de versión.
- [ ] Usar **parada al primer error** (`ON_ERROR_STOP=1`).
- [ ] Usar **una única transacción** (`--single-transaction`).
- [ ] Guardar la salida completa en un archivo de registro.

```bash
# Ejemplo sintético y genérico.
psql \
  --set=ON_ERROR_STOP=1 \
  --single-transaction \
  --file=migraciones/v0.0_ejemplo.sql \
  "postgresql://usuario_ejemplo@localhost:5432/base_ejemplo" \
  2>&1 | tee /tmp/migracion-v0.0.log
```

Qué hace cada cosa, porque no es decorativo:

| Opción | Sin ella |
|---|---|
| `ON_ERROR_STOP=1` | El cliente **sigue ejecutando después del error** y deja el esquema a medias |
| `--single-transaction` | Cada sentencia confirma por separado; no hay reversión posible |
| `tee` a un archivo | Se pierde la evidencia de qué se ejecutó y qué respondió |

**Nota:** algunas operaciones no se pueden ejecutar dentro de una transacción, por ejemplo un `CREATE INDEX CONCURRENTLY`. Si la migración incluye una de ésas, separala en su propio archivo y aplicala aparte, con un plan de reversión propio.

**Criterio de parada:** ante cualquier error, **la transacción revierte sola**. No reintentes a mano ni ejecutes sentencias sueltas del archivo para "avanzar un poco". Volvé al paso 1 con el error en la mano.

## Paso 5 — Verificación de no-regresión

Éste es el paso que distingue un despliegue de un despliegue verificado. Confirmar que lo nuevo está y confirmar que lo viejo sigue igual son **dos verificaciones distintas**, y la segunda es la que se olvida.

- [ ] Contar tablas de nuevo y comparar contra la línea base.
- [ ] Confirmar que las tablas nuevas **son exactamente las esperadas**.
- [ ] Volver a correr las consultas de control del paso 3.
- [ ] Comparar los valores: **tienen que ser idénticos**.
- [ ] Verificar que triggers, funciones y vistas nuevas existen y responden.
- [ ] Probar una lectura por el camino real de la aplicación, no sólo por SQL.

```bash
# Ejemplo sintético y genérico: se repite el bloque del paso 3 y se comparan.
psql "postgresql://usuario_ejemplo@localhost:5432/base_ejemplo" \
  --file=/tmp/consultas-control.sql > /tmp/post-migracion.txt

diff /tmp/linea-base.txt /tmp/post-migracion.txt
```

Referencia de cómo se ve una verificación buena, del despliegue del 5 de agosto:

| Verificación | Antes | Después | Resultado |
|---|---|---|---|
| Tablas del esquema | 25 | 35 | Esperado |
| Valores de control preexistentes | — | — | **Idénticos** |

Un cambio en las tablas nuevas es el objetivo. Un cambio en los valores preexistentes es un incidente.

**Criterio de parada:** si un valor de control cambió y no estaba previsto, **rollback inmediato**. No investigues con la migración aplicada en producción.

## Paso 6 — Registro en `schema_migrations`

- [ ] Confirmar que la fila de la nueva versión quedó registrada.
- [ ] Verificar que la fecha de aplicación es la real.
- [ ] Confirmar que el orden de versiones es consistente.

```bash
# Ejemplo sintético y genérico.
psql "postgresql://usuario_ejemplo@localhost:5432/base_ejemplo" \
  -c "SELECT version, applied_at FROM esquema_ejemplo.schema_migrations ORDER BY applied_at DESC LIMIT 3;"
```

Si la migración no registra su propia versión, agregá esa inserción **dentro** del archivo de migración, no como un paso manual posterior. Un registro que depende de que alguien se acuerde no sirve para detectar drift — y detectar drift es justamente para lo que existe esta tabla.

## Paso 7 — Cierre

- [ ] Guardar el registro de la migración junto al backup.
- [ ] Anotar la fecha de aplicación en el repositorio si se lleva ese registro.
- [ ] Confirmar que la aplicación funciona: una operación de lectura y una de escritura por el camino normal.
- [ ] Verificar que no aparecieron errores nuevos en la captura centralizada.
- [ ] Si había un cambio de código asociado, desplegarlo **después** de la migración, no antes.

## Rollback

### Cuándo

| Situación | Acción |
|---|---|
| Error durante la aplicación | Ninguna. La transacción ya revirtió |
| Un valor de control cambió sin estar previsto | **Rollback inmediato** |
| La aplicación falla después de la migración | Rollback, salvo que la causa esté clara y sea trivial |
| Duda razonable | Rollback. Volver a aplicar es barato; investigar en producción no |

### Cómo

Hay tres caminos, en orden de preferencia:

**1. La transacción revirtió sola.** Es el caso normal ante un error de SQL. No hay nada que hacer: verificá el estado y volvé al paso 1.

**2. Migración inversa.** Si la migración trae su reversión escrita y probada, aplicala con el mismo procedimiento: transacción, parada al primer error, verificación.

**3. Restaurar el backup.** Es el último recurso y **pierde todo lo escrito desde el backup**. Antes de restaurar:

- [ ] Confirmar que el backup es el correcto y está verificado.
- [ ] Estimar qué datos se pierden en la ventana entre el backup y ahora.
- [ ] Cortar la escritura si hay forma de hacerlo.

```bash
# Ejemplo sintético y genérico. Destructivo. Leer dos veces antes de correr.
pg_restore --clean --if-exists \
  --dbname="postgresql://usuario_ejemplo@localhost:5432/base_ejemplo" \
  /ruta/ejemplo/backups/pre-migracion-AAAAMMDD-HHMMSS.dump
```

- [ ] Después de restaurar: repetir el paso 5 contra la línea base para confirmar que volviste al estado previo.

**Advertencia honesta:** al 2026-08-05 **no hay un ensayo de restauración demostrado** en este sistema. Los backups son diarios, con lock, manifiesto y script de chequeo, y sin copia fuera del sitio. El camino 3 está descrito, no probado. Es una deuda abierta y publicada, y significa que en la práctica hay que apoyarse en los caminos 1 y 2.

## Checklist completa

Para copiar y pegar cuando se ejecuta:

```text
PRECONDICIONES
[ ] Migración versionada en el repositorio
[ ] Tests en verde contra el DDL real
[ ] Ventana disponible

PASO 0 — ESTADO REAL DEL SERVIDOR
[ ] schema_migrations consultado EN EL SERVIDOR
[ ] Brecha comparada contra el repositorio
[ ] Brecha es la esperada

PASO 1 — PRECONDICIONES
[ ] Migración leída completa
[ ] Operaciones destructivas o transformadoras identificadas
[ ] Permisos del rol verificados
[ ] Duración estimada
[ ] Idempotencia confirmada
[ ] Estado esperado posterior anotado

PASO 2 — BACKUP
[ ] Backup tomado
[ ] Integridad verificada
[ ] Hash y tamaño registrados
[ ] Tamaño coherente con el backup anterior
[ ] Ubicación anotada

PASO 3 — LÍNEA BASE
[ ] Conteo de tablas
[ ] Conteo de filas de las tablas afectadas
[ ] Valores agregados de control
[ ] Todo guardado en archivo

PASO 4 — APLICACIÓN
[ ] Una migración por vez, en orden
[ ] ON_ERROR_STOP=1
[ ] Transacción única
[ ] Salida guardada en un registro

PASO 5 — NO-REGRESIÓN
[ ] Conteo de tablas comparado
[ ] Tablas nuevas son las esperadas
[ ] Consultas de control repetidas
[ ] Valores preexistentes IDÉNTICOS
[ ] Triggers, funciones y vistas verificados
[ ] Lectura probada por el camino de la aplicación

PASO 6 — REGISTRO
[ ] Fila en schema_migrations
[ ] Fecha correcta
[ ] Orden de versiones consistente

PASO 7 — CIERRE
[ ] Registro archivado junto al backup
[ ] Aplicación verificada: una lectura y una escritura
[ ] Sin errores nuevos en la captura centralizada
[ ] Código asociado desplegado DESPUÉS
```

## Criterios de parada, todos juntos

Cinco momentos donde corresponde detenerse, en orden de aparición:

1. **Paso 0** — el servidor está más de una migración atrás de lo esperado. Es un drift: cambiá el plan.
2. **Paso 1** — no podés explicar en una frase qué hace la migración.
3. **Paso 2** — el backup no se pudo verificar, o su tamaño no es coherente.
4. **Paso 4** — cualquier error durante la aplicación. La transacción revierte; no reintentes a mano.
5. **Paso 5** — un valor de control cambió sin estar previsto. Rollback inmediato.

Y una regla que los cubre a todos: **ante la duda, parar**. Un despliegue postergado cuesta unas horas. Un despliegue mal hecho sobre datos financieros cuesta la confianza en los datos, que es lo único que hace útil al sistema.

## Evidencia

| Afirmación | Estado |
|---|---|
| Procedimiento derivado de la remediación real del 2026-08-05 | `Verificado` |
| Uso de `ON_ERROR_STOP=1` en transacción durante esa remediación | `Verificado` |
| Verificación de no-regresión 25 → 35 tablas con valores idénticos | `Verificado` |
| DDL v3.1 aplicado el 2026-07-27 con backups y SHA-256 verificados | `Verificado` |
| Tabla `schema_migrations` en el esquema | `Verificado` |
| Backups diarios con lock, manifiesto y script de chequeo | `Verificado` |
| Ausencia de copia fuera del sitio y de ensayo de restauración | `Verificado` como deuda abierta |
| Que este runbook se haya ejecutado completo, con casillas, en un despliegue posterior | `Pendiente de verificar` |

> Última verificación: 2026-08-05
