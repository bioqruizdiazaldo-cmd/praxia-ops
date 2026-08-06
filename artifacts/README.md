# Artefactos

Acá viven las piezas concretas del sistema —SQL, estructura de workflows, prompts y contrato de API— reescritas para poder publicarse sin exponer la infraestructura de la que salieron.

---

## Advertencia, primero

> **Estos artefactos son representaciones didácticas. No son dumps de producción.**
>
> Ningún archivo de esta carpeta fue exportado del sistema real y después limpiado. Todos fueron **escritos de nuevo**, fieles al diseño y a los nombres de tablas, columnas, estados y contratos verificados, pero con valores, datos y ejemplos **sintéticos**.
>
> Un archivo puede ser correcto y ejecutable sin ser el archivo que corre en el VPS. Eso es exactamente lo que son estos.

La regla raíz de la política de publicación del proyecto:

> *"Los artefactos públicos deben enseñar un principio reutilizable sin exponer el sistema privado del que salió la lección."*

---

## Qué hay acá

| Carpeta | Contenido | Naturaleza |
|---|---|---|
| [`sql/`](sql/) | Seis archivos SQL para PostgreSQL 16: esquema de memoria, consulta full-text, núcleo financiero, invariantes y triggers, vistas de lectura, roles y permisos | Reconstrucción didáctica ejecutable |
| [`workflows-n8n/`](workflows-n8n/) | Plantilla de manifiesto de workflow, estructura nodo por nodo del orquestador y del buscador, contrato de subworkflow | Descripción estructural, sin JSON exportado |
| [`prompts/`](prompts/) | Prompt de sistema del orquestador reconstruido y comentado, y los patrones de prompt reutilizables | Reconstrucción sintética |
| [`openapi/`](openapi/) | Descripción del contrato de la API financiera y un fragmento OpenAPI 3.1 sintético | Descripción + fragmento propio |

---

## Cómo fue sanitizado

El procedimiento aplicado a cada artefacto, en este orden:

### 1. Reescritura, no limpieza

Ningún artefacto salió de un export. Se partió de la descripción verificada del diseño —nombres de tablas, columnas, estados, contratos, reglas— y se escribió código nuevo. Esto elimina de raíz el riesgo de que quede un resto en un campo que nadie miró.

### 2. Eliminación de identificadores de infraestructura

Fuera de todo artefacto publicado:

- IP y hostnames del VPS.
- Nombres de dominio de los servicios.
- IDs de credenciales de n8n (se usan **referencias simbólicas**: `CRED_TELEGRAM_BOT`, `CRED_PG_MEMORIA`).
- Rutas de claves SSH y de volúmenes.
- Puertos y topología explotable.

### 3. Eliminación de datos personales

Fuera: `chat_id` de Telegram, direcciones de correo reales, nombres y edades de familiares, CUIT, datos fiscales, saldos y montos reales, IDs de workflow cuando no aportan nada.

### 4. Sustitución por datos sintéticos declarados

Cada ejemplo lleva valores inventados y **dice que son inventados**. Los perfiles de ejemplo son `PERFIL_PERSONAL` y `PERFIL_PROFESIONAL`; los montos son redondos; las fechas caen dentro del período documentado; los tokens son literales del tipo `TOKEN_DE_EJEMPLO`.

Vale la advertencia del propio proyecto:

> *"Cambiar el nombre de una persona no es anonimización suficiente."*

Por eso no se cambiaron nombres: se cambiaron los datos.

### 5. Escaneo de secretos

Búsqueda de patrones de credenciales, claves privadas, tokens y cadenas de conexión sobre el resultado final, antes de publicar.

### 6. Verificación técnica

Los archivos SQL se revisaron para que sean **válidos para PostgreSQL 16 y ejecutables de corrido en orden** (`01` a `06`). Preferimos claridad sobre exhaustividad: falta detalle que existe en producción, y lo que está es correcto.

### 7. Aprobación humana

Última compuerta. Un artefacto no se publica porque el proceso lo aprobó: se publica porque una persona lo miró y dijo que sí.

Las seis compuertas de revisión del proyecto son: procedencia · escaneo de secretos y datos personales · licencia · exactitud técnica · aprobación humana · revisión de release.

---

## Qué está permitido y qué no

**Permitido publicar:** plantillas y checklists originales, ejemplos ficticios, datasets sintéticos, diagramas conceptuales, implementaciones clean-room, referencias públicas verificadas con atribución, y —en este proyecto— nombres de tablas, columnas, estados de máquina, contratos y decisiones.

**Prohibido:** secretos y credenciales; datos personales, financieros, médicos o fiscales reales; mails, chats, calendarios o documentos privados; backups, logs y exports crudos; identificadores internos, direcciones o topología explotable; y afirmar pruebas, adopción o publicación sin evidencia.

---

## Cómo usar estos artefactos

Sirven para tres cosas:

1. **Leer el diseño.** Un esquema con `COMMENT ON` en cada tabla explica más rápido que un documento aparte.
2. **Copiar patrones.** Los triggers de invariantes, el gate determinístico, el contrato de evidencia con estados tipados y el manifiesto de workflow son reutilizables tal cual en otro proyecto.
3. **Levantar un laboratorio.** Los seis archivos SQL corren de corrido sobre un PostgreSQL 16 limpio y dejan un esquema con el que se puede experimentar.

No sirven para reproducir el sistema. Falta deliberadamente la mayor parte.

---

## Cómo leer el estado de cada afirmación

El repositorio usa un vocabulario de evidencia fijo:

`Verificado` · `Confirmado por el responsable` · `Inferido` · `Pendiente de verificar` · `Historia incompleta`

Cuando falta un dato, aparece `[PENDIENTE DE VERIFICAR]`. No se rellena.

---

## Licencia

[Apache 2.0](../LICENSE), como el resto del repositorio. Reutilizables con atribución.

> Última verificación: 2026-08-05
