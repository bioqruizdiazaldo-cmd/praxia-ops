# Seguridad y permisos del Agente Fiscal

La separación entre proponer y aprobar es el eje del subsistema, y no se sostiene con una instrucción en el prompt: se sostiene con tres credenciales distintas, un 403 comprobado por igualdad exacta antes que cualquier otra regla, y un script de despliegue que aborta si ese 403 no aparece. Este documento describe qué puede hacer cada token, cómo se verifica en el entorno real, y también dónde el sistema todavía depende de una guarda de prompt en lugar de una de código.

---

## Los tres tokens

Definidos y validados en `api/auth.mjs`.

| Token | Variable de entorno | Alcance |
|---|---|---|
| **General** | `API_TOKEN` / `FINANZAS_API_TOKEN` | Todo. Es el del titular |
| **Lectura** | `PRAXIA_FINANZAS_API_READ_TOKEN` | Solo GET a `/api/movimientos`, `/api/resumen` y `/api/saldos`. Es el que usa Oppenheimer |
| **Fiscal** | `PRAXIA_FINANZAS_API_FISCAL_TOKEN` | La capa fiscal de lectura y la creación de propuestas |

`validateApiTokens()` corre al arranque y exige tres cosas:

- Mínimo **24 caracteres** cada uno.
- Los tres **mutuamente distintos**.
- La comparación se hace con `timingSafeEqual` sobre digests SHA-256, no con `===`.

Exigir que sean distintos parece trivial hasta que se piensa en cómo se despliega esto: copiar el mismo valor en las tres variables es el error de configuración más natural del mundo, y el resultado sería que el token fiscal tiene permisos de administrador sin que nada lo indique. El proceso no arranca.

---

## Qué puede el token fiscal

### Permitido, sin permiso humano adicional

| Ruta | Qué hace |
|---|---|
| `GET /api/fiscal-lectura/*` | Las nueve operaciones de lectura |
| `GET /api/fiscal-propuestas` | Listar propuestas |
| `POST /api/fiscal-propuestas` | **Crear** una propuesta |
| `GET /api/fiscal-diagnostico` | Diagnosticar un período |
| `GET /api/fiscal-diagnostico?registrar=true` | Diagnosticar y crear las propuestas resultantes |

Que el agente pueda **crear** propuestas sin pedir permiso es correcto: crear una propuesta es hacer una pregunta, y una pregunta no tiene efecto. Los frenos contra el abuso de esa facultad no son de permisos sino de diseño de datos — el índice único parcial sobre la huella pendiente y la exigencia de motivo para reconsiderar. Ver [propuestas-y-huellas.md](propuestas-y-huellas.md).

### Prohibido — requiere token general

| Ruta | Respuesta con token fiscal |
|---|---|
| `POST /api/fiscal-propuestas/decidir` | **403 duro** |
| Rutas de escritura financiera: obligaciones, movimientos, ingesta, cierres, y todo lo demás | **403** |

Mensajes:

> *«el Agente Fiscal puede proponer, no aprobar: la decisión requiere el token general»*

> *«token limitado a la capa fiscal (lectura y propuestas)»*

---

## El 403 duro sobre `/decidir`

La regla de `POST /api/fiscal-propuestas/decidir` se comprueba **primero** en la cadena de autorización y **por igualdad exacta** de la ruta, no por prefijo ni por patrón.

El motivo está escrito en el código: *«para que ninguna regla más permisiva de abajo la habilite por accidente»*.

Es una decisión de orden de evaluación, y es la correcta. La lista de permisos del token fiscal contiene `POST /api/fiscal-propuestas`. Cualquier chequeo por prefijo, o cualquier regla evaluada antes que la denegación, haría que `/api/fiscal-propuestas/decidir` cayera dentro de lo permitido. La denegación va arriba de todo y compara la cadena completa: no hay refactor de la lista de permitidos que pueda abrir esta puerta sin que alguien borre explícitamente la línea del 403.

> *«un agente que puede aprobar sus propias propuestas no está pidiendo permiso: está avisando. […] La separación no descansa en que el agente se porte bien, descansa en que no tenga la credencial.»*
> — `api/auth.mjs`

---

## La verificación operativa

`ops/verificar_alcances.sh` corre contra el entorno desplegado y **no modifica nada**. Comprueba:

