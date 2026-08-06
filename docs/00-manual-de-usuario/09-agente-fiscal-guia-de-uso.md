# El Agente Fiscal — guía de uso

Cómo pedirle el diagnóstico de un mes, cómo se leen sus propuestas, por qué aprobar no cambia nada todavía y qué hacer cuando un cierre no avanza.

## Antes de empezar: qué es y qué no es

El Agente Fiscal es la parte del sistema que **mira** tus movimientos ya cargados y te dice qué falta para poder cerrar un mes. No es un contador y no es un trámite.

**Lo que hace por vos:**

- Te dice en qué estado está el cierre de un mes y qué le falta.
- Te lista los vencimientos del período, marcando primero los que ya vencieron y siguen impagos.
- Te avisa qué movimientos quedaron sin clasificar.
- Te **propone** cómo clasificar algunos de ellos, citando cómo clasificaste vos antes un movimiento con la misma descripción.
- Te señala inconsistencias: una deuda que figura pagada sin ningún pago registrado, un comprobante duplicado, un monto que parece mal leído.
- Te arma un borrador del cierre y te lo exporta.

**Lo que no va a hacer nunca:**

- **No presenta ni paga nada ante el organismo fiscal (ARCA).** Está fuera de alcance por contrato. Si el sistema dice que un período está "presentado", es porque **vos** cargaste el número de acuse de una presentación que hiciste por otro lado.
- No modifica tus movimientos. No cambia saldos, no crea pagos, no anula nada.
- No decide si te conviene monotributo ni en qué categoría. Eso es de tu contador.
- No decide si una obligación del catálogo realmente te aplica. El catálogo es *una ayuda para no olvidarse*, no una determinación fiscal.
- No aprueba sus propias propuestas. No puede: la credencial con la que trabaja recibe un rechazo del servidor si lo intenta.

Esa última línea es el corazón del diseño y está desarrollada en el [ADR-010](../04-decisiones/adr-010-el-agente-propone-el-humano-decide.md). Para usar el sistema alcanza con quedarse con esto: **todo lo que tenga consecuencia lo decidís vos.**

---

## Pedirle el diagnóstico de un mes

Es una sola llamada:

```
GET /api/fiscal-diagnostico?periodo=202607&proposito=cierre de julio
```

El `periodo` va en formato **AAAAMM**: cuatro dígitos de año y dos de mes. `202607` es julio de 2026. Si el formato está mal, no adivina: devuelve `AMBIGUOUS_PERIOD` y no hace nada.

El `proposito` es un texto libre y corto que explica para qué pedís el análisis. Queda registrado. No es burocracia: es lo que después permite entender por qué se consultó algo.

### Mirar y registrar son dos cosas distintas

Hay un parámetro más, y conviene entenderlo bien:

| Llamada | Qué pasa |
|---|---|
| `...?periodo=202607` | **Mirás.** El agente analiza el mes y te devuelve el diagnóstico. No queda nada guardado |
| `...?periodo=202607&registrar=true` | **Mirás y quedan registradas las propuestas.** Cada propuesta se guarda como pendiente, esperando que la apruebes o la rechaces |

Por defecto **no registra**. Es a propósito:

> *«leer el estado de un mes no debería tener efectos, y por eso registrar hay que pedirlo aparte y a propósito»*

En la práctica: mirá primero sin registrar, leé el diagnóstico, y recién cuando estés por sentarte a decidir, pedilo de nuevo con `registrar=true`. Si registrás dos veces lo mismo, el sistema no duplica nada — reconoce que es la misma pregunta y no la vuelve a hacer.

---

## Cómo se lee un diagnóstico

El diagnóstico viene con un campo `mensaje` escrito en castellano, listo para leer. El orden de los bloques no es casual: está pensado para que si dejás de leer a la mitad, ya hayas visto lo urgente.

### Los bloques, en orden

