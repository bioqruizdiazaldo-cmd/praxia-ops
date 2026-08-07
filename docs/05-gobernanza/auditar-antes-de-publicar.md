# Auditar antes de publicar

Nueve controles para revisar una carpeta de trabajo compartida con agentes de IA antes de que algo de ahí adentro salga a un lugar público.

> **In English** — Nine concrete controls for auditing a working folder shared with AI agents before anything
> from it becomes public: secrets in git history rather than just the working tree, stray `.git` directories,
> credential files by extension, secret patterns by content, personal data, infrastructure topology, raw dumps
> and exports, conversation transcripts, and — the one almost nobody runs — the agent's own permission
> configuration. Each control lists what to look for, the command to run, and how to read the result. The
> ninth gets its own section: a real configuration held 152 pre-approved permissions and zero deny rules, and
> two entries added for a one-off deployment handed over the server key with no confirmation prompt. Also
> covered: severity levels and what each one buys you, the rule that matters most — **rotate, don't delete** —
> what a scan does *not* prove, and the false positives you will actually hit and how to triage them.

<!-- fin del resumen en inglés -->

---

## Qué problema resuelve

Una carpeta de trabajo compartida con agentes acumula secretos y datos personales sin que nadie lo decida.

Nadie escribe nunca "voy a dejar un token de API en la nube". El token queda ahí porque resolvía algo puntual: había que probar un endpoint, había que hacer un despliegue, había que no tener que confirmar cada comando durante una hora. Después la carpeta se sincroniza a un servicio en la nube, o alguien la abre desde otro dispositivo, o un día se le hace `git init` a un subdirectorio y el `.gitignore` no cubría ese archivo.

Ninguno de esos pasos es un error grave por separado. El resultado combinado sí lo es.

Este documento convierte esa revisión en un procedimiento repetible. No reemplaza a la [política de publicación](politica-de-publicacion.md) —que decide *qué* se publica— sino que le da a su compuerta 2, el escaneo de secretos y datos personales, un método concreto en vez de una intención.

**Dos condiciones para que sirva:**

- Se corre en **modo lectura**. Una auditoría no borra, no mueve y no arregla. Produce una lista; la remediación es una decisión posterior y con dueño.
- Se corre **antes** de publicar y **cada tanto** sobre la carpeta entera. El primer uso siempre encuentra más de lo esperado. Eso es la señal de que hacía falta, no de que algo esté mal hecho.

---

## Los nueve controles

| # | Control | Busca | Severidad típica |
|---|---|---|---|
| 1 | Historia de git | Secretos en commits viejos, no sólo en el árbol actual | Crítica |
| 2 | Repositorios inesperados | Un `.git` donde no debería haber uno | Crítica |
| 3 | Archivos de credenciales | Claves y archivos de entorno, por extensión y nombre | Crítica |
| 4 | Patrones de secreto | Tokens y contraseñas, por contenido | Crítica |
| 5 | Datos personales | Identificadores, correos, domicilios, nombres | Alta |
| 6 | Topología | IPs, hostnames, puertos, rutas absolutas del servidor | Media-baja |
| 7 | Dumps y exports crudos | Volcados sin sanitizar | Media-baja |
| 8 | Transcripciones | Conversaciones con agentes | Media |
| 9 | **Permisos del agente** | La configuración que decide qué puede hacer sin preguntar | **Crítica** |

Se recorren en orden. Los cuatro primeros son los que pueden obligar a rotar algo hoy; el noveno es el que más rinde y el que casi nadie hace.

---

### 1. Secretos en la historia de git, no sólo en el árbol de trabajo

**Qué buscar.** Un archivo borrado en un commit posterior sigue en el historial. Un token que estuvo cinco minutos en un commit que después se revirtió está en el repositorio para siempre, y si el repositorio es público, en el caché de cualquiera que lo haya clonado.

