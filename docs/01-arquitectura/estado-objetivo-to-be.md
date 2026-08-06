# Estado objetivo (TO-BE)

Adónde va el sistema, en qué orden, y —lo más importante— qué evento concreto dispara cada paso.

Este documento no es una lista de deseos. Cada ítem tiene tres cosas: **qué falta**, **por qué importa** y **qué lo dispara**. Sin disparador, un TO-BE es una carta a los Reyes.

---

## La frase que define el objetivo

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Todo lo que sigue es una consecuencia de esa inversión. Hoy el runtime es la verdad y el repositorio es un reflejo; el objetivo es exactamente lo contrario.

Y la prioridad, también textual:

> *"La próxima mejora de mayor valor es convertir evidencia dispersa en fuentes de verdad, ambientes separados y releases trazables antes de expandir funcionalidades."*

**Antes de expandir funcionalidades.** Eso es lo que hace que este documento sea una restricción y no una aspiración.

---

## 1. El repositorio como fuente de verdad

**Qué falta**

Que todo workflow productivo exista como artefacto exportado, normalizado y versionado en git, con su manifiesto al lado, y que el runtime se reconstruya desde ahí. Hoy hay repositorio para el código de Finanzas y para las migraciones SQL; no lo hay para los workflows de n8n.

**Por qué importa**

Sin esto no se puede responder "¿qué versión está corriendo?" ni "¿qué cambió entre el martes y el jueves?" sin abrir el lienzo. Y sin poder responder eso, no hay revisión, no hay rollback confiable y no hay auditoría posible. Es también la causa raíz del drift del 2026-08-05.

**Qué lo dispara**

Ya se disparó. El checkpoint del **2026-07-28** en Finanzas —*"No hay repo git. 3275 líneas de JS + 33 migraciones SQL, sin control de versiones"*— produjo el commit inicial. La línea base de gobernanza del **2026-08-03** extendió el criterio a los workflows. Falta ejecutarlo para n8n.

Ver [ADR-008](../04-decisiones/adr-008-el-repositorio-como-fuente-de-verdad.md) y [versionado no-code](../05-gobernanza/versionado-no-code.md).

---

## 2. Ambientes separados (dev / staging / prod)

**Qué falta**

Al menos dos entornos reales: uno donde probar sin consecuencias y uno donde corre lo que la gente usa. Con credenciales distintas, datos distintos y un procedimiento de promoción entre ellos.

**Por qué importa**

Hoy los 125 workflows de laboratorio y los 25 activos comparten runtime. Toda la separación es el flag activo/inactivo y la memoria de quien edita. Con un solo usuario y mucha disciplina eso aguanta. Con un segundo agente, con un cliente, o con un mal día, no.

**Qué lo dispara**

El primero de estos tres eventos:

- Un segundo usuario humano en el sistema (el agente de la segunda persona).
- El primer cliente piloto.
- Un incidente causado por una prueba que tocó producción.

Los dos primeros son planificables. El tercero no, y es el que hace que valga la pena adelantarse.

---

## 3. Releases trazables

**Qué falta**

Que cada cambio en producción tenga un identificador, una fecha, un responsable, la evidencia de prueba que lo habilitó y el artefacto de rollback correspondiente. Hoy existe para migraciones SQL; no existe para workflows.

**Por qué importa**

Un release sin registro es un cambio sin dueño. Cuando algo se rompe tres días después, la pregunta "¿qué cambió?" no tiene respuesta y se depura a ciegas.

**Qué lo dispara**

El primer incidente en producción cuya causa no se pueda determinar en menos de treinta minutos. También es requisito previo del punto 2: no se puede promover entre ambientes sin un concepto de release.

Ver la [plantilla RELEASE](../05-gobernanza/plantillas/RELEASE.md) y el [checklist de release](../05-gobernanza/checklists/checklist-de-release.md).

---

## 4. Manifiestos de workflow

**Qué falta**

Los once campos mínimos —nombre lógico estable, owner, entorno, estado de ciclo de vida, contrato de entrada y salida, dependencias, credenciales por referencia simbólica, clasificación de datos, revisión de origen, evidencia de test, artefacto de rollback— presentes para los 25 workflows activos. Hoy la plantilla existe; la cobertura no está completa.

**Por qué importa**

Un JSON de n8n no tiene diff legible. El manifiesto es lo que permite revisar un cambio sin abrir el lienzo, y lo que permite decidir si un workflow con nombre raro se puede borrar. Los dos activos "clase C" del inventario del 2026-07-25 —los que parecían pruebas y servían tráfico— habrían sido triviales de identificar con manifiesto.

