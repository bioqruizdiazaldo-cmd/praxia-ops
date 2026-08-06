# ADR-008 — El repositorio como fuente de verdad

El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue. Hoy no es así, y este ADR registra la decisión de invertir esa relación.

## Estado

Aceptada.

Aceptada como objetivo (TO-BE) y **parcialmente implementada**. El código de PraxIA Finanzas está versionado desde el 28/07; los workflows de n8n **no lo están**. Se declara así para no afirmar una adopción que no ocurrió.

## Fecha

2026-08-03 — línea base de gobernanza, donde queda escrito el TO-BE.
Motivada por dos hechos anteriores y uno posterior: el checkpoint del 28/07, el estado del runtime al 03/08 y el drift detectado el 05/08.

## Contexto

Tres hechos, en orden, arman el argumento entero.

### 28 de julio: no había repositorio

El checkpoint fue textual:

> *"No hay repo git. 3275 líneas de JS + 33 migraciones SQL, sin control de versiones."*

Once días de código en producción sin historial. No había forma de saber qué había cambiado, cuándo ni por qué; el único registro del sistema era el sistema mismo. Ese día se hizo el commit inicial.

### 3 de agosto: el runtime como archivo histórico

La inspección global registró el estado del runtime de n8n:

| Categoría | Cantidad |
|---|---|
| Workflows registrados | 217 |
| Activos | 25 |
| Archivados | 25 |
| **Con nomenclatura de laboratorio** | **125** |

Y el diagnóstico:

> *"El entorno de producción también ha sido utilizado como laboratorio y archivo histórico, porque conserva numerosos workflows de prueba, candidatos y respaldos."*

Un runtime donde el 58% de los workflows son de laboratorio no puede ser la referencia de qué está desplegado. La pregunta "¿cuál es la versión buena de este workflow?" se responde mirando cuál está activo, y esa es una respuesta frágil.

### 5 de agosto: el drift

Al ir a aplicar la migración v4.6 se descubrió que producción estaba en **v4.4, tres migraciones atrás, desde el 31 de julio**. La causa, textual:

> *"nadie había mirado el servidor, solo el repositorio."*

Este hecho es el que cierra el argumento, y merece precisión: **el repositorio estaba impecable**. Migraciones numeradas, tag `v4.3-pre-fase2`, tests en verde. Lo que faltaba era lo inverso de lo que faltaba el 28 de julio. Antes el problema era que no había registro del sistema; ahora el problema era que había registro y **nadie verificaba que el sistema se pareciera al registro**.

Versionar sin verificar el despliegue produce una ilusión de control que es peor que la falta de control, porque genera confianza.

## Decisión

**Se adopta como objetivo de arquitectura que el repositorio sea la fuente de verdad y el runtime un despliegue derivado de él.** Textual del TO-BE:

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Y la prioridad que lo acompaña:

> *"La próxima mejora de mayor valor es convertir evidencia dispersa en fuentes de verdad, ambientes separados y releases trazables antes de expandir funcionalidades."*

La frase clave es **"antes de expandir funcionalidades"**. Es una decisión de secuencia, no una aspiración.

### Qué implica, concretamente

| Componente | Estado al 2026-08-05 | Objetivo |
|---|---|---|
| Código de la API financiera | Versionado desde el 28/07 | Mantener |
| Migraciones SQL | Versionadas y numeradas, con `schema_migrations` en la base | Mantener y **verificar contra producción en cada release** |
| Servidor MCP | Recuperado y versionado el 02–03/08 | Mantener |
| **Workflows de n8n** | **No versionados.** El runtime es la única copia | Exportar, normalizar y versionar con manifiesto |
| Documentación | Vault en Markdown, sincronizado a la nube | Migrar lo publicable a repositorios |
| Ambientes | **Uno solo.** No hay dev/staging/prod | Al menos staging aislado |

### Los cuatro compromisos que se adoptan ya

1. **Toda migración se verifica contra producción**, no contra el repositorio. Formalizado en el [runbook de despliegue](../06-runbooks/despliegue-de-una-migracion.md): la verificación de no-regresión se corre sobre el servidor.
2. **Los workflows de n8n se versionan con el pipeline de 10 pasos** y el manifiesto mínimo de 11 campos. Ver [runbook](../06-runbooks/publicar-un-workflow-n8n.md).
3. **El runtime se limpia con inventario previo**, no por patrón de nombre. Ver [runbook](../06-runbooks/limpieza-de-runtime.md).
4. **La expansión de funcionalidades cede prioridad** frente a fuentes de verdad, ambientes separados y releases trazables.

### El manifiesto mínimo del workflow

Un workflow exportado a JSON no es un artefacto versionado: es un volcado. Para ser fuente de verdad necesita once campos que el JSON no trae — nombre lógico estable, dueño, entorno, estado de ciclo de vida, contrato de entrada y salida, dependencias, credenciales por referencia simbólica, clasificación de datos, revisión de origen, evidencia de test y artefacto de rollback.

Con ciclo de vida explícito: `draft → test → staging → production → deprecated → archived`.

