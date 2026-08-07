/**
 * Tests del exportador.
 *
 * Nada de red: el `fetch` se inyecta. Un test que necesita una instancia de n8n
 * arriba no se corre nunca, y un test que no se corre no protege nada.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { leerConfiguracion, ocultarSecreto, aSlug, nombreDeArchivo, recorrerWorkflows, exportarTodos } from '../exportar.mjs';

const CLAVE_FALSA = 'clave-de-prueba-que-no-existe-en-ningun-lado';
const ENTORNO_OK = { N8N_URL: 'https://n8n.example.com/', N8N_API_KEY: CLAVE_FALSA };

/** fetch falso que sirve dos páginas con cursor. */
function fetchDeMentira(paginas, registroDePedidos = []) {
  return async (url) => {
    registroDePedidos.push(url);
    const cursor = new URL(url).searchParams.get('cursor');
    const indice = cursor ? Number(cursor) : 0;
    const pagina = paginas[indice];
    return {
      ok: true,
      status: 200,
      json: async () => pagina,
    };
  };
}

function workflowDePrueba(id, name) {
  return {
    id,
    name,
    active: true,
    updatedAt: '2026-08-06T00:00:00.000Z',
    nodes: [{ id: 'n1', name: 'Inicio', type: 'n8n-nodes-base.manualTrigger', typeVersion: 1, position: [0, 0], parameters: {} }],
    connections: {},
  };
}

test('sin N8N_URL o N8N_API_KEY no arranca, y el mensaje dice qué falta', () => {
  assert.throws(() => leerConfiguracion({}), /N8N_URL y N8N_API_KEY/);
  assert.throws(() => leerConfiguracion({ N8N_URL: 'https://n8n.example.com' }), /N8N_API_KEY/);
  assert.throws(() => leerConfiguracion({ N8N_API_KEY: CLAVE_FALSA }), /N8N_URL/);
  assert.throws(() => leerConfiguracion({ N8N_URL: '   ', N8N_API_KEY: '  ' }), /N8N_URL y N8N_API_KEY/);
});

test('no hay instancia por defecto: una URL vacía nunca cae en localhost', () => {
  try {
    leerConfiguracion({ N8N_API_KEY: CLAVE_FALSA });
    assert.fail('debería haber fallado');
  } catch (error) {
    assert.ok(!/localhost/.test(error.message.split('\n')[0]));
    assert.match(error.message, /no asume ninguna instancia por defecto/);
  }
});

test('la URL se valida y se le saca la barra final', () => {
  assert.equal(leerConfiguracion(ENTORNO_OK).url, 'https://n8n.example.com');
  assert.throws(() => leerConfiguracion({ ...ENTORNO_OK, N8N_URL: 'n8n.example.com' }), /http/);
});

test('ocultarSecreto tapa la clave completa, sin dejar prefijo', () => {
  const mensaje = `falló al pedir https://n8n.example.com con clave ${CLAVE_FALSA}`;
  const tapado = ocultarSecreto(mensaje, CLAVE_FALSA);
  assert.ok(!tapado.includes(CLAVE_FALSA));
  assert.ok(!tapado.includes(CLAVE_FALSA.slice(0, 6)));
  assert.match(tapado, /API KEY OCULTA/);
});

test('el slug es estable y aguanta acentos, símbolos y nombres largos', () => {
  assert.equal(aSlug('Ejemplo — Buscador Genérico V1'), 'ejemplo-buscador-generico-v1');
  assert.equal(aSlug('[TEST] Copia de algo'), 'test-copia-de-algo');
  assert.equal(aSlug('  '), 'sin-nombre');
  assert.ok(!aSlug('a'.repeat(200)).endsWith('-'));
  assert.equal(nombreDeArchivo({ id: 'wfEjemplo01', name: 'Resumen Diario' }), 'resumen-diario.wfEjemplo01.json');
});

