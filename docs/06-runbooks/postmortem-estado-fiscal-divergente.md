# Post-mortem: `estado_fiscal` divergente

El 5 de agosto de 2026 se clasificaron 22 movimientos. Quedaron bien clasificados y, al mismo tiempo, sin clasificar. Dos partes del sistema daban dos respuestas distintas a la misma pregunta y nada avisaba.

Este documento es **blameless**: describe cómo el diseño permitió la incoherencia, no quién la produjo. En un proyecto de una sola persona esa distinción importa todavía más, porque la alternativa es escribir un documento inútil.

## Ficha del incidente

| Campo | Valor |
|---|---|
| Fecha de detección | 2026-08-05 |
| Origen | El mismo día, durante la clasificación masiva de movimientos del período |
| Duración | Horas. Detectado dentro de la misma sesión de trabajo |
| Alcance | 22 movimientos con `ambito` y `deducible` correctos y `estado_fiscal = 'sin_clasificar'` |
| Detección | Manual, al contrastar el diagnóstico del agente con los chequeos del cierre |
| Impacto en usuarios | Ninguno. Un cierre trabado, ningún dato perdido ni mal declarado |
| Severidad | Media. Sin daño, con potencial de daño alto |
| Estado | Remediado en la migración v4.7 |

## Línea de tiempo

| Momento | Qué pasó |
|---|---|
| 2026-07-28 | La v4.0 agrega a `movimientos` las columnas fiscales: `ambito`, `deducible`, `deducible_porcentaje` y `estado_fiscal`, este último `NOT NULL DEFAULT 'sin_clasificar'` |
| 2026-07-28 | `cierre_chequeos()` nace con trece ramas. Una de ellas, el bloqueante `sin_clasificar`, mira **`estado_fiscal`** |
| 2026-08-05 | Puesta al día de producción: se aplican v4.4, v4.5 y v4.6. Se clasifican **22 movimientos** del período |
| 2026-08-05 | El diagnóstico del Agente Fiscal los ve **clasificados**: mira `ambito` y `deducible`, y ambos están bien |
| 2026-08-05 | Los chequeos del cierre los siguen marcando como **bloqueantes**: miran `estado_fiscal`, que sigue en `'sin_clasificar'` |
| 2026-08-05 | Se contrastan las dos salidas y aparece la contradicción |
| 2026-08-05 | Al investigar el mismo camino de escritura aparece **el segundo hallazgo**: `puedeTransicionar()` nunca se ejecutaba |
| 2026-08-05 | Se escribe y aplica la migración **v4.7**, con las dos correcciones en una sola pieza. 492 tests en verde |

## Impacto

**Observado: un cierre que no cerraba.** El período no podía pasar a `listo_para_aprobar` por movimientos que estaban, de hecho, clasificados. Ningún dato se perdió, ningún importe se calculó mal, ninguna presentación salió incorrecta.

Que el impacto haya sido ése y no otro es circunstancia, no mérito del diseño. La incoherencia era **simétrica**: en esta dirección trabó un cierre, y en la dirección contraria habría hecho lo opuesto.

| Escenario | Consecuencia |
|---|---|
| `ambito` y `deducible` cargados, `estado_fiscal` en `sin_clasificar` | **Lo que pasó.** El cierre se traba por movimientos que sí están clasificados. Molesto, visible |
| `estado_fiscal` en `clasificado`, `ambito` o `deducible` en null | El chequeo bloqueante **no se dispara** y el mes cierra con movimientos sin encuadre real. Silencioso |

El segundo escenario es el que hace que esto valga un post-mortem. La misma causa —dos campos que responden lo mismo sin nada que los mantenga sincronizados— podía producir un cierre aprobado sobre movimientos sin clasificar, y no había ningún control que lo detectara.

Y hay algo más incómodo: la contradicción sólo apareció porque **alguien puso las dos salidas al lado**. El diagnóstico decía una cosa, los chequeos decían otra, y cada uno por separado se veía perfectamente razonable.

## Causa raíz

**La verdad vivía en dos lugares y no había nada que los mantuviera coherentes.**

