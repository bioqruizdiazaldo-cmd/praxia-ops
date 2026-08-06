# Rutinas automáticas

Todo lo que el sistema hace solo, sin que se lo pidas: a qué hora, qué hace y cómo se apaga.

## Por qué importa saber esto

Si te llega un mensaje a las 6:30 de la mañana, no es que el agente se despertó con ganas de charlar: es una rutina programada. Conocerlas te evita confundir una automatización con una falla, y te permite apagar la que no te sirve.

Hay siete rutinas. Cuatro son de horario fijo, tres se disparan por evento.

## Tabla de rutinas

| Rutina | Cuándo | Qué hace | Cómo se apaga o se cambia |
|---|---|---|---|
| **Briefing de Noticias** | 06:30 diario | Lee RSS de Infobae, Clarín, Olé y BBC, sintetiza con OpenAI y manda a Telegram | Desactivar el workflow `Oppenheimer — Briefing Noticias` en n8n, o editar su nodo de horario |
| **Briefing Diario** | 07:00 diario | Junta agenda, tareas, mails y clima, y manda un resumen a Telegram | Desactivar `Oppenheimer - Briefing Diario` en n8n, o editar su nodo de horario |
| **Export de memoria** | 23:30 ART diario | Vuelca hechos, tareas y proyectos de PostgreSQL a Markdown en la bóveda Obsidian | Desactivar `PraxIA Sync — Export MD` en n8n |
| **Sync a OneDrive** | 23:35 diario | Un cron con rclone sube los archivos exportados a OneDrive | No es un workflow de n8n: es un cron en el servidor. Se cambia editando el cron |
| **Alertas TradingView** | Por evento | Recibe la alerta por webhook y la reenvía a Telegram | Se apaga desde TradingView (borrando la alerta) o desactivando el workflow en n8n |
| **Recordatorios** | Por evento | Espera el tiempo pedido y manda el aviso por Telegram | Los creás vos pidiéndoselos. `[PENDIENTE DE VERIFICAR]`: no hay flujo documentado para cancelar un recordatorio ya programado |
| **Avisador de errores** | Por falla | Registra en `praxia.agent_errors` y alerta por Telegram | **No conviene apagarlo.** Es la red de seguridad del sistema entero |

## Detalle de cada una

### Briefing de Noticias — 06:30

Es lo primero que llega. Un resumen de titulares de cuatro medios: **Infobae, Clarín, Olé y BBC**.

El circuito es corto: se leen los feeds RSS, se sintetiza todo con OpenAI y se manda un mensaje a Telegram.

