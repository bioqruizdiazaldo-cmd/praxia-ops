# ADR-006 — El Buscador General no se publica

Pasó 2 de 7 pruebas contra una exigencia declarada de 7/7. Estaba construido, funcionaba y no se publicó. Es la decisión más importante de este repositorio.

> **In English** — The decision not to publish a finished component. The "Buscador General" — a broader web
> search agent with relevance scoring, a consolidated validator and a coverage metric — scored 2 of 7 on a
> case matrix frozen before the run, against a pass threshold of 7/7 declared in advance. It was not
> published, and the fixtures were not adjusted: the recorded diagnosis is that the four failures were not
> false positives of the new validator but cases that genuinely lacked enough evidence for a grounded answer.
> Lowering the bar to 5/7 and shipping it labelled "experimental" were both considered and rejected — the
> label protects the author, not the reader. The narrower Tavily V1 stays in production with seven typed
> output states, including `no_reliable_source` and `insufficient_evidence`. The underlying asymmetry: the
> cost of not shipping is visible and bounded, the cost of shipping unsupported answers is open-ended.

<!-- fin del resumen en inglés -->

## Estado

Rechazada.

## Fecha

2026-07-27 — revalidación real acotada y decisión de no publicar. Se mantiene al 2026-08-05.

## Contexto

El 25 de julio a las 23:18 se publicó el **Buscador Web Tavily V1**: nueve nodos, contrato de evidencia y siete estados de salida tipados. Funciona y sigue en producción.

Ese buscador es acotado a propósito. La idea del **Buscador General** era la ambiciosa: un componente capaz de responder cualquier consulta con respuesta fundada en fuentes, con validación de relevancia, cobertura temporal y alcance.

Se trabajó dos días. La secuencia, verificada:

| Fecha | Trabajo |
|---|---|
| 26/07 | Auditoría correctiva de fechas: hoy/ayer/temporada, `target_date`, `date_scope` — 8/8 |
| 26/07 | Corrección estructural del contexto (`tavily_response`) — 8/8 |
| 26–27/07 | Corrección de cobertura temática: etiquetas por resultado, fallback de 72 horas |
| 27/07 | Fases 3B → 3E1: relevancia, validador consolidado, métrica de alcance, fallback |
| 27/07 | Auditoría de ejecuciones y **matriz de casos fija** |
| 27/07 | **Revalidación real acotada: 2/7 PASS** |

Dos detalles del método que definen todo lo que sigue.

**Primero: el umbral se declaró antes de correr.** La exigencia era **7/7**. No "la mayoría", no "que ande bien": los siete casos de la matriz. Fijado antes de ver un solo resultado.

**Segundo: la matriz de casos se congeló antes de la revalidación.** Ese paso —"auditoría de ejecuciones y matriz fija"— es lo que hace que el resultado sea información y no negociación. Con la matriz abierta, cualquier resultado se puede acomodar.

El resultado fue 2 de 7.

## Decisión

**No se publica.**

Y una decisión secundaria que importa tanto como la primera: **no se ajustan los fixtures**. El diagnóstico quedó escrito así:

> *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."*

Hay que leer esa frase despacio, porque dice algo más incómodo de lo que parece. No dice "el validador está mal calibrado". Dice que **el validador tenía razón**: los casos realmente no contenían evidencia suficiente para una respuesta fundada, y por lo tanto la respuesta correcta del sistema era no responder. Lo que falló no fue la detección: fue la capacidad de conseguir evidencia.

Un buscador que se publica en ese estado tiene dos comportamientos posibles y los dos son malos. Si respeta el validador, contesta "no puedo" la mayor parte de las veces y es inútil. Si se afloja el validador para que conteste igual, produce respuestas sin respaldo con apariencia de fundamento — que es peor que inútil, porque es indistinguible de lo bueno.

