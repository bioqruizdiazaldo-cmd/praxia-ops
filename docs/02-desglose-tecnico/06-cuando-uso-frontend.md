# Cuándo uso frontend

Cuándo un sistema con agentes necesita una pantalla y cuándo el chat alcanza — y por qué esa pantalla acá es un solo archivo HTML sin framework.

## Criterio

El chat es una interfaz excelente para una clase de tareas y muy mala para otra. La confusión de moda es creer que porque el agente entiende lenguaje natural, la interfaz de lenguaje natural sirve para todo.

### Dónde gana el chat

| Tarea | Por qué |
|---|---|
| Entrada rápida y ambigua ("café 3500 con la tarjeta") | Escribir es más rápido que llenar cinco campos |
| Consulta puntual con respuesta corta | No hace falta abrir nada |
| Entrada multimodal (foto de un ticket, audio, PDF) | Ya estás en la app donde tenés el archivo |
| Interacción desde el celular, en movimiento | No hay UI que compita con mandar un mensaje |
| Acciones de una sola vez | El costo de una pantalla no se amortiza |

### Dónde pierde

| Tarea | Por qué pierde |
|---|---|
| Revisar 40 registros | Un chat no tiene tabla. Enumerar 40 ítems en texto es ilegible |
| Comparar valores | Sin columnas alineadas no hay comparación |
| Corregir muchas cosas seguidas | Cada corrección es un turno completo: escribir, esperar, verificar |
| Ver **qué falta** | El chat muestra lo que preguntaste; la pantalla muestra lo que hay |
| Confiar en un total | Un número en una burbuja de chat no se puede auditar sin volver a preguntar |
| Trabajo con estado ("¿cuáles ya revisé?") | El chat es un log, no un tablero |

### La prueba de las tres preguntas

Necesitás una pantalla cuando alguna respuesta es "sí":

1. **¿Hay que revisar más de ~7 cosas seguidas?** Es el límite práctico de lo que se sigue en texto.
2. **¿Hay estado pendiente que alguien tiene que mirar aunque no pregunte?** Un pendiente que sólo aparece si preguntás no existe.
3. **¿Hay que corregir lo que el agente decidió?** Corregir por chat es caro; corregir en una tabla es un clic.

En sistemas agénticos la número 2 es la decisiva. Un agente que clasifica movimientos genera, inevitablemente, cosas que no supo resolver. Si esas cosas viven en una tabla que nadie mira, el sistema acumula deuda silenciosa hasta que el reporte mensual sale mal.

### Cuatro criterios de UI propios de sistemas con agentes

Estos no aparecen en las guías de UI clásicas porque suponen que del otro lado hay un formulario, no un modelo.

**1. Mostrar el estado, no sólo el dato.**
Un movimiento no es sólo monto y fecha: es `pendiente`, `confirmado` o `anulado`, y eso tiene que verse antes que el número. El estado es la información más importante en un sistema donde una máquina propuso el dato.

**2. Permitir corregir en el lugar donde se ve el error.**
Si detectás la equivocación en la tabla y para arreglarla tenés que ir al chat, la corrección no va a pasar. La fricción entre ver y arreglar determina si el sistema converge o se degrada.

**3. Hacer visible lo pendiente.**
Lo pendiente necesita su propia sección, no un filtro escondido. Es la métrica de salud del sistema: si crece, el agente está fallando en clasificar o el humano no está revisando.

**4. No esconder lo que el agente decidió.**
Si el agente eligió una categoría, se muestra que **él** la eligió y con qué evidencia. Una decisión automática presentada como dato de entrada es indistinguible de un dato cargado por una persona, y eso rompe la auditabilidad. Es el mismo principio que en la memoria: `Verificado` no es lo mismo que `Inferido`.

## En este sistema

**`api/public/index.html`: HTML/JS vanilla en un solo archivo, 1.911 líneas.** No hay React, Vue ni Tailwind. Sin build step, sin `node_modules`, sin bundler.

### Por qué esa elección

Lo que se gana:

- **No hay pipeline de build.** El deploy del frontend es copiar un archivo. No hay una versión compilada que pueda diferir del fuente.
- **Cero dependencias de front.** Ninguna cadena de suministro de npm en el navegador, ningún paquete que se abandone en seis meses.
- **Lee lo mismo que se ejecuta.** "Ver código fuente" muestra el código real. En un sistema donde la auditabilidad es un principio, no es un detalle menor.
- **Coherencia con el backend.** Node sin framework atrás, JS sin framework adelante. Una sola forma de pensar el proyecto.
- **Ninguna dependencia se rompe sola.** Un archivo estático de 2026 sigue funcionando en 2029.

Lo que se pierde, sin adornos:

- **No hay componentes reutilizables de verdad.** Hay funciones que devuelven strings de HTML. Con 7 secciones es manejable; con 20 sería un problema serio.
- **El estado se maneja a mano.** Sincronizar UI y datos es responsabilidad del código, y ahí es donde aparecen los bugs de "la tabla no se actualizó".
- **1.911 líneas en un archivo son 1.911 líneas en un archivo.** La navegación es por búsqueda de texto.
- **No hay tests de UI.** Los 554 casos cubren backend y lógica; hay tests de **exportación del dashboard**, que verifican el dato que sale, no la interacción.
- **Accesibilidad y estados de carga hay que escribirlos a mano**, uno por uno.

El balance depende enteramente de la escala. Para 7 secciones sobre una API bien definida, con un solo usuario, la elección es correcta y ahorra semanas. Para una app multiusuario con permisos por pantalla, sería la elección equivocada y habría que migrar.

### Las 7 secciones

