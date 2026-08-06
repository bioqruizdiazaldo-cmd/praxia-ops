# ADR-004 — Aprobación humana en acciones consecuentes

Mandar un mail, borrar, gastar y publicar pasan por una persona. No es una preferencia de configuración: es una restricción de arquitectura.

## Estado

Vigente.

## Fecha

2026-07-14 — decisión D-7 de la planificación maestra.
Implementada progresivamente: aprobación de envío de correo entre el 14 y el 24 de julio, prohibición de borrado el 27 de julio, gate de escritura financiera y scopes MCP entre el 27 de julio y el 3 de agosto.

## Contexto

Un agente con acceso a Gmail, Calendar, Drive, Sheets y una base financiera puede hacer cosas que no se deshacen. Un mail enviado no vuelve. Un registro borrado no vuelve. Un movimiento mal cargado ensucia un saldo que después alguien usa para decidir.

El riesgo no es principalmente que el modelo alucine, aunque también. Es más banal y más frecuente: **una instrucción ambigua interpretada con demasiada iniciativa**. "Contestale a Juan" tiene una lectura razonable y varias desastrosas.

La decisión D-7 se tomó el mismo día que la planificación maestra, antes de que existiera un solo workflow que pudiera mandar un mail. Ese orden importa: la restricción se fijó antes de que hubiera algo funcionando que se sintiera cómodo dejar suelto.

El criterio para decidir qué requiere aprobación no fue "qué es peligroso" —demasiado vago— sino una prueba concreta de dos preguntas:

1. **¿Es reversible por el propio sistema?**
2. **¿Es visible para un tercero, o mueve plata?**

Si la respuesta a la primera es no, o la respuesta a la segunda es sí, requiere una persona.

## Decisión

**Cuatro clases de acción requieren aprobación humana explícita: enviar correo, borrar, gastar y publicar.**

Cada una se implementa con un mecanismo distinto, apropiado a su capa:

### 1. Enviar correo — aprobación interactiva en el canal

El subagente de correo puede buscar, leer y redactar sin pedir nada. **Enviar** pasa por dos nodos:

`Telegram - Approve Send` → `If - Approved`

El borrador completo se muestra en el chat y no sale nada hasta que la persona confirma. El envío efectivo lo hace un workflow separado (`Oppenheimer - Enviar Gmail`), disparado únicamente después de la confirmación. Separar redacción de envío en dos workflows distintos hace que un error en el primero no pueda producir un envío.

### 2. Borrar — no existe el camino

Acá la decisión fue más fuerte que pedir permiso: **se eliminó la capacidad**. En el sistema financiero no hay borrado físico posible.

- Trigger `prohibir_delete_fisico` en la base.
- El rol `praxia_finanzas_rw` **no tiene permiso `DELETE`**.
- **Cero endpoints `DELETE`** en toda la API.
- Baja lógica con auditoría en `movimientos_auditoria`, y una tabla `fiscal_auditoria` inmutable.

Está desarrollado en el [ADR-007](adr-007-sin-borrado-fisico.md). Se menciona acá porque es el caso donde la aprobación humana se resolvió quitando la acción en lugar de custodiarla. Cuando se puede, es mejor.

### 3. Gastar — escritura mínima y confirmación explícita

En el sistema financiero la superficie de escritura es deliberadamente chica. De las 22 herramientas MCP:

| Scope | Herramientas | Naturaleza |
|---|---|---|
| `praxia.read` | 8 | Solo lectura |
| `praxia.fiscal.read` | 10 | Solo lectura |
| `praxia.write` | 1 | Alta de movimiento |
| `praxia.modify` | 4 | **Marcadas "¡REQUIERE CONFIRMACIÓN EXPLÍCITA!"** |

**Dieciocho de veintidós son de lectura.** Las cuatro de `praxia.modify` —corregir, confirmar, anular e importar documento— llevan la advertencia dentro de la propia descripción de la herramienta, de modo que llega al cliente LLM en el momento de decidir si la usa.

