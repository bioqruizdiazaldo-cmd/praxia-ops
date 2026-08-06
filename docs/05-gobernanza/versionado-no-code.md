# Versionado de workflows no-code

Cómo se versiona algo que no tiene diff legible, que vive dentro de un runtime y que cualquiera puede editar arrastrando un nodo.

El objetivo está en una línea:

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Hoy es al revés. Este documento describe cómo se da vuelta.

---

## El problema, en concreto

Un desarrollador que cambia una función tiene: un diff de tres líneas, un revisor que lo entiende en treinta segundos, un historial que dice cuándo y por qué, y un `git revert`.

Quien cambia un workflow de n8n tiene: un lienzo, un botón de guardar, y un JSON de miles de líneas que nadie va a leer.

Cinco problemas específicos, todos verificados en este sistema:

| Problema | Consecuencia real |
|---|---|
| El artefacto vive en el runtime, no en un archivo | El drift del 2026-08-05: cinco días de diferencia entre lo que decía el repositorio y lo que corría |
| El JSON no tiene diff útil | Nadie revisa cambios de workflow. Se aprueba mirando el lienzo, o no se aprueba |
| No hay ramas ni entornos | 125 workflows de laboratorio en el mismo runtime que los 25 activos |
| El nombre es el único metadato | Dos workflows con `[TEST]` en el nombre servían tráfico real |
| Las credenciales están adentro | Un export ingenuo publica IDs de credencial |

---

## Artefacto canónico

**El artefacto canónico es el JSON exportado, normalizado y versionado en git. No es lo que está en el runtime.**

Consecuencias que hay que aceptar para que esto funcione:

- Si el runtime y el repositorio difieren, **gana el repositorio**, y la diferencia es un incidente, no una curiosidad.
- Un cambio hecho directo en el lienzo de producción no existe hasta que se exporta y se commitea. Mientras tanto es un parche no registrado.
- Desplegar es **importar** el artefacto, no editarlo en el lugar.

Cada artefacto va acompañado de su manifiesto. Uno sin el otro no sirve: el JSON sin manifiesto no se puede revisar, y el manifiesto sin JSON no se puede desplegar.

---

## El manifiesto mínimo — 11 campos

| # | Campo | Qué responde |
|---|---|---|
| 1 | **Nombre lógico estable** | ¿Qué workflow es, más allá de cómo se llame hoy en el lienzo? |
| 2 | **Owner** | ¿Quién responde por esto? Una persona, no un equipo, no "IA" |
| 3 | **Entorno** | `dev` · `staging` · `prod` |
| 4 | **Estado de ciclo de vida** | ¿En qué punto del ciclo está? |
| 5 | **Contrato de entrada y salida** | ¿Qué recibe y qué devuelve, con tipos y estados posibles? |
| 6 | **Dependencias** | ¿Qué otros workflows, APIs o tablas necesita? |
| 7 | **Credenciales por referencia simbólica** | ¿Qué credenciales usa, por nombre lógico y nunca por ID ni valor? |
| 8 | **Clasificación de datos** | ¿Toca datos públicos, internos, sensibles o prohibidos? |
| 9 | **Revisión de origen** | ¿Quién lo escribió, quién lo revisó, qué agente participó? |
| 10 | **Evidencia de test** | ¿Qué pruebas pasó y con qué resultado? |
| 11 | **Artefacto de rollback** | ¿A qué versión se vuelve y dónde está? |

La plantilla completa con el detalle de cada campo y un ejemplo con datos sintéticos está en [`artifacts/workflows-n8n/manifiesto-de-workflow.md`](../../artifacts/workflows-n8n/manifiesto-de-workflow.md).

**Por qué once y no dos.** Cada campo responde una pregunta que alguien hizo y no pudo contestar. El campo 4 existe por los 125 de laboratorio. El 7, porque un export ingenuo filtra IDs de credencial. El 11, porque un release sin rollback no es un release. El 1, porque el nombre del lienzo cambia y el workflow es el mismo.

---

## El ciclo de vida

```
draft → test → staging → production → deprecated → archived
```