| # | Bloque | Qué te está diciendo |
|---|---|---|
| 1 | **Encabezado** | Qué período, qué contribuyente y en qué estado está el cierre |
| 2 | **Régimen del período** | Bajo qué condición fiscal estabas **en ese mes**, no hoy. Si el sistema no pudo determinarla, la advertencia aparece acá arriba, antes que cualquier número |
| 3 | **Vencimientos vencidos e impagos** | Lo urgente. Va primero |
| 4 | **Vencimientos del período** | Lo que vence dentro del mes que estás mirando |
| 5 | **Obligaciones sin importe determinado** | Sabés que existen, todavía no sabés cuánto |
| 6 | **Saldo impago, por moneda** | Separado por moneda, siempre |
| 7 | **Obligaciones que el régimen implica y no están cargadas** | Salen de un catálogo general. Confirmalo con tu contador |
| 8 | **Bloqueantes del cierre** | Qué impide declarar el mes listo |
| 9 | **Propuestas** | Lo que el agente sugiere, con su fundamento |
| 10 | **Necesitan tu criterio** | Los movimientos sobre los que no se anima a sugerir nada |

### Por qué los vencimientos impagos van primero

Porque el resto puede esperar y eso no:

> *«un vencimiento impago acumula intereses todos los días y no espera a que alguien lea hasta el final»*

Es una decisión de redacción, no un detalle estético. Si abrís el mensaje en el celular y leés tres líneas, esas tres líneas tienen que ser las que cuestan plata por día.

### Dos cosas que el diagnóstico nunca hace

**No suma monedas.** Si tenés obligaciones en pesos y en dólares, vas a ver dos saldos separados. No hay un total "equivalente": convertir con un tipo de cambio que nadie acordó produce un número que se ve bien y está mal.

**No mezcla contribuyentes.** Un diagnóstico es siempre de una sola persona. Si hay varios contribuyentes activos y no aclaraste cuál, el agente **da error en vez de elegir**, porque *«un diagnóstico atribuido a la persona equivocada es peor que ninguno, porque parece correcto»*.

---

## Las propuestas

### Qué es una propuesta

Una propuesta es una sugerencia de clasificación con su fundamento, guardada como registro. Tiene un criterio propuesto, una explicación, un nivel de confianza, la evidencia en que se apoya, sus advertencias, y un estado.

Lo importante es de dónde sale el fundamento. **El agente no adivina de qué se trata tu gasto.** Cita cómo lo clasificaste vos antes:

> *«Mirando "cafe con un colega" no hay forma honesta de saber si fue una reunión de trabajo o una salida con un amigo. […] Lo que sí se puede afirmar: "el 12/07 clasificaste un movimiento con esta misma descripción como profesional deducible". Eso es verificable, se puede citar, y el humano puede desmentirlo en un segundo.»*

Por eso toda propuesta viene con esta advertencia fija: *la propuesta se apoya en un precedente, no en el comprobante de este gasto*. El detalle está en el [ADR-011](../04-decisiones/adr-011-precedentes-verificables-en-vez-de-inferencia.md).

### El nivel de confianza

Es un número entre 0 y 1 que depende de **cuántas veces** clasificaste antes algo con esa misma descripción:

| Precedentes | Confianza |
|---|---|
| 1 | 0.60 — con una advertencia extra: «alcanza para sugerir, no para dar por sentado» |
| 2 o 3 | 0.75 |
| 4 o más | 0.85 |

**Nunca llega a 1.** No importa cuántas veces hayas clasificado igual: el agente no tiene forma de saber que este gasto en particular es lo mismo que los anteriores. Si ves confianza por debajo de 0.70, la propuesta viene además con un warning automático.

### Cómo se aprueba o se rechaza

```
POST /api/fiscal-propuestas/decidir
```

Necesitás tres cosas, y las tres son obligatorias:

- El identificador de la propuesta.
- El estado: `aprobada` o `rechazada`. No hay otra opción — *caducar lo hace el sistema*, no vos.
- **Tu firma y tu motivo.** Sin aprobador no se registra, porque *«una decisión sin firma humana no es una decisión»*, y sin motivo tampoco, incluso cuando aprobás.

Esto último molesta la primera vez y después se agradece: dentro de seis meses, la pregunta no va a ser qué decidiste sino por qué.

### Aprobar no aplica nada

Es lo más importante de este capítulo y lo más fácil de malentender.

> *«**REGLA:** La aprobación no ejecuta nada financieramente.»*

