# Artefactos SQL

Seis archivos que reconstruyen el diseño de datos de PraxIA Ops: la memoria del agente, el núcleo financiero, las invariantes escritas como triggers, las vistas de lectura y los permisos.

> **Reconstrucción didáctica sintética. No son dumps de producción.**
> Cada archivo fue escrito de nuevo a partir del diseño verificado. Los nombres de tablas, columnas, estados, funciones y guards son fieles al sistema real; los tipos exactos, los datos de ejemplo y buena parte de los constraints son una reconstrucción razonable. No hay datos, credenciales ni identificadores reales.

---

## Los archivos, en orden

| # | Archivo | Qué contiene |
|---|---|---|
| 01 | [`01-esquema-praxia-memoria.sql`](01-esquema-praxia-memoria.sql) | Esquema `praxia`: `memory_facts`, `memory_events`, `projects`, `tasks`, `agent_errors`, la función `praxia.normalizar` y `praxia.upsert_agent_error` con deduplicación y reserva de alerta |
| 02 | [`02-consulta-memoria-fulltext.sql`](02-consulta-memoria-fulltext.sql) | La consulta de memoria: transacción `READ ONLY`, `unaccent`, `to_tsvector('spanish')`, tier estricto y tier laxo |
| 03 | [`03-esquema-finanzas-nucleo.sql`](03-esquema-finanzas-nucleo.sql) | Núcleo de `praxia_finanzas`: `perfiles`, `cuentas`, `categorias`, `fx_rates` + `fx_vigente()`, `ingesta_raw`, `movimientos`, `transferencias`, `movimientos_auditoria`, `schema_migrations` |
| 04 | [`04-invariantes-y-triggers.sql`](04-invariantes-y-triggers.sql) | Los guards como código: `prohibir_delete_fisico`, `movimiento_estado_fiscal_derivado`, `deuda_pago_validar`, `recalcular_saldo_deuda`, `movimiento_respaldo_deuda_guard`, `propuesta_nace_pendiente`, `propuesta_contenido_inmutable`, `propuesta_transicion_valida` |
| 05 | [`05-vistas-de-lectura.sql`](05-vistas-de-lectura.sql) | `v_saldos_por_moneda`, `v_patrimonio_usd`, `v_gasto_mensual_usd`, `v_pendientes_completables`, `v_requiere_revision`, `v_deuda_resumen` |
| 06 | [`06-roles-y-permisos.sql`](06-roles-y-permisos.sql) | Rol `praxia_finanzas_rw` **sin `DELETE`**, roles de sólo lectura, GRANTs por esquema y privilegios por defecto |

**Hay dependencias entre archivos.** Ejecutarlos de 01 a 06. El 05 usa `praxia.normalizar` del 01 para detectar duplicados; el 04 necesita las tablas del 03; el 06 necesita ambos esquemas creados.

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
         06-roles-y-permisos.sql
do
    psql -d praxia_lab -v ON_ERROR_STOP=1 -f "$f" || break
done
```

El `ON_ERROR_STOP=1` no es decorativo: es el mismo criterio con el que se aplican las migraciones en producción. Una migración que sigue después de un error deja la base en un estado que nadie puede describir.

El archivo 06 necesita permisos de superusuario o `CREATEROLE`. Los demás corren con el dueño de la base.

---

## Las cuatro ideas que vale la pena robarse

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

### 4. Derivar en vez de sincronizar

`estado_fiscal` no se escribe: se calcula desde `ambito` + `deducible` en un trigger. Antes de la migración v4.7 eran tres campos independientes, y bastaba corregir uno para tener un movimiento que decía dos cosas distintas.

Si un valor se puede calcular, no se guarda como decisión independiente.

---

## Lo que falta a propósito

- El cifrado real de `datos_sensibles` y el mecanismo del `placeholder_token` `⟦S1⟧`.
- Todo el núcleo fiscal v4.0: `comprobantes`, `comprobante_iva`, `fiscal_cierres`, `fiscal_obligaciones`, `fiscal_auditoria`.
- Documentos, plantillas recurrentes, planes de pago y obligaciones (v3.6 y v4.6).
- `valuaciones`, `cuotas_movimientos`, `proyectos`, `datos_sensibles`.
- Las 33+ migraciones reales, sus checksums y su orden exacto.

El esquema de producción tiene 35 tablas. Acá hay doce. Alcanza para entender el modelo y no alcanza para reproducirlo, que es exactamente el objetivo.

---

## Verificación

Los seis archivos se ejecutaron de corrido sobre PostgreSQL 16 antes de publicarse, y se probó que los guards fallen cuando tienen que fallar: pago en moneda distinta, pago que excede el saldo, borrado físico, combinación personal + deducible, propuesta que nace aprobada, edición de contenido de una propuesta, aprobación sin responsable y reapertura de un estado terminal.

`Verificado` — ejecución limpia y guards rechazando los casos previstos, 2026-08-05.

---

## Documentos relacionados

- [Cuándo uso SQL](../../docs/02-desglose-tecnico/01-cuando-uso-sql.md)
- [PraxIA Memory Core](../../systems/praxia-memory-core/)
- [PraxIA Finanzas](../../systems/praxia-finanzas/)
- [ADR-007 — Sin borrado físico](../../docs/04-decisiones/adr-007-sin-borrado-fisico.md)

> Última verificación: 2026-08-05
