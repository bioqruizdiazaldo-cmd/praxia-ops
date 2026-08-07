#!/usr/bin/env node
/**
 * cli.mjs — punto de entrada único del toolkit.
 *
 *   node cli.mjs exportar|normalizar|verificar|manifiesto [opciones]
 *
 * Cada comando es un paso del pipeline de publicación documentado en
 * `docs/05-gobernanza/versionado-no-code.md`. Se pueden encadenar o usar sueltos.
 *
 * Códigos de salida, para poder usarlo en CI:
 *   0  todo bien
 *   1  la compuerta bloqueó (hallazgo de severidad alta, o manifiesto inválido)
 *   2  error de uso o de configuración
 */

import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { normalizarWorkflow, serializar, hashDeWorkflow, CAMPOS_DE_RUNTIME } from './normalizar.mjs';
import { verificarWorkflow, formatearReporte } from './verificar.mjs';
import { generarManifiesto, validarManifiesto, formatearValidacion, manifiestoAYaml } from './manifiesto.mjs';
import { exportarTodos } from './exportar.mjs';

const AYUDA = `
n8n-versionado — herramientas para versionar workflows de n8n en git.

  Un export de n8n no tiene diff legible: cambia en cada guardado aunque no hayas
  tocado nada. Estas cuatro órdenes convierten ese volcado en un artefacto
  revisable, con manifiesto y con una compuerta de secretos antes de publicar.

USO
  node cli.mjs <comando> [opciones]

COMANDOS

  exportar                     Paso 1 y 2. Trae los workflows de la API de n8n y los
                               escribe normalizados, uno por archivo.
      --destino <carpeta>      Dónde escribir (default: workflows)
      --dry-run                Lista qué traería, sin escribir nada
      --simbolizar             Reemplaza {id,name} de credencial por CRED_*
                               (obligatorio si el repositorio es público)

      Requiere N8N_URL y N8N_API_KEY en el entorno. No hay valores por defecto:
      apuntar sin querer a producción es peor que no correr. La clave nunca se
      imprime, ni completa ni parcial.

  normalizar <archivo.json>    Paso 2. Saca la metadata de runtime, ordena claves y
                               nodos, y emite la forma canónica.
      --salida <archivo>       Escribe en un archivo en vez de en stdout
      --hash                   Imprime sólo el sha256 del artefacto normalizado
      --simbolizar             Simboliza credenciales
      --campos                 Muestra la tabla de campos que se sacan y por qué

  verificar <archivo.json...>  Paso 3. Compuerta de secretos y datos personales.
                               Sale con 1 si hay algo de severidad alta.
      --estricto               La severidad media también bloquea
      --json                   Salida en JSON, para CI

  manifiesto generar <archivo.json>
                               Arma el esqueleto de los 11 campos. Lo que tiene que
                               decidir una persona queda en null, a propósito.
      --yaml                   Emite YAML en vez de JSON
      --salida <archivo>

  manifiesto validar <manifiesto.json>
                               Verifica los 11 campos, el estado de ciclo de vida y
                               que las credenciales sean simbólicas. Sale con 1 si no valida.

PIPELINE COMPLETO

  export N8N_URL=... N8N_API_KEY=...
  node cli.mjs exportar --destino workflows --simbolizar
  node cli.mjs verificar workflows/*.json
  node cli.mjs manifiesto generar workflows/mi-workflow.abc.json --yaml > MANIFIESTO.yaml
  # completar a mano lo que quedó en null, después:
  node cli.mjs manifiesto validar MANIFIESTO.json

LO QUE ESTO NO HACE

  No revisa el grafo visual (paso 7 del pipeline, y no se puede automatizar).
  No prueba que el workflow funcione. Y el escaneo de secretos busca patrones
  conocidos: que no encuentre nada no prueba que no haya nada.
`.trim();

/** Parseo de argumentos sin dependencias: banderas largas y posicionales. */
function parsearArgumentos(argv) {
  const posicionales = [];
  const opciones = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith('--')) {
      posicionales.push(arg);
      continue;
    }
    const nombre = arg.slice(2);
    const siguiente = argv[i + 1];
    if (siguiente !== undefined && !siguiente.startsWith('--')) {
      opciones[nombre] = siguiente;
      i += 1;
    } else {
      opciones[nombre] = true;
    }
  }
  return { posicionales, opciones };
}

async function leerJson(ruta) {
  try {
    return JSON.parse(await readFile(ruta, 'utf8'));
  } catch (error) {
    throw new Error(`No se pudo leer "${ruta}": ${error.message}`);
  }
}

// --- comandos ---------------------------------------------------------------

