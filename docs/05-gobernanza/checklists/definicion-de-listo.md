# Definición de listo

La compuerta de entrada: qué tiene que estar resuelto **antes** de empezar a construir algo.

Se usa al cerrar la etapa 1 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md). Si un ítem no se puede tildar, el trabajo no está listo para empezar — y empezarlo igual es cómo se producen los errores de alcance.

---

## El requisito

- [ ] Existe un `REQ-XXXX` escrito, no una conversación recordada
- [ ] El objetivo cabe en una frase y dice **qué tiene que ser cierto** cuando termine, no qué se va a hacer
- [ ] El alcance está enumerado: archivos, tablas, workflows y endpoints con nombre
- [ ] El **fuera de alcance** está enumerado explícitamente
- [ ] Está claro qué problema real resuelve, y para quién
- [ ] Se evaluó la alternativa de **no hacerlo** y se descartó con una razón

## Los criterios de aceptación

- [ ] Son verificables, no opinables: se pueden tildar sin discutir
- [ ] Alguien que no participó del diseño podría verificarlos leyendo sólo el requisito
- [ ] Están escritos **antes** de la implementación, no ajustados después para que den bien
- [ ] Si hay un umbral numérico, está declarado (por ejemplo: 7/7 pruebas)
- [ ] Está definido qué pasa si el umbral no se alcanza

## La línea base

- [ ] Se inspeccionó el estado actual del **sistema real**, no sólo del repositorio
- [ ] Existe un punto de retorno identificado: backup, tag, export o commit
- [ ] Se verificó que el punto de retorno se puede restaurar, no sólo que existe
- [ ] Lo que se encontró está etiquetado con el vocabulario de evidencia
- [ ] Los huecos están declarados como `[PENDIENTE DE VERIFICAR]`, no rellenados

## Datos y seguridad

- [ ] Está declarada la clasificación de los datos que toca: público / interno / sensible / prohibido
- [ ] Si toca datos sensibles, está definido cómo se protegen antes de llegar al modelo
- [ ] Si necesita credenciales, están identificadas **por nombre simbólico**, no por valor
- [ ] Ningún dato real va a usarse como fixture de prueba
- [ ] Si genera artefactos públicos, se leyó la [política de publicación](../politica-de-publicacion.md)

## Dependencias y riesgo

- [ ] Las dependencias están listadas: otros workflows, APIs, tablas, servicios externos
- [ ] Se sabe qué se rompe si esto falla, y a quién afecta
- [ ] Hay una idea concreta de cómo se vuelve atrás
- [ ] Si depende de un servicio externo, está definido el comportamiento cuando no responde
- [ ] El costo está dentro del presupuesto declarado (**D-8**)

## Trabajo con agentes de IA

- [ ] Está definido el **modo de trabajo** del agente: solo lectura / escritura sin commit / escritura con commit / incluye despliegue
- [ ] Las acciones prohibidas para este encargo están escritas, no sobreentendidas
- [ ] Está claro qué evidencia tiene que devolver el agente
- [ ] Está definido qué hace el agente si se traba — por defecto: **parar y preguntar**, nunca asumir
- [ ] Si el trabajo incluye una acción del círculo 2 (escribir, desplegar, borrar, publicar, gastar), el permiso está pedido **para esta tarea**, no heredado de otra parecida
- [ ] Está identificado el **humano responsable** por nombre. No "el equipo", no "la IA"

---

## Las tres preguntas de control

Si alguna no tiene respuesta, la definición de listo no se cumple aunque todas las casillas estén tildadas.

1. **¿Cómo sabemos que terminó?** — Si la respuesta es "cuando funcione", falta la sección de criterios de aceptación.
2. **¿Cómo volvemos si sale mal?** — Si la respuesta es "hacemos un backup antes", falta verificar que ese backup se puede restaurar.
3. **¿Qué pasa si no lo hacemos?** — Si la respuesta es "nada grave", el trabajo probablemente no debería empezar todavía.

> Última verificación: 2026-08-05
