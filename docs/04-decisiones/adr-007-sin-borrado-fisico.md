# ADR-007 — Sin borrado físico

En el sistema financiero no se borra nada. No es una convención del equipo: es un trigger en la base, un rol sin permiso y una API que no tiene el verbo.

## Estado

Vigente.

## Fecha

2026-07-27 — DDL v3.1 aplicado al VPS, con el trigger `prohibir_delete_fisico` incluido desde el primer despliegue.

## Contexto

La decisión D-7 del 14 de julio incluía "borrar" entre las cuatro acciones que requieren aprobación humana. Al llegar al diseño del esquema financiero apareció una pregunta mejor: **¿por qué custodiar una capacidad que no hace falta?**

En un sistema financiero personal, un borrado físico casi nunca es lo que se quiere. Lo que se quiere es alguna de estas tres cosas:

| Lo que se pide | Lo que en realidad se necesita |
|---|---|
| "Borrá este gasto, lo cargué mal" | Corregirlo, dejando registro de qué decía antes |
| "Borrá este movimiento, nunca ocurrió" | Anularlo, dejando registro de que se anuló y cuándo |
| "Borrá esto, es un duplicado" | Marcarlo como duplicado y vincularlo al original |

Las tres se resuelven sin destruir información. Y las tres necesitan que la información previa siga existiendo, porque un saldo es una acumulación: si un registro desaparece sin dejar rastro, el saldo cambia y **no hay forma de explicar por qué**.

Hay un segundo motivo, específico de un sistema donde escriben agentes. Un modelo de lenguaje con acceso a un `DELETE` es una superficie de riesgo asimétrica: la probabilidad de que borre algo indebido es baja, y la consecuencia es irreversible. Con la aprobación humana bien puesta el riesgo baja, pero sigue existiendo el escenario de una instrucción ambigua —"limpiá los movimientos de prueba"— interpretada con demasiada iniciativa.

La forma más barata de manejar ese riesgo no es vigilarlo. Es que la capacidad no exista.

## Decisión

**El borrado físico está prohibido en el esquema `praxia_finanzas`, y la prohibición está implementada en cuatro capas independientes.**

### 1. Trigger en la base

El trigger `prohibir_delete_fisico` rechaza el borrado a nivel de motor. Es la capa de la que **nada puede escapar**: ni la API, ni un workflow de n8n, ni una sesión de consola, ni un agente con credenciales.

### 2. Rol sin permiso

El rol `praxia_finanzas_rw` **no tiene permiso `DELETE`**. La operación falla antes de llegar al trigger. Dos controles independientes sobre el mismo riesgo, a propósito: si alguien alguna vez desactiva el trigger para una migración, el permiso sigue faltando.

### 3. Cero endpoints `DELETE`

De los más de 60 endpoints de la API, **ninguno es `DELETE`**. No hay ruta que lo intente. Lo que existe en su lugar:

- `POST /api/movimientos/{id}/anular` — baja lógica.
- `POST /api/deudas/{id}/pagos/{pagoId}/anular` — anulación de un pago vinculado.
- `PATCH /api/movimientos/{id}` — corrección con registro.
- `GET /api/movimientos/{id}/auditoria` — el historial de todo lo anterior.
- `GET /api/duplicados` — los duplicados se listan y se resuelven, no se borran.

### 4. Auditoría inmutable

- `movimientos_auditoria` registra los cambios sobre movimientos.
- `deuda_auditoria` hace lo propio para deudas (v4.4).
- `fiscal_auditoria` es **inmutable** por diseño (v4.0).
- `propuesta_contenido_inmutable` (v4.8) impide que el contenido de una propuesta cambie después de creada.

Una auditoría que se puede editar no es una auditoría. La inmutabilidad es lo que hace que el registro valga algo.

### El caso legítimo, resuelto por otro lado

¿Y si algo entró mal de verdad y no debería estar? Se anula. Queda en la base con estado de anulado, no computa en saldos, y el motivo queda registrado. El costo es unas filas que nadie va a mirar. El beneficio es que **el saldo de cualquier fecha pasada se puede reconstruir y explicar**.

## Opciones consideradas

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| **Prohibición en cuatro capas: trigger, rol, API y auditoría** | Ninguna ruta de borrado, ni siquiera con acceso directo a la base; historia completa; saldos reconstruibles | Filas que crecen para siempre; borrar algo legítimamente requiere intervención deliberada fuera del camino normal | **Elegida** |
| Baja lógica sólo en la aplicación | Simple; el `DELETE` queda para emergencias | Un `DELETE` accidental desde cualquier otro camino rompe la invariante. **Es una convención, no una garantía** | Rechazada |
| Borrado con aprobación humana | Coherente con D-7 | Custodiar una capacidad que casi nunca se necesita, en vez de eliminarla. Más superficie por menos valor | Rechazada |
| Borrado diferido: marcar y purgar a los N días | Controla el crecimiento | La purga es un borrado físico con retardo. El mismo problema, más tarde y automatizado | Rechazada |
| Borrado sólo para el rol administrador | Válvula de escape para el operador | Es exactamente el rol que usaría un agente con credenciales completas | Rechazada |

