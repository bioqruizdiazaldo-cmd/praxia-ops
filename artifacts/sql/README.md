# Artefactos SQL

Nueve archivos que reconstruyen el diseño de datos de PraxIA Ops: la memoria del agente, el núcleo financiero, las invariantes escritas como triggers, las vistas de lectura, los permisos, el núcleo fiscal, las invariantes del cierre y el modelo de propuestas.

> **Reconstrucción didáctica sintética. No son dumps de producción.**
> Cada archivo fue escrito de nuevo a partir del diseño verificado. Los nombres de tablas, columnas, estados, funciones y guards son fieles al sistema real; los tipos exactos, los datos de ejemplo y buena parte de los constraints son una reconstrucción razonable. No hay datos, credenciales ni identificadores reales.

---

## Los archivos, en orden

| # | Archivo | Qué contiene |
|---|---|---|
| 01 | [`01-esquema-praxia-memoria.sql`](01-esquema-praxia-memoria.sql) | Esquema `praxia`: `memory_facts`, `memory_events`, `projects`, `tasks`, `agent_errors`, la función `praxia.normalizar` y `praxia.upsert_agent_error` con deduplicación y reserva de alerta |
| 02 | [`02-consulta-memoria-fulltext.sql`](02-consulta-memoria-fulltext.sql) | La consulta de memoria: transacción `READ ONLY`, `unaccent`, `to_tsvector('spanish')`, tier estricto y tier laxo |
| 03 | [`03-esquema-finanzas-nucleo.sql`](03-esquema-finanzas-nucleo.sql) | Núcleo de `praxia_finanzas`: `perfiles`, `cuentas`, `categorias`, `fx_rates` + `fx_vigente()`, `ingesta_raw`, `movimientos`, `transferencias`, `movimientos_auditoria`, `schema_migrations` |
| 04 | [`04-invariantes-y-triggers.sql`](04-invariantes-y-triggers.sql) | Las invariantes del núcleo **financiero** como código: borrado lógico (`prohibir_delete_fisico`), pagos de deuda (`deuda_pago_validar`), recálculo de saldos (`recalcular_saldo_deuda`) y respaldo único de un movimiento (`movimiento_respaldo_deuda_guard`), más las tablas mínimas de deuda |
| 05 | [`05-vistas-de-lectura.sql`](05-vistas-de-lectura.sql) | `v_saldos_por_moneda`, `v_patrimonio_usd`, `v_gasto_mensual_usd`, `v_pendientes_completables`, `v_requiere_revision`, `v_deuda_resumen` |
| 06 | [`06-roles-y-permisos.sql`](06-roles-y-permisos.sql) | Rol `praxia_finanzas_rw` **sin `DELETE`**, roles de sólo lectura, GRANTs por esquema y privilegios por defecto |
| 07 | [`07-nucleo-fiscal.sql`](07-nucleo-fiscal.sql) | El núcleo fiscal v4.0: `fiscal_perfiles` con vigencia temporal y simultánea + `fiscal_perfiles_vigentes()`, `comprobantes` con su índice único **parcial**, `comprobante_iva` por alícuota, el puente N:N `comprobante_movimientos`, las columnas fiscales de `movimientos`, `fiscal_reglas` con `es_ficticia`, `fiscal_obligaciones` (8 estados), `fiscal_cierres` (6 estados), `fiscal_auditoria` append-only, `fiscal_borradores`, los triggers de período y las cuatro vistas fiscales |
| 08 | [`08-cierre-y-estado-derivado.sql`](08-cierre-y-estado-derivado.sql) | Las invariantes del cierre v4.7: `movimiento_estado_fiscal_derivado()` —y por qué no toca `observado`, `incluido_en_cierre` ni `presentado`—, `cierre_transicion_valida()` con el grafo de seis estados y su `HINT`, el CHECK `chk_cierre_nace_abierto` y una versión abreviada de `cierre_chequeos(periodo, actor)` con 6 de las 13 ramas reales |
| 09 | [`09-propuestas-fiscales.sql`](09-propuestas-fiscales.sql) | El modelo de propuestas v4.8: `fiscal_propuestas` con doble huella, los tres constraints de tabla, el índice único **parcial** sobre `huella WHERE estado_aprobacion = 'pendiente'`, los tres triggers (nace pendiente, contenido inmutable, transición válida) y un bloque de ejemplos que demuestra los guards rechazando |

**Hay dependencias entre archivos.** Ejecutarlos de 01 a 09. El 05 usa `praxia.normalizar` del 01 para detectar duplicados; el 04 necesita las tablas del 03; el 06 necesita ambos esquemas creados; el 07 alinea `movimientos` con el diseño real de v4.0; el 08 necesita `fiscal_cierres` y las vistas del 07; el 09 sólo necesita el esquema y reutiliza `prohibir_delete_fisico()` del 04.

