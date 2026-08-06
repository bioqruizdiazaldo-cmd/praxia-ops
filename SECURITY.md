# Política de seguridad

Cómo reportar un problema de seguridad en este repositorio, y qué garantías ofrece —y cuáles no— el material publicado acá.

---

## Qué hay en este repositorio

Documentación, plantillas, esquemas SQL sintéticos y artefactos sanitizados de un sistema de agentes de IA que corre en infraestructura privada.

**Este repositorio no distribuye software ejecutable en producción.** No hay servicio desplegado desde acá, no hay paquete publicado, no hay imagen de contenedor. Los archivos SQL son reconstrucciones didácticas verificadas contra PostgreSQL 16, pensadas para leerse y adaptarse, no para aplicarse tal cual sobre una base con datos.

---

## Versiones soportadas

| Versión | Soporte |
|---|---|
| `main` | La documentación se corrige. No hay compromiso de compatibilidad hacia atrás. |

No hay releases versionados todavía.

---

## Reportar una vulnerabilidad

**No abras un issue público.** Usá **GitHub Private Vulnerability Reporting**, en la pestaña *Security* de este repositorio.

Si el canal privado no está disponible, escribí por el contacto que figura en el perfil y pedí un canal privado antes de mandar detalles.

### No incluyas nunca en un issue, discusión o pull request público

- credenciales, tokens o claves;
- datos personales, financieros, médicos o fiscales de alguien;
- detalles de infraestructura privada (direcciones, hostnames, topología);
- una demostración de explotación contra un sistema real;
- logs o backups.

Para demostrar un problema, usá sistemas ficticios y datos sintéticos.

---

## Qué se considera dentro de alcance

- Un secreto, dato personal o dato de infraestructura que se haya filtrado a este repositorio pese a la sanitización.
- Un error en los esquemas SQL o en los guards que enseñe una práctica insegura a quien los copie.
- Un error en las plantillas o checklists que induzca a saltear un control relevante.
- Un enlace de este repositorio a contenido malicioso o comprometido.

## Fuera de alcance

- Vulnerabilidades en productos de terceros mencionados (n8n, PostgreSQL, Docker, Traefik, proveedores de modelos). Reportalas a quien corresponda.
- El sistema privado en sí, que no es accesible desde acá.
- Pedidos de consultoría general.

---

## Tiempos de respuesta propuestos

Son objetivos declarados, no compromisos contractuales:

- acuse de recibo dentro de 3 días hábiles;
- clasificación inicial dentro de 7 días hábiles;
- divulgación coordinada sólo después de que exista una corrección.

---

## Si encontrás algo sensible ya publicado

El procedimiento está escrito en [`docs/05-gobernanza/politica-de-publicacion.md`](docs/05-gobernanza/politica-de-publicacion.md): se preserva la evidencia del incidente en privado, se elimina la exposición por un proceso aprobado, y se documenta una corrección sanitizada. La historia de git se reescribe sólo si el dato expuesto lo amerita, y se rota lo que haya que rotar antes de tocar nada.

Avisar rápido vale más que avisar prolijo.

> Última verificación: 2026-08-05