**Con qué comando.** Primero, todos los blobs que existieron alguna vez, filtrados por nombre:

```bash
git rev-list --objects --all \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(rest)' \
  | awk '$1 == "blob" { print $3 }' \
  | grep -Ei '(^|/)\.env|\.pem$|\.p12$|\.pfx$|id_rsa|id_ed25519|credentials\.json|\.pgpass'
```

Después, búsqueda por contenido en todas las revisiones. Es lenta en repositorios grandes; conviene correrla una vez y anotar el resultado:

```bash
git grep -nI -E 'sk-[A-Za-z0-9]{32,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' \
  $(git rev-list --all) 2>/dev/null | head -50
```

Y los archivos sensibles que se agregaron y después se borraron:

```bash
git log --all --diff-filter=D --name-only --format='%h %ad' --date=short -- '*.env' '*.pem' '*.key'
```

**Cómo interpretarlo.** Una sola coincidencia en la historia significa que ese secreto está comprometido, aunque el archivo ya no exista y aunque el repositorio nunca haya sido público — porque "nunca fue público" es una afirmación sobre el pasado, no una garantía. Si el repositorio sí fue público, asumí que fue visto: un repositorio público es indexable, clonable y archivable por terceros en minutos.

La acción no es reescribir el historial. La acción es **rotar**, y después, si hace falta, reescribir el historial.

---

### 2. Un `.git` donde no debería haber uno

**Qué buscar.** Repositorios anidados o inesperados dentro de la carpeta de trabajo. El peor escenario es un `.git` en la raíz de una carpeta sincronizada a la nube: significa que todo lo que estuvo ahí adentro alguna vez está en un historial, y que un `git push` distraído lo publica entero.

**Con qué comando.**

```bash
find <carpeta-de-trabajo> -type d -name .git -prune -print
```

En PowerShell:

```powershell
Get-ChildItem -Path <carpeta-de-trabajo> -Recurse -Force -Directory -Filter '.git' |
    Select-Object -ExpandProperty FullName
```

**Cómo interpretarlo.** Para cada `.git` encontrado, tres preguntas: ¿tiene un remoto configurado (`git remote -v`)?, ¿ese remoto es público?, ¿el `.gitignore` cubre los archivos de entorno? Un repositorio local sin remoto es un problema menor pero real: el historial existe y viaja con la carpeta.

Que **no** haya un `.git` en la raíz de la carpeta sincronizada es un resultado que conviene dejar escrito. Es el peor escenario, y verificar que no ocurrió vale tanto como encontrar un hallazgo.

---

### 3. Archivos de credenciales, por extensión y por nombre

**Qué buscar.** Los archivos cuyo nombre ya dice qué contienen. Es el control más barato y el que primero da resultado.

**Con qué comando.**

```bash
find <carpeta-de-trabajo> -type f \
  \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.p12' \
     -o -name '*.pfx' -o -name '*.key' -o -name 'id_rsa*' -o -name 'id_ed25519*' \
     -o -name '.pgpass' -o -name 'credentials.json' -o -name '*.kdbx' \) \
  ! -name '*.example' ! -name '*.sample' ! -path '*/node_modules/*'
```

**Cómo interpretarlo.** Cada coincidencia es un ítem a triar, no todavía un hallazgo. Un `.env.example` es una plantilla y se queda; un `.env` con un valor real es crítico. La diferencia se ve abriendo el archivo, no adivinando por el nombre.

Dos preguntas por cada archivo con valores reales: **¿está en una carpeta que se sincroniza a la nube?** y **¿está cubierto por un `.gitignore`?** Un `.env` local y no sincronizado es aceptable. El mismo `.env` dentro de una carpeta que replica a un servicio en la nube existe en al menos tres lugares: el disco, los servidores del proveedor, y cualquier otro dispositivo con esa cuenta.

---

### 4. Patrones de secreto, por contenido

