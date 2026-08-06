# INC-XXXX — <qué pasó, en cinco palabras>

Plantilla de incidente: qué pasó, por qué, y qué control nuevo evita que vuelva. Es la salida de la etapa 9 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md).

<!--
CÓMO USAR ESTA PLANTILLA
1. Copiala a INC-0001-nombre-corto.md
2. Se escribe DESPUÉS de contener, no durante. Primero se apaga el fuego
3. Sin culpables. La pregunta es qué control faltaba, no quién se equivocó
4. Un incidente NO está cerrado hasta que produjo un control nuevo
   que entró al ciclo como trabajo
-->

| Campo | Valor |
|---|---|
| **ID** | INC-XXXX |
| **Estado** | <!-- Abierto / Contenido / En análisis / Cerrado --> |
| **Severidad** | <!-- Crítica / Alta / Media / Baja --> |
| **Detectado** | AAAA-MM-DD HH:MM |
| **Contenido** | AAAA-MM-DD HH:MM |
| **Cerrado** | AAAA-MM-DD |
| **Componente** | |
| **Responsable del análisis** | |

---

## 1. Qué pasó

<!-- Dos o tres frases. Un lector que no estaba tiene que entender el problema acá. -->

## 2. Impacto

| Aspecto | Valor |
|---|---|
| Duración | <!-- desde el inicio real, no desde la detección --> |
| A quién afectó | |
| Qué dejó de funcionar | |
| ¿Hubo pérdida de datos? | |
| ¿Hubo exposición de datos? | <!-- si sí: ir también a la política de publicación, procedimiento de corrección --> |
| ¿Hubo impacto económico? | |

## 3. Línea de tiempo

<!--
Con horas. Incluir el momento en que EMPEZÓ, no sólo cuando se detectó:
la diferencia entre ambos es una métrica en sí misma.

Ejemplo real: el drift de producción empezó el 31/07 y se detectó el 05/08.
Cinco días. Ese número es el hallazgo principal del post-mortem.
-->

| Hora | Evento |
|---|---|
|  | Empieza el problema |
|  | Primer síntoma observable |
|  | Se detecta |
|  | Se contiene |
|  | Se resuelve |

**Tiempo hasta la detección:** <!-- el número que importa -->

## 4. Cómo se detectó

<!--
Sé honesto. "Por casualidad" y "porque un usuario avisó" son respuestas
válidas y son las más informativas: significan que faltaba un control de detección.
-->

| Campo | Valor |
|---|---|
| Mecanismo | <!-- alerta automática / revisión rutinaria / casualidad / aviso de usuario --> |
| ¿Existía una alerta para esto? | |
| Si existía, ¿por qué no sonó? | |

## 5. Causa raíz

<!--
No el síntoma: la causa. Preguntá "por qué" hasta que la respuesta
sea un control faltante, no un error humano.

Mal:  "Alguien se olvidó de desplegar las migraciones"
Bien: "Desplegar es un acto manual sin verificación posterior del estado
       real del servidor. Nadie había mirado el servidor, solo el repositorio"

La segunda formulación produce un control. La primera produce culpa.
-->

**Causa raíz:**

**Por qué no se detectó antes:**

**Por qué el control existente no lo evitó:**

## 6. Qué se hizo para contener

| # | Acción | Hora | Resultado |
|---|---|---|---|
| 1 |  |  |  |

## 7. Corrección definitiva

| Campo | Valor |
|---|---|
| Qué se corrigió | |
| Release asociado | RELEASE-XXXX |
| Verificado | |

## 8. Controles nuevos

<!--
La sección más importante del documento. Un incidente sin control nuevo
va a volver, y la segunda vez no vas a poder decir que no lo sabías.

Ejemplo real — el PDF de 21,9 MB del 2026-07-25 produjo CUATRO controles:
validación previa, límite de 20 MiB, verificación de firma %PDF-,
y una máquina de estados explícita. 6/6 PASS.
-->

| # | Control nuevo | Tipo | Requisito asociado | Estado |
|---|---|---|---|---|
| 1 |  | <!-- prevención / detección / mitigación --> | REQ-XXXX | |

<!--
Un buen incidente produce al menos un control de PREVENCIÓN y uno de DETECCIÓN.
Si sólo hay mitigación, el problema va a volver igual y sólo va a doler menos.
-->

## 9. Qué NO se pudo determinar

<!--
Los huecos del relato. Se declaran, no se rellenan.
  "Es preferible mantener un vacío explícito antes que completar
   la historia con una narración no demostrable."

Ejemplo real: durante los cinco días de drift no hay registro de qué se
intentó ejecutar contra el esquema desatendido. Ese pedazo no existe.
-->

- <!-- [PENDIENTE DE VERIFICAR] o "Historia incompleta: ..." -->

## 10. Participación de agentes de IA

| Pregunta | Respuesta |
|---|---|
| ¿Un agente participó en lo que causó el incidente? | |
| Si sí, ¿fue error de ejecución, de alcance o de afirmación? | |
| ¿El agente reconstruyó la línea de tiempo? | |
| ¿El cierre lo declaró un humano? | <!-- debe ser SÍ --> |
| ¿Se agregó una restricción al encargo de agentes a partir de esto? | |

## 11. Lecciones

<!--
Qué se aprendió, en forma de regla reutilizable. Una o dos, no diez.
Si son diez, no se va a acordar ninguna.
-->

- 

## 12. Cierre

- [ ] Causa raíz escrita y aceptada por el responsable
- [ ] Corrección desplegada y verificada
- [ ] Al menos un control nuevo definido y convertido en `REQ-XXXX`
- [ ] Los huecos del relato están declarados, no rellenados
- [ ] Si hubo exposición de datos, se ejecutó el procedimiento de corrección de la política de publicación
- [ ] El documento es legible por alguien que no estaba

## 13. Historial

| Fecha | Cambio | Quién |
|---|---|---|
| AAAA-MM-DD | Creado | |

> Última verificación: 2026-08-05
