# ADR-010 — El agente propone, el humano decide

El Agente Fiscal escribe en una sola tabla que no mueve un peso, y no tiene la credencial para aprobar lo que escribe. La separación no descansa en que el agente se porte bien.

## Estado

Vigente.

## Fecha

2026-08-05 — implementada con la migración v4.8 (`fiscal_propuestas`) y el control de alcance del token fiscal. Es la especialización fiscal del [ADR-004](adr-004-aprobacion-humana-en-acciones-consecuentes.md).

## Contexto

El Agente Fiscal lee evidencia financiera ya registrada, la contrasta contra el régimen y el calendario del contribuyente, y produce diagnósticos. La pregunta que había que responder antes de implementar nada era: **¿qué pasa cuando el agente concluye que un movimiento está mal clasificado?**

Hay dos respuestas posibles y son incompatibles.

La primera es que lo corrija. Es la que primero se le ocurre a cualquiera, es la que "ahorra un paso", y es la que convierte un asistente en un actor. Si el agente puede reclasificar, entonces el registro fiscal del titular es el resultado de un modelo estadístico corriendo sin testigo.

La segunda es que lo proponga y espere. Es más lenta, exige atención humana todos los meses, y es la única compatible con el principio del contrato Finanzas↔Fiscal v1.0:

> *«Toda corrección debe formularse como propuesta.»*
> — Contrato §2, principios no negociables

> *«Toda acción con impacto financiero o fiscal requiere aprobación humana.»*
> — Contrato §2

El problema es que ese principio, escrito así, es una declaración de intenciones. Un agente con el token que le permite aprobar va a poder aprobar, diga lo que diga el documento. Y el modo de falla no es dramático: es que el agente proponga, apruebe y avise, y que todo se vea exactamente igual que si un humano hubiera decidido.

> *«un agente que puede aprobar sus propias propuestas no está pidiendo permiso: está avisando. […] La separación no descansa en que el agente se porte bien, descansa en que no tenga la credencial.»*
> — `api/auth.mjs`

## Decisión

**El agente propone. Escribe en una sola tabla, `praxia_finanzas.fiscal_propuestas`, y no tiene la credencial que permite decidir sobre ella.**

Tres consecuencias concretas de esa frase:

1. **Una sola tabla escribible.** El módulo de propuestas no toca movimientos, deudas, obligaciones ni cierres. La tabla, por construcción, no tiene forma de aplicar nada: *«Esta tabla no toca ningún saldo, ninguna deuda y ningún movimiento: no tiene forma de hacerlo, y eso es a propósito.»*
2. **Aprobar no aplica.** La regla del §10 es literal: *«**REGLA:** La aprobación no ejecuta nada financieramente.»* Aprobar registra una decisión humana con firma y motivo. Aplicarla es un acto posterior y separado, por las rutas de escritura, con otro token.
3. **La decisión requiere el token general.** `POST /api/fiscal-propuestas/decidir` devuelve **403** al token fiscal. El control se evalúa **primero y por igualdad exacta de ruta**, «para que ninguna regla más permisiva de abajo la habilite por accidente». Mensaje: *«el Agente Fiscal puede proponer, no aprobar: la decisión requiere el token general»*.

### Las tres formas verificables en que se cumple

No alcanza con afirmarlo. Está verificado de tres maneras independientes, y una de ellas lee el propio archivo fuente.

| # | Garantía | Cómo se comprueba |
|---|---|---|
| 1 | **El módulo escribe en una sola tabla** | Un test **lee el fuente de `api/fiscal_propuestas.mjs`** y falla si aparece un INSERT o UPDATE sobre cualquier tabla financiera. La cabecera del módulo lo declara: *«Este módulo escribe en UNA tabla: `fiscal_propuestas`. No toca movimientos, deudas, obligaciones ni cierres, y hay una prueba que lo verifica leyendo este archivo.»* Si mañana alguien agrega el atajo de "aplicar al aprobar", la suite se pone en rojo |
| 2 | **Decidir solo actualiza campos de decisión** | `decidirPropuesta()` ejecuta un único UPDATE sobre `estado_aprobacion`, `aprobador`, `motivo_decision` y `fecha_decision`. No hay otra sentencia. La respuesta lleva el warning fijo: *«Aprobada. Esto NO ejecutó ningún cambio financiero: queda registrada la decisión. Aplicarla es un acto separado.»* |
| 3 | **La tabla no tiene forma de aplicar nada** | No hay trigger, función ni columna que propague la aprobación a un saldo. El rollback de la migración lo confirma desde el otro lado: tirarla abajo *«no afecta saldos, movimientos, deudas ni cierres»* |

