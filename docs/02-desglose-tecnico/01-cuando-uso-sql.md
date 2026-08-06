# Cuándo uso SQL

Cuándo una regla de negocio va escrita en la base de datos y no en el prompt del agente, en el workflow o en la API.

## Criterio

Un sistema agéntico tiene, como mínimo, cuatro caminos por los que puede entrar una escritura: el agente conversacional, un workflow automático, una interfaz web y un import de archivo. Con el tiempo aparece un quinto: alguien conectado con `psql` arreglando algo a mano un domingo.

Cada regla que escribís en la aplicación la tenés que escribir **una vez por camino**. Cada regla que escribís en la base la escribís una sola vez y no se puede saltear.

De ahí sale el criterio central:

> Si una invariante no puede romperse nunca, va en la base. Si puede tolerarse rota por un rato y corregirse después, puede vivir más arriba.

### La escalera de garantías

De más fuerte a más débil. Bajás un escalón sólo cuando el de arriba no alcanza.

| Nivel | Mecanismo | Garantiza | Costo |
|---|---|---|---|
| 1 | Tipo de dato + `NOT NULL` + `CHECK` | Forma del dato | Casi nulo |
| 2 | `FOREIGN KEY`, `UNIQUE`, exclusion constraints | Coherencia entre filas | Bajo; índices |
| 3 | Trigger | Reglas que dependen de otras filas o del estado anterior | Medio; hay que testearlo |
| 4 | Función + permisos de rol | Lógica compleja con una sola puerta de entrada | Medio-alto |
| 5 | Validación en la API | Mensajes de error útiles, reglas que cambian seguido | Alto; hay que repetirla por camino |
| 6 | Validación en el workflow / prompt | Experiencia de usuario, aclaraciones, repreguntas | Muy alto; no es garantía |

El error típico en sistemas con LLM es empezar por el nivel 6 porque es el más rápido de escribir. Funciona hasta que el modelo cambia de versión, o hasta que un import de CSV entra por otro lado.

### Cuándo NO conviene bajar a la base

Ser honesto con el trade-off: la lógica en SQL es más difícil de leer para quien no escribe SQL, más difícil de versionar si no tenés migraciones ordenadas, y los mensajes de error que produce un trigger son horribles para mostrarle a un usuario final.

| Señal | Conviene |
|---|---|
| La regla cambia varias veces por mes | Aplicación |
| El usuario necesita un mensaje explicativo y una sugerencia | Aplicación (con la constraint igual abajo, como red) |
| La regla depende de un servicio externo | Aplicación |
| Romper la regla corrompe datos de forma irrecuperable | **Base** |
| Hay más de un cliente escribiendo | **Base** |
| La regla es "esto nunca se borra" o "esto nunca cambia" | **Base** |

## En este sistema

PraxIA Finanzas usa PostgreSQL 16 con el esquema `praxia_finanzas` dentro de la misma base que ya usaba la memoria (`praxia_memory`). La decisión fundacional del 2026-07-26 fue explícita:

> *"PraxIA Contable debe construirse como un esquema adicional dentro del PostgreSQL que ya corre en el VPS. Reutiliza ~80% de infraestructura existente. Construir una app aparte sería tirar a la basura el Memory Core."*

El esquema está en **v4.13** con **40+ migraciones** versionadas y **39 tablas** en producción al corte.

### Contratos de datos: la tabla como interfaz

`ingesta_raw` es el ejemplo más claro. Toda alta —Telegram, dashboard, PDF, CSV, email o un agente— produce el mismo contrato y termina en la misma tabla, con el texto original, el canal, el actor y una `idempotency_key`.

```sql
-- SINTÉTICO: refleja la forma, no el DDL real
create table praxia_finanzas.ingesta_raw (
  id              bigserial primary key,
  canal           text not null
                  check (canal in ('telegram','dashboard','pdf','csv','email','agente')),
  actor           text not null,
  idempotency_key text not null,
  payload_cifrado bytea not null,
  recibido_en     timestamptz not null default now(),
  constraint ingesta_raw_idem_uq unique (canal, idempotency_key)
);
```