Cuando aprobás una propuesta, el sistema registra que estuviste de acuerdo. Eso es todo. La respuesta te lo dice con todas las letras: *«Aprobada. Esto NO ejecutó ningún cambio financiero: queda registrada la decisión. Aplicarla es un acto separado.»*

**Aplicarla es otro paso**, por las rutas de clasificación normales. Son dos actos porque tienen que poder fallar por separado: estar de acuerdo con un criterio y querer que se escriba ahora no son la misma cosa.

Si aprobaste todo y el cierre sigue bloqueado, no es un error: es esto.

### Una decisión no se cambia, se reconsidera

Los tres estados finales —`aprobada`, `rechazada`, `caducada`— son **terminales**. No se vuelve atrás.

Si cambiás de idea, se crea una propuesta nueva que apunta a la vieja, con un motivo de reconsideración obligatorio. La razón:

> *«Una decisión humana registrada es evidencia: si después hay que cambiar de idea, se crea una propuesta nueva que apunta a esta. Reescribir la vieja borraría el hecho de que se decidió distinto, que suele ser el dato más importante de los dos.»*

Y el sistema **no te repregunta lo que ya decidiste**. Si el agente vuelve a analizar el mismo mes y llega a la misma pregunta, se encuentra con tu decisión anterior y no la registra de nuevo: *«Repreguntar lo ya decidido, sin motivo, es desgastar al aprobador hasta obtener un sí.»*

---

## Por qué a veces dice «necesito tu criterio»

Porque no tiene precedente en el cual apoyarse. Hay cuatro situaciones y todas terminan igual:

| Situación | Por qué se abstiene |
|---|---|
| Es la primera vez que aparece esa descripción | No hay nada que citar. «Necesito tu criterio la primera vez» |
| La descripción tiene menos de 5 caracteres | Demasiado corta para identificar nada: *«"nafta" (5) sirve; "pago" (4) coincide con medio mes»* |
| Clasificaste distinto la misma descripción en el pasado | **No elige la mayoría.** *«La contradicción es el dato interesante»* |
| La descripción es parecida pero no idéntica a otra | La coincidencia es **exacta**, no por parecido. Un precedente que no reconocés como tuyo no te sirve para decidir |

**Qué tenés que hacer:** clasificar ese movimiento a mano, como siempre. Y con eso, sin que nadie reentrene nada, el agente queda en condiciones de proponer la próxima vez que aparezca la misma descripción.

Por eso el primer mes propone muy poco. Es correcto: todavía no sabe nada.

Lo que **no** va a pasar es que un movimiento sin clasificar se le escape. Todos aparecen en el diagnóstico, con propuesta o con el motivo de por qué no la hay: *«el silencio sobre un movimiento que falta clasificar sería peor que decir "este no lo sé"»*.

---

## Por qué a veces una propuesta aparece «caducada»

Porque **la evidencia cambió entre que se generó la propuesta y el momento en que fuiste a aprobarla**.

Cuando el agente crea una propuesta, guarda una huella de las filas en las que se apoya: el movimiento con su fecha, su monto, su moneda, su descripción, su clasificación. Cuando vas a aprobar, el sistema **vuelve a leer esas filas** y compara. Si cambiaron, no te deja aprobar: marca la propuesta como `caducada` y te devuelve un aviso de datos inconsistentes.

> *«Aprobar un texto que ya no describe la realidad es peor que no tener propuesta.»*

Ejemplo concreto: el agente propone clasificar un movimiento como profesional deducible. Antes de que decidas, corregís el monto de ese movimiento porque estaba mal cargado. La propuesta describía otra cosa. Caduca.

Dos detalles que importan:

- **No caduca sola con el tiempo.** La huella se calcula deliberadamente sin `actualizado_en` ni ningún campo que se mueva por su cuenta: *«una propuesta que caduca sin que nadie haya cambiado nada enseña a la gente a ignorar el aviso»*. Si caducó, alguien cambió algo.
- **Rechazar no revalida.** Podés rechazar una propuesta aunque su evidencia haya cambiado: *«decir "no" a algo que ya no aplica sigue siendo una respuesta válida»*.

