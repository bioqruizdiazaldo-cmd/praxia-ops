# Contrato de subworkflow

El acuerdo de entrada y salida que cumple todo subagente invocado como herramienta desde el orquestador.

> **Reconstrucción didáctica.** El contrato descripto es el patrón real del sistema; los ejemplos JSON son **sintéticos**.

---

## Por qué hace falta un contrato

Un subagente invocado desde un orquestador con LLM tiene un problema que no tiene una función normal: **el que lo llama interpreta la respuesta con un modelo de lenguaje.** Si la salida es texto libre, el modelo la interpreta bien casi siempre — y "casi siempre" es exactamente el tipo de fiabilidad que no sirve para mandar un mail o registrar un gasto.

El contrato resuelve eso con tres reglas:

1. **La salida siempre tiene la misma forma**, haya salido bien o mal.
2. **El estado es un valor de una lista cerrada**, no una frase.
3. **El fracaso es un estado, no una excepción.** Un subagente que se cae le deja al orquestador un error genérico; uno que devuelve `technical_error` le deja algo que puede explicar.

---

## Forma general

### Entrada

```jsonc
{
  "action":       "string",   // obligatorio · verbo de una lista cerrada
  "payload":      { },        // obligatorio · parámetros de la acción
  "contexto":     { },        // opcional   · lo que el orquestador ya sabe
  "requiere_aprobacion": true // opcional   · fuerza el paso humano
}
```

| Campo | Regla |
|---|---|
| `action` | Verbo de una lista cerrada y documentada. Nunca lenguaje natural |
| `payload` | Sólo los datos que esa acción necesita. Permiso mínimo también en los datos |
| `contexto` | Hechos de memoria, fecha resuelta, perfil. Evita que el subagente repregunte |
| `requiere_aprobacion` | El llamador puede exigir aprobación aunque la acción no la exija por defecto. Nunca al revés |

### Salida

```jsonc
{
  "estado":   "string",   // obligatorio · valor de la lista cerrada del subagente
  "datos":    { },        // presente sólo si estado = ok
  "mensaje":  "string",   // texto breve para el usuario, en español
  "motivo":   "string",   // por qué no salió ok · null si salió ok
  "evidencia": [ ],       // fuentes, ids, referencias verificables
  "meta": {
    "subagente": "string",
    "version":   "string",
    "duracion_ms": 0
  }
}
```

---

## Las cinco reglas duras

### 1. Estados cerrados y tipados

Cada subagente publica su lista de estados en el manifiesto. El buscador web tiene siete: `ok`, `clarification_required`, `no_reliable_source`, `search_not_configured`, `technical_error`, `stable_knowledge_handoff`, `insufficient_evidence`.

Un subagente de escritura tiene otros: `ok`, `pendiente_aprobacion`, `rechazado_por_usuario`, `validacion_fallida`, `technical_error`.

**El orquestador nunca ve un estado que no esté en la lista.**

### 2. El error no se propaga como excepción

Las llamadas HTTP salientes van con la opción de no fallar (`neverError=true` en n8n) y un timeout explícito. El fallo se captura y se traduce a un estado del contrato.

La excepción sí llega al `errorWorkflow` global cuando es un fallo del propio subworkflow, no del servicio que consulta. Son dos cosas distintas: un proveedor caído es un estado; un nodo mal configurado es un error.

### 3. Ausencia de dato no es cero ni invento

Si no hay evidencia, el estado lo dice y `datos` viene vacío. Nunca un cero, nunca un valor por defecto, nunca una estimación silenciosa.

> *"La ausencia de datos no debe convertirse en un dato inventado."*

### 4. La aprobación humana es un paso del flujo

Cuando la acción es consecuente —enviar, borrar, gastar, publicar— el subagente **no la ejecuta y devuelve `pendiente_aprobacion`** con el borrador exacto de lo que haría. El orquestador muestra ese borrador, espera la confirmación y recién entonces vuelve a llamar con el token de aprobación.

Lo que se aprueba es exactamente lo que se ejecuta. Si el contenido cambia entre la aprobación y la ejecución, la aprobación no vale.

### 5. Sin secretos, en ninguna dirección

Ni el `payload` ni los `datos` transportan credenciales. Las credenciales viven en la configuración del nodo, referenciadas simbólicamente. Un subagente que recibe un token en el payload es un subagente que va a loguearlo.

---

## Ejemplo completo — subagente de email

**Datos sintéticos.** Direcciones, nombres e identificadores inventados.

### Llamada 1 — el orquestador pide redactar y enviar