test('la paginación sigue el cursor hasta que se termina', async () => {
  const paginas = [
    { data: [workflowDePrueba('a1', 'Uno'), workflowDePrueba('a2', 'Dos')], nextCursor: '1' },
    { data: [workflowDePrueba('a3', 'Tres')], nextCursor: null },
  ];
  const pedidos = [];
  const traidos = [];
  for await (const wf of recorrerWorkflows({ url: 'https://n8n.example.com', apiKey: CLAVE_FALSA }, { fetchImpl: fetchDeMentira(paginas, pedidos) })) {
    traidos.push(wf.id);
  }

  assert.deepEqual(traidos, ['a1', 'a2', 'a3']);
  assert.equal(pedidos.length, 2);
  assert.match(pedidos[0], /limit=100/);
  assert.match(pedidos[1], /cursor=1/);
});

test('un cursor que no avanza corta en vez de girar para siempre', async () => {
  // Una API que devuelve siempre el mismo cursor haría un bucle infinito. Se
  // detecta en cuanto el cursor recibido es igual al enviado: la segunda vuelta
  // es inevitable —recién ahí se sabe—, la tercera no.
  let pedidos = 0;
  const fetchTerco = async () => {
    pedidos += 1;
    return { ok: true, status: 200, json: async () => ({ data: [workflowDePrueba('x', 'X')], nextCursor: 'siempre-el-mismo' }) };
  };

  const traidos = [];
  for await (const wf of recorrerWorkflows({ url: 'https://n8n.example.com', apiKey: CLAVE_FALSA }, { fetchImpl: fetchTerco })) {
    traidos.push(wf.id);
  }
  assert.equal(pedidos, 2, 'tiene que cortar apenas detecta que el cursor se repite');
  assert.equal(traidos.length, 2);
});

test('un 401 se explica sin imprimir la clave', async () => {
  const fetch401 = async () => ({ ok: false, status: 401, json: async () => ({}) });
  await assert.rejects(
    (async () => {
      for await (const _ of recorrerWorkflows({ url: 'https://n8n.example.com', apiKey: CLAVE_FALSA }, { fetchImpl: fetch401 })) {
        // no debería llegar acá
      }
    })(),
    (error) => {
      assert.match(error.message, /401/);
      assert.ok(!error.message.includes(CLAVE_FALSA));
      return true;
    },
  );
});

test('--dry-run lista lo que traería y no escribe nada', async () => {
  const destino = await mkdtemp(path.join(tmpdir(), 'n8n-versionado-'));
  const paginas = [{ data: [workflowDePrueba('a1', 'Uno')], nextCursor: null }];
  const lineas = [];

  const resultado = await exportarTodos({
    destino,
    dryRun: true,
    entorno: ENTORNO_OK,
    fetchImpl: fetchDeMentira(paginas),
    registrar: (l) => lineas.push(l),
  });

  assert.equal(resultado.total, 1);
  assert.deepEqual(await readdir(destino), [], 'el dry-run no debe escribir');
  assert.ok(lineas.some((l) => l.includes('[dry-run]')));
});

test('la exportación escribe un archivo por workflow, ya normalizado', async () => {
  const destino = await mkdtemp(path.join(tmpdir(), 'n8n-versionado-'));
  const paginas = [{ data: [workflowDePrueba('a1', 'Uno'), workflowDePrueba('a2', 'Dos')], nextCursor: null }];

  const resultado = await exportarTodos({ destino, entorno: ENTORNO_OK, fetchImpl: fetchDeMentira(paginas) });

  const archivos = (await readdir(destino)).sort();
  assert.deepEqual(archivos, ['dos.a2.json', 'uno.a1.json']);

  const contenido = JSON.parse(await readFile(path.join(destino, 'uno.a1.json'), 'utf8'));
  assert.equal(contenido.id, undefined, 'el id de instancia no va adentro del archivo');
  assert.equal(contenido.updatedAt, undefined);
  assert.equal(contenido.nodes[0].position, undefined);

  // El hash reportado es el del archivo escrito: es lo que se registra en el paso 9.
  assert.match(resultado.archivos[0].hash, /^[0-9a-f]{64}$/);
});
