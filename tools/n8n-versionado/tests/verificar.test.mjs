/**
 * Tests del verificador.
 *
 * Dos propiedades importan igual:
 *   1. Que encuentre lo que hay (si no, no sirve de compuerta).
 *   2. Que NO grite por cosas legítimas (si grita de más, el equipo aprende a
 *      ignorarlo, y una compuerta ignorada es peor que no tener compuerta).
 *
 * Y una tercera, que es de seguridad y no de funcionalidad: que el reporte nunca
 * contenga el valor encontrado.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { normalizarWorkflow } from '../normalizar.mjs';
import { SENUELOS, VALORES_SEMBRADOS, cargarWorkflowSucio } from './senuelos.mjs';
import { verificarWorkflow, detectarEnCadena, esCuitValido, formatearReporte } from '../verificar.mjs';

const AQUI = path.dirname(fileURLToPath(import.meta.url));

async function cargarFixture(nombre) {
  // El workflow con problemas no está versionado como tal: se arma desde una
  // plantilla, reemplazando marcadores por señuelos. Ver tests/senuelos.mjs.
  if (nombre === 'workflow-con-problemas.json') return cargarWorkflowSucio();
  return JSON.parse(await readFile(path.join(AQUI, 'fixtures', nombre), 'utf8'));
}

const tipos = (resultado) => resultado.hallazgos.map((h) => h.tipo);

test('el fixture limpio pasa la compuerta', async () => {
  const workflow = normalizarWorkflow(await cargarFixture('workflow-limpio.json'));
  const resultado = verificarWorkflow(workflow);

  assert.deepEqual(resultado.hallazgos, [], `hallazgos inesperados: ${JSON.stringify(resultado.hallazgos, null, 2)}`);
  assert.equal(resultado.bloquea, false);
  assert.equal(resultado.limpio, true);
});

test('el fixture limpio tampoco falla en modo estricto', async () => {
  const workflow = normalizarWorkflow(await cargarFixture('workflow-limpio.json'));
  assert.equal(verificarWorkflow(workflow, { estricto: true }).bloquea, false);
});

test('el fixture con problemas bloquea y encuentra cada cosa sembrada', async () => {
  const workflow = normalizarWorkflow(await cargarFixture('workflow-con-problemas.json'));
  const resultado = verificarWorkflow(workflow);
  const encontrados = tipos(resultado);

  assert.equal(resultado.bloquea, true);
  for (const esperado of [
    'clave_estilo_openai', // token plantado en una cabecera
    'cadena_de_conexion_con_contrasena', // URI de postgres con contraseña
    'credencial_con_valor', // credencial con el token adentro
    'token_de_bot_telegram',
    'secreto_en_query_string',
    'identificador_de_conversacion', // chat_id
    'correo_electronico',
    'cuit',
    'direccion_ip',
  ]) {
    assert.ok(encontrados.includes(esperado), `no detectó "${esperado}". Detectó: ${encontrados.join(', ')}`);
  }
  assert.ok(resultado.resumen.alta >= 6);
});

test('los hallazgos apuntan al nodo por nombre, no por índice', async () => {
  const workflow = normalizarWorkflow(await cargarFixture('workflow-con-problemas.json'));
  const resultado = verificarWorkflow(workflow);

  const credencial = resultado.hallazgos.find((h) => h.tipo === 'credencial_con_valor');
  assert.equal(credencial.ruta, 'nodes["Avisar al grupo"].credentials.telegramApi');

  const cuit = resultado.hallazgos.find((h) => h.tipo === 'cuit');
  assert.match(cuit.ruta, /^nodes\["Completar datos del titular"\]\./);
});

test('el reporte NUNCA contiene el valor encontrado', async () => {
  const crudo = await cargarFixture('workflow-con-problemas.json');
  const resultado = verificarWorkflow(normalizarWorkflow(crudo));

  const serializado = JSON.stringify(resultado) + formatearReporte(resultado, 'fixture');
  for (const valor of VALORES_SEMBRADOS) {
    assert.ok(!serializado.includes(valor), `el reporte filtró el valor "${valor.slice(0, 6)}…"`);
  }
});

test('no da falso positivo con un correo de dominio de ejemplo', () => {
  for (const correo of ['soporte@example.com', 'x@example.org', 'y@algo.invalid', 'z@localhost']) {
    assert.deepEqual(detectarEnCadena('$.p', correo), [], `${correo} no debería ser un hallazgo`);
  }
  assert.equal(detectarEnCadena('$.p', 'contacto@empresa-real-cualquiera.com').length, 1);
});

test('no da falso positivo con un id de credencial ni con una expresión de n8n', () => {
  const inocuos = [
    'credSinteticaTelegram01',
    '={{ $credentials.httpHeaderAuth.value }}',
    '={{ $json.chat_id }}',
    'https://api.servicio-de-ejemplo.example.com/v1/tareas',
    'INSERT INTO contactos (nombre) VALUES ($1)',
    'application/json',
    '2026-08-06T18:41:07.512Z',
  ];
  for (const valor of inocuos) {
    assert.deepEqual(detectarEnCadena('$.parameters.valor', valor), [], `"${valor}" no debería disparar nada`);
  }
});

test('un chat_id por expresión no es hallazgo; uno literal sí', async () => {
  const limpio = normalizarWorkflow(await cargarFixture('workflow-limpio.json'));
  assert.ok(!tipos(verificarWorkflow(limpio)).includes('identificador_de_conversacion'));

  const conChatId = { nodes: [{ name: 'Enviar', parameters: { chatId: '-1009876543210' } }], connections: {} };
  const resultado = verificarWorkflow(conChatId);
  assert.deepEqual(tipos(resultado), ['identificador_de_conversacion']);
  assert.equal(resultado.hallazgos[0].severidad, 'alta');
});

test('una credencial por referencia pura no es hallazgo; una con datos adentro sí', () => {
  const referencia = {
    nodes: [{ name: 'A', credentials: { telegramApi: { id: 'credSintetica01', name: 'Bot de ejemplo' } } }],
    connections: {},
  };
  assert.deepEqual(verificarWorkflow(referencia).hallazgos, []);

  const simbolizada = { nodes: [{ name: 'A', credentials: { telegramApi: { referencia: 'CRED_BOT' } } }], connections: {} };
  assert.deepEqual(verificarWorkflow(simbolizada).hallazgos, []);

  const conValor = {
    nodes: [{ name: 'A', credentials: { telegramApi: { id: 'credSintetica01', name: 'Bot', data: { token: 'lo-que-sea-largo' } } } }],
    connections: {},
  };
  const resultado = verificarWorkflow(conValor);
  assert.ok(tipos(resultado).includes('credencial_con_valor'));
  assert.equal(resultado.bloquea, true);
});

test('el formato antiguo de credencial avisa pero no bloquea', () => {
  const antiguo = { nodes: [{ name: 'A', credentials: { telegramApi: 'Bot de ejemplo' } }], connections: {} };
  const resultado = verificarWorkflow(antiguo);
  assert.deepEqual(tipos(resultado), ['credencial_en_formato_antiguo']);
  assert.equal(resultado.bloquea, false);
  assert.equal(verificarWorkflow(antiguo, { estricto: true }).bloquea, true);
});

test('detecta claves privadas, JWT y tokens de otros proveedores', () => {
  const casos = [
    ['clave_privada', SENUELOS.clavePrivada],
    ['jwt', SENUELOS.jwt],
    ['token_de_github', SENUELOS.github],
    ['clave_de_acceso_aws', SENUELOS.aws],
    ['token_de_slack', SENUELOS.slack],
  ];
  for (const [tipo, valor] of casos) {
    const hallazgos = detectarEnCadena('$.p', valor).map((h) => h.tipo);
    assert.ok(hallazgos.includes(tipo), `no detectó ${tipo}`);
  }
});

test('el CUIT se valida por dígito verificador, no sólo por forma', () => {
  assert.equal(esCuitValido('20-11111111-2'), true);
  assert.equal(esCuitValido('20-11111111-9'), false, 'un dígito verificador que no cierra no es un CUIT');
  assert.deepEqual(detectarEnCadena('$.p', 'Factura 20-11111111-9 del mes'), [], 'sin verificador válido, no se reporta');
  assert.equal(detectarEnCadena('$.p', 'Titular 20-11111111-2').length, 1);
});

test('las IP de loopback y los resolvers públicos no cuentan como topología', () => {
  for (const ip of ['127.0.0.1', '0.0.0.0', '8.8.8.8']) {
    assert.deepEqual(detectarEnCadena('$.p', `http://${ip}:5678/`), []);
  }
  assert.equal(detectarEnCadena('$.p', 'http://10.20.30.40:5678/').length, 1);
});

test('verificar sobre el JSON crudo también encuentra lo que hay en pinData', async () => {
  const crudo = await cargarFixture('workflow-con-problemas.json');
  crudo.pinData = { 'Webhook de alta': [{ json: { email: 'persona.inventada@otro-dominio-inventado.com' } }] };
  const resultado = verificarWorkflow(crudo);
  assert.ok(tipos(resultado).includes('correo_electronico'));
});

test('el reporte formateado dice explícitamente que no prueba ausencia', async () => {
  const limpio = normalizarWorkflow(await cargarFixture('workflow-limpio.json'));
  assert.match(formatearReporte(verificarWorkflow(limpio), 'limpio'), /No prueba que no haya secretos/);
});
