# REQ-XXXX — <título corto y descriptivo>

Plantilla de requisito: qué hay que hacer y cómo se sabe que está bien. Es la salida de la etapa 1 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md).

<!--
CÓMO USAR ESTA PLANTILLA
1. Copiá este archivo a REQ-0001-nombre-corto.md
2. Numeración secuencial de cuatro dígitos, no se reutiliza nunca
3. Borrá los comentarios HTML antes de dar el documento por escrito
4. Si no podés completar una sección, el requisito no está listo:
   escribí [PENDIENTE DE VERIFICAR] en vez de inventar
-->

| Campo | Valor |
|---|---|
| **ID** | REQ-XXXX |
| **Estado** | <!-- Borrador / En revisión / Aprobado / En curso / Cumplido / Descartado --> |
| **Fecha** | AAAA-MM-DD |
| **Responsable humano** | <!-- Una persona con nombre. No "el equipo", no "IA" --> |
| **Sistema afectado** | <!-- Oppenheimer / PraxIA Memory Core / PraxIA Finanzas / Infraestructura / Documentación --> |
| **Prioridad** | <!-- Crítica / Alta / Media / Baja --> |
| **Documentos relacionados** | <!-- PLAN-XXXX, ADR-XXXX, INC-XXXX --> |

---

## 1. Objetivo

<!--
Una frase. Qué tiene que ser CIERTO cuando esto termine, no qué se va a hacer.

Mal:  "Implementar un buscador web con Tavily"
Bien: "El agente puede responder preguntas sobre hechos actuales citando fuentes
       verificables, y dice explícitamente cuándo no encontró evidencia suficiente"
-->

## 2. Problema

<!--
Qué duele hoy, con un ejemplo concreto de cuándo dolió.
Si no podés dar un ejemplo real, quizás el problema todavía no existe.
-->

## 3. Alcance

<!-- Enumerado, con nombres reales de archivos, tablas, workflows y endpoints. -->

**Incluye**

- 

**No incluye**

<!--
Esta lista es la que previene los errores de alcance. Escribila con más cuidado
que la anterior. Incluí lo que "obviamente" no entra: eso es lo que se cuela.
-->

- 

## 4. Alternativa de no hacerlo

<!--
Qué pasa si esto no se hace nunca. Si la respuesta es "nada grave",
el requisito probablemente no debería empezar todavía.
"No hacerlo" siempre es una alternativa válida — el ADR-006 es exactamente eso.
-->

## 5. Criterios de aceptación

<!--
Verificables, no opinables. Otro tiene que poder tildarlos sin discutir.
Si hay umbral numérico, declaralo acá y NO lo cambies después.

Mal:  "El buscador funciona bien"
Bien: "Sobre la matriz fija de 7 consultas, 7 devuelven un estado válido
       del contrato y ninguna inventa una fuente. Umbral: 7/7"
-->

| # | Criterio | Cómo se verifica |
|---|---|---|
| 1 |  |  |
| 2 |  |  |
| 3 |  |  |

**Umbral declarado:** <!-- p. ej. 7/7. Y qué pasa si no se alcanza: no se publica. -->

## 6. Datos que toca

| Aspecto | Valor |
|---|---|
| Clasificación | <!-- público / interno / sensible / prohibido --> |
| Tablas o esquemas | |
| Protección requerida | <!-- cifrado, placeholders antes del LLM, ninguna --> |
| Credenciales necesarias | <!-- por nombre simbólico, NUNCA por ID ni valor --> |

## 7. Dependencias

<!-- Otros workflows, APIs, tablas, servicios externos. Y qué pasa si cada uno no responde. -->

| Dependencia | Qué pasa si falla |
|---|---|
|  |  |

## 8. Riesgos

| Riesgo | Impacto | Mitigación |
|---|---|---|
|  |  |  |

## 9. Encargo al agente de IA

<!-- Completar sólo si un agente va a participar. Ver el acuerdo de trabajo con agentes. -->

| Campo | Valor |
|---|---|
| Modo de trabajo | <!-- solo lectura / escritura sin commit / escritura con commit / incluye despliegue --> |
| Acciones prohibidas | <!-- además de las permanentes del acuerdo --> |
| Evidencia esperada | |
| Si se traba | <!-- por defecto: parar y preguntar, nunca asumir --> |

## 10. Nivel de evidencia

| Afirmación de este documento | Nivel |
|---|---|
|  | <!-- Verificado / Confirmado por el responsable / Inferido / Pendiente de verificar / Historia incompleta --> |

## 11. Historial

| Fecha | Cambio | Quién |
|---|---|---|
| AAAA-MM-DD | Creado | |

> Última verificación: 2026-08-05
