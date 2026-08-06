# Infra y despliegue

Cómo corre esto en producción, cómo se sube un cambio de esquema sin poder deshacerlo a mano, y cuáles son los agujeros que todavía tiene.

## Criterio

En un sistema de una sola persona la infraestructura tiene un objetivo distinto al de una empresa. No se trata de alta disponibilidad ni de escalar a millones. Se trata de que **el operador pueda dormir**: que las cosas se recuperen solas, que los errores avisen, y que cualquier cambio se pueda deshacer sin improvisar a las dos de la mañana.

De ahí salen cuatro criterios.

**1. La superficie que no existe no se audita.**
Cada puerto publicado es una decisión de seguridad que hay que sostener para siempre. Si un servicio sólo lo consumen otros contenedores, no tiene por qué escuchar en la interfaz pública. Es la misma lógica que la ausencia de `DELETE` en la API: la capacidad que no existe no se explota.

**2. Un cambio que no se puede deshacer no se aplica.**
Antes de tocar producción tiene que existir el artefacto de vuelta, y tiene que estar guardado en algún lado, no en la cabeza de nadie.

**3. Backup no verificado es esperanza, no backup.**
Un archivo `.sql.gz` de 400 MB en un disco no prueba nada. Prueba algo un restore que se hizo y funcionó. Esta es, en la mayoría de los sistemas chicos, la distancia entre lo que se cree y lo que hay.

**4. El runtime es lo que hay que verificar, no el repositorio.**
El repo dice qué debería estar. Sólo el servidor dice qué está. Confundirlos es una clase de bug con nombre: drift.

### Tabla de decisión

| Señal | Conviene |
|---|---|
| Un servicio lo consume otro contenedor | Red interna, **sin publicar puerto** |
| Un servicio lo consume internet | Reverse proxy con TLS, puerto sólo en el proxy |
| Una base de datos, siempre | Loopback o red interna. Nunca `0.0.0.0` |
| Un cambio de esquema | Migración numerada, en transacción, con verificación posterior |
| Un cambio de workflow | Export previo guardado como artefacto de rollback |
| Un secreto | Variable de entorno o gestor de credenciales; **nunca** en el repo ni en un prompt |
| Un backup | Con lock, con manifest, y con un procedimiento de restore escrito y ensayado |

## En este sistema

VPS Hostinger KVM4, pago anual (decisión **D-3** del 2026-07-14). Un solo dominio (**D-4**). IP y hostnames no se publican.

### Contenedores

| Contenedor | Imagen / rol |
|---|---|
| `n8n-n8n-1` | `docker.n8n.io/n8nio/n8n:2.31.5` — runtime de orquestación |
| `n8n-traefik-1` | Reverse proxy con TLS |
| `praxia-memory-db` | `postgres:16` — memoria y finanzas |

Volúmenes: `n8n_data`, `traefik_data`.

Detalle importante: **n8n usa SQLite para su propio estado** (workflows, credenciales, ejecuciones). El PostgreSQL es para memoria y finanzas, y está separado a propósito. Las consecuencias operativas están en [02](02-cuando-uso-n8n.md): el backup de n8n es el backup de un archivo, con su procedimiento propio, construido el 2026-07-15 junto con `RECOVERY.md`.

### Traefik con TLS y sin puertos publicados

Traefik termina TLS y rutea por nombre de host. **Ningún contenedor de aplicación publica puertos al host.** PostgreSQL escucha en `127.0.0.1:5433` y está en la red `n8n_default`, de modo que n8n lo alcanza por nombre de servicio y nadie más lo alcanza.

```yaml
# SINTÉTICO — ilustra el patrón, no es el compose real
services:
  proxy:
    image: traefik:v3
    ports:
      - "80:80"
      - "443:443"          # el ÚNICO servicio con puertos publicados
    networks: [interna]

  app:
    image: ejemplo/app:1.0
    # sin "ports": sólo alcanzable desde la red interna
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.tls=true"
    networks: [interna]

  db:
    image: postgres:16
    ports:
      - "127.0.0.1:5433:5432"   # loopback: para psql local, no para internet
    networks: [interna]

networks:
  interna:
```