| Caso | Esperado |
|---|---|
| Las cuatro lecturas permitidas con token fiscal | **200** |
| Aprobar una propuesta con token fiscal | **403** |
| Generar obligaciones con token fiscal | **403** |
| Escribir movimientos con token fiscal | **403** |
| Ingesta con token fiscal | **403** |
| Decidir con **token general**, sobre un uuid inexistente | **422** |

### Por qué el 422 es la respuesta correcta

Es el caso más fino de todo el script. Con el token general, `POST /api/fiscal-propuestas/decidir` sobre un `proposal_id` que no existe debe devolver **422**: significa que la petición **pasó el control de alcance** y falló después, en la validación de negocio, porque el uuid no corresponde a ninguna propuesta.

> *«un 403 acá sería el problema»*

Un 403 con el token general indicaría que la regla de denegación es más amplia de lo que debe y está bloqueando también al aprobador humano. Verificar solo que el token fiscal reciba 403 comprobaría media garantía: hay que verificar además que el token general **no** lo reciba, o el sistema podría estar denegando todo y pareciendo seguro.

### El detalle del `fetch` dentro del contenedor

El script usa `fetch` dentro de un contenedor `node:22-alpine` porque el `wget` de BusyBox no soporta `--method`, y sin `--method` no se puede emitir el POST que la verificación necesita.

> *«un verificador que no puede hacer la pregunta reporta un fallo que no existe — y eso es peor que no verificar»*

Es una de las siete instancias catalogadas del patrón "falla en silencio": un verificador roto no se queda callado, produce un veredicto — y el veredicto es basura con la misma cara de seriedad que un veredicto real.

### El despliegue aborta

`ops/deploy_v4_8_propuestas.sh` **aborta el despliegue** si `POST /api/fiscal-propuestas/decidir` con el token fiscal no devuelve 403.

Es la diferencia entre una garantía documentada y una garantía vigente. La comprobación no corre en CI contra un entorno de prueba: corre contra el entorno al que se está desplegando, en el momento del despliegue, y si falla no hay despliegue.

---

## «La aprobación no ejecuta nada financieramente» — las tres formas verificables

La regla es del contrato §10, y está repetida literalmente en la migración y en el código. No es una promesa: hay tres mecanismos distintos, en tres capas distintas, y ninguno depende de los otros.

### 1 · El módulo escribe en UNA sola tabla, y hay un test que lee el fuente

Cabecera de `api/fiscal_propuestas.mjs`:

> *«Este módulo escribe en UNA tabla: `fiscal_propuestas`. No toca movimientos, deudas, obligaciones ni cierres, y hay una prueba que lo verifica leyendo este archivo.»*

El test se llama `el módulo no escribe en ninguna tabla financiera`. **Lee el propio archivo fuente** y falla si encuentra un INSERT o UPDATE contra una tabla financiera.

> *«si mañana alguien agrega el atajo de "aplicar al aprobar", falla»*

Es un test inusual y vale la pena señalar por qué funciona. Un test de comportamiento verifica que el código **no hizo** algo en los casos que el test probó. Este verifica que el código **no puede** hacerlo en ningún caso, porque la sentencia no existe en el archivo. Cubre el escenario que ningún test de comportamiento cubre: el atajo agregado con buena intención dentro de una rama que nadie ejercita.

### 2 · `decidirPropuesta` hace un solo UPDATE, de cuatro campos

`estado_aprobacion`, `aprobador`, `motivo_decision`, `fecha_decision`. No hay ninguna otra sentencia en la función.

La respuesta lleva el warning fijo:

> *«Aprobada. Esto NO ejecutó ningún cambio financiero: queda registrada la decisión. Aplicarla es un acto separado.»*

Que el aviso viaje en la **respuesta** y no solo en la documentación importa: lo lee quien aprueba, en el momento en que aprueba.

### 3 · La tabla no tiene forma de aplicar nada

> *«Esta tabla no toca ningún saldo, ninguna deuda y ningún movimiento: no tiene forma de hacerlo, y eso es a propósito.»*
> — `45_Migration_v4_8_propuestas_fiscales.sql`

No hay FK que dispare cascadas hacia tablas financieras, no hay trigger que propague, no hay vista que la sume. El rollback de la migración lo confirma desde el otro lado: tirar la tabla abajo *«no afecta saldos, movimientos, deudas ni cierres»*. Una tabla cuya eliminación no cambia ningún número es una tabla que no participa de ningún número.

### Y desde el lado del comportamiento

Dos tests cierran el círculo:

- `aprobar no cambió el movimiento de origen`
- `el diagnóstico no clasificó ningún movimiento por su cuenta`

---

## Otras garantías

