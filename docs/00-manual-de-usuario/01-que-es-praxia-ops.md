# Qué es PraxIA Ops

PraxIA Ops es la marca bajo la que se diseñan, construyen y operan agentes de IA con memoria, permisos y trazabilidad; Oppenheimer es el primero de ellos y el que está en producción.

## El sistema en una frase

Un asistente personal 24/7 que vive en Telegram, entiende texto, voz, imágenes y PDFs, y que por detrás coordina una decena de subagentes especializados sobre una base de datos propia donde guarda lo que hay que recordar y registra lo que hizo.

No es un chat con un modelo. Es un orquestador con herramientas reales conectadas: Gmail, Google Calendar, Google Drive, Google Sheets, búsqueda web, papers científicos, clima, una base de memoria en PostgreSQL y un sistema financiero completo.

## Qué problema resuelve

Tres problemas concretos, en este orden.

**1. La información se pierde.** Una decisión que tomaste hace tres semanas, el nombre del proveedor que te pasaron por audio, la regla que definiste para un proyecto. Todo eso vive en chats, mails y notas sueltas. El sistema lo guarda en una base estructurada y lo devuelve cuando lo necesitás.

**2. Las tareas repetitivas se hacen a mano.** Revisar la agenda, mirar el clima, leer los mails importantes, enterarse de las noticias. El sistema arma un briefing y te lo manda antes de que te levantes.

**3. La plata no se registra en el momento.** Un gasto que no anotás en los primeros treinta segundos no se anota nunca. Por eso PraxIA Finanzas acepta la carga desde donde estés: un mensaje de Telegram, una foto de un ticket, un PDF de resumen, un CSV del banco o un mail.

## Qué NO es

Vale la pena ser explícito, porque la diferencia importa.

| No es | Por qué |
|---|---|
| Un producto SaaS | Es un sistema personal autohospedado en un VPS propio. No hay signup, no hay multitenancy real todavía |
| Un chatbot genérico | Cada respuesta que toca datos pasa por herramientas verificables, no por lo que el modelo "cree recordar" |
| Un sistema con separación de ambientes | Producción se usó también como laboratorio: 125 workflows con nomenclatura de laboratorio conviven con 25 activos. Es una deuda técnica documentada |
| Una base con RAG vectorial | No hay embeddings ni búsqueda semántica. La memoria es SQL con búsqueda de texto completo en español |
| Un sistema que decide solo | Enviar mails, borrar, gastar y publicar requieren aprobación humana explícita |
| Multiusuario hoy | La arquitectura de datos contempla multiusuario, pero el único usuario activo es el dueño. Los demás agentes están planificados, no construidos |

## Los cinco principios

Estos cinco principios son una síntesis de las reglas textuales que aparecen en las decisiones y contratos del sistema (`Inferido` como agrupación; cada principio individual es `Verificado` y está citado).

### 1. Sin orden no hay sistema, solo experimentos

Textual: *"Sin orden no hay sistema, solo experimentos. El error a evitar no es técnico, es de secuencia."*

Se planifica antes de implementar. Cada decisión importante queda escrita con fecha. Existe un ciclo de vida de nueve etapas —intake, evidencia, diseño, implementación, verificación, staging, release, operación, incidente— y cada etapa tiene su compuerta.

### 2. Nunca se borra

En Finanzas no existe ningún endpoint `DELETE`. Hay un trigger llamado `prohibir_delete_fisico` que lo impide a nivel base de datos, y el rol de la aplicación no tiene permiso de borrado. Lo que se anula queda anulado y auditado, no desaparece.

La razón es simple: un dato borrado es una historia que no se puede reconstruir.

### 3. Aprobación humana para lo que tiene consecuencias

La decisión D-7 lo fija: enviar mails, borrar, gastar y publicar requieren confirmación de una persona.

En la práctica: el agente de email redacta pero no manda hasta que aprobás por Telegram; las herramientas MCP que modifican datos financieros están marcadas *"¡REQUIERE CONFIRMACIÓN EXPLÍCITA!"*; y las propuestas del motor fiscal nacen pendientes.

Textual, del contrato fiscal: *"La aprobación no ejecuta nada financieramente."* Aprobar una propuesta no mueve plata.

### 4. La ausencia de dato no es un dato inventado

Textual: *"PraxIA Finanzas es la única fuente de verdad financiera. No existen sistemas paralelos. La ausencia de datos no debe convertirse en un dato inventado."*

Y su corolario para cotizaciones: *"Ninguna cotización se inventa. Ausencia de dato es ausencia de fila, nunca un cero."*

Lo mismo aplica a la memoria: está prohibido que el agente responda "no tengo registrado" sin haber consultado primero la base y haber recibido una respuesta vacía.

### 5. Una sola puerta de entrada por dominio

En Finanzas: *"Toda entrada —Telegram, dashboard, PDF, CSV, email o un agente— produce el mismo contrato universal y termina en la misma base."* Un solo camino de alta: `POST /api/ingesta`.

En memoria: *"La memoria viva vive en PostgreSQL (esquema praxia) en el VPS; MiBoveda es el espejo humano editable."*

