/**
 * Tests del normalizador.
 *
 * La propiedad que se prueba acá no es "el código no explota": es que dos
 * exportaciones del mismo workflow den byte por byte lo mismo. Si eso no se
 * cumple, todo el resto del toolkit no sirve, porque el diff vuelve a ser
 * ilegible y el hash del paso 9 deja de detectar drift.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  normalizarWorkflow,
  serializar,
  hashDeWorkflow,
  ordenarClaves,
  simboloDeCredencial,
  CAMPOS_DE_RUNTIME,
} from '../normalizar.mjs';

const AQUI = path.dirname(fileURLToPath(import.meta.url));

async function cargarFixture(nombre) {
  return JSON.parse(await readFile(path.join(AQUI, 'fixtures', nombre), 'utf8'));
}

/** Devuelve una copia con las claves de cada objeto en orden inverso. */
function desordenarClaves(valor) {
  if (Array.isArray(valor)) return valor.map(desordenarClaves);
  if (valor === null || typeof valor !== 'object') return valor;
  const salida = {};
  for (const clave of Object.keys(valor).reverse()) salida[clave] = desordenarClaves(valor[clave]);
  return salida;
}

test('normalizar es idempotente: normalizar dos veces da lo mismo', async () => {
  const crudo = await cargarFixture('workflow-limpio.json');
  const unaVez = normalizarWorkflow(crudo);
  const dosVeces = normalizarWorkflow(unaVez);

  assert.deepEqual(dosVeces, unaVez);
  assert.equal(serializar(dosVeces), serializar(unaVez));
  assert.equal(hashDeWorkflow(dosVeces), hashDeWorkflow(unaVez));
});

test('no muta la entrada', async () => {
  const crudo = await cargarFixture('workflow-limpio.json');
  const copiaOriginal = structuredClone(crudo);
  normalizarWorkflow(crudo, { simbolizarCredenciales: true });
  assert.deepEqual(crudo, copiaOriginal, 'el normalizador no debe tocar el objeto que recibe');
});

test('dos exportaciones del mismo workflow normalizan a bytes idénticos', async () => {
  const primeraExportacion = await cargarFixture('workflow-limpio.json');

  // Segunda exportación: el humano abrió el lienzo, movió dos nodos, guardó sin
  // cambiar nada de fondo, y n8n regeneró marcas de tiempo e ids internos.
  const segundaExportacion = structuredClone(primeraExportacion);
  segundaExportacion.updatedAt = '2026-08-06T23:59:59.999Z';
  segundaExportacion.versionId = '99999999-0000-1111-2222-333333333333';
  segundaExportacion.triggerCount = 47;
  segundaExportacion.active = false;
  segundaExportacion.nodes = segundaExportacion.nodes.map((nodo, i) => ({
    ...nodo,
    id: `otro-id-regenerado-${i}`,
    position: [nodo.position[0] + 13, nodo.position[1] - 7],
    ...(nodo.webhookId ? { webhookId: '00000000-1111-2222-3333-444444444444' } : {}),
  }));
  // Y además el array de nodos vino en otro orden, cosa que n8n hace.
  segundaExportacion.nodes.reverse();
  segundaExportacion.pinData = { 'Armar resumen': [{ json: { otra: 'cosa' } }] };

  const a = serializar(normalizarWorkflow(primeraExportacion));
  const b = serializar(normalizarWorkflow(segundaExportacion));

  assert.equal(a, b, 'el ruido de runtime no debe producir ninguna diferencia');
  assert.equal(hashDeWorkflow(normalizarWorkflow(primeraExportacion)), hashDeWorkflow(normalizarWorkflow(segundaExportacion)));
});

test('el orden de las claves de entrada no cambia la salida', async () => {
  const crudo = await cargarFixture('workflow-limpio.json');
  const desordenado = desordenarClaves(crudo);

  assert.notEqual(
    JSON.stringify(crudo),
    JSON.stringify(desordenado),
    'el fixture desordenado tiene que ser distinto en crudo, si no el test no prueba nada',
  );
  assert.equal(serializar(normalizarWorkflow(crudo)), serializar(normalizarWorkflow(desordenado)));
});

test('las claves quedan ordenadas alfabéticamente en todos los niveles', async () => {
  const normalizado = normalizarWorkflow(await cargarFixture('workflow-limpio.json'));

  const revisar = (valor, ruta) => {
    if (Array.isArray(valor)) return valor.forEach((v, i) => revisar(v, `${ruta}[${i}]`));
    if (valor === null || typeof valor !== 'object') return;
    const claves = Object.keys(valor);
    assert.deepEqual(claves, [...claves].sort(), `claves desordenadas en ${ruta}`);
    for (const [k, v] of Object.entries(valor)) revisar(v, `${ruta}.${k}`);
  };
  revisar(normalizado, '$');
});

