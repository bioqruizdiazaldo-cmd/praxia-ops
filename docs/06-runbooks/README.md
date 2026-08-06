# Runbooks

Procedimientos operativos reales: dos incidentes con su análisis y tres procedimientos reutilizables que salieron de ellos.

## Qué hay acá y qué no

Un runbook es lo que se lee **mientras** algo está pasando, o antes de hacer algo que puede salir mal. No explica arquitectura ni justifica decisiones: dice qué hacer, en qué orden, y cuándo parar.

Esta sección tiene dos tipos de documento:

- **Incidentes y post-mortems** — qué pasó, por qué, cómo se arregló y qué se aprendió. Se leen una vez y se releen cuando algo se parece.
- **Procedimientos** — pasos con casillas de verificación, criterios de parada y rollback. Se leen cada vez que se ejecuta la tarea.

Los tres procedimientos existen porque los dos incidentes ocurrieron. Ése es el orden real de las cosas: primero se rompe algo, después se escribe el procedimiento.

## Índice

| Runbook | Tipo | Cuándo usarlo |
|---|---|---|
| [Incidente: PDF de Telegram](incidente-pdf-telegram.md) | Incidente | Cuando falle la ingesta de un archivo, o antes de diseñar cualquier pipeline con descarga externa |
| [Post-mortem: drift de producción](postmortem-drift-produccion.md) | Post-mortem | Cuando sospeches que el servidor no está donde dice el repositorio |
| [Desplegar una migración](despliegue-de-una-migracion.md) | Procedimiento | **Siempre** que se aplique un cambio de esquema a producción |
| [Publicar un workflow de n8n](publicar-un-workflow-n8n.md) | Procedimiento | Antes de activar o modificar cualquier workflow en producción |
| [Limpieza de runtime](limpieza-de-runtime.md) | Procedimiento | Cuando el runtime acumule workflows viejos y haya tentación de borrar por patrón de nombre |

## Cuándo usar cada uno

### Algo está fallando ahora

| Síntoma | Empezá por |
|---|---|
| Un archivo no se procesa, un PDF no llega, la descarga falla | [Incidente PDF](incidente-pdf-telegram.md) — la sección de causa raíz aplica a cualquier descarga externa |
| Una consulta devuelve una columna que no existe, o una funcionalidad nueva no anda en el servidor | [Post-mortem de drift](postmortem-drift-produccion.md) — verificá el estado del esquema desplegado antes de depurar el código |
| Un workflow se ejecuta de más, de menos, o dos veces | [Limpieza de runtime](limpieza-de-runtime.md) — puede haber una versión vieja activa en paralelo |
| Algo se rompió después de un cambio de esquema | [Desplegar una migración](despliegue-de-una-migracion.md), sección de rollback |

### Vas a hacer un cambio

| Qué vas a hacer | Leé antes |
|---|---|
| Aplicar una migración SQL | [Desplegar una migración](despliegue-de-una-migracion.md), completo, con las casillas |
| Activar o modificar un workflow | [Publicar un workflow](publicar-un-workflow-n8n.md), los 10 pasos |
| Borrar workflows viejos | [Limpieza de runtime](limpieza-de-runtime.md). **No borres nada sin inventario previo** |
| Diseñar un pipeline nuevo que descargue o procese archivos | [Incidente PDF](incidente-pdf-telegram.md), sección de hallazgo estructural |

## Los principios que comparten los cinco

Salieron de la práctica, no de un manual:

1. **Backup verificado antes de tocar nada.** Verificado significa que se comprobó su integridad, no que el archivo existe.
2. **Todo cambio en una transacción, con parada al primer error.** Un cambio a medias es peor que ningún cambio.
3. **Verificación de no-regresión después, no sólo verificación de que el cambio se aplicó.** Confirmar que lo nuevo está y que lo viejo sigue igual son dos cosas distintas.
4. **Rollback disponible y conocido antes de empezar.** Si no sabés cómo volver, todavía no estás listo para avanzar.
5. **Inventario antes de destruir.** Dos de 79 workflows con nombre de laboratorio estaban activos y recibiendo tráfico.
6. **Los estados terminales de falla son estados legítimos.** Un pipeline que sólo modela el éxito deja casos colgados para siempre.

## Nota sobre los ejemplos

Todos los comandos de estos runbooks son **sintéticos y genéricos**. Los nombres de contenedor, base, usuario y ruta son de ejemplo. No hay direcciones, nombres de host, credenciales ni identificadores reales en ninguna parte.

Antes de correr cualquier cosa, adaptala a tu entorno y entendé qué hace.

> Última verificación: 2026-08-05
