# Política de publicación

Qué se puede publicar de un sistema privado, qué no, y cómo se revisa antes de que sea tarde.

Esta política gobierna todo lo que sale de la infraestructura privada hacia cualquier lugar público: este repositorio, un posteo, una charla, un portfolio, un ejemplo en una propuesta comercial.

---

## La regla raíz

> *"Los artefactos públicos deben enseñar un principio reutilizable sin exponer el sistema privado del que salió la lección."*

Todo lo demás son consecuencias de esa frase. Si un artefacto no enseña nada, no vale la pena publicarlo. Si enseña algo pero expone el sistema, hay que reescribirlo hasta que enseñe lo mismo sin exponer nada. Si no se puede, no se publica.

La aplicación de esta regla a este proyecto quedó como [ADR-009: publicar el método, no el sistema](../04-decisiones/adr-009-publicar-el-metodo-no-el-sistema.md).

---

## Permitido

- **Plantillas y checklists originales.** Escritas acá, no copiadas.
- **Ejemplos ficticios.** Inventados para ilustrar, y declarados como inventados.
- **Datasets sintéticos.** Generados, con la forma del dato real y ninguno de sus valores.
- **Diagramas conceptuales.** Arquitectura, flujos, máquinas de estado, modelos de datos.
- **Implementaciones clean-room.** Código escrito de nuevo a partir del diseño, no copiado del privado.
- **Referencias públicas verificadas, con atribución.** Lo de otros se cita, no se absorbe.
- **Esquemas SQL con nombres de tablas y columnas.** El nombre de una tabla no es un secreto; su contenido sí.
- **Contratos, estados de máquina, decisiones y cronología.** Es el método, y es lo que vale.
- **Métricas agregadas.** "554 tests", "217 workflows", "343 de 362 ejecuciones exitosas".

---

## Prohibido

| Categoría | Ejemplos |
|---|---|
| **Secretos y credenciales** | Tokens, API keys, contraseñas, claves privadas, `JWT_SECRET`, rutas de claves SSH, IDs de credencial de n8n |
| **Datos personales, financieros, médicos o fiscales reales** | Montos, comprobantes, CUIT, saldos, diagnósticos, nombres y edades de familiares |
| **Comunicaciones y documentos privados** | Mails, chats, eventos de calendario, archivos de Drive, contenido de la memoria |
| **Backups, logs y exports crudos** | Dumps de base, exports de workflow sin sanitizar, historiales de ejecución |
| **Identificadores internos y topología explotable** | IP del VPS, hostnames reales, `chat_id`, nombres de contenedor con puerto, rutas absolutas del servidor |
| **Afirmaciones sin evidencia** | Declarar pruebas, adopción, clientes o publicación que no ocurrieron |

La última fila es la que más se subestima. Inventar un cliente o inflar un número no es un problema de privacidad: es un problema de veracidad, y contamina todo lo demás. Si el 90% del documento es cierto y verificable, el 10% inventado hace que el 100% deje de ser confiable.

---

## Las seis compuertas de revisión

Se pasan en orden. Cualquiera que falle detiene la publicación.

### 1. Procedencia

**¿De dónde salió esto?**

Cada artefacto tiene que tener origen declarado: escrito de cero, reconstruido a partir del diseño, o derivado de un artefacto privado. El tercer caso es el peligroso y exige el paso por la compuerta 2 con más cuidado.

Un archivo cuyo origen nadie recuerda no se publica. La duda es un no.

### 2. Escaneo de secretos y datos personales

**¿Contiene algo que no debería?**

Búsqueda explícita, no lectura casual. Como mínimo: tokens y claves, IPs y hostnames, correos, identificadores de chat, IDs de credencial, rutas absolutas del servidor, nombres de personas, números que podrían ser montos o documentos.

Se hace sobre el artefacto final, no sobre el borrador. Y se hace aunque el artefacto sea "obviamente" limpio: el `.env` con un token dentro de una carpeta sincronizada a la nube también era obviamente limpio hasta que se lo buscó.

### 3. Licencia

**¿Se puede publicar legalmente?**

Licencia propia declarada. Nada de terceros sin permiso o sin licencia compatible. Fragmentos de documentación ajena, citados y atribuidos, no absorbidos.

### 4. Exactitud técnica

**¿Es cierto?**

Cada afirmación con su nivel de evidencia: Verificado, Confirmado por el responsable, Inferido, Pendiente de verificar, Historia incompleta.

Un hueco se declara como hueco:

> *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

### 5. Aprobación humana

**¿Alguien decidió publicarlo?**

Una persona, con nombre, que leyó el artefacto final. No un agente, no un pipeline, no una aprobación heredada de una versión anterior.

