# ADR-011 — Precedentes verificables en vez de inferencia

El agente no adivina de qué se trata un gasto. Cita una decisión anterior del titular sobre la misma descripción, exacta, no parecida — y si no la tiene, se abstiene.

## Estado

Vigente.

## Fecha

2026-08-05 — implementada en `api/fiscal_motor.mjs` junto con la migración v4.8.

## Contexto

El motor del Agente Fiscal tiene que resolver un problema concreto todos los meses: hay movimientos confirmados, no transferencias, sin `ambito` y sin `deducible`. Alguien tiene que decir si ese gasto fue personal o profesional y si se deduce.

Un modelo de lenguaje puede producir una respuesta para cualquiera de esos movimientos. Ese es exactamente el problema. La descripción de un movimiento tiene entre cinco y cuarenta caracteres, sin contexto, sin contraparte identificada y sin comprobante adjunto en la mayoría de los casos.

El razonamiento quedó escrito en el propio motor, con el ejemplo que define la decisión:

> *«Mirando "cafe con un colega" no hay forma honesta de saber si fue una reunión de trabajo o una salida con un amigo. […] Lo que sí se puede afirmar: "el 12/07 clasificaste un movimiento con esta misma descripción como profesional deducible". Eso es verificable, se puede citar, y el humano puede desmentirlo en un segundo.»*
> — `api/fiscal_motor.mjs`

Las dos frases dicen cosas de naturaleza distinta. La primera es una inferencia sobre el mundo: para sostenerla hay que saber quién es el colega y de qué se habló. La segunda es una afirmación sobre el propio registro: se puede comprobar mirando una fila.

La diferencia importa porque una clasificación fiscal equivocada no falla ruidosamente. Un gasto personal marcado como deducible no rompe nada, no genera un error y no aparece en ningún log. Aparece, eventualmente, en una fiscalización.

## Decisión

**El agente no infiere de qué se trata un gasto. Cita un precedente: una decisión anterior del titular sobre un movimiento con la misma descripción normalizada.**

Un precedente es, con precisión:

- Un movimiento en estado `confirmado`, no transferencia, con `ambito` y `deducible` no nulos, excluyendo el propio movimiento que se está evaluando.
- Cuya **descripción normalizada** coincide: minúsculas, `btrim`, y espacios internos colapsados con `regexp_replace(..., '\s+', ' ', 'g')`.
- Agrupado por la terna `(ambito, deducible, deducible_porcentaje)`, con `veces`, `ultima_vez` y hasta tres ejemplos concretos.

**Coincidencia exacta, no por parecido.** Es la parte contraintuitiva y es deliberada:

> *«"parecido" es un umbral elegido a dedo que produce precedentes que el humano no reconoce como tales, y un precedente que no se reconoce no sirve para decidir.»*

Y el origen de los precedentes es uno solo:

> *«De las decisiones anteriores de Aldo. De ningún otro lado. […] el agente mejora a medida que Aldo decide, sin que nadie lo reentrene. Y el primer mes propone poco, que es lo correcto — todavía no sabe nada.»*

### Las reglas que se derivan

| Regla | Comportamiento |
|---|---|
| Descripción de menos de **5 caracteres** | Abstención. *«"nafta" (5) sirve; "pago" (4) coincide con medio mes»* |
| Sin ningún precedente | Abstención: «necesito tu criterio la primera vez» |
| **Precedentes contradictorios** (más de un grupo distinto) | Abstención. **No elige la mayoría**: *«No elijo la mayoría: la contradicción es el dato interesante.»* |
| Confianza | 1 precedente → **0.60** · 2 o 3 → **0.75** · 4 o más → **0.85**. **Nunca 1** |
| Con un solo precedente | Advertencia extra: «alcanza para sugerir, no para dar por sentado» |
| Ventana temporal | **Ninguna.** El precedente no caduca por antigüedad; se informa `ultima_vez` y decide el humano |
| Advertencia siempre presente | «La propuesta se apoya en un precedente, no en el comprobante de este gasto» |
| Movimientos sin encuadre | **Todos se mencionan**, con propuesta o con motivo de abstención: *«el silencio sobre un movimiento que falta clasificar sería peor que decir "este no lo sé"»* |

