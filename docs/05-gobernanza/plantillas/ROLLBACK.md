# ROLLBACK-XXXX — <componente>

Plantilla de rollback: cómo se vuelve atrás, escrito **antes** de necesitarlo.

<!--
CÓMO USAR ESTA PLANTILLA
1. Copiala a ROLLBACK-0001-componente.md
2. Se escribe ANTES del release, no cuando algo se rompe.
   Un rollback improvisado bajo presión es cómo un incidente se convierte en dos
3. Los pasos tienen que poder ejecutarlos OTRA persona, a las 3 de la mañana,
   sin preguntarte nada. Escribilos con esa suposición
4. Un release sin este documento no está completo, aunque haya salido bien
-->

| Campo | Valor |
|---|---|
| **ID** | ROLLBACK-XXXX |
| **Estado** | <!-- Preparado / Verificado / Ejecutado / No necesario / Caducado --> |
| **Fecha de preparación** | AAAA-MM-DD |
| **Release asociado** | RELEASE-XXXX |
| **Componente** | |
| **Preparado por** | |
| **Autorizado a ejecutar** | <!-- quién puede tomar la decisión de revertir --> |

---

## 1. A qué estado se vuelve

| Campo | Valor |
|---|---|
| Versión de destino | |
| Hash del artefacto | |
| Ubicación del artefacto | |
| Fecha de ese artefacto | |
| **Verificado como restaurable** | <!-- sí / no. Si es "no", el release no debería ejecutarse --> |

<!--
"Verificado" significa que se probó importarlo o aplicarlo, no que el archivo existe.
Un backup que nunca se restauró es una hipótesis.
-->

## 2. Criterio de decisión

<!--
Qué tiene que pasar para revertir. Escrito ahora, en frío.
Decidir esto en caliente es cómo se toleran sistemas rotos durante horas.
-->

**Se revierte si:**

- 

**No se revierte si:**

<!-- Los síntomas que parecen graves y no lo son, para no revertir de más. -->

- 

**Quién decide:** <!-- una persona -->

**Plazo máximo para decidir:** <!-- p. ej. 30 minutos desde el primer síntoma -->

## 3. Pasos

<!--
Numerados, concretos, ejecutables por otra persona.
Sin "verificar que todo esté bien": decir QUÉ se verifica y CÓMO.
-->

| # | Paso | Comando o acción | Verificación |
|---|---|---|---|
| 1 |  |  |  |
| 2 |  |  |  |
| 3 |  |  |  |

**Tiempo estimado total:** <!-- minutos -->

## 4. Qué se pierde al revertir

<!--
Datos ingresados después del release, funcionalidad, trabajo.
Si la respuesta es "nada", verificalo: casi nunca es "nada".
-->

| Qué se pierde | Se puede recuperar | Cómo |
|---|---|---|
|  |  |  |

## 5. Datos

<!-- Si el release incluyó migración de esquema o de datos. -->

| Campo | Valor |
|---|---|
| ¿Hubo migración de esquema? | |
| ¿La migración es reversible? | |
| Script de reversión | <!-- ubicación, o "no existe" --> |
| ¿Hay datos nuevos con el esquema nuevo? | |
| Qué pasa con esos datos al revertir | |

<!--
En este sistema no hay borrado físico: la reversión de datos es baja lógica
y queda auditada. Verificar que el rollback respeta esa regla.
-->

## 6. Dependencias afectadas

<!-- Qué otros componentes dependen de éste y qué les pasa cuando se revierte. -->

| Componente dependiente | Impacto | Acción necesaria |
|---|---|---|
|  |  |  |

## 7. Después de revertir

- [ ] El sistema volvió al estado esperado, verificado con un caso real
- [ ] Los usuarios afectados están avisados
- [ ] Se abrió un `INC-XXXX`
- [ ] El artefacto que se revirtió está conservado, no borrado
- [ ] Se sabe por qué falló, o hay un pendiente para averiguarlo
- [ ] El requisito original volvió a la etapa 4, no se dio por perdido

## 8. Registro de ejecución

<!-- Se completa sólo si el rollback efectivamente se ejecutó. -->

| Campo | Valor |
|---|---|
| Ejecutado el | AAAA-MM-DD HH:MM |
| Decidido por | |
| Ejecutado por | |
| Tiempo real | |
| ¿Los pasos escritos alcanzaron? | <!-- si no, corregir esta plantilla --> |
| Incidente asociado | INC-XXXX |

## 9. Historial

| Fecha | Cambio | Quién |
|---|---|---|
| AAAA-MM-DD | Creado | |

> Última verificación: 2026-08-05
