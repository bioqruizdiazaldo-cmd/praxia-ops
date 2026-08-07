/**
 * Tests del CLI: que el pipeline completo corra de punta a punta sobre los
 * fixtures, y que los códigos de salida sirvan para CI.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import path from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { mkdtemp } from 'node:fs/promises';
import os from 'node:os';

import { SENUELOS, materializarWorkflowSucio } from './senuelos.mjs';

const ejecutar = promisify(execFile);
const AQUI = path.dirname(fileURLToPath(import.meta.url));
const CLI = path.join(AQUI, '..', 'cli.mjs');
const FIXTURES = path.join(AQUI, 'fixtures');

/**
 * El workflow con problemas no está versionado: se materializa en un temporal
 * a partir de la plantilla. Ver tests/senuelos.mjs para el porqué.
 */
const SUCIO = await materializarWorkflowSucio(await mkdtemp(path.join(os.tmpdir(), 'n8n-versionado-')));

/** Corre el CLI y devuelve { codigo, salida, error } sin lanzar excepción. */
async function correr(...argumentos) {
  try {
    const { stdout, stderr } = await ejecutar(process.execPath, [CLI, ...argumentos], { encoding: 'utf8' });
    return { codigo: 0, salida: stdout, error: stderr };
  } catch (error) {
    return { codigo: error.code ?? 1, salida: error.stdout ?? '', error: error.stderr ?? '' };
  }
}

test('--help explica cada comando y sale con 0', async () => {
  const { codigo, salida } = await correr('--help');
  assert.equal(codigo, 0);
  for (const comando of ['exportar', 'normalizar', 'verificar', 'manifiesto']) {
    assert.ok(salida.includes(comando), `la ayuda no menciona "${comando}"`);
  }
  assert.match(salida, /LO QUE ESTO NO HACE/);
});

test('sin comando muestra la ayuda y sale con 2', async () => {
  const { codigo, salida } = await correr();
  assert.equal(codigo, 2);
  assert.match(salida, /USO/);
});

test('un comando inexistente sale con 2', async () => {
  const { codigo } = await correr('inventado');
  assert.equal(codigo, 2);
});

test('normalizar emite JSON estable y el hash es reproducible', async () => {
  const archivo = path.join(FIXTURES, 'workflow-limpio.json');
  const primera = await correr('normalizar', archivo);
  const segunda = await correr('normalizar', archivo);

  assert.equal(primera.codigo, 0);
  assert.equal(primera.salida, segunda.salida);

  const { salida: hash } = await correr('normalizar', archivo, '--hash');
  assert.match(hash.trim(), /^[0-9a-f]{64}$/);
});

test('normalizar --campos documenta qué se saca y por qué', async () => {
  const { codigo, salida } = await correr('normalizar', '--campos');
  assert.equal(codigo, 0);
  assert.match(salida, /pinData/);
  assert.match(salida, /ámbito: nodo/);
});

test('verificar: el fixture limpio pasa (0) y el sucio bloquea (1)', async () => {
  const limpio = await correr('verificar', path.join(FIXTURES, 'workflow-limpio.json'));
  assert.equal(limpio.codigo, 0, limpio.salida);
  assert.match(limpio.salida, /sin hallazgos/);

  const sucio = await correr('verificar', SUCIO);
  assert.equal(sucio.codigo, 1);
  assert.match(sucio.salida, /BLOQUEA/);
  assert.match(sucio.salida, /credencial_con_valor/);
  assert.ok(!sucio.salida.includes(SENUELOS.openai), 'el CLI no debe imprimir el valor');
});

test('verificar --json sirve para CI', async () => {
  const { codigo, salida } = await correr('verificar', SUCIO, '--json');
  assert.equal(codigo, 1);
  const informe = JSON.parse(salida);
  assert.equal(informe.bloquea, true);
  assert.ok(informe.resultados[0].hallazgos.length > 0);
});

test('manifiesto generar produce el esqueleto y validar lo rechaza por incompleto', async () => {
  const archivo = path.join(FIXTURES, 'workflow-limpio.json');
  const generado = await correr('manifiesto', 'generar', archivo);
  assert.equal(generado.codigo, 0);

  const manifiesto = JSON.parse(generado.salida);
  assert.equal(manifiesto.owner, null);
  assert.equal(manifiesto.contrato.entrada.tipo, 'cron');

  const yaml = await correr('manifiesto', 'generar', archivo, '--yaml');
  assert.equal(yaml.codigo, 0);
  assert.match(yaml.salida, /^nombre_logico:/m);
});

test('manifiesto validar sale con 1 si el manifiesto no está completo', async () => {
  // Se valida el esqueleto recién generado, que por definición está incompleto.
  const { codigo, salida } = await correr('manifiesto', 'validar', path.join(FIXTURES, 'workflow-limpio.json'));
  assert.equal(codigo, 1);
  assert.match(salida, /FALLA/);
});

test('exportar sin variables de entorno falla con 2 y sin imprimir nada sensible', async () => {
  const { stdout, stderr, code } = await ejecutar(process.execPath, [CLI, 'exportar', '--dry-run'], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH },
  }).then(
    (r) => ({ ...r, code: 0 }),
    (e) => ({ stdout: e.stdout ?? '', stderr: e.stderr ?? '', code: e.code }),
  );

  assert.equal(code, 2);
  assert.match(stderr, /N8N_URL y N8N_API_KEY/);
  assert.equal(stdout, '');
});