Que la confianza nunca llegue a 1 no es una cautela decorativa. Cuarenta precedentes idénticos no convierten la afirmación "esto es deducible" en verdadera: siguen siendo cuarenta decisiones anteriores del mismo humano sobre movimientos con el mismo texto, que es una cosa distinta y más chica. El techo de 0.85 lo dice sin discurso.

## El trade-off, dicho sin adornos

Esta decisión **cubre menos casos** que un clasificador. Es el costo y hay que nombrarlo.

| Dimensión | Precedentes exactos | Inferencia de un modelo |
|---|---|---|
| Cobertura del primer mes | Casi nula: no hay historial | Alta desde el día uno |
| Cobertura en régimen | Solo descripciones repetidas | Toda descripción |
| Alucinación | **Cero**: no hay afirmación sobre el mundo que sostener | Posible, y plausible al leerla |
| Verificabilidad por el humano | Un segundo: se cita fecha y clasificación anterior | Requiere reconstruir el razonamiento |
| Mejora con el uso | Sí, sin reentrenar nada | Requiere reentrenar o cambiar el prompt |
| Modo de falla | Silencio: «necesito tu criterio» | Silencioso y plausible |

La columna que decide es la última. Un clasificador que se equivoca produce una clasificación equivocada con apariencia de correcta, y nadie la va a revisar porque se ve bien. El motor de precedentes que no sabe produce una línea que dice «necesito tu criterio», que es incómoda de leer y trivial de detectar.

Y la asimetría de la anteúltima fila también cuenta: el sistema mejora a medida que el titular decide, sin nadie que lo reentrene. El primer mes propone poco. Eso es lo correcto: todavía no sabe nada.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Precedente por descripción exacta normalizada** | Cero alucinación; afirmación citable y desmentible en un segundo; mejora sola con el uso | Cobertura baja al principio y en descripciones únicas | **Elegida** |
| Similitud por texto (distancia de edición, embeddings) | Mucha más cobertura; agrupa variantes de la misma descripción | El umbral lo elige alguien a dedo y produce precedentes que el humano no reconoce como suyos. Un precedente que no se reconoce no sirve para decidir | Rechazada |
| Clasificador con un modelo de lenguaje sobre la descripción | Cobertura total desde el día uno | Produce una respuesta para todo, incluido aquello sobre lo que no hay información. Es el modo de falla silencioso que este sistema trata como el peligroso | Rechazada |
| Reglas escritas a mano por categoría de comercio | Explícitas, auditables | Hay que mantenerlas; envejecen; y el mismo comercio puede dar lugar a un gasto personal y a uno profesional el mismo mes | Postergada |
| Elegir la mayoría cuando hay precedentes contradictorios | Más propuestas, menos preguntas | La contradicción es justamente la señal de que la descripción no determina la clasificación. Taparla con una mayoría destruye el único dato útil | Rechazada |
| Caducar los precedentes viejos (ventana de N meses) | Evita arrastrar criterios abandonados | El corte sería arbitrario y ocultaría precedentes válidos. Se informa `ultima_vez` y decide el humano | Rechazada |

## Consecuencias

### Positivas

- **Ninguna afirmación del agente sobre un gasto es inventada.** Todo lo que dice se puede comprobar mirando una fila de `movimientos`.
- **El humano puede desmentir en un segundo.** La propuesta cita fecha y clasificación anterior; no hay que reconstruir un razonamiento.
- **El sistema aprende del titular sin reentrenamiento.** Cada decisión humana es material para la siguiente propuesta.
- **La contradicción se conserva como información.** Dos criterios distintos para la misma descripción es un dato que llega al humano en vez de resolverse por dentro.
- **La confianza no miente.** El techo de 0.85 declara que el mecanismo tiene un límite estructural, no que le falte calibración.

### Negativas

