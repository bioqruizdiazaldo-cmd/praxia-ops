# n8n-versionado — versionar workflows de n8n en git, de verdad

Cuatro órdenes de Node sin ninguna dependencia que convierten un export de n8n —un volcado ilegible que cambia en cada guardado— en un artefacto revisable, con hash estable, manifiesto de 11 campos y una compuerta de secretos antes de publicar.

Es la herramienta que le faltaba a la [guía de versionado no-code](../../docs/05-gobernanza/versionado-no-code.md). La guía decía qué había que hacer; esto lo hace.

> **In English** — A zero-dependency Node.js toolkit that makes n8n workflows reviewable in git. `exportar`
> pulls workflows from the n8n API (cursor pagination, credentials read from the environment with no
> defaults, API key never printed). `normalizar` strips the runtime metadata that pollutes the diff without
> changing behaviour — instance ids, `versionId`, timestamps, `active`, `pinData`, `staticData`, node
> `position` and `webhookId` — then sorts every object key and sorts nodes by name, so two exports of the
> same unchanged workflow are byte-for-byte identical and the SHA-256 becomes a real drift detector.
> `manifiesto` generates and validates the project's eleven-field workflow manifest, leaving as `null`
> everything a human must decide. `verificar` is the pre-publish gate: it scans for tokens, connection
> strings with passwords, embedded credential values and personal data, and reports the JSON path and the
> finding type but never the value. 65 tests, `node --test`, synthetic fixtures only. What it does not do:
> replace visual review of the graph, prove the workflow works, or prove the absence of secrets.

<!-- fin del resumen en inglés -->

---

## El problema

Quien cambia una función tiene un diff de tres líneas, un revisor que lo entiende en treinta segundos y un `git revert`. Quien cambia un workflow de n8n tiene un lienzo, un botón de guardar y un JSON de miles de líneas que nadie va a leer.

El JSON crudo de n8n es ilegible como diff por razones concretas, y ninguna tiene que ver con el comportamiento del workflow:

| Ruido | Qué lo provoca |
|---|---|
| `position` de cada nodo | Arrastrar un nodo dos píxeles |
| `updatedAt`, `versionId` | Cualquier guardado, aunque no hayas tocado nada |
| `id` de nodo, `webhookId` | Se regeneran al reimportar |
| Orden de claves y de nodos | La serialización no garantiza orden estable |
| `pinData` | Datos de prueba pegados al lienzo. Y **suelen ser datos reales** |

Resultado: cambiás el texto de un prompt y el diff muestra 400 líneas. El revisor abre, ve la marea y aprueba sin leer. Eso es peor que no revisar, porque queda registro de una revisión que no ocurrió.

Y hay un segundo problema encima del primero: **un export ingenuo publica IDs de credencial, chat_ids y a veces tokens.** Un secreto commiteado sigue expuesto aunque después borres el archivo, porque queda en el historial. La respuesta correcta no es borrar: es rotar.

---

## Qué hay acá

| Archivo | Qué hace |
|---|---|
| `cli.mjs` | Punto de entrada único: `exportar`, `normalizar`, `verificar`, `manifiesto` |
| `exportar.mjs` | Trae los workflows de la API de n8n, paginando por cursor, y los escribe normalizados |
| `normalizar.mjs` | El corazón: saca la metadata de runtime y produce una forma canónica |
| `manifiesto.mjs` | Genera y valida el manifiesto de 11 campos del repositorio |
| `verificar.mjs` | La compuerta: escanea secretos, credenciales embebidas y datos personales |
| `tests/` | 65 tests con `node --test`, sin dependencias |
| `tests/fixtures/` | Un workflow limpio, y una plantilla del que tiene problemas sembrados |
| `tests/senuelos.mjs` | Arma los valores con forma de secreto en tiempo de ejecución. Ningún archivo del repositorio contiene uno completo |

Requiere Node 18 o superior. No hay `package.json`, no hay `node_modules`, no hay que instalar nada.

---

## Uso

### Exportar

```bash
export N8N_URL="https://tu-instancia-de-n8n"
export N8N_API_KEY="…"     # nunca en un archivo versionado

node cli.mjs exportar --destino workflows --simbolizar
node cli.mjs exportar --dry-run          # lista qué traería, sin escribir
```

Dos criterios que no son negociables:

