# Patrones de prompt

Cinco patrones reutilizables que sostienen el sistema. Ninguno es un truco de redacción: todos consisten en sacarle una decisión al modelo y ponerla en un lugar donde se pueda verificar.

> Patrones originales de PraxIA Ops, extraídos del sistema real. Los ejemplos son sintéticos.

---

## 1. Gate determinístico antes del LLM

### El problema

Una instrucción del tipo "consultá la memoria cuando haga falta" delega en el modelo dos cosas a la vez: decidir si hace falta y hacerlo. La primera es una decisión que se puede equivocar en silencio, y cuando se equivoca el resultado es un asistente que dice "no me acuerdo" con el dato guardado.

### El patrón

**Poner un nodo de código antes del modelo que decida, de forma determinística, si hay que hacer la llamada.** El modelo recibe el resultado ya resuelto.

```
mensaje → [Code: gate determinístico] → [IF] → [preflight] → [LLM]
                                          └─────────────────→ [LLM]
```

### En el sistema

`Code - Memory Intent Gate` + `IF Memory Required` + `PraxIA Memory Preflight`. La decisión es código, no LLM.

### Por qué funciona

- **Es reproducible.** La misma entrada da siempre la misma decisión. Se puede testear con fixtures.
- **Es barata.** No consume tokens.
- **Es auditable.** Se puede leer por qué disparó.
- **Se puede mejorar sin reentrenar nada.** Un caso nuevo es una línea nueva en el gate.

### Cuándo aplicarlo

Cuando la decisión de usar o no una herramienta sea más importante que la interpretación del resultado. Consultar memoria, resolver una fecha relativa, detectar un adjunto, identificar al remitente: todo eso se decide mejor en código.

### Cuándo no

Cuando la decisión requiera interpretar realmente el sentido del pedido. Un gate determinístico que intente clasificar "¿esto es una consulta científica o una noticia?" va a fallar más que el modelo.

---

## 2. Clasificación de intención con etiquetas cerradas

### El problema

Un subagente que recibe lenguaje natural tiene que adivinar qué le están pidiendo, y adivina distinto cada vez. Peor: adivina distinto según cómo esté redactado el mismo pedido.

### El patrón

**Clasificar la intención en una lista cerrada de etiquetas antes de actuar**, y ramificar por la etiqueta, no por el texto.

### En el sistema

El **Agente de Planillas** clasifica cada pedido en `GUARDAR:` o `CONSULTA:` y deriva las consultas a un `Consulta Sub-Agent` separado. Son dos caminos distintos con permisos distintos: uno escribe, el otro no.

El **contrato de subworkflow** lleva el mismo principio a la interfaz: el campo `action` es un verbo de una lista cerrada, nunca lenguaje natural.

### Por qué funciona

- **La lista cerrada se puede testear**: un fixture por etiqueta.
- **Separa permisos**: el camino de lectura no necesita permiso de escritura.
- **Hace visible el caso no cubierto.** Si nada encaja, hay una etiqueta para eso y el sistema lo dice, en vez de elegir la etiqueta más parecida.

### Ejemplo sintético

```jsonc
// Entrada del usuario (lenguaje natural)
"anotá que gasté 12000 en el súper ayer"

// Clasificación
{ "intencion": "GUARDAR", "confianza": "alta" }

// Entrada del usuario
"cuánto gasté en el súper el mes pasado"

// Clasificación
{ "intencion": "CONSULTA", "confianza": "alta" }

// Entrada ambigua
"el súper"
{ "intencion": "AMBIGUA", "confianza": "baja", "repregunta": "¿Querés anotar un gasto o consultar los que ya cargaste?" }
```

`AMBIGUA` es una etiqueta de primera clase, no un fallo.

---

## 3. Contrato de evidencia con estados de salida tipados

### El problema

Un subagente que devuelve texto libre obliga al orquestador a interpretar si le fue bien o mal. Interpretar "no encontré nada relevante" y "no pude buscar porque el servicio está caído" con un LLM funciona casi siempre, y "casi siempre" es demasiado poco para decidir si reintentar o avisar.

### El patrón

**Toda herramienta devuelve un estado de una lista cerrada. El fracaso es un estado, no una excepción.** El orquestador ramifica por el estado, no por el texto.

### En el sistema

El **Buscador Web Tavily V1** tiene siete estados: `ok`, `clarification_required`, `no_reliable_source`, `search_not_configured`, `technical_error`, `stable_knowledge_handoff`, `insufficient_evidence`.

La pieza técnica que lo hace posible: `neverError=true` en la llamada HTTP, con timeout explícito. El fallo del proveedor entra al flujo como dato, y el validador lo traduce a `technical_error`.

### Por qué funciona

- **Cada estado tiene una respuesta distinta**: reintentar, repreguntar, avisar, responder sin web.
- **Se puede medir.** "El 12% de las búsquedas termina en `insufficient_evidence`" es una métrica; "a veces no encuentra" no lo es.
- **Se puede testear.** Un fixture por estado.
- **Hace imposible la respuesta sin evidencia.** Ninguno de los siete estados significa "respondé igual".

### La prueba de que se toma en serio