**Qué buscar.** Los secretos que están dentro de archivos con nombre inocente: un script, un apunte en Markdown, un JSON de configuración.

**Con qué comando.** Un escáner que recorra los archivos de texto y reporte **ruta y línea, nunca el valor**. Esto último no es un detalle de estilo: un escáner que imprime el secreto en pantalla lo copia al historial de la terminal, al scrollback, y a la captura que después se pega en un chat.

Patrones mínimos:

| Tipo | Patrón | Severidad |
|---|---|---|
| Clave privada | `-----BEGIN [A-Z ]*PRIVATE KEY-----` | Alta |
| Token de proveedor de LLM | `\bsk-[A-Za-z0-9]{32,}` | Alta |
| Token de GitHub clásico | `\bgh[pousr]_[A-Za-z0-9]{30,}` | Alta |
| Token de GitHub fine-grained | `\bgithub_pat_[A-Za-z0-9_]{50,}` | Alta |
| Token de Slack | `\bxox[baprs]-[A-Za-z0-9-]{10,}` | Alta |
| Clave de acceso AWS | `\bAKIA[0-9A-Z]{16}\b` | Alta |
| Token de bot de mensajería | `\b\d{9,10}:[A-Za-z0-9_-]{35}\b` | Alta |
| Cadena de conexión con contraseña | `postgres(?:ql)?://[^:@/\s]+:[^@/\s]+@` | Alta |
| Secreto hexadecimal de 64 | `(?i)(token\|secret\|key)\s*[=:]\s*["']?[0-9a-f]{64}\b` | Alta |
| Asignación de token | `(?i)_(TOKEN\|SECRET\|API_?KEY)\s*=\s*["']?[A-Za-z0-9+/_-]{20,}` | Alta |
| Contraseña asignada | `(?i)(password\|passwd)\s*[=:]\s*["']?\S{8,}` | Media |

Con `ripgrep`, sin mostrar el valor:

```bash
rg --no-heading --line-number --only-matching --replace '[REDACTADO]' \
   -e '\bsk-[A-Za-z0-9]{32,}' \
   -e '\bAKIA[0-9A-Z]{16}\b' \
   -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
   <carpeta-de-trabajo>
```

**Cómo interpretarlo.** Los patrones de severidad alta son secretos reales hasta que se demuestre lo contrario. Los de severidad media casi siempre son referencias a variables de entorno y hay que mirarlos uno por uno — ver la sección de falsos positivos.

Limitá el tamaño de archivo (por ejemplo, 5 MB) y excluí `.git/`, `node_modules/`, entornos virtuales y directorios de compilación. Sin esos filtros el escaneo tarda horas y devuelve ruido.

---

### 5. Datos personales

**Qué buscar.** Identificadores fiscales o de documento, correos electrónicos, teléfonos, domicilios, fechas de nacimiento, nombres de terceros, y cualquier combinación de esos datos que permita reidentificar a alguien.

**Con qué comando.** Patrones por formato:

| Tipo | Patrón de ejemplo |
|---|---|
| Identificador fiscal nacional | `\b\d{2}-\d{8}-\d\b` |
| Documento de identidad | `\b\d{1,2}\.\d{3}\.\d{3}\b` |
| Correo electrónico | `[A-Za-z0-9._%+-]+@(?!example\.\|test\.)[A-Za-z0-9.-]+\.[A-Za-z]{2,}` |

```bash
rg --no-heading --line-number --count-matches \
   -e '\b\d{2}-\d{8}-\d\b' \
   <carpeta-de-trabajo>
```

**Cómo interpretarlo.** Acá lo que importa no es la coincidencia individual sino **la superficie**: en cuántos archivos distintos aparece el mismo dato. En la auditoría que originó este documento, el mismo identificador fiscal aparecía en **38 archivos**, y una parte era una copia duplicada completa de un expediente que ya existía en otra carpeta.