- **No hay instancia por defecto.** Si falta `N8N_URL` o `N8N_API_KEY`, falla y no arranca. Un default silencioso —"si no hay URL, uso localhost"— es cómodo hasta el día que apunta a producción sin que nadie lo haya pedido.
- **La clave no se imprime nunca**, ni completa ni parcial. Un prefijo de cuatro caracteres en el log de CI no sirve para depurar y sí achica el espacio de búsqueda de quien la quiera.

Cada workflow se escribe en `<destino>/<nombre-slug>.<id>.json`. El `id` va en el nombre del archivo —no adentro del JSON, de donde el normalizador lo saca— para que dos workflows con el mismo nombre no se pisen.

### Normalizar

```bash
node cli.mjs normalizar workflow.json --salida workflows/mi-workflow.json
node cli.mjs normalizar workflow.json --hash        # el sha256 del artefacto
node cli.mjs normalizar --campos                    # qué se saca y por qué
```

Qué hace, en orden:

1. Saca los campos de runtime (la lista completa está abajo).
2. Ordena las claves de todo objeto, en todos los niveles.
3. Ordena los nodos por nombre —no por id, que se va—.
4. Reduce las etiquetas a nombres.
5. Serializa con indentación fija y una sola nueva línea al final.

Con `--simbolizar`, además reemplaza cada credencial `{id, name}` por `{referencia: "CRED_NOMBRE"}`. **Para un repositorio público es obligatorio:** un ID de credencial no aporta nada y ayuda a quien esté mapeando el sistema. El costo es que el artefacto ya no se reimporta tal cual — hace falta remapear las credenciales en el entorno de destino, que es exactamente lo que hace posible tener ambientes separados.

### Verificar

```bash
node cli.mjs verificar workflows/*.json          # sale con 1 si hay algo grave
node cli.mjs verificar workflows/*.json --estricto --json
```

Busca tokens de formato conocido (Telegram, `sk-*`, GitHub, Slack, AWS, JWT), claves privadas PEM, cadenas de conexión con contraseña, secretos en query string, cabeceras `Authorization` literales, credenciales con valor embebido, `chat_id` numéricos, correos que no sean de dominios reservados para ejemplos, CUIT con dígito verificador válido y direcciones IP.

Cada hallazgo informa **ruta dentro del JSON y tipo. Nunca el valor.** Si el reporte imprimiera el token, el reporte pasaría a ser el nuevo lugar donde está el token: en la salida de CI, en el log, en el ticket.

```text
BLOQUEA  workflows/alta-de-contacto.json: 12 hallazgo(s).
  [ALTA] credencial_con_valor
      ruta: nodes["Avisar al grupo"].credentials.telegramApi
      por qué: La credencial trae claves fuera de la referencia (data). El valor de una credencial nunca se versiona.
```

Sale con **1** si hay algo de severidad alta, así se puede usar como compuerta en CI. Con `--estricto`, la severidad media también bloquea.

### Manifiesto

```bash
node cli.mjs manifiesto generar workflows/mi-workflow.json --yaml > MANIFIESTO.yaml
# completar a mano lo que quedó en null, y después:
node cli.mjs manifiesto validar MANIFIESTO.json
```

`generar` deriva lo que se puede derivar del JSON sin interpretar nada: nombre en runtime, tipo de entrada, servicios, credenciales como símbolos, subworkflows invocados. **Todo lo demás queda en `null` a propósito.** Un manifiesto autocompletado con valores plausibles es peor que uno vacío, porque parece revisado.

Lo que nunca se infiere, y por qué:

| Campo | Por qué no se adivina |
|---|---|
| `owner` | Es una persona que se hace cargo. No sale de un JSON |
| `estado` | Inferirlo de `active` sería el error exacto que el campo previene: el `errorWorkflow` de este sistema dice `[TEST]` en el nombre y está activo desde julio |
| `clasificacion_datos` | Depende de qué atraviesa el flujo, no de qué nodos tiene |
| `evidencia_test` | Si no se probó, se escribe que no se probó |
| `rollback` | Un rollback que no se verificó es una intención, no un plan |

`validar` comprueba los 11 campos y sus subcampos, que el estado de ciclo de vida sea uno de los seis (`draft`, `test`, `staging`, `production`, `deprecated`, `archived`), que el entorno y la clasificación de datos estén en su lista, que un workflow en `draft` o `test` no se declare en `prod`, que el hash de rollback parezca un SHA-256 y que **las credenciales sean referencias simbólicas `CRED_*`** y no IDs, nombres de runtime ni objetos con datos adentro.

