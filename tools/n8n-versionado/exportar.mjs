/**
 * exportar.mjs — paso 1 del pipeline: sacar los workflows del runtime.
 *
 * Trae los workflows por la API pública de n8n y los deja en disco, uno por
 * archivo y ya normalizados. Un archivo por workflow y no un volcado único,
 * porque el diff de un archivo con 217 workflows adentro no le sirve a nadie:
 * el objetivo de todo esto es poder revisar un cambio.
 *
 * Sobre la configuración: `N8N_URL` y `N8N_API_KEY` se leen del entorno y NO
 * tienen valor por defecto. Es el mismo criterio del servidor MCP. Un default
 * silencioso —"si no hay URL, uso localhost"— es cómodo hasta el día en que
 * apunta a producción sin que nadie lo haya pedido.
 *
 * Sobre la clave: no se imprime nunca, ni completa ni parcial. Un prefijo de
 * cuatro caracteres en el log de CI no sirve para depurar y sí reduce el espacio
 * de búsqueda de quien la quiera.
 */

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { normalizarWorkflow, serializar, hashDeWorkflow } from './normalizar.mjs';

/**
 * Lee y valida la configuración. Falla temprano y con un mensaje que dice qué
 * falta y cómo se arregla.
 */
export function leerConfiguracion(entorno = process.env) {
  const url = (entorno.N8N_URL ?? '').trim();
  const apiKey = (entorno.N8N_API_KEY ?? '').trim();
  const faltantes = [];
  if (!url) faltantes.push('N8N_URL');
  if (!apiKey) faltantes.push('N8N_API_KEY');

  if (faltantes.length > 0) {
    throw new Error(
      `Falta configuración: ${faltantes.join(' y ')}.\n` +
        '  Este exportador no asume ninguna instancia por defecto: apuntar sin querer a\n' +
        '  producción es peor que no correr. Definí las variables antes de ejecutar:\n' +
        '    export N8N_URL="https://tu-instancia-de-n8n"\n' +
        '    export N8N_API_KEY="<la clave, que nunca se escribe en un archivo versionado>"',
    );
  }

  if (!/^https?:\/\//i.test(url)) {
    throw new Error(`N8N_URL debe empezar con http:// o https:// (recibido: "${url}").`);
  }
  if (/^http:\/\//i.test(url) && !/^http:\/\/(localhost|127\.0\.0\.1)/i.test(url)) {
    // Aviso, no error: hay instancias detrás de un proxy interno. Pero mandar la
    // API key en claro por la red merece que alguien lo lea.
    process.emitWarning('N8N_URL usa http sin TLS: la API key viaja en claro.');
  }

  return { url: url.replace(/\/+$/, ''), apiKey };
}

/**
 * Quita un secreto de un texto antes de imprimirlo.
 * Se usa en el manejo de errores: un mensaje de fetch puede arrastrar la URL
 * completa o el encabezado, y ese texto termina en un log.
 */
export function ocultarSecreto(texto, secreto) {
  if (!secreto) return String(texto);
  return String(texto).split(secreto).join('«API KEY OCULTA»');
}