**Una tabla, una invariante, un archivo que la crea.** Ningún archivo destruye lo que hizo otro. El reparto de los guards es el siguiente:

| Invariante | Dueño |
|---|---|
| Borrado lógico, pagos de deuda, saldos derivados, respaldo único | 04 |
| Auditoría fiscal append-only, período derivado de la fecha | 07 |
| `estado_fiscal` derivado, transiciones del cierre | 08 |
| Propuesta nace pendiente, contenido inmutable, transición válida | 09 |

**Los nueve son idempotentes.** Se pueden volver a aplicar sobre la misma base sin error: todo es `CREATE ... IF NOT EXISTS`, `CREATE OR REPLACE` o `DROP ... IF EXISTS` previo. La demostración de guards del 09 se saltea sola si la tabla ya tiene filas.

---

## Cómo levantar un laboratorio

Sobre un PostgreSQL 16 limpio:

```bash
createdb praxia_lab

for f in 01-esquema-praxia-memoria.sql \
         02-consulta-memoria-fulltext.sql \
         03-esquema-finanzas-nucleo.sql \
         04-invariantes-y-triggers.sql \
         05-vistas-de-lectura.sql \
         06-roles-y-permisos.sql \
         07-nucleo-fiscal.sql \
         08-cierre-y-estado-derivado.sql \
         09-propuestas-fiscales.sql
do
    psql -d praxia_lab -v ON_ERROR_STOP=1 -f "$f" || break
done
```

El `ON_ERROR_STOP=1` no es decorativo: es el mismo criterio con el que se aplican las migraciones en producción. Una migración que sigue después de un error deja la base en un estado que nadie puede describir.

El archivo 06 necesita permisos de superusuario o `CREATEROLE`. Los demás corren con el dueño de la base.

---

## Las seis ideas que vale la pena robarse

### 1. Una sola definición de "forma normalizada"

`praxia.normalizar()` se usa en tres lugares: la columna generada `fact_norm`, la búsqueda full-text y la huella de deduplicación de errores. Si la consulta normalizara distinto que el dato guardado, el índice no serviría de nada.

Está declarada `IMMUTABLE` usando la forma de dos argumentos de `unaccent()`, que es la única inmutable. Es el patrón documentado para poder usarla en columnas generadas e índices.

### 2. Deduplicar por huella, no por mensaje

`praxia.upsert_agent_error` enmascara los números antes de calcular la huella: `timeout after 30012 ms` y `timeout after 29876 ms` son el mismo error. Sin eso, una deduplicación no dedupica nada.

En la misma llamada atómica reserva la alerta. Dos ejecuciones simultáneas no mandan dos avisos.

### 3. `CROSS JOIN LATERAL` contra la función de cotización

Todas las vistas que convierten moneda usan `CROSS JOIN LATERAL fx_vigente(...)`. Si no hay cotización, **la fila desaparece**. Un `LEFT JOIN` habría dado `NULL`, y un `coalesce(..., 0)` aguas abajo habría convertido "no sé" en "cero".

Es la traducción literal de la regla del contrato: *"Ninguna cotización se inventa. Ausencia de dato es ausencia de fila, nunca un cero."*

Y por eso `fx_vigente()` devuelve `TABLE`, no `numeric`: una función que devuelve un número invita a que alguien lo defaultee.

### 4. Derivar en vez de sincronizar, y saber dónde parar

`estado_fiscal` no se escribe: se deriva de `ambito` + `deducible` en un trigger. Antes de la migración v4.7 eran tres campos independientes, y bastaba corregir uno para tener un movimiento que decía dos cosas distintas.

La segunda mitad de la idea es la interesante: el trigger sincroniza **sólo** el par `sin_clasificar` / `clasificado`. No toca `observado`, `incluido_en_cierre` ni `presentado`, porque esos tres son decisiones de un proceso posterior y no consecuencias del encuadre. Un movimiento ya presentado no vuelve atrás porque alguien le corrija un campo.

Si un valor se puede calcular, no se guarda como decisión independiente. Y si es una decisión, ningún derivador lo pisa.

### 5. El índice único parcial como forma de decir "sólo cuando tiene sentido"

Aparece tres veces en la serie, y siempre resuelve el mismo tipo de problema: una regla que es cierta en la mayoría de los casos y falsa en los bordes.

| Índice | Aplica cuando | Qué pasaría sin el `WHERE` |
|---|---|---|
| `idx_comprobante_unico` | hay punto de venta, número y CUIT emisor | habría que inventarle un número a un ticket de estacionamiento para poder cargarlo |
| `idx_obligacion_unica` | `estado <> 'anulada'` | anular y volver a cargar una obligación sería imposible sin borrar la anulada |
| `uq_propuesta_huella_pendiente` | `estado_aprobacion = 'pendiente'` | o se puede repreguntar sin límite, o no se puede reconsiderar nunca |

