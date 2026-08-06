# Límites y deudas del Agente Fiscal

Esta página es el inventario de lo que el subsistema **no** hace, lo que hace mal a sabiendas, y lo que todavía nadie decidió. Está publicada al mismo nivel que el resto de la documentación y por la misma razón: un sistema que opera sobre obligaciones fiscales necesita que su lista de limitaciones sea tan fácil de encontrar como su lista de capacidades. Un límite escrito es un activo — se puede planificar, se puede compensar y se puede discutir. Un límite no escrito es una sorpresa esperando fecha.

---

## El patrón de riesgo que gobierna todo

> *«Un sistema fiscal falla de dos maneras muy distintas: ruidosamente […] y en silencio: devuelve algo plausible y equivocado. La segunda es la peligrosa.»*

Hay **siete instancias catalogadas** de este patrón en la historia del proyecto: el parser de montos, `/api/resumen`, los vencimientos cruzando husos horarios, `cargar_datos_maestros` devolviendo `INSERT 0 0`, la función `prohibido()`, el verificador con `wget` que no podía emitir la petición que tenía que verificar, y el tratamiento del régimen `historico`.

Ninguna de las siete produjo un error. Las siete produjeron una respuesta con buena cara. Por eso el diseño prefiere abstenerse antes que aproximar, y por eso esta página existe.

---

## Fuera de alcance v1 (contrato §17)

No son "todavía no". Son "no en esta versión, y ampliarlo requiere modificar el contrato".

1. Escritura directa Fiscal → base de datos.
2. Modificación de movimientos históricos o actuales.
3. **Presentar declaraciones o interactuar con ARCA.**
4. Pago automático de deudas, VEPs o saldos.
5. Asientos correctivos automáticos.
6. Modificación de saldos de cuentas.
7. Reclasificación automática sin supervisión.
8. Acceso a claves fiscales productivas.
9. Despliegue y DevOps.
10. Integración productiva ejecutable.
11. Implementación real de HTTP/RPC — **matizado por el Anexo A.4**: la prohibición regía mientras el contrato era borrador; la aprobación habilita implementarlo sin ampliar ningún permiso.
12. Alteración de vistas del Dashboard.

---

## No implementado (Anexo A.5 y estado actual)

| # | Qué falta | Estado |
|---|---|---|
| 1 | **Rol de PostgreSQL de solo lectura** (§14, *«exclusividad técnica a nivel de motor»*) | El guardia de aplicación existe y funciona. La segunda barrera es **tarea de despliegue pendiente**: crear el rol, otorgarle `SELECT` solo sobre las tablas del §5 y apuntar la capa a ese rol |
| 2 | **Persistencia de la auditoría de consultas** | Hoy es una línea JSON al log del proceso. Ver abajo |
| 3 | Clave de idempotencia completa de propuestas | **Resuelto en v4.8** con `calcularHuella()`. El Anexo A.5 quedó desactualizado en este punto |
| 4 | **Disparo mensual automático en n8n** | El 3% que falta. Ver abajo |
| 5 | Cargar las plantillas reales de obligaciones con sus importes vigentes | Pendiente |
| 6 | Dashboard v3 | El prototipo se perdió en el directorio temporal de la máquina de desarrollo. Las cuatro notas de diseño están completas |

### Sobre la auditoría de consultas

> *«Escribirla en una tabla exigiría permiso de INSERT, que es justamente lo que el rol fiscal no debe tener. Si se necesita persistirla, debe hacerlo un componente aparte que recoja el log.»*

No es una omisión: es la consecuencia de tomarse en serio "solo lectura". La solución correcta está identificada —un recolector de logs externo— y no se implementó todavía. Mientras tanto, la auditoría existe pero vive con la retención del log del proceso.

### Sobre el disparo mensual

El workflow `04_agente_fiscal_mensual.json` es un **esqueleto lineal de cuatro nodos con trigger manual**:

```
[Trigger Manual] → [Set Periodo] (periodo hardcodeado)
                 → [Get Chequeos] (GET a la ruta de chequeos del cierre)
                 → [Guardar Borrador] (POST a la ruta de borrador)
```

Sin condicionales, sin manejo de error, sin envío a Telegram. Y con un detalle que conviene mirar: **el host y puerto internos que usa difieren de los que usa el resto del sistema** — `<api-interna>:<puerto-A>` contra `<api-interna>:<puerto-B>`. Posible drift entre el workflow versionado y la topología real.

