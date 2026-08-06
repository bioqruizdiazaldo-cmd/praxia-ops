# Cuando algo falla

Guía de diagnóstico para el que usa el sistema: síntoma, causa probable, qué hacer y cuándo escalar.

## Antes de empezar

Esta guía es para vos, no para el que mantiene el servidor. No vas a tener que mirar logs ni entrar por SSH. Lo que sí vas a tener que hacer es **juntar información antes de escalar**, porque un reporte de "no anda" no se puede diagnosticar.

Hay una lista al final de [qué juntar](#qué-información-juntar-antes-de-escalar). Leela una vez ahora y vas a ahorrarte una ida y vuelta después.

## Tabla rápida

| Síntoma | Causa más probable | Ir a |
|---|---|---|
| No responde nada | Runtime caído, o el mensaje no pasó el filtro de dueño | [↓](#síntoma-no-responde-nada) |
| Dice "no tengo registrado" | Realmente no está guardado, o está guardado con otras palabras | [↓](#síntoma-responde-no-tengo-registrado) |
| El PDF no entra | Supera 20 MiB, o no es un PDF real | [↓](#síntoma-el-pdf-no-entra) |
| El mail no se envió | Quedó esperando tu aprobación | [↓](#síntoma-el-mail-no-se-envió) |
| "No encontré fuente confiable" | Es una respuesta válida, no un error | [↓](#síntoma-la-búsqueda-web-dice-que-no-encontró-fuente-confiable) |
| Un movimiento quedó pendiente | Es el comportamiento normal | [↓](#síntoma-un-movimiento-quedó-pendiente) |
| Una función que leí no existe en mi dashboard | Drift entre repositorio y servidor | [↓](#síntoma-una-función-documentada-no-aparece) |
| No llegó el briefing de la mañana | Workflow desactivado o falla nocturna | [↓](#síntoma-no-llegó-el-briefing) |

---

## Síntoma: no responde nada

Le escribís y no vuelve nada. Ni respuesta, ni error.

### Causas probables, en orden

**1. El mensaje no pasó el filtro de dueño.** El primer nodo del orquestador es `If - Owner Only`. Si escribiste desde otra cuenta de Telegram, desde otro dispositivo con otra sesión, o desde un grupo, el flujo se corta ahí sin decir nada. Es silencio por diseño.

**2. El runtime está caído.** n8n corre en Docker en un VPS. Si el contenedor se cayó, no hay nadie del otro lado.

**3. Un nodo del orquestador se rompió.** El mensaje entró pero el flujo murió a mitad de camino. En ese caso **debería** llegarte una alerta del avisador de errores — si no llegó, el avisador también puede estar afectado.

**4. Timeout de una herramienta externa.** Si el pedido dependía de Gmail, Calendar o Tavily y esa API está lenta, la respuesta puede demorar mucho más de lo normal.

### Qué hacer

1. **Esperá un minuto.** Algunas cadenas con búsqueda web o papers tardan.
2. **Mandá un mensaje trivial**: "hola". Si contesta eso, el sistema está vivo y el problema era el pedido anterior.
3. **Verificá desde qué cuenta escribiste.** Tiene que ser la del dueño, en el chat directo con el bot.
4. **Fijate si te llegó alguna alerta de error** antes o después.
5. Si nada de eso funciona, **escalá** con la información de la lista final.

### Qué NO hacer

No repitas el mismo pedido cinco veces. Si el flujo está encolado, vas a generar cinco ejecuciones y ensuciar el diagnóstico.

---

## Síntoma: responde "no tengo registrado"

Le preguntás por algo que estás seguro de haber guardado y te dice que no lo tiene.

### Lo primero: esa respuesta tiene respaldo

En el prompt del orquestador hay una prohibición explícita:

> *"Está prohibido responder 'no tengo registrado' sin haber llamado primero a PraxIA_Memory con action=consultar y haber recibido facts=[]"*

Y hay un gate de código —no un LLM— que fuerza la consulta antes de que el modelo responda. Así que **fue a buscar y volvió vacío**. La pregunta no es "¿por qué no miró?" sino "¿por qué no encontró?".

### Causas probables

**1. Nunca se guardó.** Lo dijiste en una conversación pero no le pediste que lo guarde. La memoria corta no persiste: lo que no va a la base, se pierde.

**2. Está guardado con otras palabras.** La búsqueda es por texto completo en español, no semántica. Si guardaste "acuerdo con la firma del norte" y preguntás "¿qué pasa con el proveedor?", el motor de texto puede no conectarlos. No hay embeddings que salven esa distancia.

**3. El hecho está inactivo.** Si alguna vez pediste olvidarlo, quedó con `active` en falso y no aparece más en las consultas.

**4. El gate de secretos lo rechazó al guardarlo.** Si lo que intentaste guardar tenía pinta de credencial, el Router lo derivó a `Rechazo Secreto` y nunca se escribió. Deberías haber visto una advertencia en su momento.

### Qué hacer

1. **Volvé a preguntar con las palabras exactas** que usaste al guardar.
2. **Preguntá más amplio**: "¿qué tenés guardado sobre el proyecto X?" en vez de la pregunta puntual.
3. **Mirá el espejo en Obsidian.** El export nocturno tiene todos los hechos activos en texto plano, y ahí podés buscar con Ctrl+F sin depender del motor de búsqueda. Ojo: refleja el estado de anoche, no el de hace cinco minutos.
4. **Si no está, guardalo de nuevo.** Y esta vez, guardalo con las palabras con las que vas a preguntar después.

---

## Síntoma: el PDF no entra

Mandás un PDF y vuelve un rechazo, o directamente falla.

### Causas probables

| Causa | Cómo la reconocés |
|---|---|
| **Supera 20 MiB** | El rechazo llega rápido, en la validación previa |
| **No es un PDF real** | Falla la verificación de firma `%PDF-`. Suele pasar con archivos renombrados |
| **Es un escaneo sin texto** | Entra bien pero la extracción devuelve poco o nada |
| **Problema de red o de Drive** | Falla en el paso de archivado, después de haber extraído el texto |

### El límite de 20 MiB no es arbitrario

El 2026-07-25 a las 18:25 ART, la ejecución 1292 murió con `Bad Request: file is too big` intentando bajar un PDF de 21,9 MB. La reparación que se publicó ese día puso una **validación previa**: ahora el sistema chequea el tamaño **antes** de intentar descargar, así que el rechazo es limpio en vez de ser una explosión.

### Qué hacer

**Si es por tamaño:**

- Comprimí el PDF.
- Partilo en partes.
- Subilo vos a Google Drive y pedile que lo busque desde ahí (tiene el nodo `Buscar en Drive`).

**Si es por firma:** abrí el archivo y verificá que sea realmente un PDF. Un `.docx` renombrado a `.pdf` se rechaza, y está bien que así sea.

**Si es un escaneo sin texto:** el flujo no tiene OCR documentado. Pasalo antes por una herramienta de OCR, o mandá una foto de la página y usá el flujo de imagen, que sí interpreta con el modelo.

### Dónde se cortó, exactamente

La máquina de estados te dice el punto de falla:

```
received → validated → text_extracted → reviewed → archived
                    ↘ failed
```

Si nunca pasó de `received`, fue tamaño o firma. Si llegó a `text_extracted` y no a `archived`, el problema está en Drive, no en tu archivo.

### PDF financiero

Si era un resumen de tarjeta o un extracto bancario, **no va por este flujo**. Va por la sección `importar` de Finanzas, que tiene deduplicación por SHA-256 y análisis previo. Ver [importar un documento](04-praxia-finanzas-guia-de-uso.md#importar-un-documento).

---

## Síntoma: el mail no se envió

Le pediste que mande un mail y no llegó a destino.

### La causa más probable: nunca lo aprobaste

**Esto es lo normal, no una falla.** El agente de email **no manda nada** sin aprobación humana. El flujo tiene dos nodos: `Telegram - Approve Send` te muestra el borrador y espera, e `If - Approved` decide.

Es la decisión D-7: *"Aprobación humana obligatoria para enviar mails, borrar, gastar y publicar."*

### Qué revisar

1. **Buscá el mensaje de aprobación en Telegram.** Si el chat siguió con otras cosas, quedó más arriba.
2. **¿Apretaste el botón?** No alcanza con responder "sí, dale" en texto. `[PENDIENTE DE VERIFICAR]`: la fuente no documenta si el nodo acepta respuesta libre además del botón. Usá el botón.
3. **¿Cuánto pasó?** Un pedido de aprobación viejo puede haber expirado con la ejecución.

### Si lo aprobaste y aun así no llegó

Ahí sí puede ser una falla.

- Fijate si llegó una alerta del avisador de errores.
- Verificá en la carpeta de enviados de Gmail: si está ahí, el mail salió y el problema es de entrega del otro lado (spam, casilla llena, dirección mal escrita).
- Si no está en enviados, falló el workflow `Oppenheimer - Enviar Gmail`. Escalá.

### Por qué están separados redactar y enviar

Son dos workflows distintos a propósito: el agente que redacta no tiene permiso de envío. Así, un error del redactor no puede mandar un mail. Cuesta un clic más y elimina toda una clase de accidente.

---

## Síntoma: la búsqueda web dice que no encontró fuente confiable

Le pedís que busque algo y te contesta que no encontró fuente confiable, o que la evidencia no alcanza.

### Esto no es un error

El buscador está diseñado para poder decir que no. Devuelve estados, no siempre respuestas:

| Estado | Qué significa | Qué hacer |
|---|---|---|
| `ok` | Encontró con evidencia | Nada |
| `clarification_required` | Tu pedido era ambiguo | Precisá: fecha, lugar, entidad |
| `no_reliable_source` | Buscó, no hay fuente confiable | Reformulá, o aceptá que no hay |
| `insufficient_evidence` | Hay material pero no alcanza para afirmar | Bajá la exigencia o buscá otro ángulo |
| `search_not_configured` | La búsqueda no está configurada | Escalá: es un problema del sistema |
| `technical_error` | Falló la llamada | Reintentá; si persiste, escalá |
| `stable_knowledge_handoff` | Es conocimiento estable, no hace falta web | Preguntale directo, sin pedir que busque |

**La distinción clave**: `search_not_configured` y `technical_error` son fallas del sistema. Los demás son respuestas legítimas.

### Por qué está hecho así

Porque la alternativa es peor. Un buscador que siempre contesta algo, contesta cualquier cosa cuando no encuentra. La frase que cerró el trabajo de validación lo dice bien:

> *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."*

### Qué hacer en la práctica

1. **Precisá el pedido.** Fecha concreta, entidad concreta, lugar concreto.
2. **Probá otro ángulo.** Otras palabras, otro recorte temporal.
3. **Si el tema es científico**, pedile papers en vez de búsqueda web: es otro subagente y otras fuentes.
4. **Aceptá el no.** A veces la respuesta correcta es que no hay información confiable disponible.

---

## Síntoma: un movimiento quedó pendiente

Cargaste un gasto y aparece como pendiente en vez de confirmado.

### Esto es el comportamiento normal

**Todo movimiento nace pendiente.** Por cualquier vía: Telegram, voz, dashboard, PDF, CSV, email o agente. Pendiente significa "registrado, esperando que lo des por bueno".

La razón: una transcripción de voz puede equivocar un dígito y un adaptador de PDF puede leer mal una fila. El estado pendiente es el colchón entre la carga y el dato firme.

### Qué hacer

1. Abrí la sección **`pend`** del dashboard. Es tu bandeja de entrada financiera.
2. Revisá monto, fecha, cuenta y categoría.
3. Si está bien: **confirmá**.
4. Si está mal: **corregí** (no anules y vuelvas a cargar — la corrección queda auditada y conserva el hilo).
5. Si no debería existir: **anulá**. Queda como anulado, con su rastro. No desaparece.

### Si querés saber por qué quedó pendiente

Hay dos vistas que clasifican los pendientes:

- **`v_pendientes_completables`**: le falta información que se puede completar.
- **`v_requiere_revision`**: hay algo que no cierra y necesita ojo humano.

Y si querés el historial completo de un movimiento: `GET /api/movimientos/{id}/auditoria`.

### Ojo con esto

Existe lógica de auto-confirmación en el sistema. Si un movimiento aparece confirmado sin que lo hayas tocado, probablemente sea eso. `[PENDIENTE DE VERIFICAR]`: las condiciones exactas de auto-confirmación no están documentadas en la fuente.

---

## Síntoma: una función documentada no aparece

Leíste acá que existe algo —una tabla de deudas, una vista fiscal, un endpoint— y en tu sistema no está.

### Causa probable: drift

El **drift** es la diferencia entre lo que dice el repositorio y lo que está corriendo en el servidor.

Pasó de verdad: el 2026-08-05 se descubrió que producción estaba **tres migraciones atrás desde el 31 de julio**, porque —textual— *"nadie había mirado el servidor, solo el repositorio"*. Cinco días de diferencia entre el código y la realidad.

### Qué hacer

1. **No asumas que te confundiste.** Puede ser drift real.
2. **Verificá con `GET /api/salud`** o la herramienta MCP `salud`, que reporta el estado del sistema.
3. **Escalá** indicando qué funcionalidad esperabas y de qué versión del esquema es.

### Cómo se arregla (del lado técnico)

Con backup verificado antes, migraciones con `ON_ERROR_STOP=1` dentro de una transacción, y verificación de no-regresión contando tablas antes y después. Así se hizo la puesta al día del 2026-08-05: de 25 a 35 tablas, sin pérdida.

---

## Síntoma: no llegó el briefing

Son las 8 de la mañana y no llegó ni el de noticias ni el diario.

### Causas probables

1. **El workflow quedó desactivado.** Alguien lo apagó y no lo volvió a prender.
2. **Falló durante la noche.** Debería haber llegado una alerta del avisador.
3. **Falló una dependencia**: los feeds RSS, la API de OpenAI, Calendar o el clima.
4. **El runtime estuvo caído** en ese momento.

### Qué hacer

1. **Escribile al bot.** Si contesta, el runtime está vivo y el problema es del workflow puntual.
2. **Buscá alertas de error** en el chat, de la madrugada.
3. **Pedí la información a mano**: "¿qué tengo hoy?" te da la agenda sin depender del briefing.
4. Si no llega dos días seguidos, escalá.

### Caso parecido: no se actualizó Obsidian

Si el export nocturno no aparece, distinguí dos etapas:

- **El export (23:30)** es un workflow de n8n. Si falló, debería haber alerta.
- **El sync a OneDrive (23:35)** es un cron del sistema, no un workflow. **No lo cubre el avisador de errores de n8n.** Si el export corrió pero los archivos no llegaron a OneDrive, el problema está en el cron o en rclone, y falla en silencio.

---

## Qué información juntar antes de escalar

Sin esto, el diagnóstico arranca a ciegas. Con esto, suele resolverse en una pasada.

| Dato | Por qué importa |
|---|---|
| **Hora aproximada** del intento (con zona horaria) | Permite ubicar la ejecución en los logs |
| **El texto exacto** que mandaste | La intención detectada depende de las palabras |
| **La respuesta exacta** que recibiste, o "silencio" | Distingue falla de comportamiento esperado |
| **Canal**: texto, voz, imagen o PDF | Cada uno tiene un flujo distinto |
| **Si era la primera vez** o si antes funcionaba | Separa una regresión de algo que nunca anduvo |
| **Si llegó alguna alerta de error** y qué decía | Es el diagnóstico ya hecho |
| **Para archivos**: tamaño y formato | El límite de 20 MiB explica la mitad de los casos |
| **Para finanzas**: el ID del movimiento | Permite mirar su auditoría completa |
| **Qué esperabas que pasara** | A veces el sistema hizo justo lo que debía |

### Lo que NO hay que mandar

Nunca incluyas en un reporte: contraseñas, tokens, capturas con datos financieros reales, direcciones de mail de terceros, ni identificadores de infraestructura. Es la misma política de publicación que rige todo el proyecto: *"Cambiar el nombre de una persona no es anonimización suficiente."*

## A quién escalar

`[PENDIENTE DE VERIFICAR]`: no hay un canal de soporte, un responsable de guardia ni un SLA definidos en la fuente.

El sistema es personal y autohospedado: el responsable técnico es el mismo que lo construyó. En la práctica, escalar significa registrar el problema con la información de arriba y revisarlo cuando haya tiempo de mirar el runtime.

Si en algún momento este sistema se opera para terceros, definir el canal de escalamiento y el tiempo de respuesta es un requisito previo, no un detalle.

## Un recordatorio final

El sistema tiene deudas técnicas reconocidas y publicadas: no hay separación de ambientes, los backups no tienen off-site ni ensayo de restauración demostrado, y producción convive con 125 workflows de laboratorio.

Eso significa que **algunas fallas van a ser del sistema y no tuyas**. La regla de la casa aplica también acá: *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."* Si no sabés por qué falló, decilo así.

> Última verificación: 2026-08-05
