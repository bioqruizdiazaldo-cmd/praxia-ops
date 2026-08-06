# Cuándo construyo un subagente

El criterio central de este repo: cuándo un dominio merece un subagente propio y cuándo alcanza con agregarle una herramienta más al orquestador.

## Criterio

La pregunta se plantea mal casi siempre. No es "¿cuántos agentes necesito?" sino "¿qué gano separando, y qué pago?".

Un subagente es una **frontera**. Como toda frontera, sirve para contener algo: un prompt que crecía, un permiso que no quiero que se filtre, una decisión que necesita su propia aprobación. Si no hay nada que contener, la frontera es burocracia con latencia.

### Las cinco señales que justifican separar

**1. El prompt del orquestador está creciendo por un dominio.**
Si al orquestador le agregaste 40 líneas de instrucciones que sólo aplican a Gmail, ese dominio ya pide su propio agente. El prompt del orquestador debería explicar *cuándo* llamar a cada herramienta, no *cómo* funciona cada una. Cuando el "cómo" se cuela, el prompt se vuelve largo, caro y frágil: cambiar la política de mail rompe la de calendario porque comparten contexto.

**2. El dominio de permisos es distinto.**
Este es el motivo más fuerte. Si una capacidad puede mandar un mail, borrar un evento o mover plata, y las otras no, separarla acota el blast radius. El subagente recibe sólo las credenciales que necesita y no ve el resto del contexto de la conversación.

**3. Necesita su propia aprobación humana.**
Cuando una acción exige un "sí" explícito antes de ejecutarse, ese ciclo de aprobación —pregunta, espera, respuesta, ramificación— es un flujo completo. Enterrado en el orquestador ensucia el flujo principal; en un subagente es lineal y auditable.

**4. Se puede testear aislado.**
Si podés escribir "dada esta entrada, el subagente debe devolver este estado", ya tenés un contrato. Un contrato es la mitad de un subagente. Y al revés: si no podés definir su entrada y su salida sin hablar de la conversación completa, no es un subagente, es una parte del orquestador.

**5. Se va a reusar.**
Dos consumidores distintos de la misma capacidad justifican la extracción, igual que en cualquier refactor.

### El costo real, que hay que pagar sí o sí

Ninguna de estas cosas es gratis y conviene tenerlas escritas antes de decidir:

| Costo | Qué significa en la práctica |
|---|---|
| **Latencia** | Un salto más: el orquestador llama, espera, recibe. En un subagente con LLM propio son dos inferencias en serie, no una |
| **Contrato** | Hay que definir entrada y salida y **mantenerlos**. Un contrato mal definido es un bug distribuido en dos workflows |
| **Versionado** | Dos artefactos que se despliegan por separado y pueden desincronizarse |
| **Observabilidad** | El error aparece en el subagente pero la causa está en lo que le pasó el orquestador. Sin correlación, se debuggea a ciegas |
| **Prompt duplicado** | El subagente necesita su propio contexto mínimo: quién es el usuario, qué fecha es, qué tono usar |
| **Superficie de fallo** | Un workflow más que puede estar inactivo, con credencial vencida o con la versión vieja |

### Tabla de decisión

| Señal | Conviene |
|---|---|
| Es una llamada HTTP sin estado ni permisos especiales | **Herramienta** en el orquestador |
| Es un cálculo | **Herramienta** (`Calculator`) |
| Escribe en un sistema externo con credenciales propias | **Subagente** |
| Requiere confirmación humana antes de ejecutar | **Subagente** |
| Tiene más de 3 pasos internos con ramas | **Subagente** |
| Tiene estados de salida propios que el orquestador debe interpretar | **Subagente** |
| Lo van a llamar dos flujos distintos | **Subagente** |
| Es una variante del 90% de otro subagente | **Ninguno**: parámetro del que ya existe |
| Todavía no sabés cuál es su contrato | **Ninguno**: hacelo inline y extraelo cuando se estabilice |

La última fila importa. Extraer temprano es tan caro como extraer tarde, pero más difícil de revertir: una vez que hay un contrato, alguien lo usa.

## En este sistema

Todos los subagentes se invocan como `toolWorkflow` / `executeWorkflow` desde `Oppenheimer - Orquestador`. Para el orquestador son funciones con nombre y descripción; no ve los nodos del otro lado.

### Inventario y por qué cada uno está separado

