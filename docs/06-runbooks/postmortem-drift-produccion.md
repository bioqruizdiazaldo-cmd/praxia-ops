# Post-mortem: producción tres migraciones atrás

El 5 de agosto de 2026, al ir a aplicar una migración, se descubrió que producción estaba en v4.4 desde el 31 de julio. Cinco días de atraso silencioso, con el repositorio impecable.

Este documento es **blameless**: describe cómo el sistema de trabajo permitió el problema, no quién se equivocó. En un proyecto de una sola persona esa distinción es aún más importante, porque la alternativa es escribir un documento inútil.

## Ficha del incidente

| Campo | Valor |
|---|---|
| Fecha de detección | 2026-08-05 |
| Origen del atraso | 2026-07-31, tras la migración v4.4 |
| Duración | 5 días |
| Brecha | 3 migraciones (v4.4 en producción, v4.6 en el repositorio) |
| Detección | Manual, al preparar el despliegue de v4.6 |
| Impacto en usuarios | Ninguno observado |
| Severidad | Media. Sin daño, con potencial de daño alto |
| Estado | Remediado |

## Línea de tiempo

| Fecha | Qué pasó |
|---|---|
| 2026-07-31 | Se aplica v4.4 a producción. Se crea el tag `v4.3-pre-fase2`. **Último estado en que repositorio y servidor coincidieron** |
| 2026-08-01 | Se desarrolla y versiona v4.5 (`deuda_pagos`, guards de moneda, recálculo de saldo). Tests en verde. **No se aplica a producción** |
| 2026-08-02/03 | Se desarrolla y versiona v4.6 (obligaciones recurrentes, 8 tablas nuevas). Tests en verde. **No se aplica a producción** |
| 2026-08-03 | Inspección global de solo lectura del runtime de n8n. Se audita el entorno de workflows; **el esquema de la base no formó parte de esa inspección** |
| 2026-08-04 | Se aprueba el contrato Finanzas↔Fiscal v1.0 y la capa de lectura fiscal |
| 2026-08-05 | Al preparar el despliegue de v4.6 se consulta el estado del esquema desplegado. **Producción está en v4.4** |
| 2026-08-05 | Remediación: backup verificado, v4.5 y v4.6 aplicadas en transacción, verificación de no-regresión |
| 2026-08-05 | Durante la puesta al día, **el propio agente detecta un bug real** en el código que se estaba desplegando |
| 2026-08-05 | Se continúa con v4.7 y v4.8 sobre producción ya al día |

## Impacto

**Observado: ninguno.** Ningún usuario reportó nada, ninguna ejecución falló por esta causa, ningún dato se perdió ni se corrompió.

Ese resultado no es mérito del proceso: es circunstancia. Las funcionalidades de v4.5 y v4.6 —pagos de deuda y obligaciones recurrentes— todavía no se usaban desde el canal de producción. Si se hubieran usado, el impacto habría sido inmediato y confuso: llamadas a endpoints existentes en el código contra tablas que no existían en la base, con errores de SQL difíciles de atribuir.

**Impacto potencial, que es el que importa para el análisis:**

| Riesgo | Por qué no se materializó |
|---|---|
| Errores de columna o tabla inexistente en producción | Las funcionalidades nuevas no se usaban todavía |
| Depuración en la dirección equivocada | Nadie llegó a depurar; la detección fue previa |
| Tres migraciones acumuladas aplicadas juntas | Se detectó a las tres; a las diez habría sido mucho peor |
| Falsa confianza en los tests | Los tests corrían contra el esquema del repositorio, que estaba bien. **Verde en tests, atrasado en producción** |

Ese último punto es el más incómodo. Los 554 tests estaban en verde todo el tiempo. No podían detectar esto, porque prueban el esquema del repositorio con PGlite y el problema estaba justamente en la diferencia entre repositorio y servidor. **Una suite de tests verde no dice nada sobre el estado de producción.**

## Causa

La causa quedó dicha en una sola frase:

> *"nadie había mirado el servidor, solo el repositorio."*

Vale la pena desarmarla, porque es más interesante que "se olvidaron de desplegar".

### El proceso funcionaba, en su mitad

El flujo de trabajo era: escribir la migración → probarla con PGlite → commitear → seguir con la próxima. Ese flujo es correcto y estaba bien ejecutado. Las migraciones estaban numeradas, probadas, versionadas y con tag.

Lo que faltaba era el paso siguiente, y no faltaba por descuido puntual: **no estaba en el proceso**. No había un paso "verificar que producción esté donde debe estar", así que no se salteó — nunca existió.

### La ausencia de señal

Tres cosas conspiraron para que el atraso fuera invisible:

1. **No hay ambiente de staging.** Con staging, desplegar es un acto explícito con su propia verificación. Sin él, "listo" significa "commiteado" y no hay nada que empuje a mirar el servidor.
2. **No hay panel de administración de la base.** Es una consecuencia directa de la decisión del [ADR-002](../04-decisiones/adr-002-postgres-propio-en-vez-de-supabase.md). Con un servicio gestionado, la versión del esquema se ve al entrar. Con PostgreSQL propio hay que ir a preguntarle.
3. **No hay integración continua.** Nada corre solo, y por lo tanto nada compara solo.

### El agravante: el repositorio estaba impecable

Este es el punto que hace que el incidente valga la pena documentarlo. **No fue un caso de falta de disciplina.** Fue un caso de disciplina aplicada a la mitad correcta del problema.

Migraciones numeradas, tests verdes, tag antes del cambio grande, commits ordenados. Todo eso genera una sensación fundada de control, y esa sensación fue exactamente lo que impidió preguntarse por el servidor. Ocho días antes, el 28 de julio, el problema había sido el opuesto: no había repositorio. Se lo resolvió, y el péndulo quedó del otro lado.

La lección de fondo: **versionar sin verificar el despliegue produce una ilusión de control que es peor que no versionar**, porque genera confianza. Es el argumento entero del [ADR-008](../04-decisiones/adr-008-el-repositorio-como-fuente-de-verdad.md).

## Detección

Fue **manual y por casualidad de secuencia**: al preparar el despliegue de v4.6 se consultó la tabla `schema_migrations` del servidor, y ahí apareció v4.4.

Hay que decirlo claro: si esa consulta no hubiera sido parte de la preparación de ese despliegue en particular, el atraso habría seguido creciendo. **No hubo ninguna alerta, ningún panel, ningún chequeo automático.** La detección dependió de que alguien mirara.

Tiempo de detección: **cinco días**. Es la métrica que hay que bajar.

## Remediación

Se aplicó el procedimiento que después quedó escrito como [runbook de despliegue de una migración](despliegue-de-una-migracion.md). Cuatro pasos.

### 1. Backup verificado

Antes de tocar nada, backup completo y **verificado** — comprobada su integridad, no solamente comprobado que el archivo existe. Un backup no verificado es una hipótesis.

### 2. Aplicación transaccional con parada al primer error

Las migraciones v4.5 y v4.6 se aplicaron dentro de una transacción, con parada inmediata ante el primer error. En un cliente de línea de comandos de PostgreSQL eso es `ON_ERROR_STOP=1` combinado con `BEGIN` / `COMMIT`:

```bash
# Ejemplo sintético y genérico. Adaptar al entorno propio.
psql \
  --set=ON_ERROR_STOP=1 \
  --single-transaction \
  --file=migraciones/v4.5_ejemplo.sql \
  "postgresql://usuario_ejemplo@localhost:5432/base_ejemplo"
```

Sin `ON_ERROR_STOP=1`, el cliente sigue ejecutando después de un error y deja el esquema a medio migrar, que es el peor estado posible: ni el viejo ni el nuevo. Con transacción, o se aplica todo o no se aplica nada.

Las migraciones se aplicaron **en orden**: v4.5 y después v4.6. Aplicar tres cambios acumulados de una vez es más riesgoso que aplicarlos de a uno, y el orden importa cuando una depende de la anterior.

### 3. Verificación de no-regresión

Éste es el paso que distingue un despliegue de un despliegue verificado. No alcanza con confirmar que lo nuevo está: hay que confirmar que **lo viejo sigue igual**.

| Verificación | Resultado |
|---|---|
| Conteo de tablas antes | 25 |
| Conteo de tablas después | 35 |
| Tablas nuevas esperadas | Las de v4.5 y v4.6 |
| Valores preexistentes | **Idénticos antes y después** |

Que los valores sean idénticos es la parte importante. Una migración puede aplicarse sin error y aun así alterar datos por un `DEFAULT` mal puesto, una constraint que rechaza filas existentes o un trigger nuevo que se dispara en el `ALTER`. Comparar valores antes y después es lo único que lo detecta.

### 4. Registro y continuación

`schema_migrations` quedó registrando el estado real. Con producción al día, se siguió con v4.7 y v4.8 el mismo día, esta vez con el procedimiento completo desde el principio.

## El bug que apareció durante la puesta al día

Un detalle que merece su propia sección, porque es el resultado más interesante del incidente.

Durante la puesta al día, **el propio agente que estaba ejecutando el despliegue detectó un bug real** en el código que se estaba desplegando. No un problema de la migración: un defecto genuino en la lógica, encontrado al revisar el cambio con atención mientras se lo aplicaba.

Tres cosas que muestra esto:

1. **La revisión durante el despliegue tiene valor propio.** Un despliegue apurado —copiar, pegar, listo— no habría encontrado nada. Un procedimiento con pasos de verificación crea el espacio para mirar.
2. **Un agente de IA es un buen revisor en el momento del despliegue**, porque lee todo el diff sin cansarse y sin el sesgo de quien escribió el código y ya sabe qué quiso hacer.
3. **El incidente produjo un beneficio neto.** Los cinco días de atraso obligaron a una puesta al día cuidadosa, y esa puesta al día encontró un defecto que un despliegue rutinario habría dejado pasar. No justifica el atraso, y hay que anotarlo.

Coherente con el principio de la línea base: *"Los agentes de IA pueden proponer, implementar y verificar trabajo. No se convierten en el dueño responsable del riesgo, el acceso o la decisión de release."* El agente encontró el bug; la decisión de qué hacer con él fue humana.

## Acciones correctivas

| # | Acción | Estado | Prioridad |
|---|---|---|---|
| 1 | Escribir el procedimiento de despliegue de migraciones como runbook con casillas | **Hecho** — ver [runbook](despliegue-de-una-migracion.md) | Alta |
| 2 | Incorporar la verificación de no-regresión como paso obligatorio, no como buena costumbre | **Hecho** | Alta |
| 3 | Consultar `schema_migrations` del servidor al comienzo de todo despliegue | **Hecho** — es el paso 0 del runbook | Alta |
| 4 | Adoptar formalmente el repositorio como fuente de verdad y el runtime como despliegue | **Hecho** — [ADR-008](../04-decisiones/adr-008-el-repositorio-como-fuente-de-verdad.md) | Alta |
| 5 | Chequeo automático y periódico de correspondencia entre migraciones del repositorio y `schema_migrations` del servidor | **Pendiente** | **Alta** |
| 6 | Alerta cuando la brecha supere una migración | **Pendiente** | Alta |
| 7 | Ambiente de staging separado | **Pendiente** | Media |
| 8 | Integración continua que corra los 554 tests sin intervención | **Pendiente** | Media |
| 9 | Ensayo de restauración de backup documentado | **Pendiente** | Media |

Las acciones 5 y 6 son las que atacan la causa directamente. Sin ellas, la mitigación actual es "acordarse de mirar", que es exactamente lo que falló.

Se declara sin adornos: **al 2026-08-05 la detección de drift sigue siendo manual.** El runbook baja la probabilidad de que se repita, no la elimina.

## Lecciones

### 1. Un repositorio impecable no dice nada sobre producción

Es la lección central. Commits ordenados, migraciones numeradas y tests verdes describen el repositorio. El estado del servidor es una pregunta distinta y hay que hacerla explícitamente.

### 2. La disciplina que cubre la mitad del problema genera confianza injustificada

Ocho días antes el problema era que no había repositorio. Se resolvió bien, y esa resolución produjo la sensación de que el flujo estaba completo. **Una mejora parcial puede empeorar la percepción del riesgo.**

### 3. Los tests verdes no son evidencia de despliegue

Los 554 tests corren contra el esquema del repositorio con una base embebida. Por diseño no pueden ver producción. Confundir "los tests pasan" con "producción está bien" es un error de categoría.

### 4. Sin señal automática, el tiempo de detección lo decide el azar

Cinco días fue el tiempo que tardó en aparecer una tarea que obligara a mirar el servidor. Podrían haber sido veinte.

### 5. Desplegar de a poco es más seguro que desplegar acumulado

Tres migraciones juntas se pudieron aplicar sin drama. Diez habrían sido otra conversación. La frecuencia de despliegue es una variable de riesgo, y desplegar más seguido baja el riesgo en vez de subirlo.

### 6. Un procedimiento con pasos crea el espacio para encontrar cosas

El bug apareció porque el despliegue fue lento y verificado. La prisa no sólo aumenta el riesgo de romper algo: también reduce la probabilidad de encontrar lo que ya estaba roto.

## Evidencia

| Afirmación | Estado |
|---|---|
| Producción en v4.4 al 2026-08-05, tres migraciones atrás desde el 31/07 | `Verificado` |
| Cita textual *"nadie había mirado el servidor, solo el repositorio"* | `Verificado` |
| Backup verificado antes de la remediación | `Verificado` |
| Migraciones aplicadas con `ON_ERROR_STOP=1` en transacción | `Verificado` |
| Verificación de no-regresión: 25 → 35 tablas, valores idénticos | `Verificado` |
| Bug real detectado por el propio agente durante la puesta al día | `Verificado` |
| v4.7 y v4.8 aplicadas el mismo día tras la puesta al día | `Verificado` |
| Tag `v4.3-pre-fase2` del 2026-07-31 | `Verificado` |
| Ausencia de impacto en usuarios | `Inferido` — por ausencia de reportes y de errores registrados, no por una auditoría dedicada |
| Naturaleza específica del bug encontrado | `Historia incompleta` — se registra el hecho, no el detalle |
| Chequeo automático de correspondencia repositorio/servidor | `Pendiente de verificar` — no implementado |

> Última verificación: 2026-08-05
