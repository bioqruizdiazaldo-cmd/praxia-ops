# Manifiesto de workflow

La ficha mínima que acompaña a cada workflow versionado: once campos que convierten un lienzo visual en un artefacto revisable.

> Plantilla original de PraxIA Ops. El ejemplo del final usa **datos sintéticos**.

---

## Por qué once campos y no dos

Un workflow de n8n no tiene diff legible ni revisión de código. El manifiesto es lo que permite responder, sin abrir el lienzo, las preguntas que importan antes de tocarlo: **de quién es, qué recibe, qué devuelve, de qué depende, qué datos toca, y cómo se vuelve atrás.**

La regla que lo justifica:

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Si el manifiesto y el runtime no coinciden, gana el manifiesto.

---

## Los 11 campos mínimos

### 1. Nombre lógico estable

El identificador que **no cambia** cuando el workflow se renombra en el lienzo. Es lo que permite seguir un workflow a través de versiones, entornos y renombres.

Formato sugerido: `<sistema>.<componente>.<version-mayor>` — por ejemplo `oppenheimer.buscador-web.v1`.

### 2. Owner

La persona responsable. No el equipo, no "IA": una persona.

> *"Los agentes de IA pueden proponer, implementar y verificar trabajo. No se convierten en el dueño responsable del riesgo, el acceso o la decisión de release."*

### 3. Entorno

`dev` · `staging` · `prod`. Se declara aunque el entorno no exista todavía: declarar `prod` en un sistema sin staging es la forma de que la carencia sea visible.

### 4. Estado de ciclo de vida

`draft → test → staging → production → deprecated → archived`

Un solo valor. Si el nombre en el runtime dice `[TEST]` y el manifiesto dice `production`, hay que corregir el runtime.

### 5. Contrato de entrada y salida

Qué recibe y qué devuelve, con tipos y estados posibles. Para un subagente invocado como herramienta, es el contrato completo (ver [`contrato-subworkflow.md`](contrato-subworkflow.md)). Para un trigger, es la forma del evento.

**Los estados de salida son cerrados y tipados.** Nada de texto libre donde el que llama espera un estado.

### 6. Dependencias

Otros workflows, tablas, endpoints y servicios externos de los que depende. Es lo que se mira antes de cambiar algo: quién se rompe si esto cambia.

### 7. Credenciales por referencia simbólica

`CRED_TELEGRAM_BOT`, `CRED_PG_MEMORIA`. **Nunca el ID de la credencial.** El mapeo vive en el runtime, fuera del repositorio.

### 8. Clasificación de datos

Qué clase de datos atraviesa el workflow: `público` · `interno` · `personal` · `financiero` · `sensible`. Determina qué se puede loguear, qué se puede exportar y qué necesita cifrado o reemplazo antes de llegar al modelo.

### 9. Revisión de origen

De dónde salió: escrito a mano, generado por un agente, adaptado de una plantilla pública, importado de n8n cloud. Con quién lo revisó.

Un workflow generado por IA y no revisado por nadie es un riesgo distinto a uno escrito y revisado. El campo lo hace visible.

### 10. Evidencia de test

Qué se probó, con qué fixtures, cuándo y con qué resultado. Números concretos: `8/8 PASS`, `2/7 PASS`.

> *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

Si no se probó, se escribe que no se probó.

### 11. Artefacto de rollback

Dónde está el export de la versión anterior y cuál es su hash. Sin esto no se publica.

---

## Plantilla en blanco

```yaml
# Manifiesto de workflow — PraxIA Ops
nombre_logico:        # <sistema>.<componente>.<version-mayor>
nombre_en_runtime:    # cómo se llama hoy en el lienzo
owner:                # persona responsable
entorno:              # dev | staging | prod
estado:               # draft | test | staging | production | deprecated | archived

contrato:
  entrada:
    tipo:             # trigger | herramienta | webhook | cron
    esquema:          # campos y tipos
  salida:
    esquema:          # campos y tipos
    estados:          # lista cerrada de estados posibles

dependencias:
  workflows:          # otros workflows invocados
  datos:              # tablas, esquemas, vistas
  servicios:          # APIs externas

credenciales:         # sólo referencias simbólicas

clasificacion_datos:  # público | interno | personal | financiero | sensible

origen:
  procedencia:        # escrito a mano | generado por agente | plantilla | importado
  revisado_por:
  fecha_revision:

evidencia_test:
  fixtures:
  resultado:          # N/M PASS
  fecha:

rollback:
  artefacto:          # ruta del export anterior
  hash_sha256:
  verificado:         # sí | no
```

