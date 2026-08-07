# Sacar datos operativos de la bóveda sincronizada

Cómo se limpia una carpeta de notas que, sin que nadie lo decidiera, terminó guardando la dirección del servidor de producción y cien megas de volcados de workflows.

> **In English** — A private notes vault that syncs to consumer cloud storage tends to accumulate two
> things nobody ever chose to put there: operational coordinates (the production host written
> literally into runbooks and diagnostic scripts) and bulk dumps (full workflow exports, one-off SQL,
> throwaway diagnostics). Neither is a leaked secret, so the "rotate, don't delete" rule does not
> apply — but both widen the blast radius of any single sync account compromise, and both travel
> silently into every agent session that reads the folder. This runbook describes the fix as one
> idempotent, dry-run-by-default script: detect the host, move it to a single config file outside the
> synced folder, replace the literal with a placeholder in prose, parameterise the scripts so they
> read from that config and fail loudly without it, prune the agent permission rules that authorise
> open-ended commands against that host, and cold-archive the dumps. Nothing is deleted; everything
> modified is backed up first. The design principle is that the host belongs in exactly one place,
> and that place is not the folder that syncs.

<!-- fin del resumen en inglés -->

---

## Por qué

Una bóveda de notas no se diseña: se acumula. Después de unos meses de trabajo real, la nuestra tenía dos cosas que nadie decidió poner ahí.

**Coordenadas operativas.** La dirección del servidor de producción escrita literal en veintisiete archivos: runbooks, informes, scripts de diagnóstico y — el peor caso — el archivo de permisos del agente, noventa y cinco veces, siempre en la forma `ssh root@<host>`.

**Volcados.** Ciento veinticuatro megas de exportaciones completas de workflows de n8n y scripts de una sola vez. Sin claves adentro: lo verificamos. Pero con mil trescientas referencias de credencial, setecientos identificadores de webhook y doscientos treinta chat_id.

Nada de eso es un secreto filtrado. La regla de [rotar en vez de borrar](rotar-una-credencial-expuesta.md) no aplica: no hay valor que invalidar. Pero las dos cosas tienen el mismo defecto. Están dentro de una carpeta que sincroniza a un servicio de nube de consumo, y que además lee cualquier agente que trabaje sobre el proyecto. Si esa cuenta se compromete, el atacante no encuentra una credencial — encuentra un mapa.

La corrección no es dramática. Es aburrida, y por eso hay que automatizarla: lo que depende de que alguien se acuerde, tarde o temprano no se hace.

---

## El principio

**El host vive en un solo lugar, y ese lugar no es la carpeta que sincroniza.**

Un archivo de configuración fuera del área sincronizada, o una variable de entorno. Los scripts leen de ahí. La prosa usa un marcador. Si el archivo no está, el script **falla fuerte** con un mensaje que dice exactamente qué falta — la misma disciplina que aplicamos al servidor MCP, que no arranca si le falta una variable en vez de arrancar con un valor por defecto.

Fallar fuerte importa más de lo que parece. Un script que se queda callado y usa un valor viejo es peor que uno que no arranca.

---

## El procedimiento

Un script, cinco pasos, en este orden. Por defecto **no toca nada**: informa lo que haría.

```powershell
# 1. Ver qué haría
powershell -ExecutionPolicy Bypass -File .\ARCHIVO-FRIO.ps1

# 2. Ejecutarlo
powershell -ExecutionPolicy Bypass -File .\ARCHIVO-FRIO.ps1 -Aplicar
```

### Paso 1 — Detectar el host y sacarlo de la carpeta

El script recorre la bóveda buscando direcciones IPv4, descarta las privadas, las reservadas y las de resolutores públicos conocidos, y se queda con la que más se repite. Si ninguna aparece al menos tres veces, no hay nada que limpiar y lo dice.

El valor detectado se guarda en un archivo de configuración fuera del área sincronizada. Si ya existe con otro valor, **no lo pisa**: avisa y sigue. Adivinar cuál de dos hosts es el bueno no es trabajo de un script.

### Paso 2 — Marcador en la prosa

En los `.md` y `.txt`, el literal se reemplaza por `<IP-VPS>`. Riesgo cero: la documentación no se ejecuta. Un runbook que dice `ssh root@<IP-VPS>` se entiende igual, y quien lo siga ya tiene el valor en su configuración.

### Paso 3 — Parametrizar los scripts

Acá hay que tener cuidado, porque un reemplazo ciego rompe herramientas que funcionan. El script sólo toca el patrón que reconoce — `'root@<host>'` como elemento de una lista de argumentos — y le antepone al archivo el bloque que resuelve el valor:

```powershell
$praxiaVpsHost = $env:PRAXIA_VPS_HOST
if (-not $praxiaVpsHost) {
    $praxiaVpsConf = Join-Path $env:USERPROFILE '.praxia\vps.txt'
    if (Test-Path $praxiaVpsConf) { $praxiaVpsHost = (Get-Content $praxiaVpsConf -Raw).Trim() }
}
if (-not $praxiaVpsHost) {
    throw 'Falta el host del VPS. Defini PRAXIA_VPS_HOST o crea %USERPROFILE%\.praxia\vps.txt'
}
```

Si después del reemplazo todavía queda el literal en algún lado, o si el patrón no coincide, **deja el archivo como estaba y avisa**. Y después de escribir, vuelve a parsear el archivo: si quedó con error de sintaxis, lo dice y señala el respaldo.

Ese último control no es paranoia. En este proyecto un script de limpieza ya escribió una vez un BOM en un archivo de permisos y lo dejó ilegible para el agente. Se detectó verificando en disco, no leyendo la salida del script.

### Paso 4 — Podar los permisos abiertos

El hallazgo incómodo de la auditoría. Entre las reglas de permiso del agente había varias de esta forma:

```
Bash(ssh -i ~/.ssh/<clave> root@<host> ' *)
```

Un asterisco al final autoriza **cualquier continuación**. Esa regla, leída literalmente, dice "ejecutar lo que sea como root en producción, sin preguntar". No se puso ahí con mala intención: se acumuló aprobando comandos puntuales durante sesiones largas, y el prefijo común se fue acortando hasta quedar en nada.

El script quita las reglas de la lista de permitidos que mencionan el host **y** terminan en comodín. Deja las puntuales, que son largas y específicas. Con `-PodarTodo` saca todas las que mencionan el host.

Quitar una regla de la lista de permitidos **no prohíbe nada**: el comando vuelve a pedir confirmación cuando haga falta. El costo es una pregunta más; el beneficio es que ya no hay una llave maestra escrita en un archivo que sincroniza. Ver [permisos de agente](../05-gobernanza/permisos-de-agente.md) para la sintaxis completa y sus trampas.

### Paso 5 — Archivo frío

Los volcados se **mueven**, no se borran, a una carpeta fechada fuera del área sincronizada. Donde estaban queda un `LEEME-MOVIDO.md` que dice qué había, dónde está ahora y por qué se movió. Sin esa nota, dentro de tres meses alguien abre la carpeta vacía y asume que se perdió algo.

El script además lista otras carpetas con más de diez megas de volcados **sin tocarlas**, para que la decisión la tome una persona.

Para no volver a acumular: los workflows se versionan con [la herramienta de versionado](../../tools/n8n-versionado/), que exporta, normaliza y verifica sin dejar basura.

---

## Lo que el script nunca hace

- **No borra.** Mueve, respalda y avisa.
- **No imprime valores sensibles.** Los hosts se muestran enmascarados; los conteos van completos.
- **No pisa configuración existente.** Si encuentra un valor distinto al que detectó, avisa y sigue.
- **No toca lo que no reconoce.** Un archivo con el host en un contexto inesperado se reporta para revisión manual.

---

## Verificar

Después de correrlo, tres comprobaciones, en disco y no en pantalla:

1. Abrir uno de los documentos tocados y confirmar que dice el marcador.
2. Correr uno de los scripts parametrizados y confirmar que sigue funcionando.
3. Confirmar que el archivo de permisos sigue siendo JSON válido y sin BOM.

Y una cuarta, la más importante y la que no automatiza ningún script: **el archivo frío no es un respaldo.** Está en el mismo disco. Si esos volcados importan, tienen que ir a otro lado — es el bloqueante de respaldos fuera del sitio que sigue abierto en el [roadmap](../../ROADMAP.md).

---

## Qué hace que esto dure

**La corrección es un script, no una lista de pasos.** Una lista de veintisiete archivos para editar a mano se hace una vez y nunca más.

**Simulación por defecto.** Un script destructivo cuyo modo natural es "contame qué harías" se corre sin miedo, y por eso se corre.

**Idempotente.** La segunda corrida reporta cero cambios y cero errores. Se puede volver a pasar cada vez que la bóveda crece, que es exactamente cuando hace falta.

> Última verificación: 2026-08-06 — probado contra una bóveda de prueba, en simulación y en aplicación, dos corridas seguidas.
