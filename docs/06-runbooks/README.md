# Runbooks

Procedimientos operativos reales: tres incidentes con su análisis y siete procedimientos reutilizables.

## Qué hay acá y qué no

Un runbook es lo que se lee **mientras** algo está pasando, o antes de hacer algo que puede salir mal. No explica arquitectura ni justifica decisiones: dice qué hacer, en qué orden, y cuándo parar.

Esta sección tiene dos tipos de documento:

- **Incidentes y post-mortems** — qué pasó, por qué, cómo se arregló y qué se aprendió. Se leen una vez y se releen cuando algo se parece.
- **Procedimientos** — pasos con casillas de verificación, criterios de parada y rollback. Se leen cada vez que se ejecuta la tarea.

Casi todos los procedimientos existen porque antes ocurrió un incidente. Ése es el orden real de las cosas: primero se rompe algo, después se escribe el procedimiento. El cierre fiscal mensual es la excepción parcial — se escribió para una tarea recurrente, pero varios de sus criterios de parada salen del [post-mortem de `estado_fiscal`](postmortem-estado-fiscal-divergente.md).

## Índice

| Runbook | Tipo | Cuándo usarlo |
|---|---|---|
| [Incidente: PDF de Telegram](incidente-pdf-telegram.md) | Incidente | Cuando falle la ingesta de un archivo, o antes de diseñar cualquier pipeline con descarga externa |
| [Post-mortem: drift de producción](postmortem-drift-produccion.md) | Post-mortem | Cuando sospeches que el servidor no está donde dice el repositorio |
| [Desplegar una migración](despliegue-de-una-migracion.md) | Procedimiento | **Siempre** que se aplique un cambio de esquema a producción |
| [Publicar un workflow de n8n](publicar-un-workflow-n8n.md) | Procedimiento | Antes de activar o modificar cualquier workflow en producción |
| [Limpieza de runtime](limpieza-de-runtime.md) | Procedimiento | Cuando el runtime acumule workflows viejos y haya tentación de borrar por patrón de nombre |
| [Post-mortem: `estado_fiscal` divergente](postmortem-estado-fiscal-divergente.md) | Post-mortem | Cuando dos partes del sistema respondan distinto a la misma pregunta, o antes de escribir una validación en código |
| [Cierre fiscal mensual](cierre-fiscal-mensual.md) | Procedimiento | **Todos los meses**, para cerrar un período fiscal de punta a punta |
| [Rotar una credencial expuesta](rotar-una-credencial-expuesta.md) | Procedimiento | Cuando un token, una clave o una contraseña haya estado en una carpeta sincronizada, en el historial de git, en un log o en un chat |
| [Publicar una actualización](publicar-una-actualizacion.md) | Procedimiento | Cada vez que un cambio de este repositorio tiene que llegar a GitHub |
| [Sacar datos operativos de la bóveda](sacar-datos-operativos-de-la-boveda.md) | Procedimiento | Cuando la carpeta de trabajo acumuló la dirección del servidor, volcados pesados o permisos de agente demasiado abiertos |

## Cuándo usar cada uno

### Algo está fallando ahora

| Síntoma | Empezá por |
|---|---|
| Un archivo no se procesa, un PDF no llega, la descarga falla | [Incidente PDF](incidente-pdf-telegram.md) — la sección de causa raíz aplica a cualquier descarga externa |
| Una consulta devuelve una columna que no existe, o una funcionalidad nueva no anda en el servidor | [Post-mortem de drift](postmortem-drift-produccion.md) — verificá el estado del esquema desplegado antes de depurar el código |
| Un workflow se ejecuta de más, de menos, o dos veces | [Limpieza de runtime](limpieza-de-runtime.md) — puede haber una versión vieja activa en paralelo |
| Algo se rompió después de un cambio de esquema | [Desplegar una migración](despliegue-de-una-migracion.md), sección de rollback |
| Un cierre fiscal no avanza, o dos partes del sistema dicen cosas distintas del mismo movimiento | [Post-mortem de `estado_fiscal`](postmortem-estado-fiscal-divergente.md) y el paso 5 del [cierre mensual](cierre-fiscal-mensual.md) |
| Apareció un secreto donde no tenía que estar | [Rotar una credencial expuesta](rotar-una-credencial-expuesta.md) — **rotar, no borrar**: mover el archivo no invalida el valor |

