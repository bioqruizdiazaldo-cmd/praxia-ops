# PLAN-XXXX — <título corto>

Plantilla de plan de implementación: cómo se va a hacer, decidido antes de empezar. Es la salida de la etapa 3 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md).

<!--
CÓMO USAR ESTA PLANTILLA
1. Copiala a PLAN-0001-nombre-corto.md
2. Un plan no se escribe mientras se implementa: se escribe antes y se aprueba
3. Si durante la implementación el plan cambia, se actualiza el plan
   y se vuelve a aprobar. Un plan que se ignora es peor que no tener plan
-->

| Campo | Valor |
|---|---|
| **ID** | PLAN-XXXX |
| **Estado** | <!-- Borrador / En revisión / Aprobado / En ejecución / Ejecutado / Abandonado --> |
| **Fecha** | AAAA-MM-DD |
| **Requisito** | REQ-XXXX |
| **Responsable humano** | |
| **Aprobado por** | <!-- nombre y fecha --> |

---

## 1. Resumen del enfoque

<!-- Dos o tres frases. Cómo se va a resolver, en una versión que se entienda sin leer el resto. -->

## 2. Línea base

<!-- Etapa 2 del ciclo de vida. Qué hay HOY, verificado sobre el sistema real, no sobre el repositorio. -->

| Aspecto | Estado actual | Nivel de evidencia |
|---|---|---|
|  |  |  |

**Punto de retorno**

| Campo | Valor |
|---|---|
| Tipo | <!-- backup / tag / export / commit --> |
| Ubicación | |
| Verificado como restaurable | <!-- sí / no. Si es "no", el plan no está aprobable --> |
| Fecha | |

## 3. Alternativas evaluadas

<!--
Al menos dos, y una de ellas puede ser "no hacerlo".
Escribir por qué se descartaron es lo que evita rediscutir esto en dos semanas.
-->

| Alternativa | A favor | En contra | Decisión |
|---|---|---|---|
| A. |  |  | <!-- elegida / descartada --> |
| B. |  |  |  |
| C. No hacerlo |  |  |  |

**Elegida:** <!-- cuál y por qué en una frase -->

<!-- Si la decisión es estructural o difícil de revertir, además hace falta un ADR-XXXX. -->

## 4. Pasos

<!--
Cada paso: qué hace, qué produce, y si es reversible por sí solo.
Un paso que no se puede revertir solo tiene que estar marcado como punto de no retorno.
-->

| # | Paso | Produce | Reversible |
|---|---|---|---|
| 1 |  |  | <!-- sí / no --> |
| 2 |  |  |  |
| 3 |  |  |  |

**Puntos de no retorno:** <!-- cuáles y qué se hace antes de cruzarlos -->

## 5. Cambios en datos

| Tabla / esquema | Cambio | Migración | Reversible |
|---|---|---|---|
|  |  |  |  |

<!-- Si hay migración de datos, la vuelta atrás también se define acá, no en el momento. -->

## 6. Plan de verificación

<!-- Cómo se va a demostrar que funciona. Los casos concretos, no "se va a probar". -->

| # | Caso a probar | Fixture | Resultado esperado |
|---|---|---|---|
| 1 |  | <!-- sintético --> |  |

**Umbral heredado del requisito:** <!-- p. ej. 7/7 -->

## 7. Plan de rollback

<!-- Esbozo. El ROLLBACK-XXXX completo se escribe antes del release, no acá. -->

| Campo | Valor |
|---|---|
| Cómo se vuelve | |
| Cuánto tarda (estimado) | |
| Qué se pierde | |
| Criterio para decidir revertir | |

## 8. Participación de agentes de IA

| Paso | Quién lo hace | Modo | Aprobación necesaria |
|---|---|---|---|
|  | <!-- humano / agente --> | <!-- lectura / escritura / despliegue --> | |

**Acciones prohibidas en este plan**

<!-- Además de las permanentes del acuerdo de trabajo con agentes. -->

- 

## 9. Riesgos de ejecución

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
|  |  |  |  |

## 10. Qué queda fuera de este plan

<!-- Trabajo que se identificó y se decidió no hacer ahora. Con el disparador que lo activaría. -->

| Pendiente | Por qué no ahora | Qué lo dispararía |
|---|---|---|
|  |  |  |

## 11. Nivel de evidencia

| Afirmación | Nivel |
|---|---|
|  |  |

## 12. Historial

| Fecha | Cambio | Quién |
|---|---|---|
| AAAA-MM-DD | Creado | |

> Última verificación: 2026-08-05
