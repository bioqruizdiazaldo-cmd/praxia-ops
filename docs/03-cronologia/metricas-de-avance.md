# Métricas de avance

Los números duros del sistema, cada uno con su fecha de corte y su fuente — y un párrafo honesto sobre qué no miden.

Todas las cifras salen de una inspección directa de artefactos el 2026-08-05, salvo donde se indique otra fecha de corte. Ningún número está proyectado ni redondeado hacia arriba.

## Runtime n8n

| Métrica | Valor | Fecha de corte | Evidencia |
|---|---|---|---|
| Workflows registrados | 217 | 2026-08-03 | `Verificado` |
| Workflows activos | 25 | 2026-08-03 | `Verificado` |
| Workflows archivados | 25 | 2026-08-03 | `Verificado` |
| Workflows con nomenclatura de laboratorio | 125 | 2026-08-03 | `Verificado` |
| Nodos del orquestador | 51 | 2026-08-03 | `Verificado` |
| Nodos del orquestador (backup anterior) | 47 | 2026-07-27 | `Verificado` |
| Nodos del orquestador (aprobación productiva) | 37 | 2026-07-23 | `Verificado` |
| Nodos del Buscador Web Tavily V1 | 9 | 2026-07-25 | `Verificado` |
| Workflows de n8n en PraxIA Finanzas | 9 | 2026-08-05 | `Verificado` |
| Workflows totales en la auditoría de memoria | 44 | 2026-07-24 | `Verificado` |
| Versión de n8n | 2.31.5 | 2026-08-05 | `Verificado` |

El orquestador creció de 37 a 51 nodos en once días: **+38%** sin reescritura. La razón es que las capacidades nuevas se agregaron como subagentes invocados, no como ramas dentro del workflow central.

## Ejecuciones

| Métrica | Valor | Fecha de corte | Evidencia |
|---|---|---|---|
| Ejecuciones conservadas | 377 | 2026-08-03 | `Verificado` |
| Exitosas (ventana de 7 días) | 343 | 2026-08-03 | `Verificado` |
| Fallidas (ventana de 7 días) | 19 | 2026-08-03 | `Verificado` |
| Tasa de éxito de la ventana | 94,8% | 2026-08-03 | `Inferido` (cálculo sobre 343 / 362) |
| Filas en `praxia.agent_errors` al aprobar la integración | 0 | 2026-07-23 | `Verificado` |

La ventana de retención es de 7 días y 377 no es el total histórico de ejecuciones del sistema: es lo que quedaba conservado al momento del corte. El total histórico está `Pendiente de verificar`.

## Datos y esquemas

| Métrica | Valor | Fecha de corte | Evidencia |
|---|---|---|---|
| Tablas en producción (post puesta al día) | 35 | 2026-08-05 | `Verificado` |
| Tablas en producción (pre puesta al día) | 25 | 2026-08-05 | `Verificado` |
| Migraciones SQL sin control de versiones al checkpoint | 33 | 2026-07-28 | `Verificado` |
| Líneas de JavaScript sin control de versiones al checkpoint | 3.275 | 2026-07-28 | `Verificado` |
| Versión del esquema `praxia_finanzas` | v4.8 | 2026-08-05 | `Verificado` |
| Migraciones de atraso detectadas en el drift | 3 (v4.4 → v4.6) | 2026-08-05 | `Verificado` |
| Días de drift entre repositorio y servidor | 5 (31/07 → 05/08) | 2026-08-05 | `Verificado` |
| Versión de PostgreSQL | 16 | 2026-08-05 | `Verificado` |

## Memoria

