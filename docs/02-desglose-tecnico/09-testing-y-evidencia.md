# Testing y evidencia

Cómo se prueba un sistema donde parte de la lógica vive en SQL, parte en workflows visuales y parte en un modelo de lenguaje — y qué se considera "probado".

## Criterio

Un sistema agéntico tiene tres clases de componentes y cada una se prueba distinto. Tratarlos igual es la razón por la que muchos proyectos con LLM no tienen tests: se intenta testear todo como si fuera un modelo, se descubre que es no determinístico, y se abandona.

| Componente | Determinista | Cómo se prueba |
|---|---|---|
| Lógica de negocio (montos, fechas, estados, saldos) | Sí | Tests unitarios y de integración. **Debe ser el grueso** |
| Contratos (entrada, salida, estados) | Sí | Tests de contrato con fixtures |
| Comportamiento del modelo | No | Evaluación con umbral declarado, canary, aprobación humana |

La consecuencia práctica es de diseño, no de testing: **empujá todo lo que puedas hacia la columna determinista**. Cada regla que sacás del prompt y ponés en código o en SQL es una regla que pasa de "hay que evaluarla" a "hay que testearla". El Memory Intent Gate es el ejemplo canónico: la decisión de consultar memoria podría haber sido del modelo, y es una regex con tests.

### Por qué una base real embebida y no mocks

Cuando parte de la lógica vive en la base —constraints, triggers, funciones, vistas— mockear la base es testear el mock.

Un test que simula el repositorio verifica que el código llame bien al repositorio. No verifica que el trigger `deuda_pago_validar` rechace un pago en otra moneda, ni que `movimiento_estado_fiscal_derivado` devuelva lo que decís que devuelve, ni que la vista `v_saldos_por_moneda` sume bien. Esas son exactamente las cosas que rompen en producción.

| Enfoque | Prueba de verdad | Costo |
|---|---|---|
| Mocks del repositorio | Que el código llama al repositorio | Bajo, y con **falsa confianza** sobre lo que vive en SQL |
| Base compartida de test | Todo, pero con estado sucio entre corridas | Medio; frágil y difícil de paralelizar |
| Docker por corrida de tests | Todo, con aislamiento | Alto en tiempo de arranque |
| **Base embebida en proceso** | Todo, con aislamiento y sin infra | Bajo; limitado por lo que la implementación soporte |

La cuarta opción sólo existe desde hace poco para PostgreSQL, y cambia el cálculo por completo.

### Qué significa "probado" cuando hay un LLM

Tres reglas que valen más que cualquier framework:

**1. El umbral se declara antes de correr.** Si el criterio de aceptación se fija después de ver los resultados, siempre se cumple. Es la falla de método más común y la más fácil de evitar.

**2. Un fixture que falla no es un fixture malo por default.** La tentación al ver un FAIL es ajustar el caso de prueba. A veces corresponde; la mayoría de las veces el caso está bien y la respuesta no alcanza.

**3. Pasar los tests no es lo mismo que funcionar en producción.** Los fixtures son sintéticos por diseño. Hace falta un canary con tráfico real, acotado y observado.

## En este sistema

**606 casos de test en verde, 0 salteados**, con `node --test` (el runner nativo de Node, sin framework — coherente con la API sin framework) y un **harness con PGlite que replica el esquema real**.

### Por qué PGlite

PGlite es PostgreSQL compilado a WebAssembly, corriendo en el mismo proceso que los tests. El harness le aplica **el mismo DDL que producción**: las mismas tablas, los mismos triggers, las mismas funciones, las mismas vistas.

Lo que eso compra:

- **Se testea lo que corre.** El trigger `prohibir_delete_fisico` se prueba intentando un `DELETE` de verdad y verificando que la base lo rechace.
- **Aislamiento por test.** Cada caso puede arrancar con una base limpia. Sin estado compartido, sin orden implícito, sin el test que sólo pasa si corre segundo.
- **Sin infraestructura.** No hace falta Docker ni un servidor levantado. `node --test` y listo. En un proyecto de una persona, la fricción determina si los tests se corren o no.
- **Las migraciones son testeables.** Hay casos específicos para **v4.6, v4.7 y v4.9**. El de la v4.7 obligó a excluirla del arnés común, porque su prueba necesita sembrar el estado incoherente *antes* de aplicar la migración que lo corrige. Una migración probada antes de tocar producción es una clase entera de incidentes que no ocurre.

Los límites, para ser honesto: PGlite no es idéntico a un PostgreSQL de producción en extensiones, concurrencia ni performance. No sirve para probar comportamiento bajo carga ni bloqueos. Para lógica de esquema —que es el 95% de lo que hay que probar acá— alcanza y sobra.

### Qué cubren los 606 casos

Por área, según el inventario verificado:

| Área | Qué se prueba |
|---|---|
| Ingesta | El contrato universal, por cada canal |
| Normalización de montos | Incluye **casos ambiguos** y separador decimal |
| Fechas | Interpretación relativa y el "mes pedido" |
| Tipo de cambio | `fx_vigente` y ausencia de cotización |
| Sanitización | Limpieza de entrada |
| Datos sensibles | Cifrado y `placeholder_token` |
| Transferencias | Dos patas con `transfer_id`, más el guard |
| Adaptadores | PDF, CSV, Excel, email |
| Deudas | Cálculos, API y pagos |
| Auto-confirmación | Cuándo se confirma solo y cuándo no |
| Reporte mensual | Agregaciones |
| Exportación del dashboard | El dato que sale |
| Migraciones | v4.6, v4.7 y v4.9 |
| Lectura fiscal | En JS **y en SQL** |
| Propuestas fiscales | Máquina de estados de v4.8, huellas y caducidad por evidencia cambiada |
| Motor de precedentes | Precedentes concordantes, contradictorios y ausentes; confianza que nunca llega a 1 |
| Catálogo de obligaciones | Feriados, fines de semana, día fijo contra terminación de CUIT, faltantes por régimen |
| Delegación de rutas fiscales | Que la ruta llegue al handler correcto |
| Herramientas MCP | Las 22, con sus scopes |
| Integración Oppenheimer↔finanzas | El camino completo |

Dos entradas merecen comentario.

**"Normalización de montos, incluidos los ambiguos".** `1.500` en Argentina puede ser mil quinientos o uno coma cinco. Es la clase de ambigüedad que en un sistema financiero produce un error de factor 1000. Que tenga tests propios dice que se detectó como problema antes de que costara plata.

**"Lectura fiscal en JS y en SQL".** La misma capa se prueba de los dos lados: que el endpoint devuelva lo correcto **y** que la vista subyacente calcule lo correcto. Es el reconocimiento explícito de que la lógica está repartida entre dos lenguajes y ninguno de los dos alcanza solo.

### El test que lee su propio archivo fuente

Hay un caso que vale documentar aparte porque es poco común y resuelve un problema que ningún test de comportamiento resuelve bien.

El módulo de propuestas fiscales declara en su cabecera que escribe en **una sola tabla**:

> *"Este módulo escribe en UNA tabla: `fiscal_propuestas`. No toca movimientos, deudas, obligaciones ni cierres, y hay una prueba que lo verifica leyendo este archivo."*

La prueba se llama `el módulo no escribe en ninguna tabla financiera` y hace literalmente eso: **abre el archivo fuente del módulo como texto y falla si encuentra un `INSERT` o un `UPDATE` sobre alguna tabla financiera.** No ejercita el código: lo inspecciona.

Por qué esto y no un test funcional:

- **Un test de comportamiento prueba los caminos que se te ocurrieron.** Se puede verificar que aprobar una propuesta no cambie el movimiento de origen —y hay un test que lo hace, `aprobar no cambió el movimiento de origen`—, pero eso cubre *ese* camino. El atajo que alguien agregue el mes que viene entra por otro.
- **La garantía que interesa es sobre el módulo entero, no sobre una ejecución.** "Este archivo no escribe en tablas financieras" es una propiedad estática. Verificarla estáticamente es lo natural; verificarla ejecutando es aproximarla.
- **Falla en el momento correcto.** El comentario del proyecto lo dice sin vueltas: *"si mañana alguien agrega el atajo de 'aplicar al aprobar', falla"*. El test rompe en el commit que introduce el atajo, no seis meses después cuando alguien nota que una aprobación movió plata.

El mismo patrón aparece dos veces más en la suite: un test lee `server.mjs` y verifica que **importe** los handlers fiscales en vez de reescribirlos —el bug real que existió fue justamente ese, un `server.mjs` que no importaba `fiscal.mjs` y dejaba 23 funciones muertas—, y otro compara el grafo de transiciones declarado en JavaScript contra el que impone el trigger de la base, fallando si divergen.

Es barato de escribir, no necesita infraestructura y cubre una clase de regresión —"alguien agregó una escritura donde no debía haberla"— que ningún fixture detecta. La contracara honesta: es sensible a cómo está escrito el código, no a lo que hace. Un `INSERT` armado por concatenación en tiempo de ejecución se le escapa. Sirve como red contra el atajo distraído, no contra el bypass deliberado.

### Fixtures sintéticos

Todos los fixtures son datos inventados. No hay ni un movimiento real, ni un comprobante real, ni un CUIT.

No es sólo una política de privacidad, aunque también lo sea (la regla del proyecto es explícita: *"Cambiar el nombre de una persona no es anonimización suficiente"*). Es que los datos sintéticos son **mejores para testear**:

- Podés construir el caso borde que en los datos reales no aparece nunca.
- El test es legible: `monto: 1500, moneda: 'ARS'` explica qué se prueba.
- El fixture es estable. Los datos reales cambian y los tests empiezan a fallar por motivos que no son bugs.
- El repo se puede publicar entero.

### El criterio "2/7 con exigencia de 7/7 → no se publica"

El caso más importante de esta sección, y el único que se mide por lo que **no** salió a producción.

El **2026-07-27**, después de las fases 3B→3E1 del "Buscador General" —relevancia, validador consolidado, métrica de alcance, fallback— se hizo una revalidación real acotada. Resultado: **2 de 7 PASS, con una exigencia declarada de 7/7. No se publicó.**

El cierre, textual:

> *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."*

Esa oración es el método completo en una línea. Frente a un FAIL hay dos caminos:

1. Concluir que el validador es muy estricto, aflojarlo, obtener 7/7 y publicar.
2. Revisar cada FAIL uno por uno y determinar si el caso está mal o la respuesta no alcanza.

Se tomó el segundo. Y la conclusión fue que los fixtures estaban bien: no había evidencia suficiente para una respuesta fundamentada, y el validador lo detectó correctamente. El componente que había que arreglar era el buscador, no el test.

Dos condiciones lo hicieron posible, y son replicables:

- **El 7/7 estaba declarado antes.** Con el umbral fijado después, 2/7 se convierte en "un avance prometedor".
- **El validador emitía estados tipados**, no un puntaje. `insufficient_evidence` es un veredicto que se puede discutir; "calidad 6,4/10" no.

Contraste dentro del mismo sistema, para que no parezca que acá nunca pasa nada: la reparación del pipeline de PDF (2026-07-25) dio **6/6 PASS** y se publicó. Las auditorías del buscador de fechas y del contexto dieron **8/8** y se publicaron. La Fase 3 de finanzas dio **141/141** y se publicó. Email V3 pasó **5 pruebas aisladas** y se publicó, con un cierre provisional honesto: faltaba el reinicio controlado y la validación desde Telegram.