El encuadre fiscal de un movimiento se expresa con `ambito` (personal, profesional, mixto) y `deducible`. El marcador `estado_fiscal` expresa lo mismo en forma de estado, y es el que consulta `cierre_chequeos()`.

Los dos se escribían por separado. El código de clasificación actualizaba `ambito` y `deducible`; actualizar `estado_fiscal` era un paso adicional que había que acordarse de hacer.

> *«Dos partes del sistema, dos respuestas distintas a la misma pregunta, sin que nada avisara de la contradicción.»*
> — `44_Migration_v4_7_estado_fiscal_derivado.sql`

### Por qué la solución obvia no alcanzaba

La reacción intuitiva es corregir el código que clasifica: que además de escribir `ambito` y `deducible`, escriba `estado_fiscal`. Es una línea, no rompe nada, y se prueba en cinco minutos.

Y no alcanza:

> *«el día que alguien escriba `ambito` por otra vía —una importación, un flujo de n8n, un psql suelto— vuelven a divergir. Lo que hace falta es que no puedan.»*

En este sistema hay al menos cuatro caminos hasta la tabla `movimientos`: la API, la ingesta de documentos, los workflows de n8n y una sesión de línea de comandos. Arreglar uno deja tres. **El código no es el único camino a la base.**

### La ausencia de señal

Tres cosas conspiraron para que la incoherencia fuera invisible:

1. **Ningún constraint la prohibía.** El `CHECK` de `estado_fiscal` verificaba que el valor fuera uno de los cinco válidos. `'sin_clasificar'` es un valor válido. Desde el punto de vista de la base, la fila estaba perfecta.
2. **Cada consumidor miraba un solo campo.** El motor mira `ambito` y `deducible`; el chequeo mira `estado_fiscal`. Ninguno de los dos tenía forma de saber que el otro veía algo distinto.
3. **Los tests probaban cada camino por separado.** Clasificar funcionaba. Chequear funcionaba. Lo que no existía era una prueba de que después de clasificar, el chequeo dejara de disparar.

## Detección

**Manual, por contraste de dos salidas.** Al leer el diagnóstico del agente junto a los chequeos del cierre, en la misma sesión, apareció la diferencia.

No hubo alerta, no hubo error, no hubo log. La detección dependió de que alguien mirara las dos cosas al mismo tiempo, y de que en ese momento el cierre estuviera trabado y hubiera motivo para investigar.

Si la divergencia hubiera ido en la dirección contraria —`estado_fiscal` en `clasificado` sin encuadre real— no habría habido nada trabado y por lo tanto ningún motivo para mirar.

## Remediación

Se resolvió en una sola migración, la **v4.7**, con tres piezas.

### 1 · Trigger derivador

`trg_mov_estado_fiscal_derivado`, `BEFORE INSERT OR UPDATE OF ambito, deducible, estado_fiscal ON movimientos`, con la función `movimiento_estado_fiscal_derivado()`:

- `ambito` y `deducible` no nulos y `estado_fiscal = 'sin_clasificar'` → pasa a `'clasificado'`.
- `ambito` o `deducible` nulos y `estado_fiscal = 'clasificado'` → vuelve a `'sin_clasificar'`.

`estado_fiscal` deja de ser un campo que alguien escribe y pasa a ser uno que se deriva. Venga la escritura de la API, de una importación, de un workflow o de una sesión suelta, el trigger corre.

**No toca** `observado`, `incluido_en_cierre` ni `presentado`:

> *«Esos tres son decisiones deliberadas de un proceso posterior, no consecuencias del encuadre. Un movimiento ya presentado ante ARCA no puede volver atrás porque alguien le corrija un campo.»*

### 2 · Corrección de las filas incoherentes

La migración corrige con un `UPDATE` las filas que ya estaban divergentes, incluidas las 22 del día.

El rollback advierte que esa corrección **no se revierte**: *«volverlas atrás sería reintroducir el error»*. Un rollback que restaura datos incorrectos no es un rollback: es una segunda falla.

### 3 · Bloque de verificación que aborta la migración

Después del `UPDATE`, un bloque `DO $$` cuenta las filas incoherentes que quedan y lanza `RAISE EXCEPTION` si encuentra alguna.