El Buscador Tavily V1 se queda en producción. Es más chico, está acotado, y sus siete estados de salida incluyen `no_reliable_source` e `insufficient_evidence`: declara sus límites en vez de disimularlos.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **No publicar y dejar el V1 acotado en producción** | Ninguna respuesta sin fundamento llega al usuario; el umbral declarado se respeta; el trabajo queda disponible para retomar | Dos días de trabajo sin entregable; la capacidad sigue sin existir | **Elegida** |
| Publicar igual, en modo experimental | Se prueba con tráfico real; se junta evidencia de uso | Un componente marcado "experimental" que responde con confianza es indistinguible de uno confiable **para quien lee la respuesta**. La etiqueta protege al autor, no al usuario | Rechazada |
| Ajustar los fixtures para que pasen | 7/7 inmediato | Es cambiar el examen después de ver las notas. Los casos estaban bien; la evidencia no alcanzaba | Rechazada |
| Bajar el umbral a 5/7 | "Suficientemente bueno" | El umbral se habría movido **después** de ver los resultados. Un umbral que se mueve no es un umbral | Rechazada |
| Publicar sólo para las categorías que pasaron | Entrega parcial real | Habría que clasificar la consulta antes de buscar, con la misma fiabilidad que falta. El problema se mueve, no se resuelve | Postergada |

## Consecuencias

### Positivas

- **Ninguna respuesta sin fundamento llegó al usuario.** Es el objetivo entero y se cumplió.
- **El umbral declarado sobrevivió al contacto con un resultado incómodo.** Un umbral que nunca se respetó en un caso doloroso no es un umbral: es decoración. Éste se respetó.
- **El diagnóstico quedó escrito.** No hay que rehacer las dos jornadas para entender qué faltaba: la limitación es de suficiencia de evidencia, no de validación.
- **El validador quedó validado.** Detectó correctamente respuestas sin respaldo. Es un activo reutilizable.
- **El V1 se benefició.** Las correcciones de fechas, contexto y cobertura temática que salieron de este trabajo están en producción.

### Negativas

- **No hay buscador general.** La capacidad no existe y no hay fecha.
- **Dos jornadas de fases 3B a 3E1 sin entregable publicable.** En cualquier métrica de productividad esto cuenta cero.
- El componente queda en estado intermedio: construido, no publicado, sin dueño de mantenimiento. Ese estado se degrada solo si no se retoma.
- **No se midió cuánto faltaba.** 2/7 dice que falló; no dice si los cinco casos fallidos estaban cerca o lejos. Estado: `Pendiente de verificar`.

### Operativas

- El Buscador Tavily V1 sigue siendo la única capacidad de búsqueda web, con sus límites conocidos.
- No hay procedimiento definido para retomar un componente rechazado. Estado: `Pendiente de verificar`.
- El costo real de esta decisión no es el trabajo perdido, sino el **componente en limbo**: existe, no está en producción y nadie lo mantiene.

### De seguridad

- Aunque no parezca una decisión de seguridad, lo es. **Una respuesta con fuentes que no respaldan lo que se afirma es un problema de integridad de la información**, y en dominios donde el sistema opera —ciencia, salud pública, bioseguridad— una afirmación sin respaldo con apariencia de fundamentada puede terminar citada.
- Se alinea con la regla de publicación del proyecto: *"afirmar pruebas, adopción o publicación sin evidencia"* está en la lista de lo prohibido. Publicar un buscador que no pasa sus propias pruebas sería violar la propia política.
- Y con el principio general: *"La ausencia de datos no debe convertirse en un dato inventado."*

## Evidencia

