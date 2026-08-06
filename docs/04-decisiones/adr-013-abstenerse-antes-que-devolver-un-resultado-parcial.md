# ADR-013 — Abstenerse antes que devolver un resultado parcial

Si un detector de discrepancias falla, la operación entera se abstiene en vez de devolver los hallazgos que sí encontró. Porque un resultado parcial se lee como «no hay discrepancias».

## Estado

Vigente.

## Fecha

2026-08-04 — establecida con la capa de lectura y el contrato Finanzas↔Fiscal v1.0. Extendida al motor de diagnóstico el 2026-08-05.

## Contexto

`ConsultarDiscrepanciasAbiertas` corre **13 detectores** y devuelve los hallazgos ordenados por severidad, cada uno con las dos evidencias del choque. Los detectores van de `deuda_pagada_sin_evidencia` (alta) a `movimiento_pendiente_antiguo` (baja).

La pregunta de diseño es qué hacer cuando uno de los trece falla —una consulta que revienta, una tabla inaccesible, un error de tipo—. La respuesta natural en cualquier API es devolver los doce que sí corrieron, quizás con un warning. Es más útil que nada, se dice.

No lo es. Y la razón está en cómo se lee la respuesta, no en cómo se produce.

> *«Una lista vacía significa únicamente que no existen discrepancias abiertas registradas o detectadas según las fuentes, reglas y alcance consultados. No demuestra por sí sola la ausencia de errores, omisiones o discrepancias no detectadas.»*
> — Contrato §7, `ConsultarDiscrepanciasAbiertas`

Esa cláusula está en el contrato porque una lista vacía es la respuesta más peligrosa que puede dar el sistema: es indistinguible de «está todo bien», y **nadie va a investigar un resultado tranquilizador**. Un resultado parcial es peor todavía, porque además viene con hallazgos reales que le dan credibilidad. Si el detector caído era `movimiento_no_coincide_con_su_comprobante` y los otros doce devolvieron tres avisos menores, el lector concluye que revisó todo y que lo que hay es menor.

Esto es una instancia del patrón de riesgo que gobierna el diseño entero del subsistema:

> *«Un sistema fiscal falla de dos maneras muy distintas: ruidosamente […] y en silencio: devuelve algo plausible y equivocado. La segunda es la peligrosa.»*

Un error que rompe la pantalla se arregla el mismo día. Un informe plausible y equivocado se archiva, se cita y se presenta.

## Decisión

**Cuando una operación no puede completarse tal como fue especificada, devuelve un código de abstención en vez de un resultado parcial.**

Dos aplicaciones concretas:

### 1 · Discrepancias

Si **cualquiera** de los 13 detectores falla, la operación devuelve `SOURCE_UNAVAILABLE`. No devuelve los hallazgos de los otros doce.

> *«un resultado parcial se leería como "no hay discrepancias"»*

### 2 · Diagnóstico del período

`diagnosticarPeriodo()` arranca con un `Promise.all` de cinco lecturas: estado del cierre, `cierre_chequeos()`, movimientos sin encuadre, régimen del período y obligaciones del período. Cualquier excepción en cualquiera de las cinco produce `SOURCE_UNAVAILABLE`.

> *«Un diagnóstico parcial se leería como "no falta nada más". Abstención.»*

La misma lógica se aplica antes, en la resolución del contribuyente: si hay varios activos y no se especificó cuál, el motor **da error en vez de elegir**, porque *«un diagnóstico atribuido a la persona equivocada es peor que ninguno, porque parece correcto»*.

### Los nueve códigos de abstención

Son los del contrato §15. No son códigos de error genéricos: cada uno nombra una razón distinta por la cual el sistema decide no afirmar nada.