Es la parte que más vale la pena copiar. Una migración correctiva que se aplica sin error pero no corrige todo deja el sistema en el peor estado posible: parece arreglado. El bloque de verificación convierte una corrección incompleta en un despliegue abortado.

### 4 · Verificación de no-regresión

- [x] Las 22 filas quedaron con `estado_fiscal = 'clasificado'`.
- [x] El chequeo bloqueante `sin_clasificar` dejó de dispararse sobre ellas.
- [x] Ningún movimiento en `observado`, `incluido_en_cierre` ni `presentado` cambió de estado.
- [x] 492 tests en verde ese mismo día.

El test de esta migración **se excluye a propósito del arnés común**, porque necesita sembrar el estado incoherente **antes** de aplicarla. Una prueba de una corrección tiene que poder crear el problema que la corrección resuelve.

## El segundo hallazgo de la misma sesión

Al investigar por dónde se escribía `estado_fiscal` apareció otra cosa, de la misma familia y peor.

`api/fiscal.mjs` definía la función `puedeTransicionar()` con el grafo completo de estados del cierre. Estaba bien escrita, cubría los seis estados y todas las transiciones válidas.

**Nunca se ejecutaba.** La ruta HTTP hacía un `UPDATE` directo sobre `fiscal_cierres`, y el `CHECK` de la tabla sólo verificaba que el valor fuera uno de los seis estados válidos — no que la transición tuviera sentido.

**Verificado el 2026-08-05:** un pedido con `estado = 'presentado'` sobre un período recién abierto **se aceptaba**. Sin pasar por revisión, sin cero bloqueantes, sin aprobación, sin evidencia de presentación.

> *«El sistema quedaría afirmando que se presentó ante ARCA algo que nunca se presentó.»*

Es el mismo patrón que las 22 filas, con dos diferencias que lo empeoran:

| | `estado_fiscal` divergente | `puedeTransicionar()` muerta |
|---|---|---|
| Qué falló | Dos campos sin sincronizar | Una validación escrita que nunca corría |
| Cómo se manifestaba | Un cierre trabado — **visible** | Un cierre que salta etapas — **silencioso** |
| Qué habría producido | Molestia | Un registro falso de presentación ante el organismo fiscal |
| Cómo se detectó | Contrastando dos salidas | Leyendo el camino de escritura por otro motivo |

El segundo hallazgo se corrigió en la **Parte 2 de la misma migración**: el trigger `trg_cierre_transicion_valida`, que valida el grafo en la base y devuelve un `HINT` con el recorrido correcto. Más `chk_cierre_nace_abierto`, declarado `NOT VALID` para no rechazar filas históricas.

El grafo ahora vive **dos veces a propósito**: en `fiscal.mjs`, para dar un mensaje claro antes de intentar la operación, y en el trigger, que es la garantía real. Y hay un test que compara los dos y falla si divergen — sin ese test, la duplicación sería exactamente el problema que este post-mortem describe.

## Acciones correctivas

| # | Acción | Estado | Prioridad |
|---|---|---|---|
| 1 | Derivar `estado_fiscal` por trigger en vez de escribirlo | **Hecho** — v4.7, Parte 1 | Alta |
| 2 | Corregir las filas ya incoherentes | **Hecho** — con `UPDATE` no reversible | Alta |
| 3 | Bloque de verificación que aborta la migración si queda alguna incoherente | **Hecho** — `DO $$` con `RAISE EXCEPTION` | Alta |
| 4 | Validar el grafo de transiciones del cierre en la base | **Hecho** — v4.7, Parte 2 | Alta |
| 5 | Test que compare el grafo de la base con el de `fiscal.mjs` | **Hecho** | Alta |
| 6 | Registrar la regla general como decisión de arquitectura | **Hecho** — [ADR-012](../04-decisiones/adr-012-la-invariante-vive-en-la-base.md) | Alta |
| 7 | Verificar que las rutas HTTP **deleguen** en los módulos en vez de reescribir su lógica | **Parcial** — hay un test que lee `server.mjs`; se corrigieron clasificación y transición de cierre | **Alta** |
| 8 | Revisar comprobantes, perfiles y borradores por el mismo patrón de lógica duplicada | **Pendiente** — «probablemente tengan el mismo patrón» | **Alta** |
| 9 | Inventariar las invariantes que siguen viviendo sólo en el código | **Pendiente** | Alta |
| 10 | Chequeo periódico de coherencia entre campos derivados y sus fuentes | **Pendiente** | Media |