El "Buscador General" llegó a revalidación con **2/7 PASS contra una exigencia de 7/7 y no se publicó**. La lectura del cierre:

> *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."*

Un contrato de evidencia que nunca bloquea nada no es un contrato.

---

## 4. Aprobación humana como paso del flujo

### El problema

"Pedí confirmación antes de enviar" en el prompt es una preferencia. El modelo la cumple casi siempre. Casi.

### El patrón

**La aprobación es un nodo del flujo, no una instrucción.** El subagente que ejecuta la acción consecuente no la ejecuta: devuelve el borrador con un estado `pendiente_aprobacion` y una **huella del contenido**. La ejecución es una segunda llamada, con esa huella.

```
[Redactar] → estado: pendiente_aprobacion + huella
           → [Telegram: mostrar y esperar]
           → [IF Aprobado]
                ├─ sí  → [Ejecutar con la huella]
                └─ no  → estado: rechazado_por_usuario
```

### En el sistema

`Telegram - Approve Send` → `If - Approved` → `Oppenheimer - Enviar Gmail`. Decisión **D-7**: enviar mails, borrar, gastar y publicar pasan por una persona.

En finanzas el mismo patrón está en la base: los triggers `propuesta_nace_pendiente`, `propuesta_contenido_inmutable` y `propuesta_transicion_valida` garantizan que ninguna propuesta nazca aprobada, que el contenido no cambie después de propuesto y que la decisión sea terminal.

### Los tres detalles que la mayoría se saltea

1. **Lo que se aprueba tiene que ser lo que se ejecuta.** De ahí la huella. Si el contenido cambia, la aprobación caduca.
2. **El rechazo es un resultado normal, no un error.** El flujo sigue, el usuario recibe una confirmación de que no se hizo nada.
3. **La aprobación no ejecuta por sí sola.** Cita literal del contrato financiero: *"La aprobación no ejecuta nada financieramente."* Aprobar y ejecutar son dos pasos, y el segundo se registra aparte.

### El anti-patrón que este patrón evita

> *"Un agente que puede repreguntar sin límite termina consiguiendo el 'sí' por cansancio."*

Contramedida: **una repregunta por pedido**, y en finanzas, el campo `huella` con un índice único que impide volver a proponer lo mismo mientras haya una propuesta pendiente.

---

## 5. "Ausencia de dato no es cero"

### El problema

Es el fallo más silencioso de todos. Un `LEFT JOIN` devuelve `NULL`, alguien pone un `coalesce(..., 0)` para que el dashboard no muestre vacío, y a partir de ahí "no sé" y "cero" son indistinguibles. El sistema queda diciendo con total seguridad algo que nadie sabe.

En un agente de IA el mismo fallo aparece como una estimación razonable presentada como dato.

### El patrón

**La ausencia de dato produce ausencia de fila, o un estado explícito. Nunca un valor por defecto.**

### En el sistema, en cuatro lugares distintos

| Capa | Implementación |
|---|---|
| **Base de datos** | `fx_vigente()` devuelve `TABLE`, no `numeric`. Sin cotización, cero filas. Una función que devuelve un número invita a que alguien lo defaultee |
| **Vistas** | `CROSS JOIN LATERAL`, no `LEFT JOIN`. Sin cotización, la moneda no aparece en `v_patrimonio_usd`. Un total incompleto y visible es mejor que uno completo e inventado |
| **Herramientas** | El buscador devuelve `insufficient_evidence` en vez de una respuesta débil |
| **Prompt** | "Declarar un vacío es una respuesta correcta. Completarlo con una suposición es un error, aunque la suposición sea razonable" |

### Las citas que lo fijan

> *"Ninguna cotización se inventa. Ausencia de dato es ausencia de fila, nunca un cero."*

> *"La ausencia de datos no debe convertirse en un dato inventado."*

> *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

La tercera es de la política de documentación, no del código. Es el mismo principio aplicado a cómo se escribe este repositorio: por eso aparece `[PENDIENTE DE VERIFICAR]` en vez de una estimación plausible.

### Cómo se ve cuando funciona

Un usuario pregunta cuánto tiene en total y el agente responde:

```
USD 1.240 en dólares.
No puedo darte el total en pesos: no tengo cotización cargada para hoy.
```

En vez de:

```
USD 1.240 en total.
```

El segundo es más lindo y es mentira.

---

## Cómo se combinan

Los cinco patrones no son independientes: se apoyan.

| Patrón | Qué le da a los demás |
|---|---|
| **Gate determinístico** | Garantiza que la herramienta se llame cuando corresponde |
| **Etiquetas cerradas** | Hace que la llamada sea inequívoca |
| **Estados tipados** | Hace que el resultado sea inequívoco |
| **Aprobación como paso** | Impide que un resultado se convierta en acción sin una persona |
| **Ausencia ≠ cero** | Impide que un vacío se convierta en un dato en cualquiera de los cuatro pasos anteriores |

El hilo común: **cada punto donde el modelo podría equivocarse en silencio se reemplaza por algo que se puede testear.**

Ese es el trabajo. El prompt es la parte fácil.

> Última verificación: 2026-08-05