El manifiesto se maneja en JSON porque parsear YAML exigiría una dependencia. La estructura es la misma que la [plantilla del repositorio](../../artifacts/workflows-n8n/manifiesto-de-workflow.md), y `--yaml` emite el YAML para pegar en el `MANIFIESTO.md`.

---

## Qué se saca al normalizar, y por qué

| Campo | Ámbito | Por qué se saca |
|---|---|---|
| `id` | raíz | Identificador del workflow dentro de esta instancia. Cambia al importar en otra |
| `versionId` | raíz | UUID regenerado en cada guardado. La fuente de ruido número uno |
| `createdAt` · `updatedAt` | raíz | El historial lo lleva git. Sin sacarlos, el hash nunca es estable |
| `active` | raíz | Estado de despliegue, no del artefacto. Si viajara, importar podría activar solo |
| `triggerCount` | raíz | Contador de runtime |
| `shared` | raíz | Usuarios, correos y roles de la instancia. Dato personal |
| `pinData` | raíz | Datos de prueba pegados al lienzo. Casi siempre son datos reales |
| `staticData` | raíz | Estado acumulado entre ejecuciones. Memoria de la instancia |
| `meta.instanceId` | meta | Huella del servidor que exportó |
| `position` | nodo | Coordenadas en el lienzo. Cero efecto sobre el comportamiento |
| `webhookId` | nodo | UUID del webhook en esta instancia. Se regenera al importar |
| `id` | nodo | UUID regenerado al reimportar. Las conexiones referencian por **nombre**, no por id |
| `id`, `createdAt`, `updatedAt` de cada tag | tag | De una etiqueta sólo importa el nombre |

La lista vive en el código como `CAMPOS_DE_RUNTIME`, con el motivo de cada campo escrito al lado, para que se pueda auditar sin leer la implementación: `node cli.mjs normalizar --campos`.

**Qué no se toca nunca:** `parameters`, `connections`, `type`, `typeVersion`, `name`, `settings`, `disabled`, y la referencia de credencial. La regla es asimétrica a propósito: un normalizador que borra de más rompe despliegues; uno que borra de menos sólo deja ruido en el diff. Ante la duda, se conserva.

---

## El pipeline completo

Los diez pasos del [runbook de publicación](../../docs/06-runbooks/publicar-un-workflow-n8n.md). Esta herramienta cubre cuatro y media; el resto es de personas y de infraestructura, y decirlo es parte del método.

| # | Paso | Quién |
|---|---|---|
| 1 | Exportar | `node cli.mjs exportar` |
| 2 | Normalizar | `node cli.mjs normalizar` (o incluido en `exportar`) |
| 3 | Escanear secretos | `node cli.mjs verificar` |
| 4 | Validar estructura | **Parcial** — se valida el manifiesto, no la topología del grafo |
| 5 | Probar contratos con fixtures | Fuera de alcance: son los tests del workflow, no de la herramienta |
| 6 | Importar en staging inactivo | Persona + un ambiente de staging que este sistema todavía no tiene |
| 7 | Revisar el grafo visual | **Una persona. No se puede automatizar** |
| 8 | Publicar tras aprobación | Persona |
| 9 | Registrar el hash | `node cli.mjs normalizar --hash` |
| 10 | Verificar y conservar rollback | Persona |

De punta a punta:

```bash
export N8N_URL="https://tu-instancia-de-n8n" N8N_API_KEY="…"

# 1 y 2 — traer y normalizar
node cli.mjs exportar --destino workflows --simbolizar

# 3 — compuerta: si encuentra algo, se para acá y se rota lo que haya que rotar
node cli.mjs verificar workflows/*.json || exit 1

# manifiesto — generar el esqueleto, completarlo a mano, validarlo
node cli.mjs manifiesto generar workflows/mi-workflow.json --yaml > MANIFIESTO.yaml
node cli.mjs manifiesto validar MANIFIESTO.json || exit 1

# 9 — el hash que se registra junto al despliegue
node cli.mjs normalizar workflows/mi-workflow.json --hash

# 4 a 8 y 10 — pruebas, staging, revisión visual, aprobación y rollback: personas
git add workflows/ MANIFIESTO.yaml && git commit
```

La estructura de repositorio que esto habilita, una carpeta por nombre lógico estable:

```text
workflows/
  ejemplo.resumen-diario.v1/
    workflow.json          ← exportado y normalizado
    MANIFIESTO.yaml        ← los 11 campos
    fixtures/
    CHANGELOG.md
```

---

