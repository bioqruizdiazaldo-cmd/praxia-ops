/**
 * normalizar.mjs — el corazón del toolkit.
 *
 * Toma el JSON crudo que devuelve n8n y produce una forma estable y comparable:
 * la misma entrada semántica siempre da los mismos bytes.
 *
 * Por qué existe: un export de n8n cambia en cada guardado aunque no hayas
 * tocado nada de fondo. Arrastrás un nodo dos píxeles y el diff son cuatrocientas
 * líneas. Un diff ilegible es un diff que nadie lee, y una revisión que nadie
 * hace igual deja registro de haberse hecho. Eso es peor que no revisar.
 *
 * La regla que gobierna todo este archivo:
 *
 *   Se saca lo que cambia sin que cambie el comportamiento.
 *   No se saca NADA que pueda cambiar el comportamiento.
 *
 * Ante la duda, se conserva. Un normalizador que borra de más rompe despliegues;
 * uno que borra de menos sólo deja ruido en el diff.
 */

import { createHash } from 'node:crypto';

/**
 * Los campos que se sacan, con su ámbito y el motivo.
 *
 * Está exportada a propósito: alguien tiene que poder auditar qué se saca sin
 * leer el código. Si algún día hace falta discutir una remoción, se discute
 * contra esta tabla.
 *
 * `ambito` dice DÓNDE se saca el campo. Es deliberado que no sea recursivo:
 * borrar toda clave llamada `id` en cualquier nivel rompería parámetros
 * legítimos de nodos (un `id` de hoja de cálculo, un `id` de fila).
 */
export const CAMPOS_DE_RUNTIME = [
  {
    campo: 'id',
    ambito: 'raiz',
    porque:
      'Identificador del workflow DENTRO de esta instancia de n8n. Al importar en ' +
      'otra instancia cambia. Además es un dato interno que no aporta nada en un repositorio público.',
  },
  {
    campo: 'versionId',
    ambito: 'raiz',
    porque:
      'UUID que n8n regenera en cada guardado, incluso si no cambiaste nada. ' +
      'Es la fuente de ruido número uno del diff.',
  },
  {
    campo: 'createdAt',
    ambito: 'raiz',
    porque: 'Marca de tiempo de la instancia. El historial de creación lo lleva git, no el JSON.',
  },
  {
    campo: 'updatedAt',
    ambito: 'raiz',
    porque:
      'Cambia en cada guardado. Si quedara, dos exports idénticos producirían un diff ' +
      'y el hash del artefacto nunca sería estable.',
  },
  {
    campo: 'active',
    ambito: 'raiz',
    porque:
      'Es estado de despliegue, no del artefacto. Qué está activo lo decide el entorno de destino; ' +
      'el manifiesto declara el estado de ciclo de vida. Si viajara en el JSON, importar un ' +
      'artefacto podría activarlo solo.',
  },
  {
    campo: 'triggerCount',
    ambito: 'raiz',
    porque: 'Contador de runtime. Cambia con el uso y no describe el workflow.',
  },
  {
    campo: 'shared',
    ambito: 'raiz',
    porque:
      'Permisos y propietarios dentro de la instancia: incluye usuarios, correos y roles. ' +
      'Es dato personal y de infraestructura, y no describe el flujo.',
  },
  {
    campo: 'pinData',
    ambito: 'raiz',
    porque:
      'Datos de prueba pegados a los nodos durante el desarrollo. Además de ruido, es el ' +
      'riesgo más común de fuga: casi siempre son datos REALES capturados de una ejecución.',
  },
  {
    campo: 'staticData',
    ambito: 'raiz',
    porque:
      'Estado que el workflow acumula entre ejecuciones (cursores, últimos IDs vistos). ' +
      'Es memoria de la instancia, no definición del flujo.',
  },
  {
    campo: 'instanceId',
    ambito: 'meta',
    porque:
      'Huella de la instancia de n8n que exportó el archivo. Identifica el servidor. ' +
      'Cero valor semántico, y en un repositorio público es información de infraestructura.',
  },
  {
    campo: 'position',
    ambito: 'nodo',
    porque:
      'Coordenadas del nodo en el lienzo. Mover un nodo dos píxeles no cambia absolutamente ' +
      'nada del comportamiento y ensucia el diff. Al importar, n8n reacomoda igual.',
  },
  {
    campo: 'webhookId',
    ambito: 'nodo',
    porque:
      'UUID que n8n asigna al webhook EN ESTA INSTANCIA. Se regenera al importar en otra. ' +
      'Versionarlo hace creer que la URL del webhook es portable, y no lo es.',
  },
  {
    campo: 'id',
    ambito: 'nodo',
    porque:
      'UUID interno del nodo, regenerado al reimportar. Las conexiones referencian a los nodos ' +
      'POR NOMBRE, no por este id, así que sacarlo no rompe el grafo. Verificado contra la ' +
      'estructura de `connections`, que usa nombres como clave.',
  },
  {
    campo: 'id | createdAt | updatedAt',
    ambito: 'tag',
    porque:
      'De cada etiqueta sólo importa el nombre. Su id y sus marcas de tiempo son de la instancia ' +
      'y cambian al reimportar.',
  },
];

