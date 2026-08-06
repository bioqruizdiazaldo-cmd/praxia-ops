# Definición de terminado

La compuerta de salida: qué tiene que ser cierto para poder decir que algo está hecho.

Se usa al cerrar la etapa 5 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md). "Terminado" no significa "funciona en mi prueba": significa que otro puede verificarlo, revertirlo y operarlo sin preguntarte nada.

---

## Funciona

- [ ] Cumple **todos** los criterios de aceptación del `REQ-XXXX`, uno por uno
- [ ] Ninguno de los criterios se modificó después de empezar a implementar
- [ ] Funciona con la entrada esperada
- [ ] Funciona con entrada vacía, mal formada o inesperada, y falla de manera predecible
- [ ] El comportamiento ante un servicio externo caído está probado, no supuesto
- [ ] No hace nada que esté fuera del alcance declarado

## Está probado

- [ ] Existe un `TEST-XXXX` con casos, resultados y veredicto
- [ ] Los fixtures son **sintéticos**. Ningún dato real se usó como caso de prueba
- [ ] Los casos límite están cubiertos: valores ambiguos, formatos alternativos, ausencia de dato
- [ ] Se probó el camino de error, no sólo el camino feliz
- [ ] El conteo de PASS/FAIL está escrito con números, no con adjetivos
- [ ] Si hay FAIL, están explicados: **por qué fallan**, no por qué no importan
- [ ] El umbral declarado en la definición de listo se alcanzó. Si no se alcanzó, **no está terminado**

> El buscador sacó 2/7 contra una exigencia de 7/7 y no se publicó. Bajar la exigencia habría sido la única forma de "terminarlo".

## Es reversible

- [ ] El artefacto anterior está exportado y guardado
- [ ] Se verificó que el artefacto anterior se puede importar o aplicar, no sólo que existe
- [ ] El procedimiento de rollback está escrito en pasos concretos
- [ ] Está claro qué se pierde si hay que revertir
- [ ] Si hay migración de datos, la vuelta atrás también está definida

## Está documentado

- [ ] El manifiesto está completo si es un workflow: los 11 campos, ninguno vacío
- [ ] El contrato de entrada y salida está escrito, con los estados posibles enumerados
- [ ] Las dependencias están listadas
- [ ] Si cambió una decisión de arquitectura, hay un `ADR-XXXX`
- [ ] Si hay algo que el próximo que lo toque necesita saber, está escrito y no en la cabeza de alguien
- [ ] Toda afirmación tiene su nivel de evidencia

## Es seguro

- [ ] No hay secretos en el artefacto: ni tokens, ni claves, ni contraseñas
- [ ] Las credenciales están por **referencia simbólica**, nunca por ID ni por valor
- [ ] No hay datos reales pegados en nodos (`pinData`) ni en fixtures
- [ ] Los datos sensibles que procesa están protegidos antes de llegar al modelo
- [ ] Los permisos son los mínimos necesarios. Nada concedido "por las dudas"
- [ ] Si escribe en la base, las invariantes que lo protegen están en la base, no sólo en el código

## Es observable

- [ ] Los errores llegan al `errorWorkflow` global o al mecanismo de captura correspondiente
- [ ] Un fallo produce un aviso, no un silencio
- [ ] Queda registro de lo que hizo: log, auditoría o historial de ejecución
- [ ] Se puede responder "¿esto corrió?" y "¿esto anduvo bien?" sin abrir el lienzo

## Está limpio

- [ ] No quedaron workflows, ramas ni nodos de prueba activos
- [ ] Los artefactos intermedios están archivados o borrados, no abandonados en producción
- [ ] El estado de ciclo de vida del manifiesto refleja la realidad
- [ ] El nombre dice lo que es. Nada activo se llama `[TEST]`

## Trabajo con agentes de IA

- [ ] El agente devolvió la evidencia pedida, no un resumen de la evidencia
- [ ] Cada afirmación del agente está etiquetada: Verificado / Confirmado por el responsable / Inferido / Pendiente de verificar / Historia incompleta
- [ ] Lo que el agente reporta como verificado, **se verificó por muestreo**. No se acepta por confianza
- [ ] El agente no tocó nada fuera del alcance del encargo
- [ ] El veredicto de las pruebas lo declaró un humano, aunque las haya ejecutado el agente
- [ ] Si el agente propuso cambiar un criterio de aceptación, la propuesta fue rechazada o se abrió un requisito nuevo — no se cambió en silencio
- [ ] Ningún hueco quedó rellenado con una narración plausible

---

## La prueba final

Tres preguntas. Si alguna falla, no está terminado, por más casillas tildadas que haya.

1. **¿Otro podría revertir esto sin preguntarte nada?** Si no, falta documentación o falta rollback.
2. **¿Podés demostrar que funciona sin ejecutarlo delante de alguien?** Si no, falta evidencia escrita.
3. **¿Dentro de tres meses vas a poder decir qué versión está corriendo?** Si no, falta el registro del release.

> Última verificación: 2026-08-05
