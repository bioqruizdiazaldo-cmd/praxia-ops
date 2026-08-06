# AI-Command-Center — DISEÑO, NO IMPLEMENTADO

> **DISEÑO — NO IMPLEMENTADO.**
> Repositorio con **cero commits**. **Fase 0, USD 0, nada instalado ni contratado.** Las carpetas del pipeline existen y están **vacías**. Lo que sigue es lo que se diseñó, no lo que funciona.

AI-Command-Center es el centro de mando de contenido para redes sociales de el titular y una segunda persona del entorno cercano (perfil profesional del área de salud). Al 2026-08-05 es un diseño completo sin una sola línea ejecutada.

**Estado:** Fase 0 (diseño) · **Corte de esta ficha:** 2026-08-05

---

## Por qué está publicado si no existe

Porque el diferencial de este repositorio es la honestidad sobre el estado real. Un diseño con cinco ADRs, un plan de costos por fase y un mapa verificado de qué APIs se pueden automatizar es un artefacto de ingeniería válido. Presentarlo como un sistema en producción no lo sería.

También sirve de contraste: [Oppenheimer](../oppenheimer/) y [PraxIA Finanzas](../praxia-finanzas/) muestran qué pasa cuando el diseño se ejecuta. Este muestra qué pasa cuando no.

---

## Qué se diseñó

Fecha de diseño: **2026-07-20**.

Un centro de mando para producir, revisar, aprobar y publicar contenido de divulgación en varias marcas, con verificación científica obligatoria antes de publicar y control humano en el paso de publicación.

Componentes previstos:

| Componente | Rol previsto |
|---|---|
| Orquestación | n8n self-host — el mismo motor que ya corre |
| Asistencia de implementación | Claude Code |
| Repositorio de contenido | Obsidian, con el pipeline por carpetas |
| Verificación científica | MCP de PubMed y Consensus |
| Publicación | Publer |
| Voz | ElevenLabs |
| Contenido médico sensible | **Ollama local** — no sale de la máquina |

La decisión de procesar contenido médico sensible con un modelo local es la más interesante del conjunto: reconoce que hay material que no debería viajar a una API de terceros, y resuelve el problema con arquitectura en vez de con una advertencia en el prompt.

---

## Los 5 ADRs

Cinco decisiones de arquitectura registradas el **2026-07-20**, numeradas ADR-001 a ADR-005 dentro del proyecto.

Al momento de esta ficha, sólo están verificados **la existencia, la cantidad y la fecha**. El contenido individual de cada uno no está reproducido acá.

`[PENDIENTE DE VERIFICAR]` — título, decisión y estado de cada uno de los cinco ADRs de AI-Command-Center.

Se documenta el vacío en vez de rellenarlo, según la regla:

> *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

---

## El pipeline por carpetas

Un flujo de contenido implementado como estructura de directorios en Obsidian. Mover un archivo de carpeta **es** el cambio de estado.

```
00_ideas  →  01_borradores  →  02_en_revision  →  03_aprobado  →  04_publicado
```

| Carpeta | Significado | Contenido hoy |
|---|---|---|
| `00_ideas` | Capturas sin trabajar | Vacía |
| `01_borradores` | Redacción en curso | Vacía |
| `02_en_revision` | Verificación científica y de estilo | Vacía |
| `03_aprobado` | Aprobado por una persona, listo para publicar | Vacía |
| `04_publicado` | Publicado, con su registro | Vacía |

La virtud del diseño es que no necesita base de datos ni herramienta de gestión: el estado es observable con `ls`, versionable con git y editable sin aplicación. La limitación es la misma: sin base de datos no hay métricas, ni auditoría, ni consultas.

El paso `03_aprobado` es donde entra la decisión **D-7** del proyecto madre: publicar es una de las cuatro acciones que exigen aprobación humana.

---

## Stack elegido

| Capa | Elección | Contratado |
|---|---|---|
| Orquestación | n8n self-hosted | Ya existe (reutilización) |
| Implementación asistida | Claude Code | Ya existe |
| Repositorio | Obsidian | Ya existe |
| Verificación | MCP PubMed + Consensus | No |
| Publicación | Publer | **No** |
| Voz | ElevenLabs | **No** |
| Modelo local | Ollama | **No instalado** |

---

## Plan de costos por fase

| Fase | Costo mensual estimado | Qué habilita |
|---|---|---|
| **F0** | **USD 0** | Diseño, pipeline por carpetas, reutilización de lo que ya corre |
| **F1** | ~USD 27 | Primeras herramientas contratadas |
| **F2** | ~USD 70–100 | Operación con publicación y voz |

Los montos son los estimados del plan del 2026-07-20 y **no fueron ejecutados**: al 2026-08-05 el gasto real del proyecto es USD 0.

El techo presupuestario general del ecosistema es la decisión **D-8**: 250.000 ARS/mes (~USD 164 al momento de esa decisión). F2 entraría dentro del techo, pero compartiéndolo con el resto de los sistemas.

`[PENDIENTE DE VERIFICAR]` — desglose por herramienta de las cifras de F1 y F2.

---

## Mapa real de APIs de redes sociales

Del proyecto hermano **Arquitecto-IA-Redes** (notas del 2026-07-24/29), que se propuso ser una fábrica de contenido para 4 marcas y cuyo aporte más valioso fue este relevamiento honesto de qué se puede automatizar y qué no.

