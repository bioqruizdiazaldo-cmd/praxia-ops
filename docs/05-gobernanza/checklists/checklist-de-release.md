# Checklist de release

La última compuerta antes de tocar producción. Se completa entera, en orden, y la firma un humano.

Se usa en la etapa 7 del [ciclo de vida](../ciclo-de-vida-sdlc-ia.md). Es la compuerta que no se delega a ningún agente.

> *"Los agentes de IA pueden proponer, implementar y verificar trabajo. No se convierten en el dueño responsable del riesgo, el acceso o la decisión de release."*

---

## Antes del release

### Precondiciones

- [ ] La [definición de terminado](definicion-de-terminado.md) está completa
- [ ] Existe un `TEST-XXXX` con veredicto favorable
- [ ] El umbral declarado se alcanzó. No se bajó para poder desplegar
- [ ] Se probó fuera de producción. Si no hay staging, está declarado explícitamente que no lo hubo y por qué se acepta el riesgo
- [ ] Nadie más está desplegando al mismo tiempo

### Estado real del destino

- [ ] Se verificó **el servidor**, no el repositorio
- [ ] La versión desplegada actualmente está identificada
- [ ] No hay drift entre lo que dice el repositorio y lo que corre. Si lo hay, se resuelve **antes** de desplegar lo nuevo

> El 2026-08-05 producción estaba tres migraciones atrás desde el 31/07 porque *"nadie había mirado el servidor, solo el repositorio"*. Este bloque existe por eso.

### Respaldo

- [ ] Backup tomado **hoy**, antes de este release
- [ ] El backup se verificó, no sólo se ejecutó
- [ ] El artefacto anterior está exportado y guardado con su hash
- [ ] Se confirmó que el artefacto anterior se puede reimportar

### Rollback

- [ ] El `ROLLBACK-XXXX` está escrito **antes** de desplegar
- [ ] Los pasos son concretos y ejecutables por otra persona
- [ ] Está declarado el criterio de decisión: qué tiene que pasar para revertir
- [ ] Está declarado qué se pierde si se revierte
- [ ] Está estimado cuánto tarda

### Sanitización, si el release incluye artefactos públicos

- [ ] Escaneo de secretos ejecutado sobre el artefacto final
- [ ] Sin IPs, hostnames, tokens, IDs de credencial, identificadores de chat ni correos
- [ ] Ejemplos sintéticos, declarados como sintéticos
- [ ] Las seis compuertas de la [política de publicación](../politica-de-publicacion.md) pasadas

---

## Durante el release

- [ ] Se aplica **exactamente** lo aprobado. Nada más, ni siquiera "una cosita"
- [ ] Las migraciones corren en transacción, con `ON_ERROR_STOP=1`
- [ ] Los workflows se importan **como inactivos** primero
- [ ] El grafo visual se revisa antes de activar
- [ ] Se registra el hash de lo desplegado
- [ ] Se registra la hora de inicio

---

## Después del release

### Verificación inmediata

- [ ] El componente responde
- [ ] Se ejecutó al menos un caso real de punta a punta
- [ ] Verificación de **no regresión**: lo que andaba antes sigue andando
- [ ] El conteo de objetos coincide con lo esperado (tablas, nodos, endpoints)
- [ ] No aparecieron errores nuevos en `praxia.agent_errors`
- [ ] No hay ejecuciones fallidas nuevas en el historial

> La puesta al día del 2026-08-05 verificó la no regresión contando tablas: 25 → 35. Un número esperado y comprobado vale más que una impresión.

### Registro

- [ ] `RELEASE-XXXX` completo: qué, cuándo, quién aprobó, hash desplegado, rollback asociado
- [ ] El manifiesto refleja el nuevo estado de ciclo de vida
- [ ] El artefacto de rollback está **conservado**, no descartado
- [ ] El `CHANGELOG` está actualizado

### Observación

- [ ] Definida la ventana de observación y qué se mira durante ella
- [ ] Definido el criterio de "esto salió mal" que dispara el rollback
- [ ] Alguien está mirando. Si nadie puede mirar, el release se posterga

---

## Trabajo con agentes de IA en un release

- [ ] El agente **no ejecutó** el release. Lo preparó y esperó
- [ ] La aprobación es de un humano con nombre, para **este** release
- [ ] La aprobación no se heredó de un release anterior parecido
- [ ] El humano leyó lo que se despliega, no sólo el resumen del agente
- [ ] Si el agente encontró algo para arreglar durante la preparación, lo reportó y **no lo arregló**
- [ ] El agente no modificó fixtures, umbrales ni criterios para que el release pudiera avanzar
- [ ] El nivel de evidencia de lo que el agente reporta como verificado fue comprobado por muestreo

---

## Criterios de detención

Cualquiera de estos detiene el release. No se negocian en el momento — negociar un criterio de detención mientras se despliega es exactamente lo que produce los incidentes.

- El backup no se pudo verificar.
- El estado real del destino no coincide con lo esperado.
- Aparece un cambio en el diff que nadie puede explicar.
- El rollback no está escrito o no está probado.
- Falta la aprobación humana.
- Alguien tiene una duda razonable y no hay tiempo de resolverla.
- Es tarde, es viernes, o el aprobador no va a estar disponible durante la ventana de observación.

---

## Firma

```
Release:        RELEASE-XXXX
Componente:     
Aprobado por:   <nombre de una persona>
Fecha y hora:   AAAA-MM-DD HH:MM
Hash desplegado:
Rollback:       ROLLBACK-XXXX
Ventana de observación: <duración> — hasta AAAA-MM-DD HH:MM
```

> Última verificación: 2026-08-05
