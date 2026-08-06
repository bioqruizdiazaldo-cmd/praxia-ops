# Cómo contribuir

Este repositorio documenta un sistema privado. Se aceptan contribuciones, con una regla que no se negocia: nada que entre acá puede exponer el sistema del que salió la lección.

---

## Qué contribuciones sirven

- Correcciones de errores factuales o técnicos en la documentación.
- Mejoras a las plantillas y checklists de [`docs/05-gobernanza`](docs/05-gobernanza/) — son el material más reutilizable del repo.
- Correcciones al SQL de [`artifacts/sql`](artifacts/sql/): un constraint mal puesto, un guard que se puede evadir, un índice que falta.
- Traducciones al inglés de documentos que todavía sólo están en español.
- Señalar una afirmación que no tenga evidencia detrás.

## Qué no entra

- Pedidos de acceso al sistema privado, a sus datos o a su runtime.
- Capturas, logs o exports de cualquier sistema real, propio o ajeno.
- Contenido generado por IA sin revisión humana ni verificación de los hechos.
- Cambios que agreguen dependencias o código ejecutable sin una decisión de arquitectura que lo justifique.

---

## Antes de abrir un pull request

1. Abrí un issue primero si el cambio es de fondo. Para un typo, mandá el PR directo.
2. Corré mentalmente la [definición de terminado](docs/05-gobernanza/checklists/definicion-de-terminado.md).
3. Verificá que no estés agregando ningún dato prohibido por la [política de publicación](docs/05-gobernanza/politica-de-publicacion.md): secretos, datos personales, direcciones, hostnames, identificadores internos.
4. Si tocás SQL, probá que corra de punta a punta sobre PostgreSQL 16 limpio.

---

## Estilo

- Español rioplatense en `docs/` y `systems/`; inglés en `docs/05-gobernanza/en/` y en `README.en.md`.
- Markdown con línea en blanco antes de cada lista y después de cada encabezado.
- Cada documento abre con un H1 y una frase que diga de qué va, y cierra con `> Última verificación: AAAA-MM-DD`.
- Los documentos clave llevan, justo después de esa frase de apertura, un bloque `> **In English**` de seis a diez líneas, cerrado por el marcador `<!-- fin del resumen en inglés -->`. No es una traducción: es lo mínimo para que alguien que no lee español entienda de qué va la página y decida si le interesa. Si agregás un documento de peso, sumale el suyo.
- Los ejemplos son sintéticos y se declara que lo son.
- Si afirmás algo sobre el sistema, marcá su estado de evidencia con el vocabulario del repo: `Verificado`, `Confirmado por el responsable`, `Inferido`, `Pendiente de verificar`, `Historia incompleta`.

---

## Sobre el uso de agentes de IA

Este repositorio se escribió con asistencia de agentes de IA, y no lo esconde. Si vos también los usás para contribuir, aplican las mismas reglas que aplicamos acá, descritas en [`acuerdo-de-trabajo-con-agentes.md`](docs/05-gobernanza/acuerdo-de-trabajo-con-agentes.md):

- el agente propone, la persona responde;
- toda afirmación necesita evidencia verificable;
- inspección no equivale a autorización de cambio;
- si el agente no pudo verificar algo, se declara el vacío en vez de completarlo con una narración plausible.

Un PR con datos inventados que suenan bien es peor que un PR vacío.

---

## Licencia de las contribuciones

Al contribuir aceptás que tu aporte se licencie bajo [Apache 2.0](LICENSE), igual que el resto del repositorio.

> Última verificación: 2026-08-05