Ese es el hallazgo accionable. El expediente original es material de trabajo legítimo y no se borra. La copia duplicada no le sirve a nadie y multiplica por dos la superficie. Y el dato dentro del archivo de instrucciones que **todo agente lee al arrancar** es el que más riesgo tiene de terminar copiado a otro lado, precisamente porque es el que más se lee.

Regla práctica: si el dato hace falta, que viva en un solo lugar y que el resto diga **dónde está**, no **cuál es**.

---

### 6. Topología de infraestructura

**Qué buscar.** IPs públicas, hostnames reales, puertos, nombres de contenedor, rutas absolutas del servidor, nombres de base de datos y de usuario del sistema.

**Con qué comando.** Un patrón de IPv4 que excluya rangos privados y de documentación:

```bash
rg --no-heading --line-number \
   -e '\b(?!127\.|10\.|192\.168\.|0\.0\.0\.0|255\.|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|172\.(?:1[6-9]|2\d|3[01])\.)(?:\d{1,3}\.){3}\d{1,3}\b' \
   <carpeta-de-trabajo>
```

**Cómo interpretarlo.** Nada de esto es un secreto en sentido estricto: la IP de un servidor con puertos abiertos es descubrible. Pero le ahorra trabajo a un atacante — le dice adónde apuntar — y no le enseña nada a un lector.

Es material para higiene progresiva, no para el mismo día. Lo que sí conviene hoy es contar en cuántos archivos aparece y decidir en cuáles es **funcionalmente necesaria** (un script que se conecta) y en cuáles es **decorativa** (un runbook que podría decir `<HOST>`).

---

### 7. Dumps y exports crudos

**Qué buscar.** Volcados de base, exports de workflows, respuestas de API guardadas "para mirar después", carpetas llamadas `scratch/`, `tmp/`, `exports/` o `audits/`.

**Con qué comando.**

```bash
find <carpeta-de-trabajo> -type f \( -name '*.json' -o -name '*.sql' -o -name '*.csv' -o -name '*.dump' \) \
  -size +1M -printf '%s\t%p\n' | sort -rn | head -30
```

**Cómo interpretarlo.** Los dumps rara vez contienen el secreto en sí; lo que contienen son **referencias e identificadores**: nombres e ids de credencial, identificadores de chat, ids de webhook. Un id de webhook permite disparar un flujo sin autenticación si el flujo no valida nada más, así que no es inofensivo.

Un dump grande, no versionado y cubierto por `.gitignore` es candidato a **archivo frío** —moverlo fuera de la carpeta sincronizada, a un respaldo cifrado— y no a borrado inmediato: suele ser evidencia histórica que en algún momento sirve.

---

### 8. Transcripciones de conversaciones

**Qué buscar.** Los archivos de sesión de las herramientas de agente: `.jsonl`, logs de chat, historiales exportados. Se acumulan solos y crecen rápido — en el caso que originó este documento, **68 MB**.

**Con qué comando.** Los mismos patrones del control 4 y del control 5, aplicados a los archivos de transcripción, con el límite de tamaño levantado:

```bash
find <carpeta-de-trabajo> -name '*.jsonl' -type f -printf '%s\t%p\n' | sort -rn | head
rg --no-heading --count-matches -e 'sk-[A-Za-z0-9]{32,}' -e '-----BEGIN ' <carpeta-de-trabajo> -g '*.jsonl'
```

**Cómo interpretarlo.** El resultado más probable es cero secretos, y conviene registrarlo así de explícito. Lo que las transcripciones sí contienen es **contexto**: nombres, montos, decisiones, fragmentos de archivos, rutas. No es material para rotar, es material para **no publicar nunca** y para decidir si tiene que seguir sincronizándose.

---

### 9. La configuración de permisos del propio agente

Este es el control que casi nadie hace y el que más rinde. Tiene su propia sección abajo.

---

## Control 9 en detalle: los permisos que nadie revisa

