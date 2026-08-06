# ADR-XXXX — <título en forma de decisión>

Plantilla de registro de decisión de arquitectura. Documenta **el momento en que se eligió**, con la información que había entonces.

<!--
CÓMO USAR ESTA PLANTILLA
1. Copiala a adr-XXX-titulo-en-kebab-case.md
2. El título se escribe como decisión, no como tema:
   Mal:  "Base de datos"
   Bien: "PostgreSQL propio en vez de Supabase"
3. Un ADR no se edita cuando la decisión cambia: se marca como superada
   y se escribe uno nuevo. El historial de decisiones es el valor
4. Ver los nueve ADR reales del proyecto en ../../04-decisiones/
-->

| Campo | Valor |
|---|---|
| **ID** | ADR-XXXX |
| **Estado** | <!-- Propuesta / Aceptada / Vigente / Aceptada y superada / Rechazada --> |
| **Fecha** | AAAA-MM-DD |
| **Decide** | <!-- una persona con nombre --> |
| **Supera a** | <!-- ADR-XXXX, o "ninguno" --> |
| **Superada por** | <!-- se completa después, si ocurre --> |
| **Documentos relacionados** | <!-- REQ-XXXX, PLAN-XXXX, INC-XXXX --> |

---

## Contexto

<!--
Qué estaba pasando cuando hubo que decidir. Qué se sabía y qué no.
Escribilo en pasado y sin el conocimiento posterior: el valor del ADR es
mostrar qué información había disponible en ese momento.
-->

## Decisión

<!--
Una frase en presente y en voz activa. Sin condicionales.

Mal:  "Se evaluaría usar PostgreSQL propio"
Bien: "La memoria viva vive en PostgreSQL propio en el VPS"
-->

## Alternativas evaluadas

| Alternativa | A favor | En contra | Por qué se descartó |
|---|---|---|---|
| A. |  |  |  |
| B. |  |  |  |
| C. No hacer nada |  |  |  |

<!-- "No hacer nada" siempre se evalúa. A veces gana: ver ADR-006. -->

## Consecuencias

**Positivas**

- 

**Negativas**

<!--
Escribilas de verdad. Un ADR sin consecuencias negativas es publicidad,
no un registro de decisión. Toda elección cuesta algo.
-->

- 

**Deuda que asume**

<!-- Lo que queda mal a propósito, y bajo qué condición se arregla. -->

| Deuda | Qué la dispararía |
|---|---|
|  |  |

## Qué invalidaría esta decisión

<!--
El criterio de revisión, escrito ahora. Sin esto, un ADR se vuelve dogma:
nadie se acuerda de por qué se decidió y nadie se anima a cambiarlo.

Ejemplo real: "Si la memoria supera N hechos y la consulta full-text
deja de encontrar lo relevante, se reevalúa el RAG vectorial."
-->

## Nivel de evidencia

| Afirmación | Nivel |
|---|---|
|  | <!-- Verificado / Confirmado por el responsable / Inferido / Pendiente de verificar / Historia incompleta --> |

## Historial

| Fecha | Cambio | Quién |
|---|---|---|
| AAAA-MM-DD | Creada | |

> Última verificación: 2026-08-05