El `unique (canal, idempotency_key)` es lo que hace que reenviar el mismo ticket de Telegram dos veces no genere dos gastos. Esa garantía no depende de que el workflow acuerde de chequear: depende de la base.

### Triggers como garantía

Tres casos reales, cada uno resolviendo una clase distinta de problema.

**`prohibir_delete_fisico` — el dato no se borra.**

El principio del sistema es que nunca se borra físicamente: hay baja lógica y auditoría. No existe ningún endpoint `DELETE` en la API, y el rol `praxia_finanzas_rw` no tiene el permiso. El trigger es la tercera red, por si alguien se conecta con otro rol.

```sql
-- SINTÉTICO
create or replace function praxia_finanzas.fn_prohibir_delete_fisico()
returns trigger language plpgsql as $$
begin
  raise exception 'DELETE físico prohibido en %. Usar baja lógica (estado=anulado).',
    tg_table_name;
end $$;

create trigger prohibir_delete_fisico
  before delete on praxia_finanzas.movimientos
  for each row execute function praxia_finanzas.fn_prohibir_delete_fisico();
```

Tres capas para la misma regla parece exagerado. No lo es: cada capa cubre un camino distinto. La API cubre al cliente honesto, el rol cubre al script apurado, el trigger cubre al `psql` del domingo.

**`deuda_pago_validar` — coherencia entre entidades relacionadas (v4.5).**

Un pago tiene que estar en la misma moneda que la deuda que cancela. Es una regla que la aplicación podría validar, pero que si se rompe deja saldos mal calculados de forma silenciosa. Va con trigger, junto a `recalcular_saldo_deuda` y `movimiento_respaldo_deuda_guard`.

La regla de negocio que sostiene todo esto es textual del contrato:

> *"Registrar una deuda, una cuota, un vencimiento o un gasto esperado no modifica saldos. El impacto financiero ocurre únicamente al registrar o vincular un pago real, y un pago se contabiliza exactamente una vez."*

"Exactamente una vez" es una invariante. Por eso está en la base.

**`propuesta_contenido_inmutable` — el agente no reescribe lo que ya propuso (v4.8).**

`fiscal_propuestas` es la tabla donde el motor fiscal deja lo que sugiere. Tiene tres triggers: `propuesta_nace_pendiente`, `propuesta_contenido_inmutable` y `propuesta_transicion_valida`. Más los campos `huella` y `huella_evidencia`, que sirven para no insistir con lo mismo y para no aprobar algo cuya evidencia caducó.

El motivo es una regla de diseño que vale la pena citar entera:

> *"Un agente que puede repreguntar sin límite termina consiguiendo el 'sí' por cansancio."*

Si el contenido de una propuesta fuera mutable, el agente podría cambiarla después de que la mirás y antes de que la aprobás. La inmutabilidad no es una optimización: es el mecanismo que hace que la aprobación humana signifique algo.

Los tres triggers cubren tres agujeros distintos del mismo circuito, y ninguno es reemplazable por los otros dos:

| Trigger | Momento | Invariante |
|---|---|---|
| `propuesta_nace_pendiente` | `BEFORE INSERT` | Ninguna propuesta puede insertarse ya aprobada. *"Aprobar es un acto humano posterior, no un valor inicial"* |
| `propuesta_contenido_inmutable` | `BEFORE UPDATE` | Una vez que la propuesta deja de estar pendiente, catorce columnas quedan congeladas. Lo aprobado es exactamente lo que se mostró |
| `propuesta_transicion_valida` | `BEFORE UPDATE` | `pendiente` puede ir a `aprobada`, `rechazada` o `caducada`; los tres son terminales. Cambiar de idea se hace con una propuesta nueva que apunta a la anterior, no reescribiendo la vieja |


### Funciones: lógica determinística con una sola puerta

**`fx_vigente()`** resuelve el tipo de cambio de una fecha. La regla asociada, textual:

> *"Ninguna cotización se inventa. Ausencia de dato es ausencia de fila, nunca un cero."*

