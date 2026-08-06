# ADR-009 — Publicar el método, no el sistema

Se publica cómo se decide, cómo se prueba y cómo se opera. No se publica el sistema que produjo esas lecciones. Es la decisión que hace posible que este repositorio exista.

## Estado

Vigente.

## Fecha

2026-08-05 — se resuelve la identidad y los repositorios públicos definitivos, que estaban pendientes de decidir.
La política de publicación de la que deriva es del 2026-08-03, dentro de la línea base de gobernanza.

## Contexto

Al 3 de agosto había un sistema en producción con material genuinamente interesante para mostrar: un orquestador con subagentes, memoria persistente sin embeddings, un núcleo fiscal con invariantes en la base, 554 tests, un incidente reparado con máquina de estados y un componente rechazado por no pasar sus pruebas.

Y había un problema evidente. Ese material está entretejido con lo que no puede salir: agenda y correo personales, movimientos financieros reales, datos fiscales, credenciales, la topología del VPS, identificadores de canal, nombres de personas.

La reacción común frente a esa tensión es una de dos, y las dos son malas:

- **No publicar nada.** Se pierde entero el valor de mostrar el trabajo, y no hay forma de que nadie evalúe cómo se trabaja.
- **Publicar con sanitización superficial.** Cambiar nombres, tachar direcciones, subir el resto. Sobre esto la línea base es tajante: *"Cambiar el nombre de una persona no es anonimización suficiente."* Un conjunto de datos con nombres cambiados sigue siendo reidentificable por sus fechas, sus montos y sus relaciones.

La salida está en la regla raíz de la política existente:

> *"Los artefactos públicos deben enseñar un principio reutilizable sin exponer el sistema privado del que salió la lección."*

Esa frase reencuadra el problema. La pregunta deja de ser *"¿cómo saco lo sensible de este artefacto?"* y pasa a ser *"¿cuál es el principio reutilizable acá, y puedo escribirlo desde cero sin necesitar el artefacto?"*. Casi siempre se puede. Y el resultado suele ser mejor, porque el artefacto original está lleno de contingencias del caso concreto que al lector no le sirven de nada.

## Decisión

**Se publica el método —decisiones, criterios, arquitectura, contratos, procedimientos, incidentes y fracasos— y no se publica el sistema: ni datos, ni credenciales, ni topología, ni artefactos crudos.**

### Qué sí se publica

| Categoría | Ejemplos concretos en este repositorio |
|---|---|
| Decisiones con su razonamiento | Los nueve ADRs, con opciones consideradas y consecuencias |
| Arquitectura y nombres de estructuras | Tablas, columnas, vistas, funciones, triggers, estados de máquina |
| Contratos | Estados de salida del buscador, contrato universal de ingesta, contrato Finanzas↔Fiscal |
| Procedimientos | Runbooks de migración, de publicación de workflow, de limpieza de runtime |
| Incidentes y post-mortems | El PDF de 21,9 MB, el drift de producción |
| **Fracasos** | El Buscador General 2/7, el hub congelado, los proyectos en Fase 0 |
| Métricas agregadas | Conteos de workflows, tablas, tests, endpoints, con su fecha de corte |
| Cronología | Fechas y hitos |
| Plantillas y checklists originales | Manifiesto de 11 campos, pipeline de 10 pasos |
| Ejemplos sintéticos | Comandos genéricos, datos ficticios, siempre declarados como tales |

### Qué no se publica

| Categoría | Por qué |
|---|---|
| Direcciones IP, nombres de host, topología | Superficie explotable |
| Tokens, claves, credenciales, identificadores de credencial | Obvio, y sin embargo la razón número uno de filtraciones en repositorios |
| Identificadores de canal, correos, nombres de personas | Datos personales de terceros que no eligieron aparecer |
| Datos financieros, fiscales, médicos o clínicos reales | Nunca, ni siquiera parcialmente |
| Contenido de correo, agenda o documentos privados | Aunque sean propios, involucran a terceros |
| Backups, registros y exports crudos | Contienen todo lo anterior mezclado |
| El contenido concreto de los skills fiscales | Se publica el método de trabajo, no los procedimientos aplicados a un caso real |
| Afirmaciones de pruebas, adopción o publicación sin evidencia | Es la forma más común de mentir sin decir una mentira |

### Las seis compuertas de revisión

Cada artefacto que sale pasa por estas seis, en orden:

1. **Procedencia** — ¿de dónde salió y hay derecho a publicarlo?
2. **Escaneo de secretos y datos personales** — automático y manual.
3. **Licencia** — compatibilidad con lo que se reutiliza.
4. **Exactitud técnica** — ¿lo que se afirma es verdad y está verificado?
5. **Aprobación humana** — una persona firma. Coherente con el [ADR-004](adr-004-aprobacion-humana-en-acciones-consecuentes.md).
6. **Revisión de release** — última mirada antes de que sea público.

### El vocabulario de evidencia como control de calidad

Toda afirmación publicada lleva estado: `Verificado`, `Confirmado por el responsable`, `Inferido`, `Pendiente de verificar` o `Historia incompleta`.

No es un adorno de estilo. Es el mecanismo que impide el modo de falla más probable de un repositorio de portafolio, que es **rellenar los huecos con narración plausible**. La regla:

> *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

Un `Pendiente de verificar` visible vale más que un párrafo bien escrito que nadie puede comprobar.

### Publicar los fracasos es parte de la política, no una concesión

Es la parte contraintuitiva y la que le da valor al resto. Un repositorio que sólo muestra éxitos **no permite evaluar el criterio de quien lo escribió**. El [ADR-006](adr-006-buscador-general-no-publicado.md) —un componente terminado que no se publicó por 2/7— dice más sobre cómo se trabaja acá que los 554 tests.

Lo mismo con las diez deudas abiertas que están publicadas tal cual: sin separación de ambientes, backups sin ensayo de restauración, el `errorWorkflow` que todavía se llama `[TEST]`, dos proyectos que resuelven el mismo problema, un token que requiere rotación. Nada de eso mejora la apariencia del sistema. Todo eso mejora la credibilidad de lo que sí se afirma.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Publicar el método, con reescritura limpia y ejemplos sintéticos** | Todo el valor didáctico sin exposición; los artefactos quedan mejor que los originales; se puede publicar lo que salió mal | Cuesta trabajo real: hay que reescribir, no copiar y tachar | **Elegida** |
| No publicar nada | Riesgo cero | Cero valor. El trabajo queda sin forma de ser evaluado por nadie | Rechazada |
| Publicar el repositorio real, sanitizado | Máxima fidelidad; menos trabajo aparente | La sanitización de artefactos reales falla en silencio; el historial de git conserva lo borrado; los datos personales sobreviven al cambio de nombres | Rechazada |
| Publicar sólo diagramas y texto de alto nivel | Seguro y rápido | Indistinguible de contenido de consultoría. No demuestra nada verificable | Rechazada |
| Repositorio privado con acceso por pedido | Control caso por caso | Fricción que anula el propósito; y el material sigue mezclado con lo sensible | Rechazada |

## Consecuencias

### Positivas

- **Este repositorio existe.** Sin esta decisión no habría nada que publicar.
- **Los artefactos publicados son mejores que los originales.** Un runbook reescrito para ser genérico es más útil que el procedimiento real lleno de particularidades del caso.
- **Se pueden publicar los fracasos**, que es el material más valioso y el que ninguna política basada en sanitización permitiría, porque los fracasos vienen pegados a los datos que los produjeron.
- **El vocabulario de evidencia obliga a la honestidad**: cada afirmación tiene que declarar su estado, y eso se nota al escribir.
- **El sistema privado sigue privado.** No hay compromiso entre publicar y proteger, porque no se publica lo mismo que se protege.

### Negativas

- **Cuesta mucho más trabajo** que exportar y tachar. Cada artefacto se reescribe.
- **Es menos impresionante para quien busca código.** No hay un repositorio que se pueda clonar y correr.
- **Requiere confianza en las afirmaciones.** Nadie puede verificar desde afuera que haya 554 tests. La mitigación es el vocabulario de evidencia y la publicación de las deudas: **un documento que declara sus propios huecos es más creíble que uno que no declara ninguno**.
- Hay material que no se puede publicar de ninguna forma y que era interesante — el contenido fiscal concreto, por ejemplo.

### Operativas

- Cada publicación pasa por seis compuertas. Es fricción deliberada.
- Los ejemplos sintéticos hay que inventarlos y marcarlos como tales, uno por uno.
- Mantener el repositorio público al día con el privado es trabajo permanente, y **hay riesgo de drift documental** exactamente igual que el drift técnico del [ADR-008](adr-008-el-repositorio-como-fuente-de-verdad.md). El pie `> Última verificación:` en cada archivo es la mitigación mínima.
- El literal de usuario de GitHub se mantiene como marcador hasta la publicación efectiva.