| Sección | Qué resuelve | Por qué no alcanza el chat |
|---|---|---|
| `inicio` | Saldos, patrimonio, resumen | Comparar varias monedas necesita columnas |
| `movs` | Listado de movimientos con filtros | Es la tabla; 40 filas no entran en un chat |
| `pend` | Lo que el agente no supo resolver | **La razón principal de que exista el dashboard** |
| `carga` | Alta manual | Cuando el texto libre no alcanza y querés control campo por campo |
| `deudas` | Deudas, pagos, vinculación | Relación uno-a-muchos con estado: imposible de seguir en texto |
| `importar` | Documentos PDF/CSV/Excel y su revisión | Hay que ver qué extrajo el parser antes de aceptarlo |
| `fiscal` | Comprobantes, período, cierre | Trabajo con estado y consecuencias regulatorias |

Operaciones que permite: ver, corregir, confirmar, anular, vincular pagos y exportar.

Cada una de esas seis existe por el criterio 2 (corregir donde se ve el error) o el criterio 4 (no esconder lo que decidió el agente). `confirmar` es el caso más claro: es el humano diciendo "sí, lo que propuso está bien". Sin esa acción, la aprobación humana sería una ficción.

### Cómo se reparten chat y pantalla acá

```
Telegram (chat)                   Dashboard (pantalla)
─────────────────                 ──────────────────────
alta rápida por texto      →      revisión de pendientes
foto de ticket             →      corrección de la extracción
audio                      →      confirmación en lote
consulta puntual           →      comparación y totales
                                  cierre fiscal
                                  exportación
```

No son dos interfaces para lo mismo: son dos mitades del mismo flujo. El chat captura, la pantalla resuelve. **Ambas escriben por `POST /api/ingesta`** — la misma puerta, el mismo contrato, la misma auditoría. La UI no es un camino privilegiado.

Eso es lo que hace que la separación funcione. Si el dashboard escribiera directo a la base, serían dos sistemas con dos conjuntos de reglas.

### Cómo se organiza un archivo de 1.911 líneas sin que sea un caos

Sin framework, la disciplina la tenés que poner vos. El patrón que hace que esto siga siendo mantenible es simple y vale para cualquier SPA vanilla:

```html
<!-- SINTÉTICO — la estructura, no el archivo real -->
<script>
// 1. Estado en un solo objeto. Nada de variables sueltas.
const estado = { seccion: 'inicio', datos: {}, cargando: false, error: null };

// 2. Una función por llamada a la API. Nada de fetch disperso en handlers.
async function api(ruta, opciones = {}) {
  const r = await fetch(`/api${ruta}`, { ...opciones, headers: cabeceras() });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return r.json();
}

// 3. Render puro: estado -> HTML. Sin efectos secundarios adentro.
function renderPendientes(items) {
  if (!items.length) return '<p class="vacio">No hay pendientes.</p>';
  return `<table>${items.map(filaPendiente).join('')}</table>`;
}

// 4. Un solo punto que aplica el render al DOM.
function pintar() {
  document.querySelector('#app').innerHTML = VISTAS[estado.seccion](estado);
}
</script>
```

Cuatro reglas que sostienen el archivo:

1. **Un objeto de estado, no variables sueltas.** Es lo único que evita el bug de "la tabla quedó vieja".
2. **Todas las llamadas HTTP pasan por una función.** Autenticación, manejo de errores y encabezados en un solo lugar.
3. **Las funciones de render son puras.** Reciben datos, devuelven string. Se pueden razonar de a una.
4. **Un solo lugar que toca el DOM.** Si diez funciones escriben en el DOM, el orden de ejecución se vuelve la lógica del programa.

Es, esencialmente, reimplementar a mano las tres ideas que un framework te da gratis: estado centralizado, render derivado del estado y un punto de montaje. Si el proyecto creciera, la conclusión honesta sería que ya estás escribiendo un framework peor — y ahí conviene usar uno.

### El prototipo UI v3

Existe un **Dashboard UI v3** para obligaciones recurrentes: **17 estados**, tema claro/oscuro con **contraste AA**, revisado y **aprobado en diseño, no migrado**. Es la Fase 6 del ADR.

Dos cosas para señalar.

**17 estados es un número honesto.** Cuando modelás obligaciones recurrentes en serio —generada, pendiente, vencida, pagada parcial, pagada total, anulada, reprogramada, en disputa, y las combinaciones con el período fiscal— llegás a 17. Un diseño que muestra tres estados y mete el resto en "otros" es un diseño que todavía no entendió el dominio. Enumerarlos primero y después dibujar es el orden correcto.

**Contraste AA como requisito, no como mejora.** El dashboard se usa para revisar números y decidir. Contraste insuficiente en una tabla de montos no es un problema estético: es un error de lectura esperando.

Y "aprobado en diseño, no migrado" es una etiqueta que vale la pena usar. Dice exactamente dónde está: hay una decisión tomada y no hay código. No es "en progreso" ni "próximamente".

### Lo que el frontend deliberadamente no hace

- **No tiene lógica de negocio propia.** Los saldos vienen de `v_saldos_por_moneda`, no se calculan en el navegador. Si se calcularan en los dos lados, divergirían.
- **No borra.** No hay botón de borrar porque no hay endpoint `DELETE`. Coherencia de arriba a abajo.
- **No guarda estado local relevante.** Refrescar la página no pierde nada porque nada importante vive sólo en el navegador.
- **No tiene login propio.** Autenticación por token, igual que el resto de los clientes. `[PENDIENTE DE VERIFICAR: mecanismo exacto de entrega del token al navegador]`

## Regla

El chat captura, la pantalla resuelve. Hacé una pantalla cuando haya que revisar muchas cosas, ver lo pendiente sin preguntar o corregir lo que el agente decidió; y hacé que escriba por la misma puerta que todo lo demás.

> Última verificación: 2026-08-05