## Consecuencias

### Positivas

- **Ninguna ruta de borrado existe.** Ni por la API, ni por un workflow, ni por una sesión directa con el rol de la aplicación.
- **Cualquier saldo histórico se puede reconstruir y explicar.** Es la propiedad que hace utilizable un sistema financiero.
- **La invariante es testeable de verdad.** El harness con PGlite corre el DDL real: la prueba intenta un `DELETE` y verifica que la base lo rechace. No es un mock de la regla, es la regla.
- **Los agentes operan sin riesgo de destrucción.** El peor caso de una escritura equivocada es un registro de más marcado como anulado.
- **Simplifica el modelo de permisos.** No hay que decidir quién puede borrar qué, porque nadie puede.

### Negativas

- **Las tablas crecen monótonamente.** Con el volumen actual es irrelevante; a años vista requiere una política de retención. Estado: `Pendiente de verificar`.
- **No hay procedimiento para un borrado legítimo.** Si algún día hay que eliminar un dato por una obligación real —un pedido formal de supresión, por ejemplo— **no está definido cómo se hace**. Es la deuda más concreta de este ADR.
- Un duplicado que se registró y se anuló sigue apareciendo en las consultas de auditoría. Es correcto y a la vez es ruido.
- La corrección requiere más pasos que borrar y volver a cargar. Se paga en cada corrección.

### Operativas

- Las migraciones que necesiten reorganizar datos tienen que trabajar dentro de la restricción. En la práctica se resuelve con columnas nuevas y estados, no moviendo filas.
- El crecimiento del almacenamiento debería monitorearse. Hoy no está instrumentado. Estado: `Pendiente de verificar`.
- Los backups incluyen todo el historial, lo cual es bueno para la recuperación y hace que crezcan igual que las tablas.
- Las vistas de lectura filtran lo anulado; el dato sigue estando abajo. Quien consulte tablas directamente tiene que saberlo.

### De seguridad

- **Elimina una clase entera de ataque y de error.** Un atacante con las credenciales de la aplicación puede leer y escribir, **no puede destruir**. Eso convierte un incidente potencialmente catastrófico en uno recuperable y visible.
- **Es la defensa contra el borrado como encubrimiento.** Quien quiera ocultar un movimiento tiene que anularlo, y la anulación queda registrada con su motivo.
- La inmutabilidad de `fiscal_auditoria` y de `propuesta_contenido_inmutable` protege contra la manipulación del propio registro: no alcanza con hacer algo y después arreglar la historia.
- **Defensa en profundidad real:** trigger, rol, API y auditoría son cuatro controles independientes. Vencer uno no alcanza.
- Contrapartida honesta que hay que decir: **conservar todo también significa conservar datos personales para siempre**. Con datos financieros propios es una decisión de una sola persona. Con datos de terceros, esta política entraría en tensión con cualquier obligación de supresión, y esa tensión **no está resuelta**.

## Evidencia

| Afirmación | Estado |
|---|---|
| Trigger `prohibir_delete_fisico` en el esquema `praxia_finanzas` | `Verificado` |
| Rol `praxia_finanzas_rw` sin permiso `DELETE` | `Verificado` |
| Cero endpoints `DELETE` en la API | `Verificado` |
| Endpoints de anulación para movimientos y para pagos de deuda | `Verificado` |
| Tabla `movimientos_auditoria` en el DDL v3.1 | `Verificado` |
| `fiscal_auditoria` declarada inmutable en v4.0 | `Verificado` |
| `deuda_auditoria` en v4.4 | `Verificado` |
| Trigger `propuesta_contenido_inmutable` en v4.8 | `Verificado` |
| Prueba de la invariante en el harness con PGlite | `Verificado` |
| Procedimiento para un borrado legítimo por obligación externa | `Pendiente de verificar` — no existe |
| Política de retención a largo plazo | `Pendiente de verificar` — no existe |
| Monitoreo del crecimiento de almacenamiento | `Pendiente de verificar` — no instrumentado |

## Disparador de revisión

Revisar cuando:

- **Aparezca una obligación real de supresión de datos.** Es el disparador más probable y hoy no hay respuesta. Con datos de un cliente o de un tercero, deja de ser una decisión de diseño y pasa a ser una obligación.
- **El crecimiento de las tablas afecte el rendimiento o el costo.** La respuesta correcta ahí no es borrar: es archivar en frío conservando la trazabilidad.
- **Se necesite un procedimiento de borrado excepcional.** Si alguna vez hace falta, debe escribirse como un procedimiento con aprobación, registro y verificación posterior — nunca como un permiso permanente.
- **Se extienda la política a otros esquemas.** Hoy la prohibición es del esquema financiero. El esquema `praxia` de memoria **sí permite corregir y desactivar hechos**, que es otro modelo. Unificar los dos criterios, o justificar por qué difieren, es trabajo pendiente.

> Última verificación: 2026-08-05