/** Estados que NO se tocan nunca, y por qué. Documentado para que se pueda discutir. */
export const CAMPOS_QUE_NUNCA_SE_TOCAN = [
  { campo: 'parameters', porque: 'Es el comportamiento del nodo. Sacar cualquier cosa de acá cambia lo que hace.' },
  { campo: 'connections', porque: 'Es la topología del grafo. Ni se poda ni se reordena.' },
  { campo: 'type / typeVersion', porque: 'Definen qué nodo es y con qué semántica se ejecuta.' },
  { campo: 'credentials', porque: 'Se conserva la REFERENCIA ({id, name}). Sin ella el nodo no resuelve nada al importar.' },
  { campo: 'settings', porque: 'Timezone, errorWorkflow, política de ejecución: todo funcional.' },
  { campo: 'disabled / notesInFlow / continueOnFail', porque: 'Cambian el comportamiento o la lectura del grafo.' },
  { campo: 'name', porque: 'Es la clave por la que las conexiones referencian al nodo. Renombrar es un cambio real.' },
];

const CAMPOS_RAIZ = CAMPOS_DE_RUNTIME.filter((c) => c.ambito === 'raiz').map((c) => c.campo);
const CAMPOS_NODO = CAMPOS_DE_RUNTIME.filter((c) => c.ambito === 'nodo').map((c) => c.campo);

/**
 * Compara dos strings por unidades de código UTF-16.
 *
 * A propósito NO usa `localeCompare`: el orden de `localeCompare` depende del
 * locale del sistema, y entonces el mismo workflow normalizado en dos máquinas
 * distintas daría archivos distintos. Todo el valor de esto es que no pase.
 */