**Qué tenés que hacer:** volver a pedir el diagnóstico con `registrar=true`. El agente vuelve a mirar el movimiento como está ahora y, si corresponde, genera una propuesta nueva.

---

## Qué bloquea un cierre y cómo destrabarlo

Un mes recorre seis estados: `abierto` → `en_revision` → `listo_para_aprobar` → `aprobado` → `presentado`, con `reabierto` como vuelta atrás. No se saltea ninguno; la base rechaza los saltos y te devuelve, en el propio error, el recorrido correcto.

El paso que se traba es siempre el mismo: **para declarar un mes `listo_para_aprobar` tiene que haber cero bloqueantes**. No hay forma de forzarlo:

> *«no hay parámetro para forzarlo — si lo hubiera, alguien lo usaría»*

### Los bloqueantes y cómo se resuelve cada uno

| Bloqueante | Qué significa | Qué hacer |
|---|---|---|
| `movimientos_pendientes` | Hay movimientos que nunca confirmaste | Confirmalos o anulalos |
| `sin_clasificar` | Hay movimientos sin `ambito` o sin `deducible` | Clasificalos. Es lo que el diagnóstico lista como «sin encuadre» |
| `posibles_duplicados` | Un movimiento quedó marcado como posible duplicado de otro | Revisá el par y anulá el que sobra, o desmarcá si son dos gastos reales |
| `gastos_sin_comprobante` | Hay gastos deducibles sin comprobante cargado | Cargá el comprobante o sacale el deducible |
| `ingresos_sin_comprobante` | Ingresos sin respaldo documental | Cargá el comprobante |
| `descalce_comprobante` | El total de un comprobante y lo imputado a movimientos difieren en más de un centavo | Revisá la imputación |
| `reglas_sin_verificar` | Una regla usada en el período está marcada como ficticia o sin verificar | Verificá la regla y cargale su fuente |
| `sin_perfil_fiscal` | No hay condición fiscal vigente registrada para ese período | Cargá el perfil fiscal con su vigencia |

Cada bloqueante trae **los identificadores concretos** de lo que hay que arreglar: *«decir "hay 3 problemas" sin decir cuáles no sirve de nada»*.

Hay además cinco avisos que **no** bloquean: transferencias sin conciliar, documentos sin procesar, comprobantes observados, IVA sin desglose y períodos inconsistentes. Conviene mirarlos igual.

### Los dos pasos finales

- **`aprobado`** congela el resumen: los totales del mes quedan como una foto. Si más adelante la base devuelve otra cosa, es que alguien tocó un movimiento de un período cerrado, y eso se ve.
- **`presentado`** exige que cargues una **evidencia**: número de acuse, comprobante o referencia de la presentación que hiciste vos. *«Esta API no presenta nada por sí misma.»*

### Cómo se reabre un mes

Desde `aprobado` o desde `presentado` se pasa a `reabierto`, y ahí es obligatorio un **motivo**. De `reabierto` se vuelve a `en_revision` y se rehace el recorrido.

Mientras un mes está `aprobado` o `presentado`, **no se pueden clasificar sus movimientos**. El mensaje es explícito: *«Reabrí el cierre antes de modificar su clasificación fiscal»*.

---

## Cuando dice que no encontró nada

Vas a ver, con esas palabras:

> *«No encontré nada pendiente. Eso significa que los chequeos y detectores que existen no ven nada, no que el período esté necesariamente perfecto.»*

Esa segunda mitad no es una fórmula de descargo. Es lo que la respuesta significa de verdad, y está escrito así también en el contrato:

> *«Una lista vacía significa únicamente que no existen discrepancias abiertas registradas o detectadas según las fuentes, reglas y alcance consultados. No demuestra por sí sola la ausencia de errores, omisiones o discrepancias no detectadas.»*

Traducido: el sistema tiene trece detectores y trece chequeos. Cubren lo que cubren. Un gasto personal cargado como profesional con la descripción correcta y su comprobante en regla **no lo detecta nadie**, porque no hay nada anómalo que detectar.

**Qué hacer con un "no encontré nada":** tomarlo como lo que es —ninguno de los controles automáticos se disparó— y hacer igual la revisión que harías sin el sistema. Un mes limpio según los chequeos sigue siendo un mes que conviene mirar antes de aprobarlo.