test('los nodos quedan ordenados por nombre', async () => {
  const normalizado = normalizarWorkflow(await cargarFixture('workflow-limpio.json'));
  const nombres = normalizado.nodes.map((n) => n.name);
  assert.deepEqual(nombres, [...nombres].sort());
});

test('saca exactamente la metadata de runtime declarada, y nada más', async () => {
  const crudo = await cargarFixture('workflow-limpio.json');
  const normalizado = normalizarWorkflow(crudo);

  for (const campo of ['id', 'versionId', 'createdAt', 'updatedAt', 'active', 'triggerCount', 'shared', 'pinData', 'staticData']) {
    assert.equal(normalizado[campo], undefined, `debería haberse sacado la raíz "${campo}"`);
  }
  assert.equal(normalizado.meta, undefined, 'meta queda vacío al sacar instanceId, así que se saca entero');

  for (const nodo of normalizado.nodes) {
    assert.equal(nodo.position, undefined, `${nodo.name}: position sigue ahí`);
    assert.equal(nodo.webhookId, undefined, `${nodo.name}: webhookId sigue ahí`);
    assert.equal(nodo.id, undefined, `${nodo.name}: el id del nodo sigue ahí`);
  }

  // Lo que no está en la lista, se conserva. `isArchived` y `settings` son ejemplo.
  assert.equal(normalizado.isArchived, false);
  assert.equal(normalizado.settings.timezone, 'America/Argentina/Buenos_Aires');
});

test('NO toca parámetros, conexiones, tipos ni referencias de credencial', async () => {
  const crudo = await cargarFixture('workflow-limpio.json');
  const normalizado = normalizarWorkflow(crudo);

  const porNombre = (lista, nombre) => lista.find((n) => n.name === nombre);
  const antes = porNombre(crudo.nodes, 'Consultar tareas abiertas');
  const despues = porNombre(normalizado.nodes, 'Consultar tareas abiertas');

  assert.deepEqual(ordenarClaves(despues.parameters), ordenarClaves(antes.parameters), 'los parámetros cambiaron');
  assert.equal(despues.type, antes.type);
  assert.equal(despues.typeVersion, antes.typeVersion);
  assert.deepEqual(despues.credentials, antes.credentials, 'la referencia de credencial cambió');
  assert.deepEqual(ordenarClaves(normalizado.connections), ordenarClaves(crudo.connections), 'la topología cambió');
  assert.deepEqual(ordenarClaves(normalizado.settings), ordenarClaves(crudo.settings), 'los settings funcionales cambiaron');
});

test('las etiquetas quedan reducidas a nombres ordenados', async () => {
  const normalizado = normalizarWorkflow(await cargarFixture('workflow-limpio.json'));
  assert.deepEqual(normalizado.tags, ['documentacion', 'ejemplo']);
});

test('con --simbolizar, la credencial pasa a referencia y el id desaparece', async () => {
  const crudo = await cargarFixture('workflow-limpio.json');
  const normalizado = normalizarWorkflow(crudo, { simbolizarCredenciales: true });
  const telegram = normalizado.nodes.find((n) => n.name === 'Avisar por Telegram');

  assert.deepEqual(telegram.credentials, { telegramApi: { referencia: 'CRED_BOT_DE_EJEMPLO' } });
  assert.ok(!serializar(normalizado).includes('credSinteticaTelegram01'), 'no debe quedar ningún id de credencial');
});

test('simboloDeCredencial saca acentos y espacios', () => {
  assert.equal(simboloDeCredencial('Memoria Postgres — producción'), 'CRED_MEMORIA_POSTGRES_PRODUCCION');
  assert.equal(simboloDeCredencial(undefined, 'telegramApi'), 'CRED_TELEGRAMAPI');
});

test('aguanta un workflow mínimo sin romperse', () => {
  const minimo = { name: 'Mínimo', nodes: [], connections: {} };
  const normalizado = normalizarWorkflow(minimo);
  assert.deepEqual(normalizado, { connections: {}, name: 'Mínimo', nodes: [] });
  assert.throws(() => normalizarWorkflow('no soy un workflow'), TypeError);
});

test('CAMPOS_DE_RUNTIME está documentado campo por campo', () => {
  assert.ok(CAMPOS_DE_RUNTIME.length >= 12);
  for (const campo of CAMPOS_DE_RUNTIME) {
    assert.equal(typeof campo.campo, 'string');
    assert.ok(['raiz', 'meta', 'nodo', 'tag'].includes(campo.ambito), `ámbito raro: ${campo.ambito}`);
    assert.ok(campo.porque.length > 40, `el motivo de "${campo.campo}" es demasiado corto para servir de auditoría`);
  }
});

test('el archivo serializado termina en una sola nueva línea', async () => {
  const texto = serializar(normalizarWorkflow(await cargarFixture('workflow-limpio.json')));
  assert.ok(texto.endsWith('}\n'));
  assert.ok(!texto.endsWith('\n\n'));
  assert.ok(!/[ \t]+\n/.test(texto), 'no debe haber espacios colgando al final de una línea');
});