El diseño acordado para reemplazarlo: un workflow del día 1 de cada mes que llame a `GET /api/fiscal-diagnostico?periodo=AAAAMM&registrar=true` y mande el campo `mensaje` por Telegram. Todo lo que ese workflow necesita ya existe; falta armarlo.

---

## Bugs conocidos declarados

### `cierre_chequeos()` arrastra el filtro que arregló la v4.13

El chequeo 13 (`sin_perfil_fiscal`) filtra por `estado IN ('vigente','en_tramite')`. La v4.13 corrigió exactamente ese criterio en `regimen_vigente()`, que dejó de exigir `estado = 'vigente'` y ahora solo descarta `baja` y `observado` — porque un régimen marcado `historico` sigue habiendo estado vigente en su momento. `cierre_chequeos()` no recibió la corrección.

**Consecuencia:** al cerrar retroactivamente un período anterior a mediados de 2022, la función dirá «No hay condición fiscal vigente» aunque la haya en el histórico. Es un falso bloqueante: ruidoso, no silencioso.

**No se corrige a propósito:**

> *«`cierre_chequeos()` es una función de trece ramas UNION ALL, y `CREATE OR REPLACE` obliga a reescribirla entera. Hacerlo sin tener las trece delante es cómo se rompe algo en silencio.»*

La decisión merece explicitarse porque es el tipo de cosa que se lee como pereza y no lo es. El bug conocido produce un bloqueo visible en un caso poco frecuente —cierres retroactivos de hace más de cuatro años— y quien lo encuentre entiende inmediatamente qué pasó. Reescribir trece ramas de memoria, en cambio, arriesga alterar alguna de las otras doce de un modo que **no** se nota: un chequeo que deja de bloquear es un chequeo que nadie extraña. Se cambia un fallo ruidoso conocido por el riesgo de introducir un fallo silencioso desconocido, y esa no es una buena permuta.

Queda pendiente para cuando se pueda revisar la función completa, con las trece ramas a la vista y tests por rama.

### Deriva del MCP desplegado contra el repositorio

`consultar_resumen` en producción espera un parámetro `periodo`; el repositorio usa `mes`. Y la versión desplegada **devuelve el mes corriente ignorando el parámetro**.

Es el patrón silencioso en estado puro: quien pida el resumen de un mes anterior va a recibir un resumen — el del mes actual — sin ningún indicio de que la pregunta no fue la que se contestó. Prioridad alta.

### Rutas fiscales sin auditar

Se corrigieron la clasificación de movimientos y la transición de cierre. **Quedan por revisar comprobantes, perfiles y borradores**, y la sospecha está escrita: *«probablemente tengan el mismo patrón»* de duplicar la lógica de `fiscal.mjs` en la ruta en lugar de delegar.

El patrón es el mismo que produjo el bug de la máquina de estados del cierre: la ruta HTTP hace el `UPDATE` directo y la función que valida existe pero nunca se ejecuta. El 2026-08-05 se descubrió que `server.mjs` **no importaba** `fiscal.mjs` en absoluto — 23 funciones muertas. Existe `tests/test_fiscal_rutas_delegan.mjs` (13 casos) que lee `server.mjs` y verifica que importe en vez de reescribir, pero la cobertura de rutas todavía es parcial.

### Datos operativos inconsistentes

Una cuenta de efectivo en pesos figura con **saldo negativo**, lo que es imposible: faltan ingresos por cargar. Conviene resolverlo antes de cerrar el período. Es el tipo de hallazgo que el detector `saldo_incoherente` reporta y que ninguna automatización debería corregir sola.

### Deuda operativa

- Actualizaciones de sistema operativo y un reinicio pendientes en el servidor.
- Cambios sin commitear: los scripts de `ops/` y el `Dockerfile` de la última sesión, perdidos cuando el entorno de trabajo perdió el montaje de la carpeta. Hay además un incidente de despliegue registrado —un `Dockerfile` con lista de archivos a mano— que terminó en rollback.

---

## Las once decisiones abiertas del §19

Todas son del titular. Ninguna se puede resolver desde el código.