/** Nombre de archivo estable a partir del nombre visible del workflow. */
export function aSlug(texto, largoMaximo = 60) {
  const base = String(texto ?? '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, largoMaximo)
    .replace(/-+$/g, '');
  return base || 'sin-nombre';
}

/**
 * El id de instancia va en el nombre del archivo —no adentro del JSON, de donde
 * el normalizador lo saca— para que dos workflows con el mismo nombre no se
 * pisen. Si el id molesta en el repositorio, se renombra el archivo a mano: el
 * contenido no depende de él.
 */
export function nombreDeArchivo(workflow) {
  const id = String(workflow?.id ?? 'sin-id').replace(/[^A-Za-z0-9_-]/g, '');
  return `${aSlug(workflow?.name)}.${id}.json`;
}

/**
 * Recorre la API paginando por cursor hasta que no haya más.
 *
 * @param {object} config     { url, apiKey }
 * @param {object} [opciones]
 * @param {number} [opciones.limite=100]      tamaño de página
 * @param {Function} [opciones.fetchImpl]     inyectable para poder testear sin red
 * @param {number} [opciones.paginasMaximas=200] cortafuegos contra un cursor que no avanza
 */
export async function* recorrerWorkflows(config, opciones = {}) {
  const { limite = 100, fetchImpl = globalThis.fetch, paginasMaximas = 200 } = opciones;
  let cursor = null;
  let paginas = 0;

  do {
    const url = new URL('/api/v1/workflows', config.url);
    url.searchParams.set('limit', String(limite));
    if (cursor) url.searchParams.set('cursor', cursor);

    let respuesta;
    try {
      respuesta = await fetchImpl(url.toString(), {
        method: 'GET',
        headers: { 'X-N8N-API-KEY': config.apiKey, accept: 'application/json' },
      });
    } catch (error) {
      throw new Error(`No se pudo contactar la API de n8n: ${ocultarSecreto(error?.message ?? error, config.apiKey)}`);
    }

    if (!respuesta.ok) {
      const pista =
        respuesta.status === 401
          ? ' La clave fue rechazada. Verificá N8N_API_KEY (sin imprimirla).'
          : respuesta.status === 404
            ? ' ¿La API pública está habilitada en esa instancia?'
            : '';
      throw new Error(`La API de n8n respondió ${respuesta.status}.${pista}`);
    }

    const cuerpo = await respuesta.json();
    const datos = Array.isArray(cuerpo?.data) ? cuerpo.data : [];
    for (const workflow of datos) yield workflow;

    const siguiente = cuerpo?.nextCursor ?? null;
    // Si el cursor no cambia, la API está devolviendo lo mismo para siempre.
    cursor = siguiente && siguiente !== cursor ? siguiente : null;
    paginas += 1;
  } while (cursor && paginas < paginasMaximas);
}

/**
 * Exporta todos los workflows a `destino`.
 *
 * @param {object} opciones
 * @param {string} opciones.destino
 * @param {boolean} [opciones.dryRun=false]  lista lo que traería, no escribe nada
 * @param {boolean} [opciones.simbolizarCredenciales=false]
 * @param {object}  [opciones.entorno=process.env]
 * @param {Function} [opciones.fetchImpl]
 * @param {Function} [opciones.registrar=console.log]
 * @returns {Promise<{archivos:Array, total:number, dryRun:boolean}>}
 */
export async function exportarTodos(opciones = {}) {
  const {
    destino = 'workflows',
    dryRun = false,
    simbolizarCredenciales = false,
    entorno = process.env,
    fetchImpl = globalThis.fetch,
    registrar = () => {},
  } = opciones;

  const config = leerConfiguracion(entorno);
  const archivos = [];

  if (!dryRun) await mkdir(destino, { recursive: true });

  for await (const crudo of recorrerWorkflows(config, { fetchImpl })) {
    const normalizado = normalizarWorkflow(crudo, { simbolizarCredenciales });
    const nombre = nombreDeArchivo(crudo);
    const ruta = path.join(destino, nombre);
    const hash = hashDeWorkflow(normalizado);
    const contenido = serializar(normalizado);

    if (dryRun) {
      registrar(`[dry-run] ${ruta}  (${contenido.length} bytes, sha256 ${hash.slice(0, 12)}…)`);
    } else {
      await writeFile(ruta, contenido, 'utf8');
      registrar(`escrito   ${ruta}  (sha256 ${hash.slice(0, 12)}…)`);
    }

    archivos.push({ ruta, nombre, hash, bytes: contenido.length, nombreEnRuntime: crudo?.name ?? null });
  }

  registrar(`${dryRun ? 'Se traerían' : 'Se escribieron'} ${archivos.length} workflow(s) en ${destino}.`);
  return { archivos, total: archivos.length, dryRun };
}
