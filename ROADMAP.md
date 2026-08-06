# Hoja de ruta

Qué existe hoy, qué falta, y qué haría falta para poder publicarlo sin faltar a la verdad.

---

## Cómo leer esta tabla

Este repositorio publica método y arquitectura de un sistema que sí está en producción. Pero hay una diferencia entre *lo construido* y *lo planeado*, y confundirlas sería violar la primera regla de la [política de publicación](docs/05-gobernanza/politica-de-publicacion.md): no afirmar pruebas, adopción ni publicación sin evidencia.

Por eso cada línea lleva su estado de evidencia:

| Estado | Significa |
|---|---|
| **Verificado** | Existe, se inspeccionó y se puede demostrar |
| **Parcial** | Existe una parte; la otra está declarada como faltante |
| **Diseñado** | Hay documento de diseño, no hay implementación |
| **No existe** | Es una intención. Nada construido |

Nada pasa a publicable hasta llegar a **Verificado**.

---

## Estado del sistema

### Construido y publicado en este repositorio

| Capacidad | Evidencia | Dónde está |
|---|---|---|
| Orquestador multiagente con subagentes especializados | Verificado | [`systems/oppenheimer`](systems/oppenheimer/) |
| Memoria persistente en PostgreSQL, en cuatro capas | Verificado | [`systems/praxia-memory-core`](systems/praxia-memory-core/) |
| Aprobación humana en acciones consecuentes | Verificado | [ADR-004](docs/04-decisiones/adr-004-aprobacion-humana-en-acciones-consecuentes.md) |
| Ingesta financiera con contrato universal e idempotencia | Verificado | [`systems/praxia-finanzas`](systems/praxia-finanzas/) |
| Invariantes como triggers y constraints en la base | Verificado | [`artifacts/sql/04-invariantes-y-triggers.sql`](artifacts/sql/04-invariantes-y-triggers.sql) |
| Ausencia total de borrado físico, con auditoría | Verificado | [ADR-007](docs/04-decisiones/adr-007-sin-borrado-fisico.md) |
| Servidor MCP con scopes OAuth y confirmación en escritura | Verificado | [`docs/02-desglose-tecnico/04-cuando-uso-un-mcp.md`](docs/02-desglose-tecnico/04-cuando-uso-un-mcp.md) |
| Búsqueda web con contrato de evidencia y abstención segura | Verificado | [`systems/oppenheimer`](systems/oppenheimer/) |
| Manejo global de errores con deduplicación y alerta | Verificado | [`systems/oppenheimer`](systems/oppenheimer/) |
| Método SDLC para trabajo con agentes de IA | Verificado | [`docs/05-gobernanza`](docs/05-gobernanza/) |
| Post-mortems e incidentes reales | Verificado | [`docs/06-runbooks`](docs/06-runbooks/) |
| Suite de 606 tests con base embebida | Verificado | [`docs/02-desglose-tecnico/09-testing-y-evidencia.md`](docs/02-desglose-tecnico/09-testing-y-evidencia.md) |
| Contrato de solo lectura entre módulos, con abstención tipada | Verificado | [`systems/praxia-agente-fiscal/capa-de-lectura.md`](systems/praxia-agente-fiscal/capa-de-lectura.md) |
| Motor de propuestas por precedente verificable, sin inferencia | Verificado | [`systems/praxia-agente-fiscal/motor-de-precedentes.md`](systems/praxia-agente-fiscal/motor-de-precedentes.md) |
| Propuestas con huella e inmutabilidad del contenido decidido | Verificado | [`systems/praxia-agente-fiscal/propuestas-y-huellas.md`](systems/praxia-agente-fiscal/propuestas-y-huellas.md) |
| Separación de credenciales que impide la autoaprobación | Verificado | [`systems/praxia-agente-fiscal/seguridad-y-permisos.md`](systems/praxia-agente-fiscal/seguridad-y-permisos.md) |

---

## Lo que falta

Ordenado por lo que desbloquea, no por lo que suena mejor.

### 1. Separación de ambientes · **Parcial** · bloqueante

Hoy producción se usó también como laboratorio: 125 workflows con nomenclatura de prueba conviven con 25 activos. Existe el inventario y la clasificación; falta el ambiente separado.

**Qué haría falta:** una instancia de staging aislada, con datos sintéticos, donde los candidatos entren inactivos antes de publicarse.
**Qué desbloquea:** todo lo demás. Sin esto, cualquier prueba de carga o de regresión toca el sistema del que dependen las finanzas y la agenda reales.
**Publicable cuando:** exista y se pueda mostrar el flujo `draft → test → staging → production` con un caso real.

### 2. Workflows versionados en git · **No existe** · bloqueante

El [TO-BE](docs/01-arquitectura/estado-objetivo-to-be.md) dice que el repositorio debería ser la fuente de verdad y el runtime un despliegue. Hoy es al revés: la verdad vive en n8n.

**Qué haría falta:** exportador que normalice el JSON (sacando metadata de runtime que ensucia el diff), el [manifiesto de 11 campos](artifacts/workflows-n8n/manifiesto-de-workflow.md) por workflow, y el pipeline de publicación automatizado.
**Publicable cuando:** haya un `n8n-git-versioning-toolkit` con exportador, normalizador y ejemplo reproducible. Hoy sólo está la guía, no la herramienta.