function compararTexto(a, b) {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

function esObjetoPlano(valor) {
  return valor !== null && typeof valor === 'object' && !Array.isArray(valor);
}

/**
 * Ordena alfabéticamente las claves de todo objeto, en todos los niveles.
 *
 * Los arrays se recorren pero NO se reordenan: el orden de un array puede ser
 * semántico (las salidas de un `IF`, por ejemplo, van por índice). El único
 * array que se reordena es `nodes`, y se hace aparte y a conciencia.
 */
export function ordenarClaves(valor) {
  if (Array.isArray(valor)) return valor.map(ordenarClaves);
  if (!esObjetoPlano(valor)) return valor;

  const salida = {};
  for (const clave of Object.keys(valor).sort(compararTexto)) {
    salida[clave] = ordenarClaves(valor[clave]);
  }
  return salida;
}

/**
 * Convierte el nombre visible de una credencial en una referencia simbólica.
 * "Telegram Bot Principal" → CRED_TELEGRAM_BOT_PRINCIPAL
 */
export function simboloDeCredencial(nombre, tipo = 'desconocida') {
  const base = String(nombre ?? tipo ?? 'desconocida')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toUpperCase();
  return `CRED_${base || 'DESCONOCIDA'}`;
}

function normalizarCredenciales(credenciales, simbolizar) {
  if (!esObjetoPlano(credenciales)) return credenciales;
  if (!simbolizar) return credenciales;

  const salida = {};
  for (const [tipo, ref] of Object.entries(credenciales)) {
    // El formato viejo de n8n guardaba sólo el nombre como string. Igual es
    // una referencia, así que se respeta y se simboliza.
    const nombre = typeof ref === 'string' ? ref : ref?.name;
    salida[tipo] = { referencia: simboloDeCredencial(nombre, tipo) };
  }
  return salida;
}

function normalizarNodo(nodo, opciones) {
  if (!esObjetoPlano(nodo)) return nodo;

  const copia = { ...nodo };
  for (const campo of CAMPOS_NODO) delete copia[campo];

  if (copia.credentials !== undefined) {
    copia.credentials = normalizarCredenciales(copia.credentials, opciones.simbolizarCredenciales);
  }
  return copia;
}

/**
 * De cada etiqueta sobrevive el nombre y nada más.
 * Se devuelven strings ordenados: un array de strings tiene diff línea a línea,
 * un array de objetos con ids no tiene diff útil.
 */
function normalizarEtiquetas(tags) {
  if (!Array.isArray(tags)) return tags;
  return tags
    .map((t) => (typeof t === 'string' ? t : t?.name))
    .filter((n) => typeof n === 'string' && n.length > 0)
    .sort(compararTexto);
}

/**
 * Normaliza un workflow completo.
 *
 * @param {object} workflow  JSON crudo tal como lo devuelve la API de n8n.
 * @param {object} [opciones]
 * @param {boolean} [opciones.simbolizarCredenciales=false]
 *        Reemplaza `{id, name}` por `{referencia: 'CRED_...'}`. Se deja apagado
 *        por default porque `verificar.mjs` necesita ver la forma original para
 *        poder juzgarla, y porque un artefacto simbolizado ya no se puede
 *        reimportar tal cual: hace falta remapear en el destino. Para publicar
 *        en un repositorio abierto, encenderlo.
 * @returns {object} workflow normalizado (no muta la entrada)
 */
export function normalizarWorkflow(workflow, opciones = {}) {
  if (!esObjetoPlano(workflow)) {
    throw new TypeError('normalizarWorkflow espera un objeto de workflow de n8n.');
  }
  const opts = { simbolizarCredenciales: false, ...opciones };

  // Copia superficial y después reemplazo de las ramas que se tocan: alcanza
  // porque no se muta nada en profundidad, se construyen objetos nuevos.
  const copia = { ...workflow };
  for (const campo of CAMPOS_RAIZ) delete copia[campo];

  if (esObjetoPlano(copia.meta)) {
    const meta = { ...copia.meta };
    delete meta.instanceId;
    // Un `meta: {}` vacío es ruido puro: aparece y desaparece según la versión
    // de n8n que exportó.
    if (Object.keys(meta).length === 0) delete copia.meta;
    else copia.meta = meta;
  }

  if (Array.isArray(copia.nodes)) {
    copia.nodes = copia.nodes
      .map((nodo) => normalizarNodo(nodo, opts))
      // Por nombre y no por id: el id se va, el nombre es la clave real del grafo.
      // El desempate por `type` mantiene el orden determinístico incluso con
      // nombres repetidos (n8n no debería permitirlo, pero un JSON armado a mano sí).
      .sort((a, b) => compararTexto(String(a?.name ?? ''), String(b?.name ?? '')) ||
        compararTexto(String(a?.type ?? ''), String(b?.type ?? '')));
  }

  if (copia.tags !== undefined) copia.tags = normalizarEtiquetas(copia.tags);

  return ordenarClaves(copia);
}

/**
 * Serialización canónica: indentación fija de 2, una sola nueva línea al final,
 * sin espacios colgando. Es lo que se commitea y lo que se hashea.
 */
export function serializar(workflowNormalizado) {
  return `${JSON.stringify(workflowNormalizado, null, 2)}\n`;
}

/**
 * Hash del artefacto normalizado — el paso 9 del pipeline ("registrar el hash
 * desplegado") sólo tiene sentido si el mismo workflow da siempre el mismo hash.
 * Sin normalización previa, este número cambiaría en cada guardado y no
 * detectaría ningún drift.
 */
export function hashDeWorkflow(workflowNormalizado) {
  return createHash('sha256').update(serializar(workflowNormalizado), 'utf8').digest('hex');
}

/** Atajo cómodo: crudo → texto listo para escribir en disco. */
export function normalizarATexto(workflow, opciones) {
  return serializar(normalizarWorkflow(workflow, opciones));
}
