# Artefactos de workflows n8n

Cómo se versiona, se documenta y se contrata un workflow no-code cuando el runtime no puede ser la fuente de verdad.

> **Reconstrucción didáctica sintética. No hay JSON exportado acá.**
> Estos documentos describen la **estructura** de los workflows —nodos, orden, entradas, salidas y contratos— sin publicar el export de n8n. Las credenciales aparecen siempre como **referencias simbólicas** (`CRED_TELEGRAM_BOT`), nunca como IDs. Todos los ejemplos usan datos sintéticos y lo dicen.

---

## El problema que resuelven

Un workflow de n8n vive en una base SQLite dentro de un contenedor. Se edita en un lienzo visual. No tiene diff legible, no tiene revisión de código, y su versión "buena" es la que está corriendo.

Eso lleva directo a lo que se encontró en la inspección del 2026-08-03:

> *"El entorno de producción también ha sido utilizado como laboratorio y archivo histórico, porque conserva numerosos workflows de prueba, candidatos y respaldos."*

217 workflows registrados, 25 activos, 125 con nomenclatura de laboratorio. Y la conclusión del TO-BE:

> *"El código y los workflows versionados deberían ser la fuente de verdad; el runtime debería representar un despliegue."*

Los tres documentos de esta carpeta son las herramientas concretas para llegar ahí.

---

## Qué hay acá

| Documento | Para qué sirve |
|---|---|
| [`manifiesto-de-workflow.md`](manifiesto-de-workflow.md) | La plantilla de manifiesto con los 11 campos mínimos, más un ejemplo completo con datos sintéticos. Es la ficha que acompaña a cada workflow versionado |
| [`estructura-orquestador.md`](estructura-orquestador.md) | Descripción nodo por nodo del orquestador de Oppenheimer y del Buscador Web Tavily V1, en tabla: nodo · tipo · qué hace · entrada · salida |
| [`contrato-subworkflow.md`](contrato-subworkflow.md) | El contrato de entrada y salida que cumple un subagente invocado como herramienta, con ejemplo JSON sintético |

---

## El pipeline de 10 pasos

El manifiesto solo no alcanza. El procedimiento completo para publicar un workflow:

1. **Exportar** el workflow desde el runtime.
2. **Normalizar** el JSON: orden estable de claves, sin metadatos volátiles, para que el diff sirva de algo.
3. **Escanear secretos** sobre el archivo normalizado.
4. **Validar estructura**: que los nodos y conexiones sean coherentes.
5. **Probar contratos** con fixtures ficticios.
6. **Importar en staging aislado como inactivo.**
7. **Revisar el grafo visual** — un JSON válido puede ser un grafo absurdo.
8. **Publicar tras aprobación** humana.
9. **Registrar el hash desplegado.**
10. **Verificar y conservar el rollback.**

Ver el [runbook de publicación](../../docs/06-runbooks/publicar-un-workflow-n8n.md).

**Estado honesto:** el pipeline está definido y se aplica de forma parcial. **No hay staging aislado** (deuda técnica #2) y la publicación se hace sobre el mismo runtime que es producción. Los pasos 1, 3, 8, 9 y 10 sí se cumplen.

---

## El ciclo de vida

```
draft → test → staging → production → deprecated → archived
```

Un workflow declara su estado en el manifiesto. Cuando el estado del manifiesto y el del runtime no coinciden, gana el manifiesto y hay que corregir el runtime.

El contraejemplo vive en producción: **PraxIA — Avisador de Errores v1 sigue llamándose `[TEST]` aunque es el `errorWorkflow` global.** Su estado real es `production` y su nombre dice otra cosa. Es exactamente el problema que el manifiesto viene a resolver.

---

## Credenciales: referencia simbólica, nunca ID

En todo artefacto publicado, una credencial se nombra por lo que es, no por su identificador:

| Referencia simbólica | Qué representa |
|---|---|
| `CRED_TELEGRAM_BOT` | Bot de Telegram del agente |
| `CRED_OPENAI` | Cuenta de OpenAI (chat, Whisper, TTS) |
| `CRED_GOOGLE_OAUTH` | OAuth de Google (Gmail, Calendar, Drive, Sheets) |
| `CRED_PG_MEMORIA` | Conexión a PostgreSQL, esquema `praxia` |
| `CRED_TAVILY_HEADER` | Header Auth del proveedor de búsqueda |
| `CRED_FINANZAS_TOKEN` | Token de la API financiera |

El mapeo entre referencia simbólica y credencial real vive en el runtime, fuera del repositorio. Un manifiesto puede publicarse entero sin exponer nada.

---

## Lo que no se publica

- El JSON exportado de cualquier workflow.
- IDs de credenciales, de workflow o de ejecución que permitan correlacionar con el runtime.
- URLs de webhook, hostnames, IPs o puertos.
- `chat_id`, direcciones de correo, nombres de personas.
- Prompts que contengan datos personales.

---

## Documentos relacionados

- [Cuándo uso n8n](../../docs/02-desglose-tecnico/02-cuando-uso-n8n.md)
- [Cuándo construyo un subagente](../../docs/02-desglose-tecnico/03-cuando-construyo-un-subagente.md)
- [Runbook: publicar un workflow n8n](../../docs/06-runbooks/publicar-un-workflow-n8n.md)
- [Runbook: limpieza de runtime](../../docs/06-runbooks/limpieza-de-runtime.md)
- [Oppenheimer](../../systems/oppenheimer/)

> Última verificación: 2026-08-05