**Qué lo dispara**

La próxima limpieza de runtime. No se puede clasificar 125 workflows sin una ficha por workflow, y hacerlo a mano una segunda vez es más caro que escribir los manifiestos.

Ver [`artifacts/workflows-n8n/manifiesto-de-workflow.md`](../../artifacts/workflows-n8n/manifiesto-de-workflow.md).

---

## 5. Row Level Security cuando entren clientes

**Qué falta**

Aislamiento a nivel de fila en PostgreSQL, con políticas por tenant, de modo que un error de aplicación no pueda devolver datos de otro cliente. Hoy el aislamiento es por `chat_id` en la capa de canal y por `perfil`/`proyecto` en la capa de datos: **lógico, no forzado por la base**.

**Por qué importa**

Con un solo usuario, un bug de filtrado es un bug. Con dos clientes, un bug de filtrado es una filtración. La diferencia no es técnica, es legal y reputacional.

**Qué lo dispara**

**El segundo tenant.** No el primero: mientras haya un solo conjunto de datos, RLS agrega complejidad sin agregar aislamiento. En el momento en que exista un segundo dueño de datos —la segunda persona cuenta como segundo dueño— pasa a ser bloqueante.

Ver [escalamiento multiagente](escalamiento-multiagente.md) y [modelo de permisos](modelo-de-permisos.md).

---

## 6. Backup off-site

**Qué falta**

Copia de los backups fuera del VPS, con cifrado en reposo y retención declarada.

**Por qué importa**

Los backups actuales viven en el mismo servidor que protegen. Cubren corrupción de datos y error humano; no cubren la pérdida del servidor. El export nocturno de la memoria a OneDrive es, hoy, el único dato que vive en dos lugares — y sólo cubre memoria, no finanzas.

**Qué lo dispara**

Está listo para ejecutarse: el mecanismo de sincronización con rclone ya existe y ya corre todas las noches para el espejo Markdown. Es cuestión de extenderlo, no de construirlo. El disparador honesto es la próxima ventana de trabajo de infraestructura.

---

## 7. Restore drill documentado

**Qué falta**

Una restauración completa, ejecutada de verdad, sobre un entorno limpio, con tiempo medido y resultado escrito.

**Por qué importa**

`restore_check.sh` verifica que el archivo de backup está bien formado. Eso no es lo mismo que verificar que el sistema vuelve a funcionar a partir de él. **Un backup que nunca se restauró es una hipótesis.**

Además de la confianza, el drill produce el dato que hoy falta: cuánto tarda. Sin ese número no hay RTO, y sin RTO no se puede prometer nada a un cliente.

**Qué lo dispara**

Debería dispararlo el calendario, no un incidente. Propuesta: un drill antes del primer cliente piloto, y después uno por trimestre.

---

## 8. Higiene del runtime

**Qué falta**

Bajar de 125 workflows de laboratorio a un número que se pueda leer de un vistazo, con criterio de clasificación y no por patrón de nombre.

**Por qué importa**

El ruido en la lista no es estético: es lo que hace que nadie revise la lista, y por lo tanto lo que permite que un workflow indebido corra sin que se note.

**Qué lo dispara**

El manifiesto (punto 4). Sin ficha por workflow, la limpieza es un ejercicio de arqueología con riesgo de romper algo — como casi pasa con los dos "clase C".

---

## 9. Cierre de las deudas de seguridad puntuales

**Qué falta**

- Rotar el token que quedó en un `.env` dentro de una carpeta sincronizada a la nube.
- Eliminar los defaults inseguros hardcodeados del servidor MCP (`JWT_SECRET`, password de owner) y hacer que el arranque **falle** si faltan las variables de entorno.
- Renombrar `PraxIA — Avisador de Errores v1` para que deje de decir `[TEST]`.

**Por qué importa**

Los tres son baratos y ninguno mejora una funcionalidad. Los dos primeros son riesgo real; el tercero es riesgo de que alguien borre por error el único mecanismo de alerta del sistema.

**Qué lo dispara**

Ya está disparado: son hallazgos abiertos de la auditoría del **2026-08-05**. Un fallback inseguro que sólo aplica "si faltan las variables" es exactamente lo que aplica en un despliegue apurado, que es cuando peor viene.

---

## 10. Resolver el solapamiento AI-Command-Center / Arquitecto-IA-Redes

**Qué falta**

Decidir cuál de los dos proyectos vive, o cómo se fusionan. Hoy resuelven el mismo problema —fábrica de contenido multimarca— con stacks distintos.

**Por qué importa**