Y la regla que cierra el diseño, textual del contrato:

> *"La aprobación no ejecuta nada financieramente."*

Es la frase más importante de este ADR. Significa que aprobar una propuesta, una clasificación fiscal o un registro **no mueve un saldo**. El impacto financiero ocurre en un acto separado y explícito: *"El impacto financiero ocurre únicamente al registrar o vincular un pago real, y un pago se contabiliza exactamente una vez."*

Separar "estoy de acuerdo" de "ejecutá" evita la clase entera de errores donde alguien aprueba un texto y sin darse cuenta mueve dinero.

### 4. Publicar — no hay canal automático

Ningún agente publica en redes por su cuenta. El pipeline de contenido de AI-Command-Center tiene una etapa `02_en_revision` antes de `03_aprobado`, y las carpetas están vacías al corte. La restricción se sostiene, entre otras razones, porque no hay nada que publicar todavía.

### Defensa contra la insistencia

Una restricción de aprobación se rompe por desgaste, no por bypass técnico. La observación quedó escrita así:

> *"Un agente que puede repreguntar sin límite termina consiguiendo el 'sí' por cansancio."*

La respuesta está en el esquema, en la migración v4.8: la tabla `fiscal_propuestas` tiene campos `huella` y `huella_evidencia`, con triggers `propuesta_nace_pendiente`, `propuesta_contenido_inmutable` y `propuesta_transicion_valida`. La huella impide volver a proponer lo mismo; la huella de evidencia impide aprobar algo cuya base ya caducó; la inmutabilidad del contenido impide que lo aprobado sea distinto de lo mostrado.

**El control de fatiga vive en la base de datos, no en el prompt.**

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Aprobación humana en las cuatro clases, con mecanismo por capa** | Cubre lo irreversible sin frenar lo cotidiano; cada control vive donde es imposible saltearlo | Fricción real en el uso diario; cuatro mecanismos que mantener | **Elegida** |
| Aprobación para todo | Máxima seguridad | El agente deja de ser útil; **la fricción constante entrena a aprobar sin leer**, que es peor que no tener control | Rechazada |
| Sin aprobación, con deshacer posterior | Mejor experiencia de uso | Un mail enviado no se deshace. La premisa no se cumple para las acciones que importan | Rechazada |
| Aprobación sólo en el prompt del sistema | Barato de implementar | Un prompt no es una garantía. Una instrucción bien armada lo rodea | Rechazada |
| Lista blanca de destinatarios y montos, sin persona | Automatiza el caso rutinario | Toda la dificultad se traslada a mantener la lista; la clase de error que preocupa es la ambigüedad, no el destinatario | Postergada |

## Consecuencias

### Positivas

- **Ningún incidente de envío o borrado indebido** en 22 días de operación. Estado: `Verificado` por ausencia de registro en la auditoría de errores.
- La restricción **se convirtió en diseño**: el rol de base sin `DELETE` y la ausencia de endpoints de borrado son consecuencia directa de D-7, y son controles que no dependen de la disciplina de nadie.
- La separación entre aprobar y ejecutar hace que el peor caso de un error de aprobación sea un registro mal clasificado, no un saldo mal movido.
- Las advertencias en las descripciones de las herramientas MCP viajan hasta el cliente LLM, incluso uno que no controlamos.
- El control anti-insistencia está en el esquema, con lo cual sobrevive a cualquier cambio de prompt o de modelo.

### Negativas

- **Hay fricción real.** Cada mail necesita un toque en el teléfono. Para un asistente que busca ahorrar tiempo, es un costo que se paga todos los días.
- **La aprobación se puede volver un reflejo.** Nadie mide con qué atención se lee el borrador antes de confirmar. Estado: `Pendiente de verificar`.
- No hay **auditoría de las aprobaciones en sí**: se registra que hubo confirmación, no cuánto tiempo pasó ni si se leyó. Estado: `Pendiente de verificar`.
- La cobertura de "publicar" **no está probada**, porque no hay publicación automática todavía. Es una restricción sin ejercitar.