```json
{
  "action": "redactar_y_enviar",
  "payload": {
    "destinatario": "destinatario.ejemplo@example.com",
    "asunto": "Confirmación de reunión del jueves",
    "puntos": [
      "Confirmar el horario de las 15:00",
      "Pedir el orden del día",
      "Avisar que la reunión es remota"
    ],
    "tono": "profesional_breve"
  },
  "contexto": {
    "fecha_resuelta": "2026-08-05",
    "facts": [
      { "id": 7, "fact": "Las reuniones remotas se hacen por videollamada" }
    ]
  },
  "requiere_aprobacion": true
}
```

### Respuesta 1 — no envía, propone

```json
{
  "estado": "pendiente_aprobacion",
  "datos": null,
  "mensaje": "Redacté el mail. Necesito tu confirmación antes de enviarlo.",
  "motivo": "accion_consecuente_requiere_aprobacion",
  "evidencia": [],
  "borrador": {
    "destinatario": "destinatario.ejemplo@example.com",
    "asunto": "Confirmación de reunión del jueves",
    "cuerpo": "Hola:\n\nTe confirmo la reunión del jueves a las 15:00. ¿Me pasás el orden del día? La hacemos por videollamada.\n\nSaludos.",
    "huella": "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  },
  "meta": {
    "subagente": "oppenheimer.agente-email",
    "version": "v3",
    "duracion_ms": 1840
  }
}
```

La `huella` es lo que une la aprobación al contenido: si el cuerpo cambiara, la huella cambiaría y la aprobación dejaría de ser válida.

### Llamada 2 — después de que la persona confirmó en Telegram

```json
{
  "action": "enviar_aprobado",
  "payload": {
    "huella": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    "aprobado_por": "owner",
    "aprobado_at": "2026-08-05T14:22:10Z"
  }
}
```

### Respuesta 2 — ejecutado

```json
{
  "estado": "ok",
  "datos": {
    "mensaje_id": "MSG-EJEMPLO-0001",
    "enviado_at": "2026-08-05T14:22:12Z"
  },
  "mensaje": "Mail enviado.",
  "motivo": null,
  "evidencia": [
    { "tipo": "mensaje_enviado", "ref": "MSG-EJEMPLO-0001" }
  ],
  "meta": {
    "subagente": "oppenheimer.agente-email",
    "version": "v3",
    "duracion_ms": 920
  }
}
```

### Respuesta alternativa — la persona rechazó

```json
{
  "estado": "rechazado_por_usuario",
  "datos": null,
  "mensaje": "No envié el mail.",
  "motivo": "aprobacion_denegada",
  "evidencia": [],
  "meta": {
    "subagente": "oppenheimer.agente-email",
    "version": "v3",
    "duracion_ms": 310
  }
}
```

El rechazo es un resultado normal del contrato, no un error. El orquestador lo informa y sigue.

---

## Ejemplo — subagente de memoria rechazando un secreto

**Dato sintético.**

### Llamada

```json
{
  "action": "guardar",
  "payload": {
    "fact": "El token de la API de ejemplo es TOKEN_DE_EJEMPLO_1234",
    "category": "recordar"
  }
}
```

### Respuesta

```json
{
  "estado": "rechazado_por_politica",
  "datos": null,
  "mensaje": "No guardo tokens ni credenciales. Puedo anotar dónde está guardado, sin el valor.",
  "motivo": "gate_de_secretos",
  "evidencia": [
    { "tipo": "regla", "ref": "hecho #14", "texto": "Nunca guardar contraseñas, tokens, API keys, claves privadas, credenciales ni datos bancarios completos." }
  ],
  "sugerencia": {
    "fact": "El token de la API de ejemplo está en las credenciales del runtime, referencia CRED_EJEMPLO",
    "category": "seguridad"
  },
  "meta": {
    "subagente": "praxia.memory-router",
    "version": "v1",
    "duracion_ms": 40
  }
}
```

Dos detalles que importan: el rechazo **cita la regla** (así el agente puede explicarla) y **ofrece la alternativa** (así el usuario consigue lo que realmente necesitaba). Un guard que sólo dice que no obliga a la persona a buscar la forma de rodearlo.

---

## Checklist antes de publicar un subagente

- [ ] La lista de `action` está cerrada y documentada en el manifiesto.
- [ ] La lista de `estado` está cerrada y documentada en el manifiesto.
- [ ] Toda llamada saliente tiene timeout explícito y no aborta la ejecución.
- [ ] Existe al menos un fixture por cada estado de salida.
- [ ] Las acciones consecuentes devuelven `pendiente_aprobacion` y no ejecutan.
- [ ] Lo aprobado está atado al contenido por una huella.
- [ ] Ningún campo del contrato transporta credenciales.
- [ ] La ausencia de dato produce un estado, no un cero.
- [ ] El subagente está enlazado al `errorWorkflow` global.

> Última verificación: 2026-08-05