| Métrica | Valor | Fecha de corte | Evidencia |
|---|---|---|---|
| Hechos en el primer export | 7 | 2026-07-19 | `Verificado` |
| Proyectos en el primer export | 1 | 2026-07-19 | `Verificado` |
| Tareas en el primer export | 1 | 2026-07-19 | `Verificado` |
| Hechos en el último export | 26 | 2026-08-05 02:30 UTC | `Verificado` |
| Proyectos en el último export | 2 | 2026-08-05 02:30 UTC | `Verificado` |
| Tareas en el último export | 4 | 2026-08-05 02:30 UTC | `Verificado` |
| Entradas deduplicadas en el último export | 1 | 2026-08-05 02:30 UTC | `Verificado` |
| Secretos omitidos en el último export | 0 | 2026-08-05 02:30 UTC | `Verificado` |
| Capas de memoria implementadas | 4 | 2026-08-05 | `Verificado` |
| Índices vectoriales o embeddings | 0 | 2026-08-05 | `Verificado` |

Veintiséis hechos después de 17 días de uso es un número deliberadamente chico. La memoria se diseñó para guardar decisiones y reglas, no para acumular transcripciones. El contador de secretos omitidos en cero significa que el gate no tuvo que actuar en ese export, no que el gate no exista.

## PraxIA Finanzas — código, tests y superficie

| Métrica | Valor | Fecha de corte | Evidencia |
|---|---|---|---|
| Casos de test | 554 | 2026-08-05 | `Verificado` |
| Archivos de test | 27 | 2026-08-05 | `Verificado` |
| Casos de test en el cierre de Fase 3 | 141/141 | 2026-07-28 | `Verificado` |
| Endpoints HTTP declarados | 60+ | 2026-08-05 | `Verificado` |
| Endpoints `DELETE` | 0 | 2026-08-05 | `Verificado` |
| Operaciones de la capa fiscal de solo lectura | 9 | 2026-08-04 | `Verificado` |
| Herramientas MCP | 22 | 2026-08-05 | `Verificado` |
| Scopes OAuth del servidor MCP | 4 | 2026-08-05 | `Verificado` |
| Herramientas MCP que exigen confirmación explícita | 4 (`praxia.modify`) | 2026-08-05 | `Verificado` |
| Dependencias de runtime del backend | 1 (`pg`) | 2026-08-05 | `Verificado` |
| Líneas del frontend (archivo único) | 1.911 | 2026-08-05 | `Verificado` |
| Secciones del dashboard | 7 | 2026-08-05 | `Verificado` |
| Versión de la API declarada en OpenAPI | 3.6.0 | 2026-08-05 | `Verificado` |
| Versión del paquete del backend | 0.2.0 | 2026-08-05 | `Verificado` |
| Versión del servidor MCP | 1.0.0 | 2026-08-05 | `Verificado` |
| Versión del contrato Finanzas↔Fiscal | 1.0 | 2026-08-04 | `Verificado` |

El reparto de las 22 herramientas MCP por scope: 8 en `praxia.read`, 10 en `praxia.fiscal.read`, 1 en `praxia.write`, 4 en `praxia.modify`. **Dieciocho de veintidós son de solo lectura.** Eso es una decisión de diseño, no una limitación pendiente de completar.

## Verificaciones y pruebas puntuales

| Prueba | Resultado | Fecha | Evidencia |
|---|---|---|---|
| Reparación del pipeline de PDF | 6/6 PASS | 2026-07-25 | `Verificado` |
| Corrección de fechas del buscador | 8/8 PASS | 2026-07-26 | `Verificado` |
| Corrección estructural del contexto del buscador | 8/8 PASS | 2026-07-26 | `Verificado` |
| Email V3, pruebas aisladas | 5/5 OK | 2026-07-24 | `Verificado` |
| Cierre de Fase 3 de Finanzas | 141/141 | 2026-07-28 | `Verificado` |
| **Buscador General, revalidación real acotada** | **2/7 PASS con exigencia de 7/7 → no publicado** | 2026-07-27 | `Verificado` |

## Limpieza de runtime

| Clase | Cantidad | Criterio | Fecha de corte |
|---|---|---|---|
| A — borrables | 73 | Sin tráfico, sin dependencias, reemplazados | 2026-07-25 |
| B — revisar antes de tocar | 4 | Dependencia o valor histórico no descartado | 2026-07-25 |
| C — activos con tráfico | 2 | Ejecutándose en producción | 2026-07-25 |
| **Total inventariado** | **79** | | 2026-07-25 |