## Qué NO resuelve

Esto es lo más importante de este README.

- **No reemplaza revisar el grafo visual.** El diff textual no muestra la topología. Una rama "aprobado" conectada al nodo de rechazo se ve en el lienzo y no se ve en el JSON. Ningún linter detecta eso. El paso 7 sigue siendo de una persona, y no es opcional.
- **No valida que el workflow funcione.** No ejecuta nada, no resuelve credenciales, no comprueba que el nodo exista en la versión de n8n de destino. Que normalice y verifique bien no dice absolutamente nada sobre si anda.
- **El escaneo de secretos es por patrones, y un patrón no prueba ausencia.** Encuentra formatos conocidos. Un token de un proveedor raro, una contraseña que parece una palabra común, una clave partida en dos campos: no los encuentra. Que salga `sin hallazgos` significa "no encontré nada de lo que sé buscar", no "está limpio".
- **No detecta nodos huérfanos, ramas sin salida ni falta de manejo de error** (paso 4 del pipeline). Valida el manifiesto, no la estructura del grafo.
- **No hace rollback ni despliega.** Escribe archivos y devuelve códigos de salida. Importar, activar y volver atrás lo hace una persona con una aprobación registrada.
- **La simbolización de credenciales rompe el reimport directo.** Es el costo de no publicar IDs: el entorno de destino tiene que resolver los símbolos contra su propio almacén. Es una función, no un accidente, pero hay que saberlo antes de intentar importar el archivo tal cual.

---

## Tests

```bash
cd tools/n8n-versionado
node --test                       # descubre tests/*.test.mjs
node --test tests/*.test.mjs      # equivalente, explícito
```

65 tests, sin dependencias, sin red. Cubren:

- Idempotencia: normalizar dos veces da lo mismo, byte por byte.
- Dos exportaciones del mismo workflow con distinto `updatedAt`, distintas `position`, ids regenerados y nodos en otro orden normalizan a un archivo idéntico y al mismo hash.
- Que normalizar **no** toque parámetros, conexiones, tipos ni referencias de credencial.
- Orden de claves estable aunque la entrada venga desordenada.
- El validador de manifiesto detectando cada uno de los 11 campos faltantes, cada estado inválido y cada forma de credencial no simbólica.
- El verificador encontrando el token plantado, la cadena de conexión con contraseña y la credencial con valor embebido — y **no** disparando con `@example.com`, con un id de credencial ni con una expresión de n8n.
- Que el reporte del verificador jamás contenga el valor encontrado.
- Paginación por cursor, `--dry-run` que no escribe, y que la API key no aparezca en ningún mensaje de error.

### Los señuelos, y por qué no están escritos

Los fixtures son **sintéticos**: no hay hostnames, IPs, IDs de workflow ni credenciales de ningún sistema real.

Pero hay un detalle que vale más que la aclaración. El workflow con problemas **no está versionado como tal**: lo que está en `tests/fixtures/` es una plantilla con marcadores, y los valores con forma de secreto se arman en tiempo de ejecución uniendo pedazos, en [`tests/senuelos.mjs`](tests/senuelos.mjs).

Eso salió de un choque real. La protección de push de GitHub rechazó un push de este repositorio por un token de Slack **falso** escrito literal en un test. Y tenía razón: un escáner que distinguiera secretos de verdad de secretos de mentira no serviría para nada, porque el que filtra una clave siempre cree que la suya es el caso especial.

La salida no fue pedir una excepción. Fue dejar de escribir cadenas con forma de secreto. Hoy ningún archivo de este repositorio contiene una —ni real ni falsa— y por eso el escaneo de secretos del CI no tiene lista de exentos. Una regla sin excepciones es una regla que se puede verificar; una con excepciones es una que hay que auditar cada vez.

---

## Estado de adopción, honesto

`Verificado` — la herramienta existe, corre y sus tests pasan.

`No` — **los workflows de este sistema todavía no están versionados con ella.** Que la herramienta exista no es lo mismo que la práctica esté adoptada, y confundir las dos cosas sería exactamente lo que la [política de publicación](../../docs/05-gobernanza/politica-de-publicacion.md) prohíbe.

Lo que falta para cerrar la brecha 2 del [ROADMAP](../../ROADMAP.md): correr esto contra la instancia real, resolver los hallazgos que aparezcan —incluida la rotación de lo que haya que rotar—, escribir los manifiestos de los 25 workflows activos y commitear el resultado.

> Última verificación: 2026-08-06