| Estado | Qué significa | Puede estar activo |
|---|---|---|
| `draft` | Se está construyendo. Incompleto por definición | **No** |
| `test` | Completo, en verificación. Fixtures sintéticos, sin datos reales | **No** |
| `staging` | Probado, esperando release. Importado como inactivo primero | Sólo en staging |
| `production` | En uso, con tráfico real | **Sí** |
| `deprecated` | Reemplazado. Sigue activo mientras dure la transición | Sí, con fecha de fin declarada |
| `archived` | Fuera de servicio. Se conserva como historia | **No** |

### La regla que más se viola

**Un workflow en estado `test` no puede estar activo en producción.** Nunca.

En este sistema la regla se rompió, y de la peor manera: el `errorWorkflow` global se llama `PraxIA — Avisador de Errores v1` con `[TEST]` en el nombre, y está activo y es crítico desde el 2026-07-23.

Es la ilustración perfecta del problema del versionado no-code: **el nombre era el único metadato**, y el nombre miente. Con manifiesto, el campo 4 diría `production` y el nombre sería irrelevante.

El riesgo no es estético. Es que la próxima limpieza de runtime borre por patrón de nombre el único mecanismo de alerta del sistema. Casi pasa: el inventario del 2026-07-25 encontró **dos workflows "clase C"** —activos con tráfico real— entre los que parecían pruebas descartables.

---

## El pipeline de 10 pasos

De un cambio en el lienzo a un release registrado.

| # | Paso | Qué hace | Falla si… |
|---|---|---|---|
| 1 | **Exportar** | Sacar el JSON del runtime | Se edita el JSON a mano en vez de exportarlo |
| 2 | **Normalizar** | Ordenar claves, quitar volátiles, formato estable | Se saltea: el diff queda inútil |
| 3 | **Escanear secretos** | Buscar tokens, IDs de credencial, URLs internas, chat_ids, correos | Se confía en la vista previa |
| 4 | **Validar estructura** | Nodos huérfanos, ramas sin cerrar, credenciales por ID, nodos deshabilitados olvidados | Se asume que si el lienzo se ve bien, está bien |
| 5 | **Probar contratos con fixtures ficticios** | Entradas sintéticas → salidas esperadas | Se prueba con datos reales |
| 6 | **Importar en staging aislado, como inactivo** | Que exista antes de correr | Se importa activo |
| 7 | **Revisar el grafo visual** | Un humano mira el lienzo importado | Se aprueba leyendo el JSON |
| 8 | **Publicar tras aprobación** | Activar en producción | Se activa antes de aprobar |
| 9 | **Registrar el hash desplegado** | Qué versión exacta está corriendo | No se registra: vuelve el drift |
| 10 | **Verificar y conservar el rollback** | Confirmar que anda + guardar la versión anterior | Se descarta el artefacto anterior |

El paso 7 no es opcional ni se puede automatizar. **Un humano tiene que mirar el grafo**, porque hay errores que sólo se ven en el lienzo: una rama que quedó colgando, un nodo que se conectó al que no era, un `IF` con las salidas invertidas. Ningún linter de JSON detecta que la rama "aprobado" quedó conectada al nodo de rechazo.

Ver el [runbook de publicación de un workflow](../06-runbooks/publicar-un-workflow-n8n.md).

---

## El problema real de los diffs de JSON de n8n

Éste es el punto donde el versionado no-code se gana o se pierde. Sin normalización, git deja de ser útil: **cada guardado produce un diff enorme aunque no hayas cambiado nada de fondo**, y cuando todo cambia, nada se revisa.

### Qué ensucia el diff

| Ruido | De dónde sale |
|---|---|
| **Coordenadas de nodos** | Arrastrar un nodo dos píxeles cambia `position`. Semánticamente: nada |
| **Marcas de tiempo** | `createdAt`, `updatedAt`, `versionId` cambian en cada guardado |
| **Orden de claves** | La serialización no garantiza orden estable entre exports |
| **Orden de nodos y conexiones** | El array puede reordenarse sin que el grafo cambie |
| **IDs internos** | Identificadores generados que cambian al reimportar |
| **`pinData`** | Datos de prueba pegados en nodos durante el desarrollo. **Además suelen ser datos reales** |
| **Metadatos de credencial** | El nombre visible de la credencial y su ID viajan dentro del nodo |
| **Configuración de UI** | Notas, colores, tamaño de los sticky notes |

Resultado sin normalizar: cambiás el texto de un prompt y el diff muestra 400 líneas. El revisor abre, ve la marea, y aprueba sin leer. Peor que no revisar, porque queda registro de una revisión que no ocurrió.