Y si en vez de "no encontré nada" te devuelve `SOURCE_UNAVAILABLE`, es otra cosa distinta y más honesta: significa que **no pudo terminar el análisis** y por eso no te da resultados parciales. Un resultado a medias se leería como "no hay problemas". Está explicado en el [ADR-013](../04-decisiones/adr-013-abstenerse-antes-que-devolver-un-resultado-parcial.md).

---

## Síntoma → causa probable → qué hacer

| Síntoma | Causa más probable | Qué hacer |
|---|---|---|
| «Aprobé todas las propuestas y el cierre sigue bloqueado» | Aprobar registra la decisión, no la aplica | Aplicá la clasificación por la ruta de clasificación. Después volvé a correr el diagnóstico |
| El diagnóstico no trae ninguna propuesta | Primer mes, o descripciones que nunca se repitieron | Normal. Clasificá a mano; el mes que viene va a proponer más |
| Una propuesta figura «caducada» | Cambió el movimiento en el que se apoyaba | Pedí el diagnóstico de nuevo con `registrar=true` |
| «Ya rechacé esto y no me lo vuelve a proponer» | La huella impide repreguntar lo ya decidido | Es lo esperado. Si querés reabrir el tema, hay que reconsiderar con un motivo escrito |
| Dice «necesito tu criterio» en muchos movimientos | Sin precedentes, descripciones cortas, o precedentes contradictorios | Clasificá a mano. Escribir descripciones consistentes al cargar mejora esto directamente |
| Devuelve `AMBIGUOUS_PERIOD` | El período no está en formato AAAAMM | Corregí el formato: `202607`, no `2026-07` ni `julio` |
| Devuelve error al resolver el contribuyente | Hay varios contribuyentes activos y no aclaraste cuál | Indicá el código del contribuyente. El agente no elige por vos |
| Devuelve `SOURCE_UNAVAILABLE` | Una de las fuentes que necesitaba no respondió | No es un resultado vacío: es una abstención. Reintentá y, si persiste, escalá |
| Dice «No hay condición fiscal vigente» y sí la hay | Puede ser el bug conocido del chequeo 13 con regímenes en estado `historico`, al cerrar períodos viejos | Verificá el perfil. Si la condición existe en histórico, es el bug documentado, no un dato tuyo faltante |
| El saldo impago aparece dividido en dos | Tenés obligaciones en más de una moneda | Es correcto. No se suman monedas distintas |
| No puedo clasificar un movimiento de un mes viejo | El cierre de ese mes está `aprobado` o `presentado` | Reabrí el cierre con un motivo, clasificá, y rehacé el recorrido |
| No llegó ningún aviso a fin de mes | El disparo mensual automático **todavía no existe** | Pedí el diagnóstico a mano. El workflow mensual sigue siendo un pendiente conocido |

---

## Lo que todavía no está

Para que no lo busques:

- **El aviso mensual automático no existe.** El workflow de n8n es un esqueleto con disparo manual y período fijo. Hoy el diagnóstico se pide a mano.
- **No hay panel para aprobar propuestas.** Se decide por API. El mecanismo definitivo —panel web o Telegram— es una decisión abierta.
- **Las plantillas reales de obligaciones no están cargadas** con sus importes vigentes.
- El detalle completo de límites y deudas está en la [ficha del subsistema](../../systems/praxia-agente-fiscal/limites-y-deudas.md).

---

## Para seguir leyendo

- [04 — PraxIA Finanzas, guía de uso](04-praxia-finanzas-guia-de-uso.md) — cargar movimientos, deudas y comprobantes, que es lo que el agente después lee
- [07 — Cuando algo falla](07-cuando-algo-falla.md) — diagnóstico general del sistema
- [08 — Glosario](08-glosario.md) — los términos que aparecen acá
- [Runbook: cierre fiscal mensual](../06-runbooks/cierre-fiscal-mensual.md) — el procedimiento paso a paso, con casillas
- [Ficha del Agente Fiscal](../../systems/praxia-agente-fiscal/README.md) — cómo está construido por dentro

> Última verificación: 2026-08-06