La configuración de permisos de un agente crece por acumulación. Cada vez que una acción se traba, se agrega una entrada para destrabarla. Nadie vuelve a mirar la lista, porque la lista no rompe nada: cuantas más entradas tiene, menos fricción produce.

### El caso, sanitizado

Una configuración de agente real tenía **152 comandos preaprobados**, **cero reglas de denegación** y **cero reglas de pregunta**. Veinticinco de esas entradas eran comodines.

Dos entradas eran las que importaban:

```
Read(//c/Users/<usuario>/.ssh/**)
Bash(ssh -i *)
```

La primera concede lectura de **todo** el directorio `~/.ssh/`, **incluidas las claves privadas**. La segunda permite abrir una sesión SSH **con cualquier clave hacia cualquier host**, sin preguntar.

Por separado, cada una tiene una justificación razonable. La primera se agregó para leer un `known_hosts` o un `config`. La segunda, para no tener que confirmar treinta comandos seguidos durante un despliegue.

Juntas, significan que cualquier agente que corra con esa configuración puede leer la clave privada del servidor y usarla, **sin que aparezca un solo pedido de confirmación**.

### Por qué pasa

Ninguna de las dos entradas se agregó con mala intención ni por descuido. Se agregaron para resolver algo puntual, funcionaron, y nadie las volvió a mirar. Es el mismo mecanismo que deja un token en un `.env`: la solución puntual que se vuelve permanente porque nada la revisa.

Es exactamente lo que previene la regla del [acuerdo de trabajo con agentes](acuerdo-de-trabajo-con-agentes.md): una excepción documentada debe tener **dueño, motivo y fecha de vencimiento**. Ninguna de las dos tenía las tres cosas. Ninguna tenía ninguna.

### Qué revisar, concretamente

- [ ] **Contar.** Cuántas entradas `allow`, cuántas `deny`, cuántas `ask`. Si `deny` es cero, ese ya es el hallazgo, sin importar qué diga el resto.
- [ ] **Buscar rutas de claves.** Cualquier regla que mencione `.ssh`, `.gnupg`, `.aws`, `.pem`, `id_rsa`, `id_ed25519` o `credentials`.
- [ ] **Buscar comodines en comandos de acceso remoto.** `ssh *`, `scp *`, `rsync * *:*`, `docker -H *`, `kubectl *`.
- [ ] **Buscar datos dentro de la configuración.** Los archivos de permisos suelen tener la IP del servidor, el usuario de conexión y la ruta de la clave escritos en las propias reglas. Esa configuración es también un documento con topología.
- [ ] **Buscar pares peligrosos.** El riesgo no está siempre en una entrada: está en la combinación de dos que por separado parecen inocentes. Lectura de un directorio de claves + ejecución de un cliente que las use es el par canónico.
- [ ] **Poner vencimiento.** A cada excepción que sobreviva la revisión, una fecha.

El detalle de cómo se escriben las reglas —y las cuatro trampas de sintaxis que hacen que una regla mal escrita no proteja y encima dé la sensación de que sí— está en [permisos de agente](permisos-de-agente.md).

### El hallazgo real

No fue que hubiera 152 permisos. Fue que **no hubiera ninguna prohibición**.

Una lista de permisos que sólo dice "sí" no tiene techo: crece indefinidamente y cada entrada nueva amplía la superficie sin que nada la limite. Lo que faltaba era un **piso** — un conjunto de acciones que ninguna entrada del `allow` pueda habilitar, por más que la lista siga creciendo.

---

## Severidad y qué hacer con cada nivel

