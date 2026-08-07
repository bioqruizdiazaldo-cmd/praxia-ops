# Publicar una actualización del repositorio

Cómo pasa un cambio de la bóveda de trabajo a GitHub, sin que nadie tenga que acordarse de los pasos.

> **In English** — The procedure that moves a change from the private working vault to the public
> repository. The working copy of this repository lives inside that vault as a normal git repository
> with a remote, so publishing is an ordinary commit and push — there is no export step and no
> second copy to keep in sync. A single idempotent PowerShell script does the whole loop: commit,
> push, description, topics, labels, backlog issues and the private vulnerability reporting toggle,
> and re-running it is always safe because every step checks state before acting. The gate before
> publishing is a secret scan that also runs in CI on every push, so a leak has to get past both a
> local check and a remote one. This page also records what to do when the loop breaks: network
> failures mid-run, orphaned git locks, and the difference between "nothing changed" and "the
> change did not reach the remote".

<!-- fin del resumen en inglés -->

---

## Cómo está armado

La copia de trabajo de este repositorio **vive dentro de la bóveda privada**, en una carpeta dedicada, y es un repositorio git normal con su remoto configurado.

Eso importa porque significa que **no hay paso de exportación**. No existe una segunda copia que haya que mantener sincronizada, ni un directorio de "publicables" que se llene a mano. Publicar es hacer commit y push, como en cualquier repositorio.

La bóveda entera está en una carpeta sincronizada a la nube; el repositorio, no: lo que llega a GitHub es solo lo que pasa por un commit, y el `.gitignore` decide qué queda afuera.

```
<bóveda privada>/
└── <carpeta del portafolio>/
    ├── praxia-ops/          ← repositorio con remoto. Copia de trabajo
    ├── perfil-github/       ← repositorio del README de perfil
    ├── PUBLICAR-EN-GITHUB.ps1
    ├── ESCANEAR-SECRETOS.ps1
    └── SEGURIDAD-LIMPIEZA.ps1
```

---

## El camino normal

### 1. Escribir el cambio

Editar los archivos dentro de `praxia-ops/`, como cualquier repositorio. Si el cambio lo produce un agente, aplican las reglas del [acuerdo de trabajo con agentes](../05-gobernanza/acuerdo-de-trabajo-con-agentes.md).

### 2. Pasar la compuerta

```powershell
powershell -ExecutionPolicy Bypass -File .\ESCANEAR-SECRETOS.ps1 -Ruta .\praxia-ops
```

Sale con código 1 si encuentra algo de severidad alta. El detalle de cómo leer el resultado y cómo triar los falsos positivos está en [auditar antes de publicar](../05-gobernanza/auditar-antes-de-publicar.md).

Esto es redundante con el CI a propósito: el mismo escaneo corre en GitHub Actions en cada push. Una fuga tiene que pasar por los dos.

### 3. Publicar

```powershell
powershell -ExecutionPolicy Bypass -File .\PUBLICAR-EN-GITHUB.ps1
```

Pide el token y hace, en orden: commit, push, descripción del repositorio, topics, etiquetas del backlog, issues del roadmap, y el reporte privado de vulnerabilidades.

**Es idempotente.** Cada paso verifica el estado antes de actuar: si el repositorio existe no lo recrea, si no hay cambios no commitea, si la etiqueta ya está la corrige en vez de duplicarla. Correrlo dos veces seguidas deja el mismo resultado que correrlo una.

### 4. Verificar contra el remoto, no contra la pantalla

Este paso no es opcional y es el que más veces salvó la jornada:

```bash
git clone --depth 1 <url-del-repositorio> /tmp/verificacion
cd /tmp/verificacion && git log --oneline -1
```

Un script puede decir "OK" y no haber subido nada. El remoto es la única fuente de verdad sobre lo que se publicó.

### 5. Borrar el token

Un token de publicación tiene una vida útil de una sesión. Si sobrevive a la tarea, es una credencial huérfana esperando a que alguien la encuentre.

---

## Cuando se rompe