La consecuencia práctica es que no hay dos lugares donde mirar. Si no está ahí, no está.

## El mapa de piezas

Cinco bloques. Si entendés estos cinco, entendés el sistema.

### El orquestador

Es el cerebro que recibe tu mensaje y decide qué hacer con él.

Técnicamente es un workflow de n8n llamado `Oppenheimer - Orquestador`, activo, nacido el 2026-07-14 a las 23:05, con 51 nodos al corte del 2026-08-03. Recibe todo por Telegram, filtra que el mensaje venga del dueño (`If - Owner Only`), interpreta la intención y llama a la herramienta o al subagente que corresponda.

Lo importante para vos: **no hay comandos con barra que memorizar**. Le hablás en castellano y él decide.

### Los subagentes

Son trabajadores especializados. El orquestador los llama, ellos hacen una cosa bien y devuelven el resultado.

Hay catorce, agrupables en cuatro familias:

- **Productividad**: Email, Calendario, Planillas, Recordatorios, Enviar Gmail.
- **Investigación**: Papers Científicos, Buscador Web Tavily.
- **Memoria**: Router, Guardar, Consultar, Tareas, Proyectos, Sync Export MD.
- **Operación**: Briefing Diario, Briefing Noticias, Alertas TradingView, Avisador de Errores.

Cada uno tiene su ficha en [subagentes](03-subagentes.md).

La ventaja de partirlo así: si el agente de email se rompe, la agenda sigue andando.

### La memoria

Cuatro capas, cada una con un trabajo distinto.

| Capa | Qué guarda | Dónde vive |
|---|---|---|
| Corta | La conversación de los últimos mensajes | `Memory Buffer` en n8n, volátil |
| Estructurada | Hechos, decisiones, preferencias, reglas, tareas, proyectos | PostgreSQL 16, esquema `praxia` |
| Documental | Espejo legible de todo lo anterior | Markdown en la bóveda Obsidian, sincronizado a OneDrive |
| Auditada | Qué se ejecutó, qué falló y cuándo | `praxia.agent_errors` + logs de ejecución |

No hay RAG vectorial. La búsqueda es SQL con `to_tsvector('spanish')`, normalización de acentos y stop-words, en dos niveles de coincidencia: uno estricto y uno laxo.

Detalle completo en [memoria](05-memoria-que-recuerda-y-que-no.md).

### Finanzas

Un sistema aparte, con su propio esquema de base (`praxia_finanzas`), su propia API, su propio dashboard y su propio servidor MCP, pero **dentro del mismo PostgreSQL**.

Esa fue una decisión deliberada del 2026-07-26: *"PraxIA Contable debe construirse como un esquema adicional dentro del PostgreSQL que ya corre en el VPS. Reutiliza ~80% de infraestructura existente. Construir una app aparte sería tirar a la basura el Memory Core."*

Lo que ves como usuario:

- Un dashboard web con siete secciones.
- Un canal de Telegram que acepta cargas en lenguaje natural.
- Importación de PDF, CSV, Excel y mails.
- Deudas, planes de pago, obligaciones recurrentes y cierre fiscal.

Guía completa en [PraxIA Finanzas](04-praxia-finanzas-guia-de-uso.md).

### La gobernanza

Es la parte que no se ve pero es la que hace que el sistema sea confiable.

Incluye:

- Un **vocabulario de evidencia** que se usa en toda la documentación: `Verificado`, `Confirmado por el responsable`, `Inferido`, `Pendiente de verificar`, `Historia incompleta`.
- Una **política de publicación**: *"Los artefactos públicos deben enseñar un principio reutilizable sin exponer el sistema privado del que salió la lección."*
- Un **manifiesto de versionado** para workflows no-code, con ciclo de vida `draft → test → staging → production → deprecated → archived`.
- Una regla que ordena todo el trabajo asistido por IA: *"Inspección no equivale a autorización de cambio."*
- Y la que más cuesta cumplir: *"Es preferible mantener un vacío explícito antes que completar la historia con una narración no demostrable."*

El cierre del documento de gobernanza es la frase que define el rol de la IA acá: *"Los agentes de IA pueden proponer, implementar y verificar trabajo. No se convierten en el dueño responsable del riesgo, el acceso o la decisión de release."*

## Dónde está corriendo

Un VPS Hostinger con Docker: n8n autohospedado detrás de Traefik con TLS, sin puertos publicados al host, y un contenedor PostgreSQL 16 aparte para memoria y finanzas. n8n usa SQLite para su propio estado. Backups diarios, semanales y mensuales con manifiesto y verificación.

No se publican IP, hostnames ni identificadores de infraestructura. Esa es política, no descuido.

## Qué sigue después de Oppenheimer

El orden de construcción está decidido: **Oppenheimer → PraxIA Ops → Ciencia Aplicada → agente familiar → Nativo Salvaje → clientes**.

Nada de lo que viene después existe todavía como sistema funcionando. Lo que sí existe son notas, ADRs y una arquitectura de datos que ya contempla multiusuario desde el día uno, que era justamente el punto.

> Última verificación: 2026-08-05