| Nivel | Qué califica | Plazo | Acción |
|---|---|---|---|
| **Crítico** | Un secreto real en una carpeta sincronizada o versionada. Un permiso que entrega acceso a claves privadas o a un servidor | **Hoy** | Rotar el secreto. Quitar el permiso. En ese orden |
| **Alto** | Datos personales replicados en muchos archivos. Un dato sensible en el archivo que todo agente lee al arrancar | **Esta semana** | Reducir superficie: eliminar duplicados, mover el dato a un solo lugar |
| **Medio** | Valores por defecto inseguros que sólo aplican si falta una variable de entorno. Transcripciones con contexto sensible sincronizadas | **Próximo ciclo** | Corregir en la fuente: sin valor por defecto, el proceso no arranca. Sacar de la sincronización |
| **Bajo** | Topología repartida en documentación. Correos. Rutas locales | **Higiene progresiva** | Reemplazar por marcadores cuando se toque el archivo por otro motivo |

Dos notas sobre los niveles.

**Un hallazgo crítico no espera al informe.** Si aparece un secreto real, se rota antes de terminar la auditoría. La auditoría sigue después.

**Un hallazgo medio no se arregla cambiando el valor.** El ejemplo clásico son los valores por defecto en el arranque de un servicio: la corrección no es reemplazar `admin` por algo mejor, es **no tener valor por defecto**. Un servicio que arranca con una contraseña adivinable es peor que un servicio que no arranca, porque el segundo se nota y el primero no.

---

## Rotar, no borrar

Es la regla que más importa de todo el documento.

> **Un secreto que estuvo sincronizado o versionado ya se fue. Moverlo de carpeta no lo invalida.**

Borrar el archivo, hacer un commit que lo quite, renombrarlo o moverlo a una carpeta de cuarentena **esconde** el secreto. No lo desactiva. El valor sigue siendo válido en el servicio que lo acepta, y sigue existiendo en:

- el historial de git, si estuvo versionado;
- los servidores del proveedor de sincronización, y sus versiones anteriores del archivo;
- cualquier otro dispositivo donde esa cuenta esté activa;
- los backups de todo lo anterior;
- las transcripciones de las conversaciones donde se lo pegó para probar algo.

El orden correcto es al revés del intuitivo:

1. **Primero rotar** — generar el valor nuevo, aplicarlo, verificar que el viejo ya no funciona.
2. **Después sacar el archivo.**

Y el criterio de éxito es explícito y comprobable: **la credencial anterior tiene que devolver 401 o 403**. Si devuelve 200, la rotación no sirvió de nada, sin importar cuántos pasos se hayan ejecutado.

El procedimiento completo está en [rotar una credencial expuesta](../06-runbooks/rotar-una-credencial-expuesta.md).

---

## Qué NO prueba un escaneo

Un escaneo limpio prueba una cosa, y sólo esa:

> **Que no haya coincidencias no prueba que no haya secretos. Prueba que no hay ninguno que coincida con esos patrones.**

Lo que un escaneo por patrones no ve:

- **Un secreto sin formato reconocible.** Una contraseña que es una frase, un token que es un UUID, una clave que es una cadena base64 sin prefijo. Ninguno tiene forma de secreto.
- **Un secreto en un archivo binario o comprimido.** PDFs, imágenes con metadatos, archivos de office, `.zip`, `.tar.gz`, bases SQLite. El escáner los salta o los lee mal.
- **Un secreto partido en dos líneas** o interpolado desde variables en tiempo de ejecución.
- **Un secreto que quedó afuera del alcance.** Fuera del árbol escaneado, arriba del límite de tamaño, en una extensión no incluida, en una carpeta excluida.
- **Un dato personal que no tiene formato.** Un nombre propio, un diagnóstico, una dirección escrita en prosa.
- **La combinación reidentificable.** Cada dato por separado es inocuo y el conjunto identifica a una persona. Ningún patrón detecta eso.

De ahí que el escaneo sea **una** de las seis compuertas de la política de publicación, no la única. La compuerta de procedencia —saber de dónde salió cada archivo— atrapa cosas que ningún patrón atrapa.

---

## Falsos positivos que vas a ver, y cómo triarlos