Una función que devuelve cero filas cuando no hay cotización obliga a que quien la llama maneje el caso. Una que devuelve `0` produce reportes silenciosamente mentirosos. Es la misma decisión que en el buscador web: `no_reliable_source` es un estado, no un string vacío.

**`cierre_chequeos()`** (v4.0) corre la batería de validaciones antes de cerrar un período fiscal. Está en SQL y no en la API porque los chequeos son consultas agregadas sobre varias tablas: escribirlos en JS sería traer todo a memoria para hacer lo que la base hace mejor.

**`movimiento_estado_fiscal_derivado`** y **`cierre_transicion_valida`** (v4.7) resuelven un bug de clase entera. Antes, `estado_fiscal` era un campo que se seteaba; podía divergir de `ambito` + `deducible`. Después de v4.7 es derivado: no puede divergir porque no se setea.

```sql
-- SINTÉTICO: el patrón, no la implementación
-- Antes: tres campos independientes que podían contradecirse.
-- Después: uno derivado de los otros dos.
create or replace function praxia_finanzas.movimiento_estado_fiscal_derivado(
  p_ambito text, p_deducible boolean
) returns text language sql immutable as $$
  select case
    when p_ambito = 'personal'        then 'no_computable'
    when p_deducible is null          then 'pendiente_clasificacion'
    when p_deducible                  then 'computable'
    else                                   'no_deducible'
  end;
$$;
```

Convertir un campo seteable en un campo derivado es la forma más barata de eliminar una familia entera de inconsistencias. Vale la pena buscar activamente estos casos.

Este en particular se pagó en incidente: el 2026-08-05 se clasificaron 22 movimientos que quedaron con `ambito` y `deducible` correctos y `estado_fiscal='sin_clasificar'`. El agente fiscal los veía clasificados y el cierre los seguía marcando como bloqueantes. La regla ya estaba escrita en el código y no alcanzó, porque el código no es el único camino: *"el día que alguien escriba `ambito` por otra vía —una importación, un flujo de n8n, un `psql` suelto— vuelven a divergir. Lo que hace falta es que no puedan."* La migración además corrige las filas ya incoherentes y verifica en un bloque `DO $$` que no quede ninguna, con `RAISE EXCEPTION` si las hay. Detalle completo en el [post-mortem del `estado_fiscal` divergente](../06-runbooks/postmortem-estado-fiscal-divergente.md).

### Vistas como API de lectura

Hay una vista por cada pregunta que el sistema sabe responder. `v_saldos_por_moneda`, `v_patrimonio_usd`, `v_gasto_mensual_usd`, `v_flujo_perfil`, `v_flujo_proyecto`, `v_pendientes_completables`, `v_requiere_revision`, `v_transferencias_invalidas`, `v_eventos_a_movimientos`, y en la capa fiscal `v_comprobantes`, `v_fiscal_periodo`, `v_fiscal_iva_periodo`, `v_movimientos_fiscal`, más `v_deudas`, `v_deuda_resumen`, `v_deuda_pagos`, `v_movimientos_elegibles_pago`.

Tres cosas que esto compra:

1. **El join vive en un solo lugar.** El endpoint HTTP, la herramienta MCP y el dashboard leen la misma vista. Si la definición de "saldo" cambia, cambia una vez.
2. **La capa fiscal de solo lectura es literalmente eso.** Las 9 operaciones de `/api/fiscal-lectura/*` leen vistas. No hay forma de que una consulta fiscal escriba.
3. **Las vistas negativas son alertas.** `v_transferencias_invalidas` y `v_requiere_revision` no responden preguntas: exponen inconsistencias. Una vista que idealmente devuelve cero filas es un test que corre en producción todo el tiempo.

### Búsqueda full-text en español

La consulta de memoria (`Consultar Memoria`, en PraxIA Memory Core) corre así:

```sql
-- SINTÉTICO
begin transaction read only;

with q as (
  select
    unaccent(lower($1)) as texto_norm,
    plainto_tsquery('spanish', unaccent(lower($1))) as tsq
)
select f.id, f.fact, f.category, f.confidence, 'estricto' as tier
from praxia.memory_facts f, q
where f.active
  and to_tsvector('spanish', unaccent(f.fact)) @@ q.tsq
union all
select f.id, f.fact, f.category, f.confidence, 'laxo'
from praxia.memory_facts f, q
where f.active
  and unaccent(lower(f.fact)) like '%' || q.texto_norm || '%'
order by tier, confidence desc
limit 20;

commit;
```

Cuatro decisiones acá, cada una con motivo:

- **`to_tsvector('spanish')`** aplica stemming y stop-words del castellano. "Reuniones" matchea "reunión" sin que nadie lo programe.
- **`unaccent` + `lower`** normalizan: quien escribe desde Telegram no pone tildes.
- **Dos tiers, estricto y laxo.** El estricto es full-text; el laxo es substring. Se devuelven ambos etiquetados para que el agente sepa qué tan bueno es cada match.
- **`BEGIN TRANSACTION READ ONLY`.** Es la parte que más me importa. Es una declaración ejecutable: esta operación **no puede** escribir, aunque el SQL que genere el agente diga otra cosa. Es la misma idea que los scopes del MCP, aplicada a nivel de transacción.

### Migraciones numeradas y `schema_migrations`

Cada cambio de esquema es un archivo numerado que se aplica en orden, y la tabla `schema_migrations` registra qué se aplicó. El recorrido está en la cronología: DDL v3.1 → v3.2..v3.6 → v4.0 → v4.2 → v4.3 → v4.4 → v4.5 → v4.6 → v4.7 → v4.8 → v4.9..v4.13.

Cómo se aplican, en producción:

```bash
# SINTÉTICO
psql -v ON_ERROR_STOP=1 -1 -f migrations/048_fiscal_propuestas.sql
```

`ON_ERROR_STOP=1` más `-1` (una sola transacción) significa que la migración entra completa o no entra. Sin esto, `psql` sigue ejecutando después de un error y te deja el esquema a mitad de camino, que es el peor estado posible.

Este mecanismo no evita todos los problemas. El **2026-08-05** se descubrió que producción estaba **tres migraciones atrás desde el 31/07**, porque —textual— *"nadie había mirado el servidor, solo el repositorio"*. Las migraciones estaban bien escritas y bien versionadas; lo que faltaba era la verificación de que el runtime coincidiera con el repo. Está en [08 — Infra y despliegue](08-infra-y-despliegue.md) y en el post-mortem.

### Roles sin DELETE

`praxia_finanzas_rw` es el rol que usa la API. Tiene `SELECT`, `INSERT`, `UPDATE`. No tiene `DELETE`.

```sql
-- SINTÉTICO
grant usage on schema praxia_finanzas to praxia_finanzas_rw;
grant select, insert, update on all tables in schema praxia_finanzas
  to praxia_finanzas_rw;
-- DELETE: deliberadamente ausente.
revoke delete on all tables in schema praxia_finanzas from praxia_finanzas_rw;
```

El razonamiento: si la aplicación no necesita borrar, el rol de la aplicación no debería poder borrar. Una vulnerabilidad de inyección en un endpoint no alcanza para destruir el historial. Es el principio de menor privilegio aplicado a la capa donde efectivamente se puede hacer daño.

### Lo que quedó afuera a propósito

- **No hay Row Level Security todavía.** La separación por usuario hoy es por `perfiles` y por identidad de bot (`chat_id`), no por RLS. Cuando entren clientes con datos separados, RLS es la respuesta correcta. Hoy sería complejidad sin usuario. `[PENDIENTE DE VERIFICAR: fecha objetivo]`
- **No hay particionado.** El volumen no lo justifica.
- **No hay réplicas de lectura.** Un solo PostgreSQL, en loopback.

## Regla

Si la invariante no puede romperse nunca, va en la base. La aplicación produce buenos mensajes de error; la base produce garantías, y son cosas distintas.

> Última verificación: 2026-08-06
