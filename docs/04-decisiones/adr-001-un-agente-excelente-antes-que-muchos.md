# ADR-001 — Un agente excelente antes que muchos

Construir un solo agente hasta que sea realmente bueno, pero apoyado desde el primer día en una arquitectura de datos que ya contemple varios usuarios.

## Estado

Aceptada.

## Fecha

2026-07-14, dentro de la planificación maestra que también cerró las decisiones D-1 a D-8.

## Contexto

El proyecto arrancó con seis agentes en mente: un asistente personal, uno administrativo de la marca, uno de ciencia aplicada, uno familiar separado, uno de una marca outdoor y agentes futuros para clientes. Cada uno con herramientas, permisos y memoria propios.

La tentación evidente era arrancar por lo ancho: montar la plataforma multiagente primero y después llenarla. Es lo que hace casi todo el mundo, y es también la razón por la que casi todo el mundo termina con seis medio-agentes que no usa nadie.

El diagnóstico fue distinto y quedó escrito textualmente:

> *"Sin orden no hay sistema, solo experimentos. El error a evitar no es técnico, es de secuencia. Hay que construir un agente excelente (Oppenheimer) sobre una arquitectura de datos que ya contemple multiusuario."*

Hay dos afirmaciones ahí, y son las dos mitades de la decisión. La primera dice qué se construye ahora: uno solo. La segunda dice qué se diseña ahora: para muchos.

El riesgo específico que se quería evitar no era el sobrediseño, sino el opuesto: construir el primer agente con supuestos de usuario único metidos en el esquema —una tabla sin columna de propietario, un identificador implícito, un prompt que asume de quién es la agenda— y descubrir a los tres meses que separar los datos exige reescribir la memoria entera.

## Decisión

**Se construye Oppenheimer y sólo Oppenheimer, hasta que esté en producción, sea confiable y se use todos los días. La arquitectura de datos y de identidad, en cambio, se diseña multiusuario desde el minuto cero.**

En concreto:

- **Un único agente en construcción activa.** Nada de trabajo paralelo en los otros cinco.
- **Identidad explícita desde el principio.** La decisión D-6 fija que la identidad se resuelve por identificador de canal, con un bot distinto por persona y datos separados por usuario.
- **Esquema con dimensiones de separación.** Las tablas de memoria llevan `project` y las de finanzas llevan `perfiles`, de modo que separar por persona o por proyecto es una consulta filtrada y no una migración.
- **Orden de construcción congelado:** Oppenheimer → PraxIA Ops → Ciencia Aplicada → agente familiar → marca outdoor → clientes.
- **Criterio de avance:** no se empieza el siguiente agente hasta que el anterior esté en producción y estable.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Un agente, arquitectura multiusuario desde el diseño** | Foco total; el esquema no hay que rehacerlo; cada agente nuevo hereda infraestructura probada | Costo de diseño adelantado que no se aprovecha hasta el segundo agente | **Elegida** |
| Un agente, arquitectura de usuario único | Máxima velocidad inicial; nada de trabajo especulativo | Separar usuarios después implica migrar memoria, permisos y auditoría con datos vivos adentro | Rechazada |
| Plataforma multiagente primero, agentes después | La escala está resuelta antes de necesitarla | Meses de plataforma sin un solo usuario real; se optimiza para un uso que todavía no se conoce | Rechazada |
| Seis agentes en paralelo, uno por dominio | Cobertura amplia rápido | Seis prototipos frágiles; ninguna pieza llega a producción; el aprendizaje no se acumula | Rechazada |

## Consecuencias

### Positivas

- **Oppenheimer llegó a producción en 22 días** y con multimodalidad completa: texto, voz, imagen y documentos.
- Cada componente que se construyó después —memoria, finanzas, avisador de errores, servidor MCP— **heredó infraestructura ya probada** en vez de inventar la suya.
- El esquema `praxia` con dimensión de proyecto y el esquema `praxia_finanzas` con perfiles sostienen la separación sin ningún cambio estructural pendiente.
- El aprendizaje se acumuló en una sola línea. La máquina de estados que salió del incidente de PDF, por ejemplo, es un patrón directamente reutilizable en cualquier agente futuro.

### Negativas

- **Cinco agentes siguen sin existir** al 2026-08-05. Para quien esperaba el suyo, la decisión se ve como una demora.
- La separación multiusuario **está diseñada pero no ejercitada**: no hay un segundo usuario real que la valide. Estado: `Pendiente de verificar` hasta que exista.
- Parte del trabajo de diseño adelantado todavía no rindió, y no rendirá hasta el segundo agente.

### Operativas

- El orden de construcción es un compromiso público dentro del proyecto: se puede cambiar, pero cambiarlo requiere un ADR nuevo, no una decisión de un día.
- El criterio "no se empieza el siguiente hasta que el anterior esté estable" necesita una definición de "estable" más dura de la que hay hoy. Estado: `Pendiente de verificar`.
- Los proyectos de contenido (AI-Command-Center, Arquitecto-IA-Redes) quedaron en Fase 0 justamente por esta decisión. Se declara como consecuencia buscada, no como abandono.

### De seguridad

- Diseñar la separación de datos antes de tener el segundo usuario es lo que evita el peor escenario del proyecto: **filtrar información de una persona a otra**. Retrofitear aislamiento sobre datos ya mezclados es una clase de trabajo donde los errores no se ven hasta que alguien lee lo que no debía.
- Un bot distinto por persona significa credenciales y superficie separadas por diseño, no por convención.
- Contrapartida honesta: hasta que no exista un segundo usuario, **el aislamiento es una propiedad afirmada y no probada**.

## Evidencia

| Afirmación | Estado |
|---|---|
| Planificación maestra del 2026-07-14 con arquitectura en 7 capas y decisiones D-1 a D-8 | `Verificado` |
| Cita textual de la regla de secuencia | `Verificado` |
| Orden de construcción: Oppenheimer → PraxIA Ops → Ciencia Aplicada → agente familiar → marca outdoor → clientes | `Verificado` |
| D-6: identidad por identificador de canal, un bot por persona, datos separados | `Verificado` |
| Oppenheimer en producción con orquestador de 51 nodos y 25 workflows activos al 2026-08-03 | `Verificado` |
| Los otros cinco agentes no existen al corte | `Verificado` |
| Que la separación multiusuario funcione con dos usuarios reales | `Pendiente de verificar` |
| Definición operativa y medible de "agente estable" | `Pendiente de verificar` |

## Disparador de revisión

Revisar este ADR cuando ocurra cualquiera de estas cosas:

- Oppenheimer se considere estable bajo un criterio escrito y medible, y corresponda arrancar el segundo agente.
- Aparezca un segundo usuario real y la separación deje de ser una propiedad afirmada.
- Se necesite un agente fuera de orden por una razón externa — un cliente que paga, por ejemplo. En ese caso el ADR no se rompe: se escribe uno nuevo que registre el desvío y su motivo.
- Se detecte que la infraestructura compartida se convirtió en acoplamiento: si un cambio para el agente B rompe al agente A, la premisa de la herencia dejó de valer.

> Última verificación: 2026-08-05