Es la aplicación de **D-7**: publicar es una de las cuatro acciones que exigen un humano.

### 6. Revisión de release

**¿Está completo y es coherente con el resto?**

Enlaces que funcionan, versión declarada, fecha de corte, coherencia con los otros documentos publicados. Un documento que contradice a otro publicado es un problema de exactitud, no de estilo.

---

## Cambiar un nombre no es anonimización

> *"Cambiar el nombre de una persona no es anonimización suficiente."*

Reemplazar un nombre propio por otro no protege a nadie si el documento igual dice que esa persona convive con el autor, cuál es su profesión y qué proyecto comparten. La reidentificación no necesita el nombre: necesita la combinación de atributos.

Lo mismo con los datos técnicos. Ocultar la IP y dejar el hostname, el proveedor, la región y el plan contratado es no ocultar nada.

Lo que sí funciona:

| En vez de | Poné |
|---|---|
| Un nombre cambiado | El **rol**: "el dueño del sistema", "el segundo usuario" |
| Un monto disfrazado | Un valor **sintético declarado como sintético**, o una métrica agregada |
| Un hostname alterado | `<HOST>`, o directamente la descripción: "el subdominio del dashboard" |
| Un caso real "levemente" modificado | Un caso **inventado** que ilustre el mismo principio |
| Un dato que no tenés | `[PENDIENTE DE VERIFICAR]` |

La prueba práctica: **si alguien que conoce al autor puede reconstruir el dato real leyendo el artefacto, la anonimización falló.**

---

## Procedimiento de corrección

Si aparece contenido sensible ya publicado. El orden importa: primero se corta la exposición, después se investiga.

### 1. Contener — minutos

- Despublicar o hacer privado el artefacto. **Ya.** No se edita en vivo con el contenido expuesto.
- Si es un repositorio público: hacerlo privado antes de tocar el historial.

### 2. Evaluar la exposición — primera hora

- ¿Qué se expuso exactamente?
- ¿Desde cuándo? Fecha del commit o de la publicación.
- ¿Se puede saber si alguien lo vio? Vistas, clones, forks, archivos en caché.
- **Asumir que fue visto.** Un repositorio público es indexable, clonable y archivable por terceros en minutos. La ausencia de evidencia de acceso no es evidencia de ausencia.

### 3. Invalidar el secreto — primeras horas

Si lo expuesto es un secreto, **el secreto ya no vale**, aunque el artefacto haya durado cinco minutos:

- Rotar tokens, claves y contraseñas.
- Revocar credenciales OAuth.
- Cambiar lo que se pueda cambiar; si algo no se puede rotar, tratarlo como comprometido de forma permanente.

Este paso no es opcional y **no depende del resultado del paso 2**. Borrar el archivo no invalida el token: sólo lo esconde.

### 4. Limpiar el rastro

- Reescribir el historial de git si hace falta. Un archivo borrado en un commit posterior sigue en el historial.
- Si hubo fork o clon, el historial ajeno no se puede limpiar. Refuerza el paso 3.
- Pedir la eliminación de cachés donde se pueda.
- Verificar que la versión limpia es efectivamente la única disponible.

### 5. Notificar

- Si hay datos de un tercero, **al tercero**. No hacerlo por vergüenza es agravar el problema.
- Si hay obligación legal aplicable, cumplirla.
- Al dueño del sistema, siempre.

### 6. Documentar

Un `INC-XXXX` con línea de tiempo, causa raíz, alcance, acciones y control nuevo. Ver la [plantilla de incidente](plantillas/INCIDENTE.md).

### 7. Agregar el control

Un incidente sin control nuevo se repite. Ejemplos: un patrón nuevo en el escaneo de la compuerta 2, un archivo agregado a `.gitignore`, un paso agregado al checklist de release.

---

## Cómo se sanitizó este repositorio

Los pasos concretos, para que el procedimiento se pueda auditar y repetir.

### 1. Se definió una fuente de verdad única antes de escribir nada

Se produjo un documento de hechos verificados —extraído de una inspección real del sistema el 2026-08-05— y **toda la documentación se escribió únicamente a partir de él**. No se consultó la bóveda privada durante la redacción.

El efecto: lo que no está en la fuente no puede aparecer en el repositorio, porque quien escribe no lo tiene. La sanitización deja de depender de la disciplina de cada frase y pasa a ser una propiedad del proceso.

### 2. Se escribió la lista de prohibiciones antes que el primer archivo

Enumerada y explícita: IP del VPS, hostnames reales, `chat_id` de Telegram, correos, IDs de credencial de n8n, rutas de claves SSH, nombres y edades de familiares, CUIT, datos financieros reales, tokens.

