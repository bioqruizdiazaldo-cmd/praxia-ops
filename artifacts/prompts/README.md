# Prompts

Los prompts del sistema, reconstruidos y comentados, y los patrones reutilizables que hay detrás.

> **Reconstrucción sintética.** Ningún prompt de esta carpeta es el texto literal que corre en producción. Están reescritos a partir de las reglas verificadas, con ejemplos sintéticos, y explicados. Lo que se publica es el **método**, no el archivo.

---

## Qué hay acá

| Documento | Contenido |
|---|---|
| [`orquestador-prompt-sistema.md`](orquestador-prompt-sistema.md) | Reconstrucción comentada del prompt de sistema del orquestador de Oppenheimer: rol, herramientas, reglas duras, formato de respuesta y manejo de incertidumbre |
| [`patrones-de-prompt.md`](patrones-de-prompt.md) | Los cinco patrones reutilizables que usa el sistema, con el problema que resuelve cada uno |

---

## La tesis

**Un prompt no es un control de seguridad.**

Casi todo lo que la gente escribe en un prompt de sistema como si fuera una regla es, en realidad, una preferencia: se puede rodear con una reformulación, con un cambio de idioma, con un ejemplo que confunda. Las reglas que no pueden violarse nunca no van en el prompt: van en un nodo de código, en un trigger de base de datos o en un permiso.

Lo que sí hace bien un prompt de sistema:

- Definir el rol y el alcance.
- Enumerar las herramientas y cuándo usar cada una.
- Fijar el formato de la respuesta.
- Decir qué hacer cuando falta información.
- **Explicar** las reglas que ya están aplicadas en otro lado, para que el agente pueda justificarlas cuando las invoca.

Esa última función se subestima. El guard anti-secretos rechaza en el Router, no en el prompt — pero el prompt es lo que permite que el agente diga *por qué* rechaza y ofrezca la alternativa, en vez de devolver un error críptico.

---

## Cómo se sanitizaron

1. **Reescritura completa.** No se tomó el prompt real y se le borraron cosas: se escribió de nuevo a partir de las reglas documentadas.
2. **Sin datos personales.** No hay nombres de familiares, direcciones de correo, `chat_id`, teléfonos ni referencias a personas concretas más allá del titular del sistema.
3. **Sin nombres de credenciales ni endpoints.** Las herramientas se nombran por su función.
4. **Ejemplos sintéticos y declarados.**
5. **Las citas textuales verificadas se marcan como tales.** Cuando una regla está en el prompt real con esas palabras, se cita entre comillas y se dice que es literal.

---

## Documentos relacionados

- [Oppenheimer](../../systems/oppenheimer/)
- [Contrato de subworkflow](../workflows-n8n/contrato-subworkflow.md)
- [ADR-004 — Aprobación humana en acciones consecuentes](../../docs/04-decisiones/adr-004-aprobacion-humana-en-acciones-consecuentes.md)
- [ADR-009 — Publicar el método, no el sistema](../../docs/04-decisiones/adr-009-publicar-el-metodo-no-el-sistema.md)

> Última verificación: 2026-08-05