Un escáner sin triaje humano genera ruido que después nadie mira. Ese es el modo de falla real: no el falso negativo, sino la lista de 400 coincidencias que se cierra sin leer.

Estos cuatro son los que aparecieron en la práctica.

| Lo que enganchó | Qué era en realidad | Cómo se descarta |
|---|---|---|
| `AKIA` seguido de 16 mayúsculas y números | Un tramo dentro de un blob **base64 de una imagen** embebida en un archivo Markdown | Mirá la longitud de la línea. Si tiene miles de caracteres sin espacios y arriba dice `data:image/png;base64,`, es una imagen |
| Algo que parece un token `sk-...` | Un **slug de URL** en un enlace a documentación | ¿Está dentro de un `](https://...)`? ¿Tiene la longitud del token real del proveedor? Los tokens de verdad tienen longitud fija |
| `PGPASSWORD=$VARIABLE` en un script | Una **referencia** a una variable de entorno, no un valor | Empieza con `$`, `${`, `%`, `os.environ`, `process.env` o `$env:`. Es una referencia. Un valor literal no tiene sigilo adelante |
| Once dígitos seguidos | Once de los trece dígitos de una **marca de tiempo en milisegundos** | El patrón estaba escrito sin anclas. Con `\b\d{11}\b` no engancha. Y el formato con guiones del identificador fiscal tampoco coincide |

### El patrón detrás de los cuatro

Tres de los cuatro se descartan mirando **el contexto de la línea**, no la coincidencia. Por eso el escáner tiene que reportar ruta y número de línea: para que el triaje sea abrir el archivo y mirar, no adivinar.

El cuarto se descarta **arreglando el patrón**. Un patrón sin anclas produce coincidencias dentro de números más largos, y esa clase de ruido se repite en cada corrida hasta que alguien lo corrige.

### La consecuencia operativa

Cada corrida de escaneo termina con una decisión escrita por cada coincidencia de severidad alta: **es un secreto** o **es un falso positivo, y por esto**. Si es falso positivo recurrente, se ajusta el patrón o se agrega una exclusión con comentario.

Un escaneo cuya salida nadie tría no es un control. Es un archivo de log.

---

## Cómo encaja con el resto

| Documento | Relación |
|---|---|
| [Política de publicación](politica-de-publicacion.md) | Este documento es el **método** de su compuerta 2. La política decide qué se publica; esto verifica que lo que sale no lleve nada de más |
| [Permisos de agente](permisos-de-agente.md) | El detalle del control 9: cómo se escriben las reglas y qué protegen de verdad |
| [Rotar una credencial expuesta](../06-runbooks/rotar-una-credencial-expuesta.md) | Qué hacer cuando el control 1, 3 o 4 encuentra algo |
| [Acuerdo de trabajo con agentes](acuerdo-de-trabajo-con-agentes.md) | La regla de que toda excepción tiene dueño, motivo y vencimiento |
| [Checklist de release](checklists/checklist-de-release.md) | Los controles 1 a 4 se corren antes de cada publicación, no sólo en la auditoría periódica |

---

## Nivel de evidencia de este documento

| Afirmación | Nivel |
|---|---|
| Los nueve controles y sus comandos | Verificado (aplicados en una auditoría real, 2026-08-06) |
| El caso del control 9: 152 permisos, cero reglas de denegación, el par de entradas que entregaba el servidor | Verificado |
| Las cifras agregadas: 38 archivos con el mismo identificador fiscal, 68 MB de transcripciones | Verificado |
| Los cuatro falsos positivos | Verificado (observados durante la misma auditoría) |
| Que el escaneo por patrones no detecta secretos sin formato reconocible | Inferido — limitación estructural del método, no medida |
| Que esta secuencia de nueve controles sea suficiente para cualquier carpeta | Pendiente de verificar — se probó sobre un solo entorno |

> Última verificación: 2026-08-06