El umbral no es un ritual: a veces se cumple y a veces no, y la diferencia decide qué sale.

### Canary en producción

Los fixtures sintéticos no prueban que el sistema funcione con entrada real. Por eso hay un paso de canary.

El **2026-07-27**, tras aplicar el DDL v3.1 y las migraciones v3.2–v3.6, hubo un **canary Telegram aprobado** antes de dar por completada la Fase 2. Tráfico real, acotado, observado, con criterio de aprobación explícito.

El canary cubre lo que ningún fixture puede: la codificación rara del mensaje real, el timeout del servicio externo, la credencial que en producción tiene otro alcance, el formato que el usuario usa y nadie previó.

Orden completo: **tests con fixtures → migración verificada → canary acotado → aprobación → publicación**. Saltearse el canary es asumir que producción se parece a los tests.

### Qué significa "evidencia" acá

El proyecto usa un vocabulario fijo, y aparece en toda la documentación:

| Término | Significa | Ejemplo |
|---|---|---|
| **Verificado** | Se inspeccionó el sistema y se registró el resultado | "51 nodos en el orquestador al 2026-08-03" |
| **Confirmado por el responsable** | Lo afirma quien lo hizo, sin inspección independiente | Una decisión de diseño relatada |
| **Inferido** | Se deduce de otra cosa; es razonable y no está comprobado | "El drift viene de que no hay chequeo automático" |
| **Pendiente de verificar** | Hueco explícito | Cualquier `[PENDIENTE DE VERIFICAR]` de esta sección |
| **Historia incompleta** | Hay evidencia parcial y falta el resto | Un cierre "provisional" |

La regla que lo sostiene:

> *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

Por qué importa en un repo público: la diferencia entre un portafolio y un registro de ingeniería es que el registro dice de dónde sabe cada cosa. Un documento sin marcas de evidencia obliga al lector a creer o descartar todo junto.

Y el corolario para trabajar con agentes de IA, que es donde este vocabulario nació:

> *"Inspección no equivale a autorización de cambio."*

Un agente puede leer todo el sistema y producir un diagnóstico excelente. Eso no lo habilita a aplicarlo. La evidencia habilita una **propuesta**; la aprobación habilita el cambio. Es la misma separación que hay entre `fiscal_propuestas` y un movimiento confirmado, y la misma que en el ciclo SDLC de 9 etapas (Intake, Evidencia y línea base, Diseño, Implementación, Verificación, Staging, Release, Operación, Incidente y aprendizaje), cada una con su compuerta.

Cierre textual de ese ciclo:

> *"Los agentes de IA pueden proponer, implementar y verificar trabajo. No se convierten en el dueño responsable del riesgo, el acceso o la decisión de release."*

### Lo que no está testeado

Declararlo es parte del método.

- **Los workflows de n8n no tienen tests automatizados.** Se validan con corridas manuales y pruebas puntuales (6/6, 8/8, 5 aisladas). El pipeline de 10 pasos incluye "probar contratos con fixtures ficticios", pero no hay un runner que lo ejecute solo. Riesgo conocido.
- **No hay tests de UI.** Hay tests de exportación del dashboard: verifican el dato, no la interacción.
- **No hay tests de carga.** El volumen no lo amerita y PGlite no sirve para eso.
- **No hay eval sistemática del comportamiento del modelo.** Hay validaciones por caso y umbrales por release, no una suite de evaluación que corra sola. `[PENDIENTE DE VERIFICAR: plan de eval automatizada]`
- **No hay CI.** Los tests se corren a mano antes de publicar. Con ambientes separados, esto es lo siguiente a automatizar.

## Regla

Empujá la lógica hacia lo determinístico y testeala con una base real embebida, no con mocks: si la regla vive en un trigger, el mock nunca la va a probar. Declará el umbral antes de correr las pruebas, y cuando un caso falle, revisá el caso antes de aflojar el criterio.

> Última verificación: 2026-08-06