**Qué esperar.** Un panorama, no periodismo verificado. No cruza fuentes ni chequea nada. Si algo del briefing te importa de verdad, pedile al [Buscador Web](03-subagentes.md#buscador-web-tavily-v1) que lo profundice: ese sí devuelve estado de evidencia.

Nació el 2026-07-15.

### Briefing Diario — 07:00

Media hora después llega el briefing personal, con cuatro bloques:

- **Agenda** del día, desde Google Calendar.
- **Tareas** pendientes, desde la memoria estructurada.
- **Mails** relevantes.
- **Clima**, desde Open-Meteo.

**Qué esperar.** Es informativo. No agenda nada, no contesta mails, no cierra tareas. Te da el estado y vos decidís.

Nació el 2026-07-14, junto con el orquestador.

### Export de memoria — 23:30 ART

Todas las noches, la memoria estructurada se vuelca a Markdown en la bóveda Obsidian.

**Qué exporta.** Hechos activos, tareas y proyectos. Deduplica y **omite explícitamente los secretos** — aunque en teoría no debería haber ninguno, porque el gate los frena en la escritura.

**Cómo verificar que corrió.** El export deja un resumen. El del 2026-08-05 02:30 UTC dice: 2 proyectos, 26 hechos, 4 tareas, 1 deduplicada, **0 secretos omitidos**.

Ese último número es una métrica de salud: si algún día no es cero, alguien intentó guardar algo que no debía.

**Dirección del flujo**: de la base al archivo, nunca al revés. Ver [memoria](05-memoria-que-recuerda-y-que-no.md#3-memoria-documental--el-espejo).

Operativo desde el 2026-07-19/20. El primer export tenía 7 hechos, 1 proyecto y 1 tarea.

### Sync a OneDrive — 23:35

Cinco minutos después del export, un **cron del sistema operativo** con **rclone** sube los archivos a OneDrive.

**Ojo con la diferencia.** Esta rutina no vive en n8n: vive en el crontab del servidor. Si el export corrió pero no ves los archivos en OneDrive, el problema está acá y se diagnostica distinto.

**El margen de cinco minutos** es a propósito: le da tiempo al export a terminar de escribir antes de que rclone empiece a copiar.

### Alertas TradingView — por evento

Cuando una alerta que configuraste en TradingView se dispara, TradingView llama a un webhook de n8n y el mensaje te llega por Telegram.

**Dónde vive la lógica.** En TradingView, no acá. El workflow solo transporta.

**Qué no hace.** No opera, no compra, no vende, no toca ningún broker. Y no guarda nada en la base financiera.

Nació el 2026-07-15.

### Recordatorios — por evento

Los creás vos: "recordame en dos horas llamar al taller". El flujo es webhook + nodo `Wait` + Telegram.

**Limitación conocida.** `[PENDIENTE DE VERIFICAR]`: la fuente no documenta cómo listar ni cancelar recordatorios ya programados. Si programaste uno y ya no lo querés, la vía documentada no existe.

**Alternativa más robusta** para cosas importantes: guardalo como tarea en la memoria estructurada. Ahí sí podés consultarlo, modificarlo y darlo de baja, y además aparece en el briefing de las 07:00.

### Avisador de errores — por falla

No tiene horario: se dispara cuando algo se rompe. Está enganchado como **`errorWorkflow` global** de n8n, así que cubre a todos los demás workflows.

**Qué hace al dispararse.** Escribe una fila en `praxia.agent_errors` usando la función `praxia.upsert_agent_error`, y manda una alerta a Telegram.

**Anti-spam.** La deduplicación y el anti-spam están validados. Si el mismo error se repite cien veces, no recibís cien mensajes.

**Por qué no lo apagues.** Sin esto, una falla silenciosa puede pasar días sin que te enteres. Es exactamente lo que pasó con el drift entre repositorio y servidor: nadie miró, y pasaron cinco días.

**Deuda técnica visible.** El workflow **todavía se llama con el prefijo `[TEST]`** aunque está en producción desde el 2026-07-23. Si lo ves así en n8n, no lo desactives pensando que es una prueba.

## Cómo se apaga o se cambia una rutina

Hay tres mecanismos distintos según dónde viva la rutina.

### Rutinas de n8n

Las cinco que son workflows de n8n (los dos briefings, el export, TradingView y los recordatorios) se controlan desde la interfaz de n8n:

- **Apagar**: desactivar el workflow con el toggle de activo/inactivo. Deja de correr, no se pierde.
- **Cambiar el horario**: editar el nodo de trigger de horario dentro del workflow.
- **Cambiar el contenido**: editar los nodos correspondientes.

`[PENDIENTE DE VERIFICAR]`: la fuente no documenta un procedimiento formal de cambio para estas rutinas. Lo de arriba es la operación estándar de n8n, no un runbook aprobado del proyecto.

### El cron del sistema

El sync a OneDrive de las 23:35 es un cron en el servidor. Se cambia editando el crontab. Requiere acceso al VPS, que está restringido —el SSH se cerró tras el despliegue verificado del 2026-07-23—.

### Las alertas de TradingView

Se administran en TradingView. Borrar o pausar la alerta allá corta el flujo en el origen.

## Antes de tocar cualquier rutina

Tres reglas de la gobernanza del proyecto que aplican también acá.

**1. Guardá el rollback.** Antes de modificar un workflow activo, exportá la versión que funciona. Es lo que se hizo el 2026-07-20 antes de meter el Memory Gate.

**2. Inspección no es autorización.** Textual, del AI Working Agreement: *"Inspección no equivale a autorización de cambio."* Mirar cómo está armado un workflow no habilita a modificarlo.

**3. Verificá después.** Un workflow que quedó activo pero roto es peor que uno apagado. Después de cambiar un horario, esperá el siguiente ciclo y confirmá que llegó el mensaje.

## Resumen del día

Así se ve una jornada completa si no hacés nada:

```
06:30  →  Briefing de noticias en Telegram
07:00  →  Briefing diario: agenda, tareas, mails, clima
  ...     (durante el día: solo respondés vos, o llegan alertas)
23:30  →  Export de memoria a Markdown
23:35  →  Sync a OneDrive
```

Dos mensajes a la mañana, dos tareas silenciosas a la noche. El resto del día el sistema está callado salvo que le hables o que algo falle.

> Última verificación: 2026-08-05