### Cómo se normaliza

Un paso de normalización determinístico, antes de commitear. Siempre el mismo, para que dos exports del mismo workflow produzcan bytes idénticos.

1. **Ordenar las claves alfabéticamente** en todos los objetos, en todos los niveles.
2. **Ordenar los nodos** por nombre lógico —no por ID, que puede cambiar—, y las conexiones por nodo de origen.
3. **Eliminar los campos volátiles**: `createdAt`, `updatedAt`, `versionId`, IDs de instancia.
4. **Redondear o descartar `position`.** Redondear a una grilla grande conserva la disposición aproximada sin generar ruido; descartar es más limpio si el lienzo se reacomoda al importar.
5. **Eliminar `pinData` siempre.** Es ruido y es un riesgo de datos: son datos de prueba que suelen ser reales.
6. **Reemplazar credenciales por referencia simbólica**: el ID y el nombre visible salen; entra un nombre lógico estable.
7. **Formato estable**: indentación fija, sin espacios al final, una sola nueva línea al final del archivo.

Con eso, el diff de "cambié el texto del prompt" son las líneas del prompt. Y un diff que se puede leer es un diff que se revisa.

### Qué se gana además del diff

- **Detección de cambios no intencionales.** Si el diff muestra algo que no esperabas, alguien más tocó el workflow.
- **Escaneo de secretos que sirve.** Buscar un patrón sobre un archivo normalizado es confiable; sobre un JSON crudo con datos pegados, no.
- **Hash estable.** El paso 9 del pipeline —registrar el hash desplegado— sólo tiene sentido si el mismo workflow produce siempre el mismo hash.
- **Comparación entre entornos.** ¿Staging y producción tienen lo mismo? Con normalización es un `diff`; sin ella, es abrir dos lienzos y mirar.

### Lo que la normalización no resuelve

**El diff sigue sin ser semántico.** Muestra que cambió un parámetro, no que ahora el flujo puede llegar a Gmail sin pasar por la aprobación. Para eso está el paso 7: la revisión visual del grafo.

La normalización hace el diff **legible**. La revisión visual lo hace **entendible**. Hacen falta las dos.

---

## Credenciales por referencia simbólica

**Regla: el JSON versionado nunca contiene un ID de credencial, ni un valor, ni un nombre que revele infraestructura.**

Contiene un nombre lógico —`gmail_owner`, `telegram_bot_principal`, `postgres_memoria`— que el entorno de destino resuelve contra su propio almacén de credenciales.

Tres razones:

1. **Seguridad.** Un ID de credencial en un repositorio público es un dato interno que no aporta nada y que ayuda a quien mapea el sistema.
2. **Portabilidad.** El mismo artefacto se importa en dev, staging y producción, y cada entorno resuelve contra sus propias credenciales. Sin esto, no hay ambientes separados posibles.
3. **Rotación.** Rotar una credencial no debería obligar a reversionar catorce workflows.

Corolario para la Fase 3 del escalamiento: **si dos agentes resuelven el mismo nombre simbólico a la misma credencial, no son dos agentes.** Ver [escalamiento multiagente](../01-arquitectura/escalamiento-multiagente.md).

---

## Workflows de test que no deben quedar activos

El estado del sistema al 2026-08-03: **125 de 217 workflows con nomenclatura de laboratorio.**

> *"El entorno de producción también ha sido utilizado como laboratorio y archivo histórico, porque conserva numerosos workflows de prueba, candidatos y respaldos."*

### Por qué pasa

No es descuido. Es la consecuencia lógica de no tener staging: si el único lugar donde se puede probar es producción, se prueba en producción. Y como borrar da miedo —con razón—, se acumulan.

### Por qué es peligroso

| Riesgo | Detalle |
|---|---|
| **Ejecución silenciosa** | Un workflow de prueba con trigger activo sigue corriendo. Puede mandar mensajes, escribir en tablas o gastar tokens |
| **Duplicación** | Dos versiones del mismo flujo activas: el trabajo se hace dos veces, o se pisa |
| **Ruido que apaga la vigilancia** | Nadie revisa una lista de 217 items. Una lista que no se revisa es una lista donde se puede esconder cualquier cosa |
| **Borrado por error** | El riesgo inverso, y el que casi se materializa |

### Las reglas