Dos soluciones al mismo problema garantizan que ninguna de las dos se termine.

**Qué lo dispara**

La primera hora de trabajo real que se le dedique a cualquiera de los dos. Ambos están en fase 0: AI-Command-Center tiene cinco ADRs y cero commits; Arquitecto-IA-Redes tiene notas y dos scripts de calidad. Decidir ahora cuesta una conversación; decidir en tres meses cuesta tirar trabajo.

---

## Tabla de brechas AS-IS → TO-BE, priorizada

Prioridad por **daño esperado × facilidad de ejecución**, no por orden de aparición.

| # | Brecha | AS-IS | TO-BE | Prioridad | Disparador |
|---|---|---|---|---|---|
| 1 | Deudas de seguridad puntuales | Token en `.env` sincronizado; defaults inseguros en MCP | Token rotado; arranque que falla sin variables | **Crítica** | Ya disparado (auditoría 2026-08-05) |
| 2 | Repositorio como fuente de verdad para n8n | Workflows sólo en el runtime | Exportados, normalizados y versionados | **Alta** | Ya disparado (línea base 2026-08-03) |
| 3 | Manifiestos de workflow | Plantilla escrita, cobertura parcial | 25 activos con los 11 campos | **Alta** | Próxima limpieza de runtime |
| 4 | Backup off-site | Backups sólo en el VPS | Copia externa cifrada con retención declarada | **Alta** | Próxima ventana de infra (mecanismo ya existe) |
| 5 | Restore drill | `restore_check.sh` verifica el archivo | Restauración completa medida y documentada | **Alta** | Antes del primer cliente; luego trimestral |
| 6 | Releases trazables | Sólo para migraciones SQL | Todo cambio productivo con ID, evidencia y rollback | **Media-alta** | Primer incidente sin causa determinable |
| 7 | Ambientes separados | Un runtime único | dev/staging/prod con credenciales separadas | **Media-alta** | Segundo usuario o primer cliente |
| 8 | Higiene del runtime | 125 workflows de laboratorio | Lista legible, clasificada por ficha | **Media** | Depende de #3 |
| 9 | Row Level Security | Aislamiento lógico por `chat_id` y `perfil` | Políticas RLS por tenant en la base | **Media (bloqueante al escalar)** | Segundo dueño de datos |
| 10 | Solapamiento de proyectos de contenido | Dos proyectos, mismo problema | Uno solo, decidido | **Baja hoy, cara mañana** | Primera hora de trabajo real en cualquiera |

### Lectura de la tabla

Las cinco primeras brechas **no agregan ninguna funcionalidad**. Ése es el punto. El sistema no necesita más capacidades: necesita que las que tiene se puedan reconstruir, auditar y revertir.

Las brechas 7 y 9 tienen algo en común: son las dos que se activan al escalar. Hoy son mejoras; el día que entre el segundo dueño de datos son requisitos. Adelantarlas ahora cuesta trabajo planificado; postergarlas cuesta una migración bajo presión con datos reales de otra persona adentro.

---

## Qué NO está en el TO-BE

Es tan importante como lo que sí:

- **RAG vectorial.** La memoria funciona con full-text en español y un gate determinístico. No hay evidencia de que haga falta. Ver [ADR-003](../04-decisiones/adr-003-memoria-en-capas-sin-rag-vectorial.md).
- **Framework en el backend de Finanzas.** `node:http` puro con una sola dependencia de runtime funciona y tiene 606 tests. Cambiarlo sería trabajo sin beneficio.
- **Reescribir el dashboard.** El prototipo UI v3 está aprobado en diseño y **no migrado**, y así queda: es la Fase 6 del ADR, no una urgencia.
- **Republicar el Buscador General.** Sacó 2/7 con exigencia declarada de 7/7. No se publica hasta que dé 7/7. Ver [ADR-006](../04-decisiones/adr-006-buscador-general-no-publicado.md).
- **Más agentes.** El orden de construcción decidido es Oppenheimer → PraxIA Ops → Ciencia Aplicada → agente de la segunda persona → marca outdoor → clientes, y no se avanza hasta cerrar las brechas 1 a 5.

---

## Nivel de evidencia de este documento

| Afirmación | Nivel |
|---|---|
| Citas textuales del TO-BE y de la línea base | Verificado |
| Brechas 1 a 10 y su estado AS-IS | Verificado |
| Priorización propuesta | Inferido (criterio de ingeniería, no dato del sistema) |
| Disparadores propuestos | Inferido |
| Costo y plazo de cada ítem | Pendiente de verificar |

> Última verificación: 2026-08-05