| Subagente | Señal que lo justificó |
|---|---|
| **Agente de Email** | Permisos + aprobación humana propia (`Telegram - Approve Send` → `If - Approved`) |
| **Agente de Calendario** | Permisos: Get/Create/Update/**Delete** sobre Calendar |
| **Agente de Planillas** | Ramificación interna: clasifica `GUARDAR:` vs `CONSULTA:` y deriva a un `Consulta Sub-Agent` separado |
| **Agente Papers Científicos v2.1** | Pipeline de 5 etapas: query-builder → Europe PMC + OpenAlex → ranker → writer → Sheets |
| **Buscador Web Tavily V1** | Contrato de evidencia con 7 estados de salida; 9 nodos |
| **PraxIA Memory — Router** | Despacho + gate de seguridad ("¿Tiene secreto?" → `Rechazo Secreto`) |
| **PraxIA Memory — Guardar / Consultar / Tareas / Proyectos** | Reuso: los llama el Router y también otros flujos. CRUD sobre `praxia.*` con verificación post-escritura |
| **PraxIA Sync — Export MD** | Trigger propio (23:30 ART), no conversacional |
| **Briefing Diario** | Trigger propio (07:00) y composición de 4 fuentes |
| **Briefing Noticias** | Trigger propio (06:30), RSS → síntesis → Telegram |
| **Recordatorios** | Estado diferido: webhook + `Wait` |
| **Enviar Gmail** | Es el ejecutor posterior al "sí". Separado a propósito del que redacta |
| **Alertas TradingView** | Webhook externo, sin relación con la conversación |
| **PraxIA — Avisador de Errores v1** | Es el `errorWorkflow` global: lo llama el runtime, no el agente |

> **Nota de conteo.** El README del repo dice "15 subagentes/workflows". Esta tabla tiene 14 filas porque agrupa los cuatro workflows CRUD de memoria en una. Según se cuenten por separado o no, el número es 14, 15 o 17. `[PENDIENTE DE VERIFICAR: criterio de conteo canónico]` — se deja el hueco visible en vez de elegir el número que queda mejor.

### Tres casos que explican el criterio mejor que la tabla

**Email: la aprobación humana como frontera.**

El Agente de Email redacta; `Oppenheimer - Enviar Gmail` envía. Entre los dos hay una aprobación por Telegram.

```
Agente de Email → redacta borrador
  → Telegram - Approve Send   (pregunta al humano)
  → If - Approved
      ├── sí → Enviar Gmail  (acción irreversible)
      └── no → cancelar
```

Podrían ser un solo workflow. Están separados porque **la acción irreversible tiene que estar del otro lado del "sí"**. La separación física hace que sea imposible que un cambio en la lógica de redacción dispare un envío por accidente: el que redacta no tiene el nodo que envía.

Esto materializa la decisión **D-7** del 2026-07-14: aprobación humana obligatoria para enviar mails, borrar, gastar y publicar.

**Buscador Web: el contrato como razón de ser.**

Los 7 estados de salida (`ok`, `clarification_required`, `no_reliable_source`, `search_not_configured`, `technical_error`, `stable_knowledge_handoff`, `insufficient_evidence`) son el motivo por el que este es un subagente y no un nodo HTTP.

Un nodo HTTP devuelve resultados o falla. Un subagente con contrato de evidencia devuelve **por qué** no puede responder, y el orquestador reacciona distinto en cada caso: pedir una aclaración no es lo mismo que avisar que el buscador no está configurado.

La contracara honesta: la versión ampliada de este buscador ("Buscador General", fases 3B→3E1 del 2026-07-27) fue sometida a una revalidación real acotada, dio **2/7 PASS contra una exigencia de 7/7 y no se publicó**. El cierre, textual:

> *"Los cuatro FAIL no son falsos positivos del nuevo validador: son fixtures que no contienen evidencia suficiente para producir una respuesta grounded."*

Un contrato explícito sirve para esto: sin estados tipados, esas cuatro fallas habrían sido "respuestas medio flojas" y el subagente estaría en producción.

**Memory Router: separar el despacho del gate.**

El Router no hace CRUD. Decide a cuál de los cuatro workflows de memoria derivar, y antes pasa por un gate de seguridad: `¿Tiene secreto?` → `Rechazo Secreto`. Detrás está la regla grabada como hecho #14:

> *"Nunca guardar contraseñas, tokens, API keys, claves privadas, credenciales ni datos bancarios completos. Si Aldo intenta guardar algo sensible, advertirle y sugerir guardar solo una referencia segura."*

El gate está en el Router, antes de la bifurcación, y no en cada workflow de escritura. Un solo lugar por el que pasa todo lo que quiere entrar a la memoria. Es la misma lógica que el `errorWorkflow` global: un punto único vale más que cuatro validaciones que hay que acordarse de replicar.

El último export verificado (2026-08-05 02:30 UTC) reporta **0 secretos omitidos**. Un cero acá no es "nunca pasó nada": es que el contador existe y se mira.

### Casos que NO son subagentes, y por qué

- **`Calculator` y `Think`**: nodos del orquestador. Sin permisos, sin estado, sin contrato propio.
- **`HTTP CLIMA` (Open-Meteo)**: una llamada HTTP sin auth. Envolverla en un subagente agregaría un salto de red para nada.
- **`Buscar en Drive` / `Drive - Subir PDF`**: nodos directos. Tienen credenciales, pero no lógica ni ramas propias.
- **Whisper y TTS**: parte del pipeline multimodal del orquestador. Son transformaciones de entrada y salida, no decisiones.

La línea es razonablemente nítida: **si no toma decisiones, no es un agente**. Es una herramienta, y las herramientas viven donde se usan.

### Cómo se ve el costo cuando se paga

El **2026-07-25 18:25 ART** la ejecución 1292 falló en `Telegram - Get Documento` con `Bad Request: file is too big` ante un PDF de 21,9 MB. El error apareció en el pipeline de PDF, pero la causa —falta de validación previa de tamaño— estaba antes.

La reparación, publicada el mismo día con **6/6 pruebas PASS**, fue exactamente lo que este documento propone: convertir un flujo implícito en una máquina de estados explícita.

```
received → validated → text_extracted → reviewed → archived
                                                 ↘ failed
```

Más validación previa, límite de 20 MiB y verificación de la firma `%PDF-`. Cada estado es un punto donde se puede observar qué pasó. `failed` es un estado legítimo, no una excepción que se pierde.

La lección trasladable: **el costo de observabilidad de un flujo distribuido se paga con estados explícitos**. Si el flujo no tiene estados nombrados, el debug es leer logs de tres workflows y adivinar el orden.

## Plantilla de definición de subagente

Esto es lo que hay que poder completar **antes** de construir. Si hay más de dos campos en blanco, todavía no es un subagente: es una idea.

```markdown
## Nombre
Nombre lógico estable. No cambia aunque cambie la implementación.
Convención acá: `<Sistema> - <Dominio> [vN]`.

## Objetivo
Una oración. Qué hace y qué NO hace.
Si necesitás dos oraciones, probablemente sean dos subagentes.

## Entrada
Campos, tipos, cuáles son obligatorios y qué pasa si falta uno.
Un ejemplo sintético completo.

## Salida
Estados posibles, **enumerados y cerrados**. Payload de cada estado.
Debe haber un estado para "no pude" que no sea una excepción.

## Permisos
Credenciales que usa, con referencia simbólica (nunca el ID real).
Qué puede escribir y en qué sistema.
Explícito: qué NO puede hacer.

## Aprobación humana
¿Alguna acción requiere un "sí"? ¿Quién lo da? ¿Por qué canal?
¿Qué pasa si no contesta? (timeout, default seguro)

## Memoria
¿Lee memoria? ¿Escribe? ¿En qué capa? ¿Persiste algo entre invocaciones?
Por defecto: no. Un subagente sin estado es más fácil de razonar.

## Errores
Modos de falla conocidos y qué devuelve en cada uno.
Está cubierto por el errorWorkflow global: sí / no.

## Pruebas mínimas
Lista numerada de casos con entrada y salida esperada.
Al menos uno del camino feliz, uno de entrada inválida y uno de fallo del
servicio externo.

## Criterio de aceptación
La condición binaria para publicar. Ej.: "7/7 casos PASS".
Definida ANTES de correr las pruebas, no después.

## Rollback
Cuál es el artefacto al que se vuelve y dónde está.
```

Dos campos son los que más se saltean y los que más duelen:

**"Explícito: qué NO puede hacer."** Es la diferencia entre un permiso pensado y un permiso heredado. La mayoría de los sobre-permisos existen porque nadie escribió el límite.

**"Criterio de aceptación definido antes."** Si el umbral se fija después de ver los resultados, siempre se cumple. El caso del Buscador General (2/7 con exigencia de 7/7 → no publicado) sólo pudo terminar en "no publicado" porque el 7/7 estaba escrito antes.

## Regla

Separá cuando haya un permiso, una aprobación o un contrato que aislar. No separes por prolijidad: cada subagente se paga con latencia, un contrato que mantener y un artefacto más que versionar.

> Última verificación: 2026-08-05