| # | Decisión | Por qué importa |
|---|---|---|
| 1 | Vistas SQL vs. API como superficie de consulta | Define si el Fiscal lee vistas o pasa siempre por la capa |
| 2 | Nivel de detalle accesible | Cuánto granular puede ver el agente sin necesidad |
| 3 | Retención de auditoría | Cuánto tiempo se guarda y dónde |
| 4 | Tratamiento de documentos | Qué puede hacer el agente con el contenido de un PDF |
| 5 | Moneda y conversión | Política de conversión aprobada; hoy no se suman monedas |
| 6 | Datos personales: PII crudo vs. anonimizado | Qué llega al modelo |
| 7 | Sincronización: *pooling* vs. *push* | Cómo se entera el agente de que hay algo nuevo |
| 8 | Mecanismo de aprobación: WebUI vs. Telegram | **Recomendación registrada: panel dashboard** |
| 9 | Acceso futuro de escritura | Si alguna vez, bajo qué condiciones |
| 10 | Integración con ARCA | Hoy fuera de alcance por contrato |
| 11 | Mecanismo seguro de secretos | Vault, variables de entorno, credenciales de n8n |

La #8 es la que más bloquea en la práctica: sin un mecanismo de aprobación cómodo, las propuestas se acumulan en `pendiente` y la garantía anti-repregunta empieza a funcionar como un tapón.

---

## Decisiones abiertas del ADR

**Resuelta — #1, USD/ARS.** Se optó por la alternativa (a), registrada en el §19 del ADR: una obligación en USD **no se cancela** con un movimiento en ARS. Se imputa en `obligacion_cargos` sin tocar el saldo, y la capa fiscal la reporta como `moneda_inconsistente_en_imputacion` con severidad alta. Es decir: el sistema no convierte, señala.

**Siguen abiertas:**

- **#2** — Fórmula de interés en `planes_pago`.
- **#3** — Renombrado de la fase 8.
- **#4** — Umbral y forma de `regla_calendario`.

### Fases del ADR

Las fases 0 y 1 están cerradas. **De la 2 a la 8, pendientes.**

La fase 4 —generación recurrente vía n8n— está **condicionada a una auditoría de la instancia viva de n8n** (§12 del ADR):

> *«el impacto cero se comprobó únicamente sobre los nueve JSON versionados. El MCP de n8n no estuvo disponible en ninguna de las dos sesiones.»*

Es una limitación de alcance declarada, no un supuesto: lo que se verificó fueron los workflows del repositorio, no los que están corriendo. La diferencia entre esas dos cosas es precisamente lo que produjo el post-mortem de drift de producción.

---

## Límites de método, no de implementación

Hay tres cosas que este subsistema **no puede** hacer bien, por diseño, y que ninguna versión futura va a arreglar sin cambiar el enfoque:

**El primer mes propone poco, y eso es correcto.** Sin precedentes, el motor se abstiene. Un agente que propusiera mucho el primer mes estaría inventando. La curva de utilidad es lenta a propósito.

**Una lista vacía no prueba nada.** El contrato lo dice de `ConsultarDiscrepanciasAbiertas` y el motor lo repite en castellano: *«los chequeos y detectores que existen no ven nada, no que el período esté necesariamente perfecto»*. El sistema puede decir qué encontró; no puede decir que no hay nada.

**El catálogo de obligaciones es una ayuda, no una determinación.** Está escrito así: *«una AYUDA PARA NO OLVIDARSE, no una determinación fiscal»*. Cuando el diagnóstico lista obligaciones que el régimen implica y no están cargadas, agrega la aclaración de confirmarlo con el contador. Ninguna mejora del catálogo cambia eso.

---

## Cómo leer esta página

No está acá para pedir disculpas. Está acá porque las tres decisiones más caras del subsistema —abstenerse en vez de aproximar, poner las invariantes en la base, y no darle al agente la credencial de aprobación— se tomaron **mirando esta lista**, no a pesar de ella. Cada límite conocido es una hipótesis sobre dónde va a fallar el sistema; tenerlas escritas es lo que permite elegir cuáles vale la pena cerrar y cuáles conviene dejar ruidosas y visibles.

Lo que no está en esta página es lo que debería preocupar.

---

## Documentos relacionados

- [Ficha del subsistema](README.md)
- [El contrato v1.0](contrato-finanzas-fiscal.md) — §17, §19 y Anexo A
- [La capa de lectura](capa-de-lectura.md)
- [Cierre fiscal](cierre-fiscal.md)
- [Seguridad y permisos](seguridad-y-permisos.md)
- [ROADMAP](../../ROADMAP.md)
- [Post-mortem: drift de producción](../../docs/06-runbooks/postmortem-drift-produccion.md)
- [Publicar un workflow n8n](../../docs/06-runbooks/publicar-un-workflow-n8n.md)
- [Política de publicación](../../docs/05-gobernanza/politica-de-publicacion.md)

> Última verificación: 2026-08-06