| Código | Cuándo |
|---|---|
| `RECORD_NOT_FOUND` | El registro pedido no existe. Proponer sobre un registro ausente es proponer sobre nada |
| `INSUFFICIENT_EVIDENCE` | Falta información necesaria para sostener la respuesta |
| `UNAUTHORIZED_ACCESS` | La credencial no alcanza para lo pedido |
| `INCOMPATIBLE_CONTRACT_VERSION` | El cliente habla una versión del contrato que no es ésta |
| `CORRUPT_DATA` | Los datos leídos son internamente inconsistentes. Es lo que devuelve una aprobación contra evidencia que cambió |
| `UNKNOWN_CURRENCY` | Una moneda que el sistema no sabe tratar. No se convierte por las dudas |
| `AMBIGUOUS_PERIOD` | El período no se puede determinar sin adivinar. Es lo que devuelve un `periodo` mal formado |
| `SOURCE_UNAVAILABLE` | Una fuente necesaria no respondió. **Es el que produce la abstención total ante un detector caído** |
| `INVALID_DATE_RANGE` | El rango de fechas no tiene sentido |

Que sean nueve y estén nombrados importa más de lo que parece. Un sistema con un solo código de error tiene un modo de falla; uno con nueve razones distintas de abstención tiene nueve situaciones que alguien se sentó a pensar. La abstención está **codificada, no sugerida**: no depende de que el llamador interprete un warning.

### Coherente con el resto

La misma disciplina aparece en todo el subsistema, y ése es el argumento de que es una decisión y no una costumbre:

- El motor **se abstiene** ante precedentes contradictorios en vez de elegir la mayoría ([ADR-011](adr-011-precedentes-verificables-en-vez-de-inferencia.md)).
- El régimen del período devuelve `condicion: null` más una advertencia si `regimen_vigente()` trae cero filas o más de una, en vez de tomar la primera.
- El resumen por período emite **ceros explícitos con `sin_datos: true`** para los meses vacíos, en vez de omitir el mes. Un mes ausente y un mes sin movimientos son cosas distintas.
- Las monedas **no se suman nunca**: *«Moneda: Original conservada; no sumar monedas distintas sin política aprobada.»* Un total en «pesos equivalentes» calculado con un tipo de cambio no acordado es un número plausible y equivocado.
- El detector del separador de miles señala el par sospechoso y **no elige cuál de los dos montos está mal**.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Abstención total con código tipado** | Nunca se lee un resultado incompleto como completo; la falla es ruidosa y el llamador tiene que decidir qué hacer | Un detector caído deja al usuario sin ninguno de los otros doce hallazgos | **Elegida** |
| Devolver los detectores que corrieron, con un warning | Máxima utilidad inmediata; algo es mejor que nada | Los warnings se ignoran, sobre todo cuando vienen junto a hallazgos reales que dan credibilidad al conjunto. El resultado se lee como completo | Rechazada |
| Devolver parcial con el resultado marcado `incompleto: true` en la raíz | Más difícil de ignorar que un warning | Sigue dependiendo de que el consumidor —una persona apurada, un workflow de n8n, un modelo de lenguaje resumiendo— mire el campo. El MCP devuelve el envelope tal cual justamente porque *«las advertencias y las discrepancias son parte de la respuesta, no decoración»*, y aun así la lectura humana salta al contenido | Rechazada |
| Reintentar el detector caído y devolver parcial si falla de nuevo | Atenúa fallas transitorias | El reintento es compatible con la abstención, no una alternativa. Si después de reintentar falla, el problema sigue siendo qué devolver | Postergada |
| Marcar el detector caído como «sin hallazgos» | Respuesta uniforme, código simple | Es afirmar que no hay discrepancias de ese tipo, que es exactamente lo que no se sabe. Convierte una falla en un dato falso | Rechazada |

## Consecuencias

### Positivas

- **Una respuesta del sistema significa lo que dice.** Si hay hallazgos, los trece detectores corrieron.
- **La falla es ruidosa.** `SOURCE_UNAVAILABLE` obliga a alguien a mirar por qué. Un parcial con warning no obliga a nada.
- **La abstención es un estado de primera clase**, con nueve razones nombradas, no un error genérico ni un `null`.
- **El contrato ya advierte que ni siquiera una lista vacía prueba ausencia de errores.** La abstención cierra el flanco restante: que un parcial se disfrace de completo.
- **Es demostrable.** Hay un test de abstención con la base caída, y otro que verifica que los 9 códigos del §15 existen y se usan.

### Negativas

