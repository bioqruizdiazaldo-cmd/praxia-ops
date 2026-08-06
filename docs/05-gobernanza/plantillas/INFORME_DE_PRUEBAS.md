# TEST-XXXX — <componente probado>

Plantilla de informe de pruebas: la evidencia que habilita —o bloquea— un release. Es la salida de la etapa 5 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md).

<!--
CÓMO USAR ESTA PLANTILLA
1. Copiala a TEST-0001-componente.md
2. El veredicto lo declara un HUMANO, aunque las pruebas las haya ejecutado un agente
3. El umbral se toma del requisito. No se ajusta acá. Nunca
4. Un FAIL se explica por qué falla, no por qué no importa
-->

| Campo | Valor |
|---|---|
| **ID** | TEST-XXXX |
| **Estado** | <!-- En curso / Cerrado favorable / Cerrado desfavorable / Invalidado --> |
| **Fecha** | AAAA-MM-DD |
| **Componente** | |
| **Versión probada** | <!-- hash, tag o versión de esquema --> |
| **Requisito** | REQ-XXXX |
| **Plan** | PLAN-XXXX |
| **Ejecutado por** | <!-- humano o agente, con nombre --> |
| **Veredicto declarado por** | <!-- SIEMPRE un humano con nombre --> |

---

## 1. Veredicto

<!--
Primero el resultado, después el detalle. Quien lee un informe de pruebas
quiere saber si pasa o no pasa antes que nada.
-->

| Campo | Valor |
|---|---|
| **Umbral declarado en el requisito** | <!-- p. ej. 7/7 --> |
| **Resultado** | <!-- p. ej. 2/7 --> |
| **Veredicto** | <!-- APROBADO / NO APROBADO --> |
| **Consecuencia** | <!-- habilita RELEASE-XXXX / no se publica / vuelve a etapa 4 --> |

<!--
Ejemplo real: el Buscador General sacó 2/7 contra una exigencia declarada de 7/7.
Veredicto: NO APROBADO. Consecuencia: no publicado. Ver ADR-006.
-->

## 2. Entorno de prueba

| Aspecto | Valor |
|---|---|
| Dónde corrió | <!-- local / staging / PGlite / runtime aislado --> |
| Datos usados | <!-- SIEMPRE sintéticos. Si se usó un dato real, el informe es inválido --> |
| Credenciales | <!-- de prueba, por nombre simbólico --> |
| Fecha y hora de ejecución | |

## 3. Casos

| # | Caso | Entrada (sintética) | Esperado | Obtenido | Resultado |
|---|---|---|---|---|---|
| 1 |  |  |  |  | <!-- PASS / FAIL --> |
| 2 |  |  |  |  |  |
| 3 |  |  |  |  |  |

**Conteo:** <!-- X PASS / Y FAIL / Z omitidos -->

## 4. Cobertura

| Categoría | Cubierta | Comentario |
|---|---|---|
| Camino feliz | <!-- sí / no --> | |
| Entrada vacía | | |
| Entrada mal formada | | |
| Valores ambiguos o límite | | |
| Servicio externo caído | | |
| Camino de error | | |
| Idempotencia / doble ejecución | | |
| Permisos y aislamiento | | |

**Qué NO se probó y por qué**

<!--
Declarar los huecos es parte del informe. Un informe que no dice
qué quedó sin probar sugiere una cobertura que no tiene.
-->

- 

## 5. Análisis de los FAIL

<!--
Uno por uno. Por qué falla, no por qué no importa.

La distinción que importa, y que es real en este proyecto:
  "Los cuatro FAIL no son falsos positivos del nuevo validador:
   son fixtures que no contienen evidencia suficiente para producir
   una respuesta grounded."

Es decir: se determinó si el problema estaba en el sistema o en la prueba,
y se dijo cuál de los dos. Sin eso, un FAIL se convierte en una excusa.
-->

| # | Por qué falla | ¿Problema del sistema o de la prueba? | Acción |
|---|---|---|---|
|  |  |  |  |

## 6. Regresión

- [ ] Lo que funcionaba antes sigue funcionando
- [ ] La suite completa corrió, no sólo los casos nuevos
- [ ] Conteo total de la suite: <!-- p. ej. 606/606 -->

## 7. Participación de agentes de IA

| Pregunta | Respuesta |
|---|---|
| ¿Un agente escribió los casos? | |
| ¿Un agente ejecutó las pruebas? | |
| ¿Un agente propuso cambiar el umbral o un fixture? | <!-- si la respuesta es sí, detallar qué se hizo con la propuesta --> |
| ¿Se verificó por muestreo lo que el agente reporta? | |

<!--
Un agente NUNCA declara el veredicto y NUNCA ajusta el umbral
para que las pruebas pasen. Ver el acuerdo de trabajo con agentes.
-->

## 8. Evidencia adjunta

<!-- Salida de la corrida, conteos, capturas. Sanitizada: sin datos reales, sin credenciales. -->

```
<pegar salida sanitizada>
```

## 9. Nivel de evidencia

| Afirmación | Nivel |
|---|---|
|  |  |

## 10. Historial

| Fecha | Cambio | Quién |
|---|---|---|
| AAAA-MM-DD | Creado | |

> Última verificación: 2026-08-05