async function comandoExportar(opciones) {
  const resultado = await exportarTodos({
    destino: opciones.destino ?? 'workflows',
    dryRun: Boolean(opciones['dry-run']),
    simbolizarCredenciales: Boolean(opciones.simbolizar),
    registrar: (linea) => console.log(linea),
  });
  return resultado.total >= 0 ? 0 : 1;
}

async function comandoNormalizar(posicionales, opciones) {
  if (opciones.campos) {
    console.log('Campos que se sacan por ser metadata de runtime:\n');
    for (const campo of CAMPOS_DE_RUNTIME) {
      console.log(`  ${campo.campo}  (ámbito: ${campo.ambito})`);
      console.log(`      ${campo.porque}\n`);
    }
    return 0;
  }

  const [archivo] = posicionales;
  if (!archivo) throw new Error('Falta el archivo. Uso: node cli.mjs normalizar <archivo.json>');

  const normalizado = normalizarWorkflow(await leerJson(archivo), {
    simbolizarCredenciales: Boolean(opciones.simbolizar),
  });

  if (opciones.hash) {
    console.log(hashDeWorkflow(normalizado));
    return 0;
  }

  const texto = serializar(normalizado);
  if (opciones.salida && typeof opciones.salida === 'string') {
    await writeFile(opciones.salida, texto, 'utf8');
    console.log(`${opciones.salida}  (sha256 ${hashDeWorkflow(normalizado)})`);
  } else {
    process.stdout.write(texto);
  }
  return 0;
}

async function comandoVerificar(posicionales, opciones) {
  if (posicionales.length === 0) {
    throw new Error('Falta el archivo. Uso: node cli.mjs verificar <archivo.json...>');
  }

  const resultados = [];
  let bloquea = false;

  for (const archivo of posicionales) {
    const resultado = verificarWorkflow(await leerJson(archivo), { estricto: Boolean(opciones.estricto) });
    resultados.push({ archivo, ...resultado });
    bloquea = bloquea || resultado.bloquea;
    if (!opciones.json) console.log(formatearReporte(resultado, archivo));
  }

  if (opciones.json) console.log(JSON.stringify({ bloquea, resultados }, null, 2));
  return bloquea ? 1 : 0;
}

async function comandoManifiesto(posicionales, opciones) {
  const [accion, archivo] = posicionales;

  if (accion === 'generar') {
    if (!archivo) throw new Error('Falta el workflow. Uso: node cli.mjs manifiesto generar <archivo.json>');
    const manifiesto = generarManifiesto(await leerJson(archivo));
    const texto = opciones.yaml
      ? `# Manifiesto de workflow — PraxIA Ops\n# Generado por tools/n8n-versionado. Lo que está en null lo completa una persona.\n${manifiestoAYaml(manifiesto)}\n`
      : `${JSON.stringify(manifiesto, null, 2)}\n`;

    if (opciones.salida && typeof opciones.salida === 'string') {
      await writeFile(opciones.salida, texto, 'utf8');
      console.log(`${opciones.salida}`);
    } else {
      process.stdout.write(texto);
    }
    return 0;
  }

  if (accion === 'validar') {
    if (!archivo) throw new Error('Falta el manifiesto. Uso: node cli.mjs manifiesto validar <manifiesto.json>');
    const resultado = validarManifiesto(await leerJson(archivo));
    if (opciones.json) console.log(JSON.stringify(resultado, null, 2));
    else console.log(formatearValidacion(resultado, archivo));
    return resultado.valido ? 0 : 1;
  }

  throw new Error('Acción no reconocida. Usá: manifiesto generar | manifiesto validar');
}

// --- despacho ---------------------------------------------------------------

export async function principal(argv = process.argv.slice(2)) {
  const { posicionales, opciones } = parsearArgumentos(argv);
  const comando = posicionales.shift();

  const pidioAyuda = comando === 'ayuda' || Boolean(opciones.help || opciones.ayuda || opciones.h);
  if (pidioAyuda || !comando) {
    console.log(AYUDA);
    // Pedir ayuda es un uso correcto (0). No pasar ningún comando es un error de uso (2).
    return pidioAyuda ? 0 : 2;
  }

  switch (comando) {
    case 'exportar':
      return comandoExportar(opciones);
    case 'normalizar':
      return comandoNormalizar(posicionales, opciones);
    case 'verificar':
      return comandoVerificar(posicionales, opciones);
    case 'manifiesto':
      return comandoManifiesto(posicionales, opciones);
    default:
      throw new Error(`Comando desconocido: "${comando}". Probá con --help.`);
  }
}

// Sólo corre si se invocó este archivo directamente; importarlo desde un test no
// dispara nada.
const esEjecucionDirecta = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (esEjecucionDirecta) {
  try {
    process.exitCode = await principal();
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exitCode = 2;
  }
}