### La ruta del documento nunca se expone

`documentos.ruta` no sale del API. Se devuelve `sha256` y el booleano `contenido_disponible`. La columna está comentada en el esquema como *«ruta interna, NUNCA una URL pública»*, y hay un test del suite SQL dedicado a verificar que no se filtre.

Es una defensa contra dos cosas a la vez: la enumeración del almacenamiento y la construcción de URLs por parte de un modelo de lenguaje, que es notoriamente propenso a inventar una URL plausible a partir de una ruta.

### El CUIT va cifrado

Se guarda cifrado con `praxia_finanzas.cifrar()` en la columna `cuit_cifrado` (bytea). Lo único que sale del API es `cuit_parcial`, con el formato que el propio sistema define: `20-****1234-5` — el valor de este ejemplo es sintético. La validación del dígito verificador la hace `cuitValido()` por módulo 11.

Aplica tanto a los perfiles fiscales como a los CUIT de emisor y receptor de cada comprobante, que también se guardan cifrados con su parcial al lado.

### El actor sale de la credencial

> *«quién pidió el análisis sale de la credencial, no de lo que el cliente diga que es»*

En las rutas de lectura, `actor` se deriva del scope del token (`scope:<scope>`). En la creación de propuestas, el servidor sobrescribe el campo **después** de procesar el body. El cliente declara el `proposito`; no declara quién es.

Es la única forma de que la trazabilidad del §11 signifique algo. Un `actor` que viaja en el body es un campo de texto libre con nombre serio.

### El resto

- SQL parametrizado en todos lados.
- El stack de error nunca se devuelve al cliente: *«puede contener fragmentos de la consulta»*.
- `fiscal_auditoria` es append-only real, con trigger `trg_faud_inmutable` sobre UPDATE y DELETE: *«La auditoría fiscal es append-only: no se puede % una fila.»*
- Los grants del esquema son granulares: `praxia_finanzas_rw` tiene **solo SELECT** sobre `fiscal_reglas` (*«son normativa, las carga un administrador, no la API»*), **SELECT + INSERT** sobre `fiscal_auditoria` (*«escribir y leer, nunca corregir»*), y DELETE únicamente sobre las dos tablas puente.

---

## Lo que es guarda de prompt y no de código

Hay que decirlo con todas las letras, porque es la diferencia entre este documento y un folleto.

La **anulación de movimientos desde Telegram** está protegida por una guarda de prompt, no por una de código. El `toolDescription` de la herramienta obliga al modelo a preguntar y a esperar un mensaje posterior del humano antes de anular.

> *«No hay un mecanismo de la API que impida a un agente anular sin preguntar.»*
> — `37_Tools_Agente_Consulta_y_Anulacion.md`

Es exactamente el tipo de garantía que el resto del subsistema evita: depende de que el modelo se comporte. Un prompt no es un control de acceso; es una sugerencia muy bien redactada. Está documentado como límite conocido y no como característica.

La asimetría con el 403 de `/decidir` es instructiva. Ahí donde el diseño se tomó en serio la separación, la protección terminó siendo una credencial ausente y un script de despliegue que aborta. Donde no llegó a tomársela, quedó una instrucción en lenguaje natural. La segunda es mejor que nada, y peor que la primera, y saber cuál es cuál es lo que permite priorizar.

### Otro pendiente del mismo tipo

El **rol de PostgreSQL de solo lectura** del §14 —la *«exclusividad técnica a nivel de motor»*— **no está desplegado**. Existe el guardia de aplicación de `fiscal_lectura.mjs`, que es sólido, pero la segunda barrera sigue siendo tarea pendiente: crear el rol, otorgarle `SELECT` únicamente sobre las tablas del §5, y apuntar la capa a ese rol. Ver [limites-y-deudas.md](limites-y-deudas.md).

---

## Documentos relacionados

- [Ficha del subsistema](README.md)
- [El contrato v1.0](contrato-finanzas-fiscal.md) — §14 y §21
- [La capa de lectura](capa-de-lectura.md)
- [Propuestas y huellas](propuestas-y-huellas.md)
- [Límites y deudas](limites-y-deudas.md)
- [Modelo de permisos](../../docs/01-arquitectura/modelo-de-permisos.md)
- [SECURITY.md](../../SECURITY.md)
- [ADR-004 — Aprobación humana en acciones consecuentes](../../docs/04-decisiones/adr-004-aprobacion-humana-en-acciones-consecuentes.md)

> Última verificación: 2026-08-06