- **El primer mes casi no propone nada.** Es correcto y es frustrante.
- **Las descripciones únicas nunca van a tener precedente.** Un gasto que ocurre una sola vez se clasifica siempre a mano.
- **Descripciones inconsistentes rompen la coincidencia.** «Nafta YPF» y «nafta ypf ruta 9» son, para el motor, dos cosas distintas. La normalización arregla mayúsculas y espacios, nada más.
- **El precedente no mira el comprobante.** Por eso la advertencia fija: la propuesta se apoya en cómo se clasificó antes, no en la evidencia de este gasto en particular.
- **Un criterio equivocado del pasado se propaga.** Si el titular clasificó mal en julio, el motor va a citar julio en agosto. Lo citado es verificable, pero la cita no vuelve correcto el precedente.

### Operativas

- El diagnóstico menciona **todos** los movimientos sin encuadre, aunque no tenga nada que proponer para ellos. La lista «necesitan tu criterio» es parte del entregable, no una excepción.
- El umbral de 5 caracteres es un valor del código (`MINIMO_DESCRIPCION`), expuesto en el objeto congelado `MOTOR`. Cambiarlo es un cambio de código con test.
- Escribir descripciones consistentes al cargar movimientos mejora directamente la cobertura del motor. Es la única palanca del usuario sobre este mecanismo.

### De seguridad

- Es una decisión de integridad de la información antes que de seguridad de acceso. Una clasificación fiscal inventada con apariencia de fundada es el mismo problema que documenta el [ADR-006](adr-006-buscador-general-no-publicado.md) para una respuesta sin fuentes: indistinguible de lo bueno hasta que alguien la audita.
- Se alinea con el principio del contrato: *«La ausencia de datos no debe convertirse en un dato inventado.»*
- El motor **no escribe** en tablas financieras: un test verifica que no hay UPDATE ni INSERT sobre ellas, y otro que el diagnóstico no clasificó ningún movimiento por su cuenta.

## Evidencia

| Afirmación | Estado |
|---|---|
| Definición de precedente: descripción normalizada, `confirmado`, no transferencia, `ambito` y `deducible` no nulos | `Verificado` |
| Coincidencia exacta, no por similitud, con su justificación textual | `Verificado` |
| `MINIMO_DESCRIPCION = 5` y su ejemplo («nafta» vs. «pago») | `Verificado` |
| Escala de confianza 0.60 / 0.75 / 0.85 y que nunca llega a 1 | `Verificado` — test dedicado |
| Abstención ante precedentes contradictorios, sin elegir mayoría | `Verificado` — test dedicado |
| Ausencia de ventana temporal; se informa `ultima_vez` | `Verificado` |
| Todo movimiento sin encuadre queda mencionado | `Verificado` — test `todo movimiento mencionado` |
| Citas de `api/fiscal_motor.mjs` (cabecera, `candidataParaMovimiento()`) | `Verificado` |
| Cobertura real del motor en un mes de producción (qué porcentaje de movimientos recibe propuesta) | `Pendiente de verificar` — no medido |
| Cuántas propuestas por precedente fueron rechazadas por el humano | `Pendiente de verificar` — no instrumentado |

## Disparador de revisión

Este ADR se revisa si ocurre alguna de estas cosas:

- **Se mide la cobertura y resulta inútilmente baja** después de varios meses de historial. Hoy no está medida, y ese es el primer paso de cualquier revisión.
- **Se mide la tasa de rechazo de las propuestas por precedente.** Si es alta, el problema no es la cobertura sino que el precedente no predice; sería un argumento fuerte contra el mecanismo entero.
- **Aparece una fuente de evidencia mejor que el precedente** — comprobante vinculado con razón social y concepto, por ejemplo. Ahí se podría afirmar algo sobre el gasto en vez de sobre el historial, y la decisión cambia de fundamento.
- **Se decide agrupar variantes de descripción** con una regla explícita, escrita y probada, que el humano pueda leer y predecir. No un umbral de similitud: una normalización más ambiciosa y determinista.

Lo que **no** es disparador: que el agente proponga poco, que sea tedioso clasificar a mano, o que un modelo de lenguaje disponible parezca bueno clasificando gastos en una prueba informal.

> Última verificación: 2026-08-06