Las acciones 8 y 9 son las que atacan la clase de problema y no el caso. Mientras no estén hechas, no se puede afirmar que no haya otra `puedeTransicionar()` escrita y muerta en algún módulo.

## Lecciones

### 1. Dos campos que responden la misma pregunta van a divergir

No es cuestión de disciplina. Si el sistema permite que difieran, en algún momento difieren. La única forma de evitarlo es que uno se derive del otro, y que la derivación esté donde no se pueda saltear.

### 2. La incoherencia visible es la suerte, no el resultado

Esto trabó un cierre y por eso alguien lo miró. La misma causa, en la dirección contraria, habría dejado cerrar un mes con movimientos sin clasificar y nadie se habría enterado.

### 3. Una validación que nunca se ejecuta es peor que no tenerla

No sólo no protege: **hace creer que protege**. Cualquiera que leyera `fiscal.mjs` habría concluido, razonablemente, que las transiciones del cierre estaban controladas.

### 4. Una migración correctiva tiene que verificarse a sí misma

El `UPDATE` que corrige puede correr sin error y no alcanzar. El bloque que cuenta lo que queda y aborta es lo que distingue una corrección de una esperanza.

### 5. La duplicación deliberada necesita un test que la vigile

El grafo vive en dos lugares por buenas razones. Eso sólo es aceptable porque hay una prueba que falla si se separan. Duplicación sin esa prueba es exactamente el problema original con otro nombre.

### 6. La lección de fondo, que es la del ADR-012

> *«Porque la regla ya estaba escrita en el código y no alcanzó. […] La base es el único lugar por donde pasan todos los caminos.»*

Escribir la regla en el código la deja del lado de uno de los caminos. Escribirla en la base la deja del lado de todos. Es más incómodo, reparte la lógica en dos lenguajes y obliga a probar contra una base real — y es la única versión que sigue siendo cierta cuando alguien entra por otra puerta.

## Evidencia

| Afirmación | Estado |
|---|---|
| 22 movimientos clasificados el 2026-08-05 con `estado_fiscal` sin actualizar | `Verificado` |
| El diagnóstico los veía clasificados y `cierre_chequeos()` los marcaba bloqueantes | `Verificado` |
| Trigger `trg_mov_estado_fiscal_derivado` y su función | `Verificado` |
| El trigger no toca `observado`, `incluido_en_cierre` ni `presentado` | `Verificado` |
| `UPDATE` correctivo no reversible, declarado así en el rollback | `Verificado` |
| Bloque `DO $$` con `RAISE EXCEPTION` que aborta si quedan filas incoherentes | `Verificado` |
| `puedeTransicionar()` definida en `fiscal.mjs` y nunca ejecutada | `Verificado` |
| Un pedido `estado = 'presentado'` sobre un período recién abierto se aceptaba | `Verificado` — comprobado el 2026-08-05 |
| Trigger `trg_cierre_transicion_valida` con `HINT` y `chk_cierre_nace_abierto` `NOT VALID` | `Verificado` |
| Test que compara el grafo de la base con el de `fiscal.mjs` | `Verificado` |
| El test de la v4.7 se excluye del arnés común para poder sembrar el estado incoherente | `Verificado` |
| 492 tests en verde el 2026-08-05 tras la v4.7 | `Verificado` |
| Si hubo filas incoherentes anteriores al 2026-08-05 y cuántas | `Historia incompleta` — se registra el conteo del día, no una auditoría retroactiva |
| Si algún cierre anterior se aprobó con movimientos sin encuadre por esta causa | `Pendiente de verificar` — no auditado |
| Otras rutas con lógica duplicada: comprobantes, perfiles, borradores | `Pendiente de verificar` — revisión abierta |

> Última verificación: 2026-08-06
