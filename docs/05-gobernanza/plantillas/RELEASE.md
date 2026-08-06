# RELEASE-XXXX — <componente y versión>

Plantilla de registro de release: qué se puso en producción, cuándo, con qué evidencia y quién lo aprobó. Es la salida de la etapa 7 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md).

<!--
CÓMO USAR ESTA PLANTILLA
1. Copiala a RELEASE-0001-componente.md
2. Se empieza a completar ANTES de desplegar, no después
3. Sin este documento, un cambio en producción es un parche sin dueño
4. El aprobador es siempre una persona. Un agente prepara y espera
-->

| Campo | Valor |
|---|---|
| **ID** | RELEASE-XXXX |
| **Estado** | <!-- Preparado / Aprobado / Desplegado / Verificado / Revertido --> |
| **Fecha y hora** | AAAA-MM-DD HH:MM |
| **Componente** | |
| **Versión** | <!-- v4.8, oppenheimer.buscador-web.v1, etc. --> |
| **Requisito** | REQ-XXXX |
| **Plan** | PLAN-XXXX |
| **Pruebas** | TEST-XXXX |
| **Rollback** | ROLLBACK-XXXX |
| **Aprobado por** | <!-- nombre de una persona, y fecha de la aprobación --> |
| **Ejecutado por** | |

---

## 1. Qué se despliega

<!-- Enumerado y concreto. Archivos, migraciones, workflows, endpoints. -->

| Artefacto | Versión / hash | Tipo de cambio |
|---|---|---|
|  |  | <!-- nuevo / modificación / corrección / migración --> |

## 2. Qué cambia para el usuario

<!-- El efecto observable, en una frase. Si no cambia nada visible, decilo. -->

## 3. Estado del destino antes del release

<!--
Verificado sobre EL SERVIDOR, no sobre el repositorio.
Este bloque existe porque el 2026-08-05 producción estaba tres migraciones
atrás desde el 31/07: "nadie había mirado el servidor, solo el repositorio".
-->

| Aspecto | Valor esperado | Valor real verificado |
|---|---|---|
| Versión desplegada actualmente | | |
| Cantidad de tablas / nodos / endpoints | | |
| ¿Hay drift respecto del repositorio? | no | <!-- si hay, se resuelve ANTES --> |

## 4. Respaldo previo

| Campo | Valor |
|---|---|
| Backup tomado el | AAAA-MM-DD HH:MM |
| Verificado | <!-- sí / no. Si es "no", el release no se ejecuta --> |
| Artefacto anterior exportado | <!-- ubicación --> |
| Hash del artefacto anterior | |
| Confirmado que se puede reimportar | <!-- sí / no --> |

## 5. Procedimiento aplicado

<!-- Los pasos ejecutados, en orden, con la hora. Exactamente lo aprobado, nada más. -->

| # | Paso | Hora | Resultado |
|---|---|---|---|
| 1 |  |  |  |

**Desvíos respecto del plan:** <!-- ninguno, o cuáles y por qué -->

## 6. Verificación posterior

| Verificación | Esperado | Obtenido | OK |
|---|---|---|---|
| El componente responde | | | |
| Caso real de punta a punta | | | |
| No regresión — conteo de objetos | <!-- p. ej. 25 → 35 tablas --> | | |
| Sin errores nuevos en `agent_errors` | 0 | | |
| Sin ejecuciones fallidas nuevas | 0 | | |

## 7. Registro de lo desplegado

| Campo | Valor |
|---|---|
| Hash desplegado | |
| Estado de ciclo de vida del manifiesto | <!-- production --> |
| Artefacto de rollback conservado en | |
| `CHANGELOG` actualizado | <!-- sí / no --> |

## 8. Ventana de observación

| Campo | Valor |
|---|---|
| Duración | |
| Hasta | AAAA-MM-DD HH:MM |
| Qué se observa | |
| Criterio de "salió mal" que dispara el rollback | |
| Quién observa | <!-- una persona disponible durante la ventana --> |

## 9. Participación de agentes de IA

| Pregunta | Respuesta |
|---|---|
| ¿Un agente preparó el release? | |
| ¿Un agente lo ejecutó? | <!-- debe ser NO --> |
| ¿El aprobador leyó lo que se despliega, no sólo el resumen? | |
| ¿El agente reportó algún hallazgo durante la preparación? | <!-- y qué se hizo: reportar, no arreglar --> |

## 10. Resultado

| Campo | Valor |
|---|---|
| **Resultado final** | <!-- Exitoso / Exitoso con observaciones / Revertido --> |
| Observaciones | |
| Trabajo pendiente que generó | <!-- REQ-XXXX nuevos --> |

## 11. Historial

| Fecha | Cambio | Quién |
|---|---|---|
| AAAA-MM-DD | Creado | |

> Última verificación: 2026-08-05