| Plataforma | Se puede automatizar hoy | Detalle |
|---|---|---|
| **YouTube Shorts** | Sí | Publicación automatizable ya |
| **Facebook** | Sí | Publicación automatizable ya |
| **LinkedIn personal** | Sí | Publicación automatizable ya |
| **Instagram** | No todavía | Requiere **app review de 2 a 4 semanas** |
| **TikTok** | Parcial | Sin auditoría, la publicación queda en `SELF_ONLY` (visible sólo para el autor) |
| **LinkedIn empresa** | **Bloqueado** | Requiere entidad legal; sin ella no hay acceso |

Es el dato más útil del proyecto y el que más ahorra: **la mitad de un plan de automatización de redes se cae contra el proceso de aprobación de las plataformas, no contra la técnica.** Diseñar el pipeline sin saber esto habría producido un sistema que publica en tres lados y falla en tres.

Único código existente en Arquitecto-IA-Redes: **gates de calidad + diccionario de normalización**. El resto son notas.

---

## La deuda de solapamiento, sin resolver

**AI-Command-Center y Arquitecto-IA-Redes resuelven el mismo problema con stacks distintos.** El solapamiento está identificado y **no está resuelto**.

| | AI-Command-Center | Arquitecto-IA-Redes |
|---|---|---|
| Fecha | 2026-07-20 | 2026-07-24/29 |
| Alcance | Titular + segunda persona | 4 marcas |
| Estado | 5 ADRs, pipeline por carpetas, cero commits | Sólo notas + gates de calidad y diccionario |
| Aporte propio | Arquitectura, costos, modelo local para contenido sensible | Mapa real de APIs, normalización |
| Publicación | Publer | `[PENDIENTE DE VERIFICAR]` |

Las tres salidas posibles, sin decisión tomada:

1. **Fusionar**: un solo proyecto que tome el mapa de APIs y los gates de Arquitecto-IA-Redes dentro de la arquitectura de AI-Command-Center.
2. **Separar por alcance**: AI-Command-Center para las dos personas, Arquitecto-IA-Redes para las marcas, con un componente compartido de publicación.
3. **Cerrar uno.**

Mientras no se decida, **cualquier trabajo en cualquiera de los dos corre el riesgo de tirarse a la basura.** Está listado como deuda técnica #6 del ecosistema.

Es también el contraejemplo de la regla que ordena todo el proyecto:

> *"Sin orden no hay sistema, solo experimentos. El error a evitar no es técnico, es de secuencia."*

Dos proyectos para el mismo problema es exactamente un error de secuencia.

---

## Qué falta para salir de Fase 0

En orden, y sin empezar por el código:

1. **Resolver el solapamiento.** Es la compuerta: no se contrata nada hasta que haya un solo proyecto.
2. **Publicar el contenido de los cinco ADRs** o marcarlos como superados.
3. **Definir el alcance mínimo**: cuántas marcas, qué plataformas, qué frecuencia.
4. **Decidir contra el mapa de APIs**: arrancar sólo por las tres plataformas automatizables hoy, y tratar Instagram y TikTok como trabajo de habilitación, no de desarrollo.
5. **Definir el gate de verificación científica** antes de escribir el primer workflow: qué evidencia hace falta para que un contenido médico pase de `02_en_revision` a `03_aprobado`.
6. **Recién ahí**, F1 y las primeras contrataciones.

---

## Criterios de aceptación para declarar Fase 1

No aplican todavía. Cuando el proyecto arranque, el mínimo es:

1. El solapamiento con Arquitecto-IA-Redes está resuelto por escrito.
2. Existe al menos un commit y el repositorio es la fuente de verdad.
3. El pipeline por carpetas tiene contenido real circulando y su estado es observable.
4. Ninguna publicación ocurre sin aprobación humana en `03_aprobado`.
5. Ningún contenido médico sensible se procesa fuera del modelo local.
6. El gasto real está medido y comparado contra el plan.
7. Sólo se automatizan las plataformas del mapa marcadas como disponibles; el resto queda declarado como pendiente de habilitación, no como fallo.

---

## Lección

Es el mismo patrón que **IA_KNOWLEDGE_HUB**: andamiaje excelente, contenido escaso (57 carpetas vacías, 1 playbook, 1 prompt validado, 26 herramientas inventariadas de las que sólo 4 están validadas), congelado desde el 2026-07-17. La lección honesta, escrita en su momento: **se creó la estructura antes que el material.**

Acá se repitió: cinco ADRs, un pipeline y un plan de costos antes del primer contenido.

La diferencia entre este proyecto y Oppenheimer no fue la calidad del diseño. Fue que Oppenheimer se empezó a usar el mismo día que se diseñó.

---

## Documentos relacionados

- [ADR-001 — Un agente excelente antes que muchos](../../docs/04-decisiones/adr-001-un-agente-excelente-antes-que-muchos.md)
- [ADR-009 — Publicar el método, no el sistema](../../docs/04-decisiones/adr-009-publicar-el-metodo-no-el-sistema.md)
- [Línea de tiempo](../../docs/03-cronologia/linea-de-tiempo.md)

> Última verificación: 2026-08-05