Es la diferencia entre "tengo el JSON guardado" y "sé qué es esto, quién lo mantiene, con qué se probó y cómo vuelvo atrás".

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Repositorio como fuente de verdad, runtime como despliegue** | Historia, revisión, rollback y trazabilidad; el drift se vuelve detectable; habilita ambientes separados | Trabajo de exportación y versionado de workflows; disciplina de release; fricción para cambios rápidos | **Elegida como objetivo** |
| Runtime como fuente de verdad (lo que había) | Cero fricción: se edita en la interfaz visual y ya | Sin historia, sin revisión, sin rollback; el laboratorio y la producción conviven; nadie sabe cuál es la versión buena | Rechazada |
| Sincronización bidireccional automática | Se puede editar en cualquiera de los dos lados | Conflictos sin forma clara de resolverlos; **dos fuentes de verdad con apariencia de una** | Rechazada |
| Exportar el runtime periódicamente como respaldo | Barato; da una copia | Un respaldo no es una fuente de verdad: no tiene revisión, ni contrato, ni dueño, ni rollback probado | Rechazada como sustituto |
| Reconstruir todo desde cero con infraestructura como código | Solución limpia y completa | Semanas de trabajo sobre un sistema en producción que anda. Ver [ADR-001](adr-001-un-agente-excelente-antes-que-muchos.md): el error a evitar es de secuencia | Rechazada |

## Consecuencias

### Positivas

- **El drift se vuelve detectable.** Con `schema_migrations` en la base y las migraciones numeradas en el repositorio, la comparación es una consulta. Antes había que acordarse.
- **La verificación de no-regresión pasó a ser un paso escrito**, no un cuidado personal.
- **Existe historia.** Desde el 28/07 hay commits y tags; `v4.3-pre-fase2` es un punto de retorno concreto.
- **Habilita ambientes separados.** Sin fuente de verdad no se puede tener staging, porque no habría de qué desplegar.
- **Hace posible este repositorio público.** Sin artefactos versionados y sanitizables, no hay nada que publicar.

### Negativas

- **Los workflows de n8n siguen sin versionar al corte.** Es el hueco más grande y el que más contradice el título de este ADR. Se declara.
- **Sigue habiendo un solo ambiente.** Todo pasa en producción. Los inventarios, canaries y backups mitigan; no reemplazan.
- **125 workflows de laboratorio siguen en el runtime.** El inventario del 25/07 clasificó 79; la limpieza completa está pendiente.
- **Sin integración continua.** Los 554 tests se corren a mano. Un repositorio como fuente de verdad sin verificación automática depende de la memoria de una persona.
- La disciplina cuesta tiempo, y el tiempo es lo escaso en un proyecto de una sola persona.

### Operativas

- Cada release necesita verificar el estado desplegado, no sólo el repositorio. Es el aprendizaje del 05/08 convertido en procedimiento.
- Versionar workflows agrega un paso a cada cambio en n8n. La fricción es real y es la razón principal por la que todavía no se hizo.
- La tabla `schema_migrations` es hoy el único mecanismo automatizable de comparación entre repositorio y servidor. Para los workflows no hay equivalente. Estado: `Pendiente de verificar`.
- Falta una verificación periódica programada de correspondencia entre repositorio y servidor. Con una habría bastado para detectar el drift en un día en vez de en cinco.

### De seguridad

- **Un artefacto versionado es un artefacto revisable.** Sin repositorio no hay revisión de código, y sin revisión no hay detección de un cambio indebido.
- Versionar workflows exige **credenciales por referencia simbólica**, nunca embebidas. Eso obliga a separar configuración de secretos, que es una mejora de seguridad por sí sola.
- El escaneo de secretos es un paso explícito del pipeline de 10 pasos, antes de cualquier publicación.
- **Advertencia central**: versionar aumenta la superficie de exposición. Un archivo `.env` con un token real quedó dentro de una carpeta sincronizada a la nube — hallazgo de esta misma auditoría, que **requiere rotación**. Es la prueba de que la disciplina de versionado sin disciplina de secretos empeora las cosas.
- Sin ambientes separados, cualquier prueba de un workflow ocurre contra datos reales. Es un riesgo de seguridad, no sólo de estabilidad.

## Evidencia

| Afirmación | Estado |
|---|---|
| Cita textual del TO-BE sobre repositorio y runtime | `Verificado` |
| Cita textual de la prioridad "antes de expandir funcionalidades" | `Verificado` |
| Checkpoint del 28/07: 3275 líneas de JS y 33 migraciones sin git; commit inicial ese día | `Verificado` |
| Estado del runtime al 03/08: 217 registrados, 25 activos, 125 con nomenclatura de laboratorio | `Verificado` |
| Cita textual sobre producción usada como laboratorio y archivo histórico | `Verificado` |
| Drift del 05/08: producción en v4.4 desde el 31/07, tres migraciones atrás | `Verificado` |
| Cita textual *"nadie había mirado el servidor, solo el repositorio"* | `Verificado` |
| Servidor MCP recuperado y versionado el 02–03/08 | `Verificado` |
| Tag `v4.3-pre-fase2` del 31/07 | `Verificado` |
| Manifiesto mínimo de 11 campos y pipeline de 10 pasos definidos | `Verificado` |
| Que los workflows de n8n estén versionados | **No.** `Verificado` como pendiente |
| Que exista un ambiente de staging | **No.** `Verificado` como pendiente |
| Fecha objetivo para versionar los workflows | `Pendiente de verificar` |

## Disparador de revisión

Revisar cuando:

- **Se versione el primer workflow de n8n con manifiesto completo.** Sería el hito que convierte este ADR de objetivo en práctica.
- **Se detecte otro drift.** Cada repetición es evidencia de que la mitigación actual no alcanza y de que hace falta verificación automática.
- **Aparezca un segundo operador.** Con una sola persona, la memoria tapa parte del hueco. Con dos, deja de taparlo.
- **Se monte un ambiente de staging.** Cambia el modelo de despliegue entero y este ADR habría que reescribirlo con ese contexto.
- **Se automatice la verificación de correspondencia** entre repositorio y servidor, que es la contramedida directa contra el incidente que originó todo esto.

> Última verificación: 2026-08-05