### De seguridad

- **La reescritura limpia es una defensa estructural, no un filtro.** No se puede filtrar mal lo que nunca se copió. Es la diferencia central con la sanitización.
- El escaneo de secretos es una compuerta explícita, y aun así **falló una vez**: un archivo `.env` con un token real quedó en una carpeta sincronizada a la nube. Se detectó en auditoría, requiere rotación, y está publicado como deuda. Es la prueba de que la compuerta 2 existe porque hace falta.
- **No publicar topología** significa que un lector no aprende nada útil para atacar la infraestructura. Los identificadores de workflow son opacos, y aun así se prefiere omitirlos o abreviarlos.
- **Los datos de terceros no se publican en ninguna forma**, ni transformados. Nombres de familiares, correos e identificadores de canal quedan afuera por completo.
- Riesgo residual: la **agregación**. Ningún dato publicado es sensible por separado, y el conjunto describe un sistema real con bastante detalle. Se acepta conscientemente, porque lo que se describe son estructuras y decisiones, no accesos.

## Evidencia

| Afirmación | Estado |
|---|---|
| Regla raíz de la política de publicación, textual | `Verificado` |
| Listas de permitido y prohibido de la política existente | `Verificado` |
| Seis compuertas de revisión: procedencia, secretos, licencia, exactitud, aprobación humana, release | `Verificado` |
| Cita textual *"Cambiar el nombre de una persona no es anonimización suficiente"* | `Verificado` |
| Vocabulario de evidencia de cinco estados | `Verificado` |
| Cita textual sobre preferir el vacío explícito a la narración no demostrable | `Verificado` |
| Hallazgo del `.env` con token real en carpeta sincronizada, pendiente de rotación | `Verificado` |
| Identidad y repositorios públicos definitivos, pendientes hasta el 2026-08-05 | `Verificado` |
| Que las seis compuertas se hayan aplicado formalmente a **cada** archivo de este repositorio | `Pendiente de verificar` |
| Rotación efectiva del token expuesto | `Pendiente de verificar` |

## Por qué esta decisión hace posible el portafolio público

Vale la pena decirlo directo, porque es el punto entero del ADR.

Un sistema con datos personales, financieros y de terceros **no se puede publicar**. No hay grado de sanitización que lo vuelva seguro, y cualquier intento produce una de dos cosas: o una filtración, o un artefacto tan vaciado que ya no enseña nada.

La decisión de publicar el método rompe ese callejón porque **el método no contiene datos**. Que la memoria tenga cuatro capas y ningún embedding es una decisión de arquitectura: se explica entera sin mostrar un solo hecho guardado. Que un PDF de 21,9 MB haya roto el pipeline y que la reparación haya sido una máquina de estados con `failed` terminal se cuenta completo sin el PDF. Que un buscador haya pasado 2 de 7 se cuenta sin las siete consultas.

Y el subproducto es el que más importa: **una vez que lo publicable es el método, publicar los fracasos deja de tener costo**. Nada obliga a maquillar, porque no hay nada expuesto que proteger. Ese es el motivo por el cual este repositorio puede tener un ADR titulado "El Buscador General no se publica" y una página de métricas cuya sección final explica qué no miden esos números.

La política no es una restricción sobre lo que se puede mostrar. Es lo que permite mostrar la parte honesta.

## Disparador de revisión

Revisar cuando:

- **Aparezca un cliente real.** Publicar sobre trabajo de terceros exige consentimiento explícito y probablemente un acuerdo escrito. La política actual asume que todos los datos son propios.
- **Haya que publicar código ejecutable**, no sólo documentación. Requiere una implementación desde cero, verificada como libre de contenido del sistema privado.
- **Se detecte una filtración.** La respuesta es rotar, corregir y revisar la compuerta que falló — no dejar de publicar.
- **El repositorio público se desactualice respecto del privado** más allá de lo tolerable. El drift documental es un riesgo real y todavía no tiene un umbral definido.
- **Se publique bajo identidad profesional plena.** La exposición cambia, y con ella el análisis de riesgo de la agregación.

> Última verificación: 2026-08-05