---

## Ejemplo completo — datos sintéticos

Manifiesto de un subagente de búsqueda web. **Todos los valores son inventados**, incluidos los hashes y las rutas.

```yaml
# Manifiesto de workflow — PraxIA Ops
# EJEMPLO SINTÉTICO. Valores inventados con fines didácticos.

nombre_logico:        oppenheimer.buscador-web.v1
nombre_en_runtime:    "Oppenheimer — Buscador Web Tavily V1"
owner:                Aldo Cáceres Ruiz Díaz
entorno:              prod
estado:               production

contrato:
  entrada:
    tipo: herramienta          # invocado por el orquestador como toolWorkflow
    esquema:
      consulta:      { tipo: string,  requerido: true,  max: 400 }
      target_date:   { tipo: date,    requerido: false, nota: "resuelto por el llamador" }
      date_scope:    { tipo: enum,    valores: [hoy, ayer, semana, temporada, cualquiera] }
      idioma:        { tipo: string,  default: "es" }
  salida:
    esquema:
      estado:        { tipo: enum }
      respuesta:     { tipo: string,  nullable: true }
      fuentes:       { tipo: array,   items: { url, titulo, fecha, etiqueta } }
      motivo:        { tipo: string,  nullable: true }
      contexto:      { tipo: object,  nota: "respuesta cruda conservada" }
    estados:
      - ok
      - clarification_required
      - no_reliable_source
      - search_not_configured
      - technical_error
      - stable_knowledge_handoff
      - insufficient_evidence

dependencias:
  workflows:
    - praxia.avisador-errores.v1     # errorWorkflow global
  datos:
    - ninguno                        # este subagente no escribe en la base
  servicios:
    - proveedor de búsqueda web (HTTP, Header Auth, timeout 20 s)

credenciales:
  - CRED_TAVILY_HEADER

clasificacion_datos:  interno
# La consulta del usuario puede contener datos personales: no se persiste
# ni se loguea completa. Sólo se registra el estado de salida.

origen:
  procedencia:   escrito a mano con asistencia de agente de código
  revisado_por:  Aldo Cáceres Ruiz Díaz
  fecha_revision: 2026-07-26

evidencia_test:
  fixtures:
    - "8 casos de resolución de fechas (hoy / ayer / temporada)"
    - "8 casos de conservación de contexto"
    - "matriz de cobertura temática con fallback de 72 h"
  resultado: "8/8 PASS (fechas) · 8/8 PASS (contexto)"
  fecha: 2026-07-27
  nota: >
    La variante "Buscador General" (fases 3B-3E1) obtuvo 2/7 PASS contra una
    exigencia de 7/7 y NO se publicó. Los cuatro FAIL no fueron falsos
    positivos del validador: fueron fixtures sin evidencia suficiente para
    producir una respuesta fundada.

rollback:
  artefacto:     "backups/workflows/2026-07-25/oppenheimer.buscador-web.v1.pre.json"
  hash_sha256:   "0000000000000000000000000000000000000000000000000000000000000000"  # sintético
  verificado:    sí
```

---

## Cómo se usa en la práctica

1. El manifiesto se escribe **antes** de publicar, no después.
2. Se versiona junto al export normalizado del workflow.
3. En la revisión de release se leen tres campos primero: **estado**, **evidencia de test** y **rollback**. Si alguno está vacío, no se publica.
4. Cuando algo se rompe, el primer archivo que se abre es el manifiesto, no el lienzo.

---

## Estado de adopción, honesto

`Confirmado por el responsable` — el manifiesto está definido como estándar en la línea base de gobernanza del 2026-08-03 y se aplica de forma parcial. No todos los workflows en producción tienen su manifiesto escrito.

`[PENDIENTE DE VERIFICAR]` — cuántos de los 25 workflows activos tienen manifiesto completo.

> Última verificación: 2026-08-05