| Afirmación | Estado |
|---|---|
| Revalidación real acotada del 2026-07-27 con resultado 2/7 PASS | `Verificado` |
| Exigencia declarada de 7/7 | `Verificado` |
| Matriz de casos fijada antes de la revalidación | `Verificado` |
| Cita textual del diagnóstico de los cuatro FAIL | `Verificado` |
| Fases 3B → 3E1: relevancia, validador consolidado, métrica de alcance, fallback | `Verificado` |
| Correcciones previas del buscador: fechas 8/8, contexto 8/8, cobertura temática | `Verificado` |
| Buscador Web Tavily V1 publicado el 2026-07-25 23:18 y en producción al corte | `Verificado` |
| Siete estados de salida tipados del V1, incluidos `no_reliable_source` e `insufficient_evidence` | `Verificado` |
| Distancia entre el resultado obtenido y el umbral en los 5 casos fallidos | `Pendiente de verificar` |
| Detalle caso por caso de la matriz de 7 | `Historia incompleta` — sólo está el agregado |

## Por qué esto es ingeniería y no un fracaso

Es la parte que justifica que este ADR esté primero en cualquier lectura del repositorio.

**Un fracaso es un resultado que no se buscaba y que enseña por accidente.** Esto fue otra cosa: se declaró un criterio de aceptación, se congeló la matriz de casos, se corrió la prueba, se leyó el resultado y se actuó en consecuencia. El sistema de verificación **funcionó exactamente como estaba diseñado**. Lo único que no funcionó fue el componente, y para eso justamente existía la verificación.

Los tres momentos donde esto se podía haber roto, y no se rompió:

1. **Después de ver 2/7, mover el umbral a 5/7.** Nadie se hubiera enterado. El umbral quedó donde estaba.
2. **Reescribir los cuatro fixtures que fallaron** con el argumento de que "no eran representativos". Se determinó lo contrario y quedó escrito.
3. **Publicar con etiqueta de experimental** y dejar que el uso decida. La etiqueta la lee el autor; la respuesta la lee el usuario.

La asimetría de fondo: **el costo de no publicar es visible y acotado** —dos jornadas, ningún entregable— **y el costo de publicar es invisible y abierto**. Nadie iba a reportar la respuesta con fuentes que no la respaldaban; simplemente se habría usado. Los sistemas que se degradan sin que nadie proteste son los peores de operar, porque la señal de que algo anda mal nunca llega.

Hay una diferencia práctica entre dos ideas que suenan parecidas:

| | Un componente que no funciona | Un componente que no se sabe si funciona |
|---|---|---|
| Se detecta | Rápido, por el uso | Nunca, o tarde y por daño |
| Se corrige | Con un arreglo | Con una crisis |
| Costo | Acotado | Abierto |

El Buscador General estaba en la segunda columna hasta que la revalidación lo movió a la primera. **Ese movimiento es todo el valor del trabajo de esos dos días**, y es exactamente lo que no aparece en ninguna métrica de entrega.

La última observación, y quizás la más útil para alguien que lea esto: **un repositorio que sólo muestra lo que se publicó no permite evaluar el criterio de quien lo escribió**. Cualquiera puede mostrar tres proyectos que funcionan. Lo que dice algo sobre cómo trabaja una persona es qué decidió no publicar, y por qué.

## Disparador de revisión

Este ADR se revisa —y el componente se puede retomar— si ocurre alguna de estas cosas:

- **Mejora la suficiencia de evidencia disponible**: una fuente adicional, más resultados por consulta, o acceso a texto completo. Es el disparador principal, porque ataca la causa real.
- **Aparece una necesidad concreta y recurrente** que el V1 acotado no cubre. Hoy no existe.
- **Se define un alcance más chico** —un dominio, un tipo de consulta— donde la matriz de casos se pueda cumplir de verdad. Es el camino más probable: no un buscador general, sino varios acotados.
- **Se instrumenta la distancia al umbral** en los casos fallidos, para saber si faltaba poco o mucho.

Lo que **no** es disparador de revisión: que haya pasado el tiempo, que el componente esté ahí sin usarse, o que dé lástima el trabajo invertido. Retomarlo exige rehacer la revalidación con la misma matriz y la misma exigencia de 7/7.

> Última verificación: 2026-08-05