El `127.0.0.1:` adelante del mapeo es la línea más importante del archivo. Sin ese prefijo, Docker publica en todas las interfaces y —esto sorprende a mucha gente— **crea reglas de iptables que pueden pasar por encima del firewall del host**. Un `5432:5432` distraído es una base de datos en internet.

SSH quedó **cerrado tras el despliegue verificado del 2026-07-23**. La operación cotidiana no requiere shell en el servidor.

### Backups

Diarios, en `<ruta-de-despliegue>/backups/{daily,weekly,monthly}`, con tres piezas:

- **Lock** — impide que dos corridas se pisen. Sin lock, una corrida lenta que se solapa con la siguiente produce archivos truncados que parecen válidos.
- **`manifest.json`** — qué contiene, cuándo se hizo, con qué versión de esquema. Un backup sin manifest obliga a abrirlo para saber qué es.
- **`restore_check.sh`** — verificación automática.

El precedente que lo justifica: el **2026-07-27**, la aplicación del DDL v3.1 al VPS se hizo con backups y **SHA-256 verificados**. Un hash es la diferencia entre "hice un backup" y "puedo demostrar que el backup es el que creo que es".

**Y acá va el hueco, declarado:** no hay off-site y no hay restore drill demostrado. Los backups están en el mismo servidor que protegen. Un backup local protege contra un error de operación —un `UPDATE` sin `WHERE`— y no protege contra la pérdida del servidor. Es un riesgo abierto y conocido, no un descuido descubierto por otro.

### Cómo se aplica una migración

El procedimiento completo, tal como se ejecutó en la puesta al día del **2026-08-05** (v4.4 → v4.6, después v4.7 y v4.8):

```bash
# SINTÉTICO — el procedimiento, con valores de ejemplo

# 1. Backup con verificación de integridad
pg_dump -Fc -d praxia_memory -f <ruta-de-despliegue>/backups/pre-v46.dump
sha256sum <ruta-de-despliegue>/backups/pre-v46.dump | tee pre-v46.sha256

# 2. Línea base: contar antes
psql -d praxia_memory -Atc "
  select count(*) from information_schema.tables
  where table_schema = 'praxia_finanzas';"     # -> 25

# 3. Aplicar en transacción, abortando al primer error
for m in 044_deudas.sql 045_deuda_pagos.sql 046_obligaciones.sql; do
  psql -v ON_ERROR_STOP=1 -1 -d praxia_memory -f "migrations/$m" || exit 1
done

# 4. Verificar no-regresión: contar después
psql -d praxia_memory -Atc "
  select count(*) from information_schema.tables
  where table_schema = 'praxia_finanzas';"     # -> 35

# 5. Comparar valores que NO debían cambiar
psql -d praxia_memory -f checks/saldos_snapshot.sql > post.txt
diff pre.txt post.txt
```

Cuatro decisiones dentro de esos cinco pasos:

**`ON_ERROR_STOP=1` con `-1`.** Por defecto `psql` sigue ejecutando después de un error y te deja el esquema a mitad de camino: el peor estado posible, porque el sistema arranca y falla más tarde en un lugar sin relación. Con las dos flags, la migración entra completa o no entra.

**Contar tablas antes y después.** Verificación cruda y efectiva: 25 → 35. Si la migración declara que crea diez tablas y el conteo no da, algo falló en silencio.

**Comparar valores que no debían cambiar.** Una migración estructural no debería mover un saldo. Si lo movió, hay un `UPDATE` que no debería estar. Esta verificación —chequear lo que **no** tiene que cambiar— es la que más veces encuentra errores reales, y la que más se saltea.

**El rollback es un artefacto, no un plan.** El dump con su SHA-256 existe antes de empezar. La misma disciplina se usó en los workflows: el Memory Gate del 2026-07-20 se aplicó **con rollback previo guardado**, y hay un backup del orquestador etiquetado "antes de Agente Papers" del 2026-07-16.

Un plan de rollback que dice "revertir los cambios" no es un plan. Un archivo con su hash sí.

### El incidente de drift

El **2026-08-05** se descubrió que producción estaba **tres migraciones atrás desde el 31/07**. Cinco días. La causa, textual:

> *"nadie había mirado el servidor, solo el repositorio"*

Vale desarmarlo porque es un modo de falla que se repite en cualquier sistema donde el runtime no se despliega desde el repo:

- **No hubo error.** Nada falló, nada alertó. La API andaba, el dashboard andaba. Las funcionalidades nuevas simplemente no estaban.
- **El repo estaba perfecto.** Migraciones escritas, numeradas, revisadas, commiteadas.
- **Faltaba el paso de verificación.** Nadie comparaba `schema_migrations` del servidor contra los archivos del repo.
- **El descubrimiento fue casual**, en una inspección, no por una alerta.

El arreglo estructural no es "acordarse de mirar". Es un chequeo automático que compare ambos lados y avise, y a más largo plazo, invertir la relación que describe el TO-BE:

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Hoy es al revés. Ese es el problema de fondo, y los 125 workflows de laboratorio en producción son el mismo problema visto desde otro ángulo.

Un antecedente del mismo linaje: el **2026-07-28**, checkpoint crítico —*"No hay repo git. 3275 líneas de JS + 33 migraciones SQL, sin control de versiones"*— y se hizo el commit inicial. Un mes de trabajo sin versionar. Se corrigió, se documentó, y aparece acá porque esconderlo haría inútil el resto del documento.

### Riesgos abiertos declarados

Estos están publicados a propósito. Un inventario de riesgos con casilleros vacíos no es un inventario.

| # | Riesgo | Estado |
|---|---|---|
| 1 | Producción usada como laboratorio: 125 workflows de laboratorio junto a 25 activos | Inventariado el 2026-07-25 (73 clase A, 4 clase B, 2 clase C). Sin sanear |
| 2 | Sin separación de ambientes (dev / staging / prod) | Abierto. Es la causa raíz de 1, 4 y 5 |
| 3 | Backups sin off-site y sin restore drill | Abierto |
| 4 | Drift repo↔servidor | Detectado y corregido el 2026-08-05. Sin chequeo automático todavía |
| 5 | El `errorWorkflow` global se llama `[TEST]` | Abierto. Cosmético |
| 6 | Dos proyectos resuelven el mismo problema con stacks distintos | Abierto (AI-Command-Center vs. Arquitecto-IA-Redes) |
| 7 | `.env` con token real en carpeta sincronizada a la nube | Requiere rotación |
| 8 | Defaults inseguros en el MCP (`JWT_SECRET`, password de owner) | Abierto. Sólo aplican si faltan las variables. Ver [04](04-cuando-uso-un-mcp.md) |
| 9 | Repositorio de gobernanza con archivos en stage y cero commits | Abierto |

El 2 es el que genera a los otros. Sin ambientes separados, probar algo obliga a hacerlo en producción; el laboratorio se acumula donde vive lo que funciona; y la fuente de verdad se invierte. Todo lo demás es consecuencia.

La conclusión de la línea base de gobernanza (2026-08-03) apunta ahí:

> *"La próxima mejora de mayor valor es convertir evidencia dispersa en fuentes de verdad, ambientes separados y releases trazables antes de expandir funcionalidades."*

Es una decisión de secuencia, y coincide con la regla que ordena el proyecto entero: *"Sin orden no hay sistema, solo experimentos. El error a evitar no es técnico, es de secuencia."*

### Lo que todavía no existe

- **Monitoreo de disponibilidad.** No hay uptime check externo. Si el VPS se cae de madrugada, se sabe cuando alguien escribe por Telegram. `[PENDIENTE DE VERIFICAR]`
- **Métricas de recursos.** No hay serie temporal de CPU, memoria ni disco. `[PENDIENTE DE VERIFICAR]`
- **Rotación de logs con política escrita.** `[PENDIENTE DE VERIFICAR]`
- **CI/CD.** Los despliegues son manuales con procedimiento escrito, no automáticos.

Lo último es defendible en esta escala: automatizar un despliegue que ocurre una vez por semana, sin ambiente de staging donde probar la automatización, agrega más riesgo del que saca. El orden correcto es ambientes primero, automatización después.

## Regla

No publiques puertos que nadie externo necesita, aplicá cada migración en transacción con `ON_ERROR_STOP=1` y verificá contra el servidor, no contra el repo. Y si el rollback no es un archivo con su hash, todavía no tenés rollback.

> Última verificación: 2026-08-05