- **Un detector roto deja al usuario sin los otros doce.** Es el costo directo, y en un mes con problemas reales duele.
- **Un diagnóstico entero se pierde por una sola lectura fallida** de las cinco del `Promise.all`.
- **La disponibilidad aparente baja.** El sistema dice «no puedo» más veces de las que un sistema tolerante diría algo.
- **Hace falta observabilidad para saber qué se rompió.** Hoy la auditoría de consultas es una línea al log del proceso y **no se persiste**: escribirla en una tabla exigiría un permiso de INSERT que el rol fiscal no debe tener.

### Operativas

- Un `SOURCE_UNAVAILABLE` no es «el sistema está caído»: es «no puedo responder esto ahora». Hay que saber leerlo, y por eso está en el manual de usuario.
- El envelope siempre trae `request_id`, `query_hash` y `trace_context`, incluso en la abstención. Una abstención sin identificador sería una abstención imposible de investigar.
- El motor **no reimplementa** los chequeos del cierre: llama a `praxia_finanzas.cierre_chequeos()`. Hay un test que lo verifica. Reimplementarlos sería crear una segunda fuente que puede fallar por su cuenta y contradecir a la primera.
- Todo lo que sale por HTTP con `status === 'error'` es un **422**, no un 500: es una respuesta válida del contrato, no una caída.

### De seguridad

- Es una decisión de integridad de la información. Un informe fiscal incompleto con apariencia de completo puede terminar respaldando una presentación.
- Se alinea con el principio del contrato: *«La ausencia de datos no debe convertirse en un dato inventado.»* Un resultado parcial presentado como total convierte una ausencia en un dato: el dato falso de que no hay nada más.
- El mismo criterio que el [ADR-006](adr-006-buscador-general-no-publicado.md) aplicado a otro componente: es preferible no responder a responder algo indistinguible de lo bueno.

## Evidencia

| Afirmación | Estado |
|---|---|
| 13 detectores en `ConsultarDiscrepanciasAbiertas` | `Verificado` |
| Un fallo de cualquier detector produce `SOURCE_UNAVAILABLE`, no resultado parcial | `Verificado` |
| Los nueve códigos de abstención del contrato §15 | `Verificado` |
| `diagnosticarPeriodo()` devuelve `SOURCE_UNAVAILABLE` ante cualquier excepción de las cinco lecturas | `Verificado` |
| `AMBIGUOUS_PERIOD` ante un `periodo` que no cumple el formato AAAAMM | `Verificado` |
| El motor da error en vez de elegir cuando hay varios contribuyentes activos sin código | `Verificado` |
| Ceros explícitos con `sin_datos: true` en meses vacíos del resumen | `Verificado` |
| Monedas nunca sumadas sin política aprobada | `Verificado` |
| Test de abstención ante base caída y test de existencia de los 9 códigos | `Verificado` |
| Citas del contrato §7 y §2, y de `api/fiscal_lectura.mjs` y `api/fiscal_motor.mjs` | `Verificado` |
| Cuántas veces se devolvió una abstención en producción, y por qué código | `Pendiente de verificar` — la auditoría de consultas no se persiste |
| Si algún consumidor trata `SOURCE_UNAVAILABLE` como «no hay nada» | `Pendiente de verificar` — no auditado |

## Disparador de revisión

Este ADR se revisa si ocurre alguna de estas cosas:

- **Se persiste la auditoría de consultas** —por un componente aparte que recoja el log, que es la única forma compatible con el rol de solo lectura—. Con esa medición se sabría cuántas abstenciones hay y por qué, que es el dato que falta para discutir el costo real.
- **Un detector falla de forma recurrente** y bloquea la operación mes tras mes. La respuesta correcta es arreglar el detector; si no se puede, habría que decidir explícitamente entre retirarlo del conjunto y aceptar el parcial, y esa decisión merece su propio registro.
- **Aparece un consumidor que necesita resultados parciales** con una razón concreta y un manejo declarado de la incompletitud. Sería una operación distinta, con otro nombre, no un parámetro de ésta.
- **Se agregan detectores hasta un número donde la abstención total sea desproporcionada.** Con trece, uno caído invalida el conjunto y es razonable. Con cincuenta, quizás no.

Lo que **no** es disparador: que un usuario prefiera ver algo antes que nada, ni que la abstención resulte molesta en un mes puntual. La molestia es la señal funcionando.

> Última verificación: 2026-08-06