### 3. Backups con off-site y ensayo de restauración · **Parcial** · bloqueante

Hay backups diarios con lock, manifest y script de verificación. No hay copia fuera del servidor ni un solo ensayo de restauración documentado.

**Qué haría falta:** destino remoto cifrado y un drill trimestral con su informe.
**Publicable cuando:** exista el informe del primer drill. Un backup que nunca se restauró es una hipótesis.

### 4. Harness de evaluación de agentes · **No existe**

Hay 606 tests de **código**. No hay evaluación del **comportamiento del modelo**: si el orquestador elige la herramienta correcta, si respeta las reglas duras del prompt, si se abstiene cuando corresponde.

**Qué haría falta:** un conjunto de casos con entrada, salida esperada y criterio de aceptación; un runner que los ejecute contra el agente real; y un reporte de métricas versionado.
**Publicable cuando:** haya al menos 30 casos corriendo con resultados reproducibles. Publicar un "pipeline de evaluaciones" sin corridas sería exactamente lo que este repositorio prohíbe.

### 5. Observabilidad · **No existe**

No hay medición de latencia extremo a extremo, costo por conversación, tasa de acierto del Memory Intent Gate ni tasa de violación de reglas del prompt. Se sabe cuántas ejecuciones fallaron, no cuánto costaron ni cuánto tardaron.

**Qué haría falta:** instrumentar el orquestador, persistir las métricas y exponer un panel.
**Publicable cuando:** existan las métricas. Un dashboard de demostración con números inventados no demuestra nada.

### 6. RLS y aislamiento por inquilino · **Diseñado**

El modelo de permisos está escrito y la identidad va por canal. Falta Row Level Security en la base.

**Qué haría falta:** políticas RLS por perfil y por dueño de datos.
**Cuándo se vuelve bloqueante:** en el momento en que exista un segundo dueño de datos. Con un solo conjunto de datos, RLS agrega complejidad sin agregar aislamiento.

### 7. Memoria documental y recuperación semántica · **No existe**

La [ADR-003](docs/04-decisiones/adr-003-memoria-en-capas-sin-rag-vectorial.md) decidió no usar RAG vectorial, y fue la decisión correcta para el volumen actual. No hay embeddings ni índice vectorial.

**Cuándo se revisa:** cuando entren papers y PDFs a escala y la búsqueda full-text en español deje de alcanzar.
**Publicable cuando:** exista y se pueda comparar contra la solución actual con números. Hasta entonces, lo publicable es la decisión de *no* hacerlo, que ya está publicada.

### 8. Fábrica de contenido multimarca · **Diseñado**

Dos proyectos ([AI-Command-Center](systems/ai-command-center/) y otro de notas) resuelven el mismo problema con stacks distintos, y el solapamiento no está resuelto.

**Qué haría falta primero:** una decisión que mate uno de los dos. Después, implementación.

### 9. Cierre del subsistema fiscal · **Parcial**

El [Agente Fiscal](systems/praxia-agente-fiscal/) está en producción y lo que hace, lo hace verificado. Lo que falta está inventariado en [límites y deudas](systems/praxia-agente-fiscal/limites-y-deudas.md) y son cuatro cosas concretas:

| Pendiente | Estado | Qué haría falta |
|---|---|---|
| **Disparo mensual automático en n8n** | **No existe** | El workflow del agente fiscal es hoy un esqueleto de cuatro nodos con trigger manual y el período hardcodeado. El diseño acordado es un workflow del día 1 que llame al diagnóstico del período con `registrar=true` y mande el mensaje por Telegram |
| **Rol de PostgreSQL de solo lectura para la capa fiscal** | **Parcial** | Hoy la garantía es de aplicación: el guardia rechaza todo lo que no empiece con `SELECT` o `WITH`. Falta la segunda barrera a nivel de motor — crear el rol, otorgarle `SELECT` sólo sobre las tablas del §5 del contrato y apuntar la capa a ese rol |
| **Persistencia de la auditoría de consultas** | **No existe** | Hoy cada consulta fiscal emite una línea JSON al log del proceso. Escribirla en una tabla exigiría permiso de `INSERT`, que es justamente lo que el rol fiscal no debe tener: tiene que hacerlo un componente aparte que recoja el log |
| **Plantillas de obligaciones reales cargadas** | **No existe** | El catálogo y el calendario existen y están probados; faltan las plantillas concretas con sus importes vigentes |

**Publicable cuando:** el disparo mensual corra sin intervención y el rol de solo lectura exista en el servidor, verificado contra `\du` y no contra el repositorio.

---

## Criterio de publicación

Todo cambio relevante se evalúa para publicación. Si puede aportar un ejemplo, plantilla, guía, demostración o caso de estudio saneado, se genera. Si no puede publicarse, se registra la razón de confidencialidad o de seguridad.

Lo que **no** se hace: publicar la intención como si fuera el resultado. Esta hoja de ruta existe justamente para que la diferencia quede escrita.

> Última verificación: 2026-08-06
