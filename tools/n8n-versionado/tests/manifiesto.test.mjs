/**
 * Tests del manifiesto.
 *
 * Lo que se prueba es que el validador reclame: un validador permisivo es peor
 * que ninguno, porque deja pasar un manifiesto a medio llenar con el sello de
 * "validado".
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  generarManifiesto,
  validarManifiesto,
  manifiestoAYaml,
  CAMPOS_DEL_MANIFIESTO,
  ESTADOS_DE_CICLO_DE_VIDA,
} from '../manifiesto.mjs';

const AQUI = path.dirname(fileURLToPath(import.meta.url));

async function cargarFixture(nombre) {
  return JSON.parse(await readFile(path.join(AQUI, 'fixtures', nombre), 'utf8'));
}

/** Un manifiesto completo y válido, con datos sintéticos. */
function manifiestoCompleto() {
  return {
    nombre_logico: 'ejemplo.resumen-diario.v1',
    nombre_en_runtime: 'Ejemplo — Resumen diario de tareas',
    owner: 'Persona Responsable De Ejemplo',
    entorno: 'prod',
    estado: 'production',
    contrato: {
      entrada: { tipo: 'cron', esquema: { disparo: 'diario 08:00' } },
      salida: { esquema: { enviado: 'boolean' }, estados: ['ok', 'sin_tareas', 'error_tecnico'] },
    },
    dependencias: {
      workflows: [],
      datos: ['ninguno'],
      servicios: ['servicio de tareas de ejemplo (HTTP)'],
    },
    credenciales: ['CRED_SERVICIO_DE_EJEMPLO', 'CRED_BOT_DE_EJEMPLO'],
    clasificacion_datos: 'interno',
    origen: { procedencia: 'escrito a mano', revisado_por: 'Persona Responsable De Ejemplo', fecha_revision: '2026-08-06' },
    evidencia_test: { fixtures: ['3 casos sintéticos'], resultado: '3/3 PASS', fecha: '2026-08-06' },
    rollback: {
      artefacto: 'backups/2026-08-05/ejemplo.resumen-diario.v1.json',
      hash_sha256: '0'.repeat(64),
      verificado: 'sí',
    },
  };
}

test('un manifiesto completo valida', () => {
  const resultado = validarManifiesto(manifiestoCompleto());
  assert.deepEqual(resultado.faltantes, []);
  assert.deepEqual(resultado.errores, []);
  assert.equal(resultado.valido, true);
});

test('detecta cada uno de los 11 campos cuando falta', () => {
  assert.equal(CAMPOS_DEL_MANIFIESTO.length, 11);

  for (const campo of CAMPOS_DEL_MANIFIESTO) {
    const m = manifiestoCompleto();
    delete m[campo.clave];
    const resultado = validarManifiesto(m);
    assert.equal(resultado.valido, false, `sin "${campo.clave}" debería fallar`);
    assert.ok(resultado.faltantes.includes(campo.clave), `no reportó como faltante "${campo.clave}"`);
  }
});

test('un campo en null o en blanco cuenta como faltante', () => {
  for (const vacio of [null, '', '   ', {}]) {
    const m = manifiestoCompleto();
    m.owner = vacio;
    assert.ok(validarManifiesto(m).faltantes.includes('owner'), `"${JSON.stringify(vacio)}" debería contar como faltante`);
  }
});

test('detecta subcampos obligatorios faltantes', () => {
  const m = manifiestoCompleto();
  m.rollback.hash_sha256 = null;
  m.contrato.salida.estados = null;
  m.evidencia_test.resultado = null;

  const { faltantes, valido } = validarManifiesto(m);
  assert.equal(valido, false);
  assert.ok(faltantes.includes('rollback.hash_sha256'));
  assert.ok(faltantes.includes('contrato.salida.estados'));
  assert.ok(faltantes.includes('evidencia_test.resultado'));
});

test('acepta los seis estados de ciclo de vida y rechaza cualquier otro', () => {
  for (const estado of ESTADOS_DE_CICLO_DE_VIDA) {
    const m = manifiestoCompleto();
    m.estado = estado;
    // `draft`/`test` en prod tienen su propio error de coherencia: se prueba aparte.
    m.entorno = estado === 'draft' || estado === 'test' ? 'dev' : 'prod';
    assert.equal(validarManifiesto(m).valido, true, `"${estado}" debería ser válido`);
  }

  for (const invalido of ['prod', 'PRODUCTION', 'activo', 'en_uso', 'live', 'borrador']) {
    const m = manifiestoCompleto();
    m.estado = invalido;
    const { valido, errores } = validarManifiesto(m);
    assert.equal(valido, false, `"${invalido}" no debería ser un estado válido`);
    assert.ok(errores.some((e) => e.campo === 'estado'), `no reportó el error de estado para "${invalido}"`);
  }
});

test('un workflow en test no puede declararse en prod', () => {
  const m = manifiestoCompleto();
  m.estado = 'test';
  const { valido, errores } = validarManifiesto(m);
  assert.equal(valido, false);
  assert.ok(errores.some((e) => e.campo === 'estado' && /prod/.test(e.problema)));
});

