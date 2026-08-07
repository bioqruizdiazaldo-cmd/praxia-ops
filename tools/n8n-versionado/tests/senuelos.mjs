/**
 * Señuelos: valores con forma de secreto, para probar que el verificador los
 * encuentra.
 *
 * Ninguno aparece completo en el código fuente. Se arman en tiempo de
 * ejecución, uniendo pedazos.
 *
 * La razón no es estética. La protección de push de GitHub escanea el
 * contenido de los blobs del commit, no la intención de quien los escribió, y
 * rechazó un push de este repositorio por un token de Slack **falso** escrito
 * literal en un test. Tenía razón en rechazarlo: un escáner que distinguiera
 * "secretos de verdad" de "secretos de mentira" no serviría para nada, porque
 * el que filtra una clave siempre cree que la suya es un caso especial.
 *
 * La salida no fue pedirle a GitHub que hiciera una excepción. Fue dejar de
 * escribir cadenas con forma de secreto. Así el repositorio no necesita
 * excepciones: ni en la protección de push de GitHub, ni en su propio escaneo
 * de CI, ni en el escáner local que corre antes de publicar. Una regla sin
 * excepciones es una regla que se puede verificar.
 *
 * Los pedazos están cortados a propósito donde el escáner busca el prefijo.
 */

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const unir = (...partes) => partes.join('');

export const SENUELOS = {
  openai: unir('sk', '-', 'EJEMPLOsintetico', '000000000000'),
  github: unir('gh', 'p', '_', 'EJEMPLOsinteticoDeTokenGithub01'),
  aws: unir('AK', 'IA', 'EJEMPLOSINTETIC0'),
  slack: unir('xo', 'xb', '-', '000000000000', '-EJEMPLOsintetico'),
  telegram: unir('1234567890', ':', 'AA', 'EJEMPLOsinteticoDeTokenDeBotNoReal0'),
  jwt: unir('ey', 'JhbGciOiJIUzI1NiJ9', '.', 'ey', 'JzdWIiOiIxMjM0NTY3ODkwIn0', '.', 'EjemploDeFirmaSintetica'),
  clavePrivada: unir(
    '-----', 'BEGIN', ' RSA PRIVATE KEY-----\n',
    'MIIEjemploSinteticoQueNoEsUnaClave\n',
    '-----', 'END', ' RSA PRIVATE KEY-----',
  ),
  conexion: unir('postgre', 'sql://usuario_demo', ':', 'clave-de-ejemplo', '@', 'db-ejemplo:5432/demo'),
  claveEnQueryString: unir('EJEMPLO', 'sintetico', '1234567890'),
};

/** Valores sembrados que el reporte no debe contener nunca. */
export const VALORES_SEMBRADOS = [
  SENUELOS.openai,
  SENUELOS.telegram,
  'clave-de-ejemplo',
  SENUELOS.claveEnQueryString,
  'usuario.demo@dominio-inventado.com',
  '20-11111111-2',
  '-1001234567890',
  '10.20.30.40',
];

const SUSTITUCIONES = {
  __SENUELO_OPENAI__: SENUELOS.openai,
  __SENUELO_TELEGRAM__: SENUELOS.telegram,
  __SENUELO_CONEXION__: SENUELOS.conexion,
  __SENUELO_QUERY_STRING__: SENUELOS.claveEnQueryString,
};

/**
 * Arma el workflow con problemas a partir de la plantilla versionada,
 * reemplazando cada marcador por su señuelo.
 */
export async function cargarWorkflowSucio() {
  const plantilla = await readFile(path.join(AQUI, 'fixtures', 'workflow-con-problemas.plantilla.json'), 'utf8');
  let texto = plantilla;
  for (const [marcador, valor] of Object.entries(SUSTITUCIONES)) {
    texto = texto.split(marcador).join(valor);
  }
  const huerfano = texto.match(/__SENUELO_[A-Z_]+__/);
  if (huerfano) {
    throw new Error(`La plantilla tiene el marcador ${huerfano[0]} sin sustituir. Agregalo a SUSTITUCIONES en senuelos.mjs`);
  }
  return JSON.parse(texto);
}

/**
 * Escribe el workflow con problemas en un directorio temporal y devuelve la
 * ruta. Lo usan los tests del CLI, que necesitan un archivo real en disco.
 */
export async function materializarWorkflowSucio(directorio) {
  await mkdir(directorio, { recursive: true });
  const destino = path.join(directorio, 'workflow-con-problemas.json');
  await writeFile(destino, JSON.stringify(await cargarWorkflowSucio(), null, 2), 'utf8');
  return destino;
}