El test que lee el propio archivo fuente es el más interesante de los tres, porque no verifica un comportamiento: verifica una **propiedad del código**. Un test de comportamiento comprueba que hoy no se escribió en `movimientos`; este comprueba que no existe la línea que podría escribir. Es la diferencia entre "no pasó" y "no puede pasar por esta vía".

A eso se suma la verificación operativa. `ops/verificar_alcances.sh` corre contra el entorno desplegado y comprueba 200 en las cuatro lecturas permitidas, 403 en aprobar y en las rutas de escritura, y **422** al decidir con el token general — 422 porque el control de alcance se pasó y el identificador no existe; *«un 403 acá sería el problema»*. Y `ops/deploy_v4_8_propuestas.sh` **aborta el despliegue** si `POST /decidir` con el token fiscal no devuelve 403.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Proponer en una tabla aparte, sin credencial para decidir** | La separación es estructural, no de comportamiento; queda registro de qué se propuso y qué se decidió; el agente puede equivocarse sin consecuencia | Exige atención humana todos los meses; el sistema no "resuelve solo" nada | **Elegida** |
| Que el agente aplique cuando la confianza supere un umbral | Menos trabajo humano; el volumen alto se resuelve solo | El umbral lo elige quien lo escribe y nadie lo audita después. Y la confianza acá se calcula por cantidad de precedentes, no mide si el precedente aplica a este caso | Rechazada |
| Aprobación humana como paso de prompt («preguntá antes de aplicar») | Se implementa en una tarde y suena igual | Es una guarda de prompt, no de código. Ya existe una así en el sistema —la anulación desde Telegram— y está documentada como límite: *«No hay un mecanismo de la API que impida a un agente anular sin preguntar»* | Rechazada |
| Un solo token con todos los permisos y auditoría posterior | Simple de operar; todo queda en el log | La auditoría detecta después de que pasó. Para una reclasificación fiscal aplicada, "después" puede ser la presentación del período | Rechazada |
| Que aprobar aplique automáticamente el cambio | Ahorra un paso al humano; parece obvio | Une dos actos que deben poder fallar por separado. Y borra la distinción entre "estoy de acuerdo con el criterio" y "quiero que esto se escriba ahora" | Rechazada |

## Consecuencias

### Positivas

- **El agente no puede dañar el registro fiscal.** No es una afirmación de confianza: es un permiso que no tiene, comprobado en cada despliegue.
- **Queda escrito quién decidió y por qué.** El constraint `chk_prop_decision_completa` exige aprobador, fecha y motivo para toda decisión: *«Una decisión sin quién ni por qué no es una decisión, es un cambio de estado.»*
- **El agente puede equivocarse barato.** Una propuesta mala cuesta un rechazo con motivo. Un cambio aplicado mal cuesta una reapertura de período.
- **La propuesta decidida es inmutable.** El trigger `trg_propuesta_inmutable` congela 14 columnas cuando el estado deja de ser `pendiente`, así que lo que se aprobó es exactamente lo que se mostró.
- **Se puede demostrar en una entrevista o ante un contador.** Hay un script que corre en el servidor y devuelve 403.

### Negativas

- **Nada se resuelve solo.** Todos los meses hay que sentarse a decidir propuestas. Si el titular no lo hace, el período no cierra.
- **Aprobar y aplicar son dos actos**, y eso confunde la primera vez. Es la fuente probable de un "aprobé todo y no cambió nada".
- **El backlog de propuestas pendientes puede crecer** sin que nada lo señale. Hoy no hay recordatorio automático: el disparo mensual en n8n sigue siendo un stub con trigger manual.
- La garantía cubre **el camino del agente**, no todos los caminos. Un `psql` suelto con el usuario de escritura sigue pudiendo hacer cualquier cosa; eso lo cubren las invariantes del [ADR-012](adr-012-la-invariante-vive-en-la-base.md), no ésta.