test('rechaza entorno y clasificación de datos fuera de la lista', () => {
  const conEntornoRaro = { ...manifiestoCompleto(), entorno: 'produccion' };
  assert.ok(validarManifiesto(conEntornoRaro).errores.some((e) => e.campo === 'entorno'));

  const conClaseRara = { ...manifiestoCompleto(), clasificacion_datos: 'confidencial' };
  assert.ok(validarManifiesto(conClaseRara).errores.some((e) => e.campo === 'clasificacion_datos'));

  // Con acento tiene que seguir funcionando: la plantilla del repo escribe "público".
  const conAcento = { ...manifiestoCompleto(), clasificacion_datos: 'público' };
  assert.equal(validarManifiesto(conAcento).valido, true);
});

test('las credenciales tienen que ser referencias simbólicas', () => {
  const casosMalos = [
    ['un id de credencial', ['credSinteticaTelegram01']],
    ['el nombre visible del runtime', ['Bot de ejemplo']],
    ['un objeto con el id adentro', [{ id: 'credSinteticaTelegram01', name: 'Bot de ejemplo' }]],
    ['minúsculas', ['cred_bot_de_ejemplo']],
  ];

  for (const [descripcion, credenciales] of casosMalos) {
    const m = { ...manifiestoCompleto(), credenciales };
    const { valido, errores } = validarManifiesto(m);
    assert.equal(valido, false, `debería rechazar ${descripcion}`);
    assert.ok(errores.some((e) => e.campo.startsWith('credenciales')), `no reportó el error para ${descripcion}`);
  }
});

test('el hash de rollback tiene que parecer un sha256', () => {
  const m = manifiestoCompleto();
  m.rollback.hash_sha256 = 'todavia-no-lo-calculamos';
  assert.ok(validarManifiesto(m).errores.some((e) => e.campo === 'rollback.hash_sha256'));
});

test('los estados de salida deben ser una lista cerrada, no texto libre', () => {
  const m = manifiestoCompleto();
  m.contrato.salida.estados = 'ok, error, o lo que devuelva';
  assert.ok(validarManifiesto(m).errores.some((e) => e.campo === 'contrato.salida.estados'));
});

test('generarManifiesto deriva lo derivable y deja en null lo que decide una persona', async () => {
  const workflow = await cargarFixture('workflow-limpio.json');
  const m = generarManifiesto(workflow);

  assert.equal(m.nombre_en_runtime, 'Ejemplo — Resumen diario de tareas');
  assert.equal(m.contrato.entrada.tipo, 'cron');
  assert.deepEqual(m.credenciales, ['CRED_BOT_DE_EJEMPLO', 'CRED_SERVICIO_DE_EJEMPLO_HEADER_AUTH']);
  assert.ok(m.dependencias.servicios.includes('telegram'));
  assert.ok(m.dependencias.servicios.includes('httpRequest'));

  // Lo que NO se infiere, y por qué: nadie puede deducir del JSON de quién es el
  // workflow, en qué punto de su vida está ni qué se probó.
  for (const clave of ['nombre_logico', 'owner', 'entorno', 'estado', 'clasificacion_datos']) {
    assert.equal(m[clave], null, `"${clave}" no debería inferirse`);
  }
  assert.equal(m.evidencia_test.resultado, null);
  assert.equal(m.rollback.hash_sha256, null);
});

test('el manifiesto recién generado NO valida: falta lo humano', async () => {
  const m = generarManifiesto(await cargarFixture('workflow-limpio.json'));
  const { valido, faltantes } = validarManifiesto(m);
  assert.equal(valido, false);
  assert.ok(faltantes.length >= 5);
});

test('generarManifiesto nunca copia el id de la credencial', async () => {
  const workflow = await cargarFixture('workflow-limpio.json');
  const texto = JSON.stringify(generarManifiesto(workflow));
  assert.ok(!texto.includes('credSinteticaTelegram01'));
  assert.ok(!texto.includes('credSinteticaHttp01'));
});

test('los extras pisan el esqueleto sin borrar lo derivado', async () => {
  const workflow = await cargarFixture('workflow-limpio.json');
  const m = generarManifiesto(workflow, {
    nombre_logico: 'ejemplo.resumen-diario.v1',
    owner: 'Persona De Ejemplo',
    contrato: { salida: { estados: ['ok', 'error'] } },
  });

  assert.equal(m.nombre_logico, 'ejemplo.resumen-diario.v1');
  assert.equal(m.contrato.entrada.tipo, 'cron', 'el extra no debe borrar lo que ya estaba derivado');
  assert.deepEqual(m.contrato.salida.estados, ['ok', 'error']);
});

test('el emisor de YAML produce algo legible y con las claves esperadas', () => {
  const yaml = manifiestoAYaml(manifiestoCompleto());
  assert.match(yaml, /^nombre_logico: /m);
  assert.match(yaml, /^estado: production$/m);
  assert.match(yaml, /^credenciales:\n {2}- CRED_SERVICIO_DE_EJEMPLO$/m);
  assert.match(yaml, /^contrato:\n {2}entrada:\n {4}tipo: cron$/m);
});

test('el validador no explota con basura', () => {
  for (const basura of [null, 'texto', 42, []]) {
    const r = validarManifiesto(basura);
    assert.equal(r.valido, false);
  }
});