Dos de esos 79 workflows con nombre de laboratorio estaban activos y recibiendo tráfico. Un borrado por patrón de nombre habría cortado producción. Es el argumento entero a favor de inventariar antes de limpiar.

## Calendario

| Métrica | Valor | Evidencia |
|---|---|---|
| Días desde el primer día de laboratorio al corte | 27 (10/07 → 05/08) | `Verificado` |
| Días desde el nacimiento del orquestador al corte | 22 (14/07 → 05/08) | `Verificado` |
| Días desde el nacimiento de Finanzas a v4.8 | 10 (26/07 → 05/08) | `Verificado` |
| Días de código en producción sin control de versiones | 11 (17/07 → 28/07) | `Inferido` |
| Etapas del proyecto | 4 | `Inferido` (agrupación propia de esta documentación) |

## Qué NO miden estos números

Esta es la parte importante de la página, y conviene leerla antes que las tablas.

**Ninguna de estas métricas mide si el sistema es bueno.** Miden volumen y actividad. 217 workflows no es mejor que 40: de hecho es peor, porque 125 de ellos tienen nomenclatura de laboratorio y conviven con producción. El número grande es un síntoma de la deuda, no una prueba de capacidad. Lo mismo con las 35 tablas: son las que hacen falta para el dominio, y si mañana fueran 60 no significaría que el sistema sirve más.

**554 tests no significan cobertura.** Es un conteo de casos, no un porcentaje de líneas ni de ramas ejecutadas. La cobertura real está `Pendiente de verificar`, y hay huecos declarados: no hay tests de interfaz de usuario, no hay tests de carga, no hay evaluación sistemática y automatizada del comportamiento del modelo, y no hay integración continua — los tests se corren a mano antes de publicar. Un número de casos alto con esos huecos describe un sistema bien probado *en su lógica determinística* y sin verificar en todo lo demás.

**La tasa de éxito del 94,8% es de una ventana de 7 días y no distingue causas.** Diecinueve ejecuciones fallidas pueden ser un timeout de un servicio externo o pueden ser un bug de lógica; el número no lo dice. Tampoco hay objetivos de nivel de servicio declarados, así que no existe una referencia contra la cual ese 94,8% sea bueno o malo. Es un dato, no una evaluación.

**Nada de esto mide fiabilidad bajo estrés ni capacidad de recuperación real.** Hay backups diarios con lock, manifiesto y script de chequeo, pero **sin copia fuera del sitio y sin un ensayo de restauración demostrado**. Un backup que nunca se restauró es una hipótesis. Ese riesgo está abierto y documentado.

**Las métricas no capturan el trabajo que produjo el mejor resultado del proyecto.** El Buscador General consumió las fases 3B a 3E1, un validador consolidado, una métrica de alcance, un fallback y una matriz fija de casos — y aparece en las tablas como "2/7 PASS, no publicado". En una métrica de entregables cuenta cero. En términos de ingeniería es el mejor resultado del repositorio: un umbral declarado antes de correr las pruebas y respetado después de verlas.

**Tampoco miden la deuda.** No hay separación de ambientes; el `errorWorkflow` global sigue llamándose `[TEST]`; dos proyectos de contenido resuelven el mismo problema con stacks distintos; hay defaults inseguros en el servidor MCP que sólo aplican si faltan variables de entorno; y un archivo de configuración con un token real quedó en una carpeta sincronizada a la nube y requiere rotación. Ninguna de esas cinco cosas baja un número de esta página. Todas bajan la calidad del sistema.

**Lo que sí muestran, leídas juntas:** un sistema chico en volumen de datos, denso en reglas, con la lógica empujada hacia lo determinístico, con superficie de escritura deliberadamente mínima, construido rápido, y con las deudas contadas en vez de escondidas.

> Última verificación: 2026-08-05