### Operativas

- El despliegue tiene un paso obligatorio nuevo: verificar el 403. El script aborta si no aparece, así que no es opcional.
- Los tres tokens (general, lectura, fiscal) deben ser mutuamente distintos y de al menos 24 caracteres; `validateApiTokens()` lo exige al arrancar comparando digests con `timingSafeEqual`.
- El mecanismo de aprobación —panel web o Telegram— **sigue siendo una decisión abierta** del contrato §19. Hoy se decide por API.
- El rol de PostgreSQL de solo lectura, que sería la segunda barrera a nivel motor, **está pendiente**. La barrera de aplicación existe y funciona; la del motor es tarea de despliegue.

### De seguridad

- La superficie de escritura del agente es **una tabla**, y esa tabla no tiene efecto financiero. Es el radio de daño más chico que se podía dejar sin volver al agente inútil.
- El `actor` de una propuesta lo pone el servidor **después** del cuerpo del pedido: *«quién pidió el análisis sale de la credencial, no de lo que el cliente diga que es»*. Un cliente no puede firmar como otro.
- El control de alcance se evalúa por igualdad exacta y en primer lugar, que es la forma correcta de escribir una denegación: las listas de permitidos se amplían por accidente, las denegaciones evaluadas primero no.
- El modo de falla que esto evita es silencioso. Un agente que aplica lo que decide produce un sistema que se ve bien y está equivocado, y esa es la clase de falla que este proyecto trata como peligrosa.

## Evidencia

| Afirmación | Estado |
|---|---|
| El agente escribe únicamente en `praxia_finanzas.fiscal_propuestas` | `Verificado` |
| Test que lee el propio fuente y falla ante un INSERT/UPDATE sobre tabla financiera | `Verificado` |
| `decidirPropuesta()` ejecuta un solo UPDATE de campos de decisión | `Verificado` |
| 403 en `POST /api/fiscal-propuestas/decidir` con el token fiscal, evaluado primero y por igualdad exacta | `Verificado` |
| `ops/deploy_v4_8_propuestas.sh` aborta el despliegue si no aparece el 403 | `Verificado` |
| 422 al decidir con el token general en `ops/verificar_alcances.sh` | `Verificado` |
| Tests `aprobar no cambió el movimiento de origen` y `el diagnóstico no clasificó ningún movimiento por su cuenta` | `Verificado` |
| Constraint `chk_prop_decision_completa` y trigger `trg_propuesta_inmutable` sobre 14 columnas | `Verificado` |
| Citas de `api/auth.mjs`, contrato §2 y §10, y `45_Migration_v4_8_propuestas_fiscales.sql` | `Verificado` |
| Rol de PostgreSQL de solo lectura como segunda barrera | `Pendiente de verificar` — no implementado |
| Mecanismo definitivo de aprobación (panel vs. Telegram) | `Pendiente de verificar` — decisión abierta del contrato §19 |

## Disparador de revisión

Este ADR se revisa si ocurre alguna de estas cosas:

- **Se define el mecanismo de aprobación del §19.** Un panel o un flujo de Telegram cambian dónde vive la firma humana, no si existe.
- **Se implementa el rol de PostgreSQL de solo lectura.** No debilita la decisión: la refuerza con una segunda barrera a nivel motor.
- **Aparece una clase de propuesta de riesgo nulo demostrable** —por ejemplo, completar un campo puramente descriptivo— donde el costo de la aprobación humana supere al riesgo. Habría que demostrar el riesgo nulo antes, no después.
- **El volumen de propuestas hace inviable la revisión manual.** La respuesta correcta ahí es agrupar y priorizar, no delegar la firma.

Lo que **no** es disparador: que sea incómodo, que el agente venga acertando hace meses, o que el backlog esté atrasado. Un agente que acierta mucho es exactamente el que consigue que le aflojen el control.

> Última verificación: 2026-08-06