### Operativas

- Si la persona no está disponible, la acción no ocurre. Es el comportamiento buscado, y hay que decirlo: **el sistema no es autónomo en las acciones que importan**.
- No hay caducidad declarada para una aprobación pendiente. Un borrador puede quedar esperando indefinidamente. Estado: `Pendiente de verificar`.
- Cuatro mecanismos distintos significan cuatro cosas que verificar cuando se toca el diseño.

### De seguridad

- **La aprobación es un control de autorización, no de autenticación.** Funciona porque el canal está restringido a un único remitente por el filtro `If - Owner Only`. Si ese filtro fallara, la aprobación no protegería nada: quien controla el canal aprueba.
- Los cuatro scopes OAuth del servidor MCP separan lectura de escritura a nivel de token. Un cliente con `praxia.read` **no puede** escribir aunque el modelo lo intente. Ese es el control duro; la advertencia en la descripción de la herramienta es el blando.
- La inmutabilidad del contenido de las propuestas cierra un ataque concreto: mostrar una cosa, aprobarla, y guardar otra.
- Riesgo residual reconocido: hay defaults inseguros en el servidor MCP —secreto de firma y contraseña de propietario— que aplican sólo si faltan las variables de entorno. Un despliegue mal configurado degradaría la autenticación y, con ella, el valor de toda esta cadena. Está en la lista de deudas abiertas.

## Evidencia

| Afirmación | Estado |
|---|---|
| D-7 del 2026-07-14: aprobación humana para enviar mails, borrar, gastar y publicar | `Verificado` |
| Nodos `Telegram - Approve Send` → `If - Approved` en el subagente de correo | `Verificado` |
| Workflow de envío separado, disparado tras confirmación | `Verificado` |
| Filtro `If - Owner Only` en el trigger de Telegram | `Verificado` |
| Trigger `prohibir_delete_fisico`, rol sin `DELETE`, cero endpoints `DELETE` | `Verificado` |
| 22 herramientas MCP en 4 scopes; 4 de ellas marcadas "¡REQUIERE CONFIRMACIÓN EXPLÍCITA!" | `Verificado` |
| Cita textual *"La aprobación no ejecuta nada financieramente"* | `Verificado` |
| Cita textual sobre el "sí" por cansancio | `Verificado` |
| `fiscal_propuestas` con `huella`, `huella_evidencia` y los tres triggers | `Verificado` |
| Email V3 validado con 5 pruebas aisladas el 2026-07-24, con cierre declarado provisional | `Verificado` |
| Ausencia de incidentes de envío indebido | `Inferido` — por ausencia de registro, no por una auditoría dedicada |
| Calidad de la atención humana al aprobar | `Pendiente de verificar` |
| Cobertura efectiva de la clase "publicar" | `Historia incompleta` — no hay publicación automática que la ejercite |

## Disparador de revisión

Revisar cuando:

- **Se detecte aprobación por reflejo**: confirmaciones sistemáticamente en menos de unos pocos segundos serían la señal. Requiere instrumentar el tiempo entre propuesta y aprobación, que hoy no se mide.
- Aparezca un **segundo usuario**. La aprobación asume un solo dueño; con dos personas hace falta definir quién aprueba qué.
- Se active un **canal de publicación real**. La restricción sobre "publicar" pasaría de teórica a operativa y habría que implementarla de verdad.
- El **volumen de correo** haga inviable la aprobación uno por uno. Ahí correspondería evaluar la lista blanca acotada, no eliminar el control.
- Se agregue **cualquier herramienta nueva que escriba**. Toda alta en el scope `praxia.write` o `praxia.modify` obliga a releer este ADR antes de publicarse.

> Última verificación: 2026-08-05