La cláusula `WHERE` es donde vive el criterio. Un índice único total es una afirmación más fuerte de lo que casi ningún dominio real soporta.

### 6. Un `NULL` que significa "todavía no lo sé"

`movimientos.ambito` y `movimientos.deducible` son nullable a propósito y sin `DEFAULT`. "Todavía no lo clasifiqué" tiene que ser distinguible de "lo clasifiqué como no deducible": la primera es trabajo pendiente, la segunda es una decisión tomada.

Un `DEFAULT` que rellene el hueco no simplifica el modelo, lo miente: ningún movimiento aparecería nunca como pendiente de clasificar y el cierre se cerraría con todo sin mirar. Es la misma regla que hace que `fx_vigente()` devuelva cero filas en vez de cero pesos.

---

## Lo que falta a propósito

- El cifrado real de `datos_sensibles`, del CUIT, y el mecanismo del `placeholder_token` `⟦S1⟧`.
- `documentos` y su columna `ruta` («ruta interna, NUNCA una URL pública»).
- `contribuyentes` con FK real y las funciones de v4.9 (`regimen_vigente()`, `perfil_fiscal_sin_solapamiento()`, `imputacion_mismo_contribuyente()`).
- `catalogo_obligaciones`, `dias_no_habiles`, `terminacion_cuit` y `vencimiento_habil()` (v4.11 y v4.12).
- `fiscal_exportaciones` (v4.2), plantillas recurrentes y planes de pago (v4.6 y v4.10).
- Siete de las trece ramas de `cierre_chequeos()`.
- `valuaciones`, `cuotas_movimientos`, `proyectos`, `datos_sensibles`.
- Las 39+ migraciones reales, sus checksums y su orden exacto.

El esquema de producción está en v4.13 y tiene 39 tablas. Acá hay 21 tablas y 10 vistas. Alcanza para entender cómo se sostiene un cierre y no alcanza para reproducir el sistema, que es exactamente el objetivo.

---

## Verificación

Los nueve archivos se ejecutaron de corrido sobre un PostgreSQL 16 limpio antes de publicarse, con `ON_ERROR_STOP=1`, y **dos veces seguidas sobre la misma base** para confirmar que son idempotentes. Después se probó a mano que los guards fallen cuando tienen que fallar.

| Caso probado | Resultado esperado |
|---|---|
| Pago en moneda distinta de la deuda | rechazado |
| Pago que excede el saldo | rechazado |
| `DELETE` físico sobre una tabla con valor probatorio | rechazado |
| `UPDATE` sobre `fiscal_auditoria` | rechazado, «la auditoría fiscal es append-only» |
| Cierre `abierto → presentado` | rechazado, con el `HINT` del recorrido correcto |
| Cierre `en_revision → aprobado` (saltea un paso) | rechazado |
| Aprobar un cierre sin `aprobado_por` | rechazado |
| Reabrir un cierre sin motivo | rechazado |
| `INSERT` de un cierre nacido `presentado` sin fecha | rechazado por `chk_cierre_nace_abierto` |
| Propuesta insertada directamente en `aprobada` | rechazado, «aprobar es un acto humano posterior» |
| Editar el criterio de una propuesta ya decidida | rechazado, contenido inmutable |
| Pasar una propuesta de `aprobada` a `pendiente` | rechazado, estado terminal |
| Segunda propuesta **pendiente** con la misma huella | rechazado por el índice único parcial |
| Misma alícuota dos veces en un comprobante | rechazado |
| Mismo comprobante (tipo, PV, número, CUIT) dos veces | rechazado |
| Dos tickets sin punto de venta ni número | **aceptado** — el índice parcial no aplica |
| Obligación duplicada viva para el mismo período | rechazado |
| Movimiento `presentado` al que se le borra el `ambito` | sigue `presentado`, el trigger no lo pisa |
| `praxia_finanzas_rw` con `INSERT` sobre `fiscal_reglas` | `false` |
| `praxia_finanzas_rw` con `UPDATE` sobre `fiscal_auditoria` | `false` (con `INSERT` en `true`) |

`Verificado` — dos ejecuciones limpias de los nueve archivos sobre la misma base y guards rechazando los veinte casos previstos, 2026-08-06.

Al cierre de la verificación, el esquema `praxia_finanzas` queda con **21 tablas, 10 vistas, 15 funciones, 20 triggers y 60 índices**; el esquema `praxia`, con 5 tablas.

---

## Documentos relacionados

- [Cuándo uso SQL](../../docs/02-desglose-tecnico/01-cuando-uso-sql.md)
- [PraxIA Memory Core](../../systems/praxia-memory-core/)
- [PraxIA Finanzas](../../systems/praxia-finanzas/)
- [ADR-007 — Sin borrado físico](../../docs/04-decisiones/adr-007-sin-borrado-fisico.md)

> Última verificación: 2026-08-06