1. Un workflow en `test` **nunca** se activa en producción.
2. Un workflow de test **siempre** usa fixtures sintéticos, jamás datos reales.
3. Un workflow de test tiene **fecha de caducidad declarada** en su manifiesto.
4. La limpieza se hace **por clasificación, no por patrón de nombre**.
5. Antes de borrar: verificar tráfico, no leer el nombre.

La regla 4 y la 5 salen del inventario del 2026-07-25, que clasificó 79 workflows: **clase A = 73** borrables, **clase B = 4** dudosos, **clase C = 2** activos con tráfico real. Los dos de clase C tenían nombre de prueba. Borrar por patrón habría roto producción.

Ver el [runbook de limpieza de runtime](../06-runbooks/limpieza-de-runtime.md).

---

## Rollback como acción de release

**El rollback no es un plan de emergencia. Es un artefacto que se produce durante el release, antes de necesitarlo.**

Un release sin rollback preparado no está completo, aunque haya salido bien.

| Momento | Qué se hace |
|---|---|
| **Antes** | Exportar la versión que está corriendo. Guardarla con su hash. Verificar que el archivo se puede importar |
| **Durante** | Registrar el hash de lo que se despliega |
| **Después** | Verificar que anda. **Conservar el artefacto anterior**, no descartarlo |
| **Si hay que volver** | Importar el artefacto anterior, verificar, registrar el `ROLLBACK-XXXX` |

Este sistema lo practicó desde temprano: el 2026-07-16 hay un backup del orquestador explícitamente etiquetado *"antes de Agente Papers"*, y el 2026-07-20 el Memory Gate se instaló *con rollback previo guardado*. Ese hábito —guardar el "antes" con el nombre de lo que viene después— es la versión artesanal del paso 10, y funcionó.

Lo que falta es el registro: hoy el rollback existe como archivo, no como entrada de release con ID, aprobador y hash.

Ver la [plantilla ROLLBACK](plantillas/ROLLBACK.md).

---

## Cómo se ve un repositorio de workflows bien versionado

Estructura propuesta, con nombres sintéticos:

```
workflows/
  oppenheimer.orquestador.v2/
    workflow.json          ← exportado y normalizado
    MANIFIESTO.md          ← los 11 campos
    fixtures/
      entrada-minima.json
      entrada-con-voz.json
    tests/
      contrato.test.mjs
    CHANGELOG.md
  oppenheimer.buscador-web.v1/
    workflow.json
    MANIFIESTO.md
    fixtures/
    tests/
    CHANGELOG.md
```

Una carpeta por nombre lógico estable. La versión mayor va en el nombre de la carpeta porque un cambio de contrato es un workflow nuevo, no una revisión del anterior.

---

## Estado de adopción en este sistema

Honestidad antes que aspiración:

| Práctica | Estado |
|---|---|
| Manifiesto definido | **Sí** — plantilla escrita |
| Manifiesto aplicado a los 25 activos | **No** — cobertura parcial |
| Exportación versionada en git | **No** para workflows. Sí para el código y las migraciones de Finanzas |
| Normalización de JSON | **No** — pendiente |
| Escaneo de secretos en el pipeline | **No** automatizado |
| Ambientes separados | **No** |
| Rollback conservado | **Parcial** — como backups etiquetados, sin registro formal |
| Hash desplegado registrado | **No** |

Es el conjunto de brechas 2, 3 y 7 del [TO-BE](../01-arquitectura/estado-objetivo-to-be.md). El método está escrito; la adopción está a mitad de camino, y decirlo es parte del método.

---

## Nivel de evidencia de este documento

| Afirmación | Nivel |
|---|---|
| Los 11 campos, el ciclo de vida y el pipeline de 10 pasos | Verificado (línea base de gobernanza 2026-08-03) |
| 125 de 217 workflows de laboratorio; clases A/B/C del inventario | Verificado |
| `[TEST]` en el `errorWorkflow` activo | Verificado |
| Backups etiquetados "antes de X" y rollback del Memory Gate | Verificado |
| La lista de fuentes de ruido en el diff de n8n y el procedimiento de normalización | Inferido (práctica de ingeniería; no hay un normalizador implementado todavía en este sistema) |
| La estructura de repositorio propuesta | Inferido — propuesta, no implementada |
| Estado de adopción | Verificado |

> Última verificación: 2026-08-05