| Síntoma | Qué pasó | Qué hacer |
|---|---|---|
| `Could not resolve host` · `Empty reply from server` · `No se puede resolver el nombre remoto` | Se cayó la conexión. No es el token ni el repositorio | Verificar con `Test-NetConnection github.com -Port 443`. Los commits quedaron en local; volver a correr el script cuando vuelva |
| `Unable to create ... index.lock: File exists` | Quedó un lock huérfano de una corrida interrumpida | Borrar `praxia-ops\.git\index.lock`. El script lo hace solo al arrancar |
| `refusing to allow a Personal Access Token to create or update workflow` | Al token le falta el permiso de Workflows | Agregarlo al token. Es una protección deliberada de GitHub sobre `.github/workflows/` |
| `GH013: Repository rule violations` · `Push cannot contain secrets` | La protección de push de GitHub encontró algo con forma de secreto. **También dispara con secretos falsos**: no distingue, y hace bien | Leer la ruta y la línea que informa. Si es un valor real: [rotarlo](rotar-una-credencial-expuesta.md) y reescribir el commit. Si es un señuelo de un test: **no pedir la excepción** — armarlo en tiempo de ejecución uniendo pedazos, para que el archivo no contenga la cadena completa. Ver [`tools/n8n-versionado/tests/senuelos.mjs`](../../tools/n8n-versionado/tests/senuelos.mjs) |
| `Resource not accessible by personal access token` al tocar etiquetas | Las etiquetas exigen **dos** permisos: Issues y Pull requests, ambos de escritura | La cabecera `X-Accepted-GitHub-Permissions` de la respuesta dice exactamente cuál falta. Leerla en vez de adivinar |
| "Sin cambios para commitear" cuando esperabas cambios | El commit ya se había hecho en una corrida anterior que falló después | Normal. El push de esta corrida lo sube |
| El script dice OK pero el remoto no cambió | Un error se tragó en un `catch` | Verificar siempre con el paso 4. Y arreglar el `catch` |
| El push entra pero el CI queda en rojo, y el job falla en segundos sin imprimir nada | GitHub Actions corre cada `run` con `bash -e`. Un paso que **espera** que un comando falle — por ejemplo comprobar que el escáner sale con 1 — muere en la línea del comando, antes de poder leer `$?` | Escribir `cmd && x=0 \|\| x=$?` en vez de `cmd` seguido de `x=$?`. Y al reproducir un job localmente, invocarlo con `bash --noprofile --norc -e -o pipefail`, no con un `bash` común: si no, pasa local y falla remoto |

---

## Los permisos del token de publicación

Seis, ni uno más:

| Permiso | Para qué |
|---|---|
| Administration · escritura | Crear el repositorio y cambiar sus ajustes |
| Contents · escritura | El push |
| Issues · escritura | Etiquetas e issues del backlog |
| Pull requests · escritura | **También** hace falta para las etiquetas: son objetos compartidos entre issues y pull requests |
| Workflows · escritura | Modificar archivos bajo `.github/workflows/` |
| Metadata · lectura | Obligatorio, lo agrega GitHub solo |

Los tableros de proyecto de una cuenta personal **no** están soportados por los tokens de grano fino: requieren un token clásico con el ámbito `project`. Es una limitación conocida de la plataforma, no un permiso que falte configurar.

---

## Qué hace que esto dure

Tres decisiones, y ninguna es técnica:

**La copia de trabajo es el repositorio.** No hay export, no hay carpeta espejo, no hay paso manual de copiar archivos. Todo lo que se pueda desincronizar, en algún momento se desincroniza.

**El script es idempotente y lo dice.** Un procedimiento que hay que ejecutar exactamente una vez, en el orden correcto, es un procedimiento que va a fallar. Uno que se puede correr de nuevo sin pensarlo se corre cuando hace falta.

**Ninguna compuerta tiene lista de exentos.** El escaneo local, el del CI y la protección de push de GitHub corren sin excepciones sobre todo el repositorio, incluidos los tests. Eso se pudo sostener sólo porque se cambió el código para que no hiciera falta la excepción, y no al revés — cuando la protección de push rechazó un token *falso* en un test, la corrección fue dejar de escribir cadenas con forma de secreto, no pedir que la dejaran pasar. Una excepción hay que recordarla, justificarla y auditarla cada vez; y la primera que se concede es siempre razonable.

**La verificación está automatizada y duplicada.** El escaneo de secretos corre local antes de publicar y remoto en cada push. Lo que depende de que alguien se acuerde, tarde o temprano no se hace — que es exactamente la lección del [post-mortem del drift](postmortem-drift-produccion.md), donde producción quedó tres migraciones atrás porque se miraba el repositorio y no el servidor.

> Última verificación: 2026-08-06