### Vas a hacer un cambio

| Qué vas a hacer | Leé antes |
|---|---|
| Aplicar una migración SQL | [Desplegar una migración](despliegue-de-una-migracion.md), completo, con las casillas |
| Activar o modificar un workflow | [Publicar un workflow](publicar-un-workflow-n8n.md), los 10 pasos |
| Borrar workflows viejos | [Limpieza de runtime](limpieza-de-runtime.md). **No borres nada sin inventario previo** |
| Diseñar un pipeline nuevo que descargue o procese archivos | [Incidente PDF](incidente-pdf-telegram.md), sección de hallazgo estructural |
| Cerrar un período fiscal | [Cierre fiscal mensual](cierre-fiscal-mensual.md), completo, con las casillas |
| Publicar cualquier cosa, o auditar la carpeta de trabajo | [Auditar antes de publicar](../05-gobernanza/auditar-antes-de-publicar.md), los nueve controles. Si encuentra un secreto, seguí con [rotar una credencial expuesta](rotar-una-credencial-expuesta.md) |
| Escribir una validación de negocio en código | [Post-mortem de `estado_fiscal`](postmortem-estado-fiscal-divergente.md) y el [ADR-012](../04-decisiones/adr-012-la-invariante-vive-en-la-base.md) antes de decidir dónde vive |
| Subir un cambio de este repositorio a GitHub | [Publicar una actualización](publicar-una-actualizacion.md). Incluye la tabla de qué hacer cuando el push falla |
| Limpiar la carpeta de trabajo: dirección del servidor escrita literal, volcados acumulados, permisos de agente que se fueron abriendo | [Sacar datos operativos de la bóveda](sacar-datos-operativos-de-la-boveda.md). Simulación primero, siempre |

## Los principios que comparten los diez

Salieron de la práctica, no de un manual:

1. **Backup verificado antes de tocar nada.** Verificado significa que se comprobó su integridad, no que el archivo existe.
2. **Todo cambio en una transacción, con parada al primer error.** Un cambio a medias es peor que ningún cambio.
3. **Verificación de no-regresión después, no sólo verificación de que el cambio se aplicó.** Confirmar que lo nuevo está y que lo viejo sigue igual son dos cosas distintas.
4. **Rollback disponible y conocido antes de empezar.** Si no sabés cómo volver, todavía no estás listo para avanzar.
5. **Inventario antes de destruir.** Dos de 79 workflows con nombre de laboratorio estaban activos y recibiendo tráfico.
6. **Los estados terminales de falla son estados legítimos.** Un pipeline que sólo modela el éxito deja casos colgados para siempre.
7. **Lo que tiene que ser siempre cierto se garantiza donde pasan todos los caminos.** Una validación escrita en código y nunca ejecutada no protege: hace creer que protege.
8. **Un secreto expuesto se rota, no se borra.** Sacar el archivo lo esconde; sólo la rotación invalida el valor. Y la rotación se comprueba: la credencial vieja tiene que devolver 401 o 403.
9. **Cada dato operativo vive en un solo lugar, y ese lugar no es la carpeta que sincroniza.** La dirección del servidor copiada en veintisiete archivos no es veintisiete veces más útil: es veintisiete veces más difícil de cambiar. Y lo que se lee de una sola fuente puede fallar fuerte cuando esa fuente no está, en vez de seguir con un valor viejo.

## Nota sobre los ejemplos

Todos los comandos de estos runbooks son **sintéticos y genéricos**. Los nombres de contenedor, base, usuario y ruta son de ejemplo. No hay direcciones, nombres de host, credenciales ni identificadores reales en ninguna parte.

Antes de correr cualquier cosa, adaptala a tu entorno y entendé qué hace.

> Última verificación: 2026-08-06