Prohibir antes de escribir es barato. Revisar después es caro y se hace mal.

### 3. Se decidió qué sí se publica, con el mismo detalle

Arquitectura, esquemas SQL con nombres de tablas y columnas, contratos, máquinas de estado, decisiones, cronología, métricas agregadas.

Una política que sólo dice "no" produce documentación vacía. La lista de lo permitido es lo que hizo posible que el repositorio tenga contenido real.

### 4. El usuario de GitHub quedó como literal

Se escribe `bioqruizdiazaldo-cmd` en todos los enlaces, y se reemplaza al publicar. Un solo punto de sustitución en lugar de una identidad esparcida en cuarenta archivos.

### 5. Todos los ejemplos son sintéticos y lo dicen

Los archivos SQL llevan el aviso arriba:

> *"Reconstrucción didáctica sintética. No son dumps de producción."*

Y aclaran el alcance de la fidelidad: nombres de tablas, columnas, estados y funciones fieles al sistema real; tipos exactos, datos de ejemplo y parte de los constraints, reconstrucción razonable.

Decir "es sintético" sin decir **en qué** es sintético deja al lector adivinando qué puede confiar.

### 6. El SQL se reescribió, no se copió

Implementación clean-room: los seis archivos de [`artifacts/sql/`](../../artifacts/sql/) se escribieron de nuevo a partir del diseño verificado. Enseñan el mismo principio —la invariante en la base, el rol sin `DELETE`, la consulta en transacción de solo lectura— sin ser el código de producción.

### 7. Los IDs de workflow se omiten o se abrevian

Aunque son opacos y ya no dan acceso, se omiten salvo cuando aportan trazabilidad real. Criterio general: si un identificador no le enseña nada al lector, no está.

### 8. La deuda técnica se publica, no se esconde

Las diez deudas abiertas —producción como laboratorio, sin ambientes, backups sin off-site, drift de cinco días, `[TEST]` en el `errorWorkflow`, el `.env` con token, los defaults inseguros del MCP— están escritas con nombre y fecha.

Dos razones. La honesta: es lo que hace creíble al resto. La operativa: una deuda escrita se arregla; una deuda escondida se arrastra.

Con un límite: se publica **que existe** la deuda, no **cómo explotarla**. "Hay defaults inseguros en el servidor MCP si faltan las variables de entorno" es un hallazgo. Dar los valores sería un exploit.

### 9. Cada documento declara su nivel de evidencia

Tabla al final, con las cinco etiquetas. Un lector puede saber, frase por frase, qué se midió y qué se dedujo.

### 10. Revisión final contra las seis compuertas

Antes de publicar: procedencia declarada, escaneo de secretos, licencia, exactitud con niveles de evidencia, aprobación humana con nombre, y revisión de coherencia entre documentos.

### Lo que quedó afuera a propósito

| Se omitió | Por qué |
|---|---|
| El contenido concreto de los skills fiscales (`arca-regularizacion-monotributo`, `arba-regularizacion-iibb`) | Se publica el método, no el procedimiento fiscal concreto |
| Los `chat_id`, los correos y los nombres de familiares | Prohibido, sin excepción |
| La IP, el hostname y la topología de red | No enseña nada y ayuda a mapear el sistema |
| Los IDs de credencial de n8n | Identificador interno, sin valor didáctico |
| Los montos, saldos y comprobantes | Dato personal financiero |
| Los valores de los defaults inseguros del MCP | Se declara el hallazgo, no el exploit |

---

## Antes de publicar cualquier cosa

Tres preguntas. Si alguna respuesta es incómoda, no está listo.

1. **¿Qué enseña esto?** Si la respuesta es "que hice algo", no se publica. Un artefacto público es material didáctico, no un trofeo.
2. **¿Qué revela?** Recorrer las seis categorías prohibidas de una en una, no de memoria.
3. **¿Sería un problema dentro de cinco años?** Los datos personales no caducan, y el repositorio queda.

---

## Nivel de evidencia de este documento

| Afirmación | Nivel |
|---|---|
| Regla raíz, listas de permitido y prohibido, las seis compuertas, la nota sobre anonimización | Verificado (política existente, 2026-08-03) |
| Los diez pasos de sanitización de este repositorio | Verificado (aplicados en esta publicación) |
| El procedimiento de corrección en siete pasos | Inferido (ampliación; no se ejecutó todavía sobre un incidente de publicación) |
| Que ningún dato prohibido quedó en el repositorio | Confirmado por el responsable, pendiente de escaneo automatizado final |

> Última verificación: 2026-08-05
