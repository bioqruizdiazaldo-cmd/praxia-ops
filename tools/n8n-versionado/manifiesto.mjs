/**
 * manifiesto.mjs — genera y valida el manifiesto de 11 campos.
 *
 * Los once campos no los inventa este archivo: están definidos en
 * `artifacts/workflows-n8n/manifiesto-de-workflow.md` y en
 * `docs/05-gobernanza/versionado-no-code.md`. Acá se implementan tal cual.
 *
 * Por qué un manifiesto y no sólo el JSON: un export es un volcado. No dice de
 * quién es, en qué punto de su vida está, qué se probó ni a qué versión se
 * vuelve. Seis meses después, esas son las únicas preguntas que importan.
 *
 * Decisión de formato: se trabaja en JSON, no en YAML. Un parser de YAML sería
 * una dependencia, y la regla del toolkit es cero dependencias. La estructura es
 * exactamente la misma que la plantilla del repositorio, y `manifiestoAYaml()`
 * emite el YAML para pegar en el MANIFIESTO.md.
 *
 * El generador deja en `null` todo lo que tiene que decidir una persona. Es a
 * propósito: un manifiesto autocompletado con valores plausibles es peor que uno
 * vacío, porque parece revisado. Vale más un vacío explícito que una narración
 * no demostrable.
 */

/** Campo 4: los seis estados del ciclo de vida. Ni uno más. */
export const ESTADOS_DE_CICLO_DE_VIDA = ['draft', 'test', 'staging', 'production', 'deprecated', 'archived'];

/** Campo 3: los entornos declarables. `prod` se declara aunque no haya staging: así la carencia se ve. */
export const ENTORNOS = ['dev', 'staging', 'prod'];

/** Campo 8: clasificación de datos. */
export const CLASIFICACIONES_DE_DATOS = ['publico', 'interno', 'personal', 'financiero', 'sensible'];

/** Campo 5: tipos de entrada posibles. */
export const TIPOS_DE_ENTRADA = ['trigger', 'herramienta', 'webhook', 'cron'];

/**
 * Los 11 campos, con las subclaves que también son obligatorias.
 * `requiere` lista rutas relativas dentro del campo: si el campo existe pero le
 * falta una subclave, el manifiesto está incompleto igual.
 */
export const CAMPOS_DEL_MANIFIESTO = [
  { n: 1, clave: 'nombre_logico', descripcion: 'Nombre lógico estable, independiente del nombre en el lienzo' },
  { n: 2, clave: 'owner', descripcion: 'Persona responsable. No un equipo, no "IA"' },
  { n: 3, clave: 'entorno', descripcion: 'dev | staging | prod' },
  { n: 4, clave: 'estado', descripcion: 'Estado de ciclo de vida' },
  { n: 5, clave: 'contrato', descripcion: 'Entrada y salida con tipos y estados', requiere: ['entrada.tipo', 'entrada.esquema', 'salida.esquema', 'salida.estados'] },
  { n: 6, clave: 'dependencias', descripcion: 'Workflows, datos y servicios de los que depende', requiere: ['workflows', 'datos', 'servicios'] },
  { n: 7, clave: 'credenciales', descripcion: 'Sólo referencias simbólicas (CRED_*)' },
  { n: 8, clave: 'clasificacion_datos', descripcion: 'público | interno | personal | financiero | sensible' },
  { n: 9, clave: 'origen', descripcion: 'De dónde salió y quién lo revisó', requiere: ['procedencia', 'revisado_por', 'fecha_revision'] },
  { n: 10, clave: 'evidencia_test', descripcion: 'Qué se probó, con qué y con qué resultado', requiere: ['fixtures', 'resultado', 'fecha'] },
  { n: 11, clave: 'rollback', descripcion: 'Dónde está el export anterior y su hash', requiere: ['artefacto', 'hash_sha256', 'verificado'] },
];

function sinAcentos(texto) {
  return String(texto)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
}

function leerRuta(objeto, ruta) {
  return ruta.split('.').reduce((acc, parte) => (acc === null || acc === undefined ? undefined : acc[parte]), objeto);
}

/** Vacío = ausente. Un `null`, un string en blanco o un objeto sin claves no completan nada. */
function estaVacio(valor) {
  if (valor === null || valor === undefined) return true;
  if (typeof valor === 'string') return valor.trim().length === 0;
  if (Array.isArray(valor)) return false; // `[]` es una declaración válida: "ninguno"
  if (typeof valor === 'object') return Object.keys(valor).length === 0;
  return false;
}

/** Nodos que representan una invocación a otro workflow. */
const TIPOS_DE_SUBWORKFLOW = ['executeWorkflow', 'toolWorkflow'];

function inferirTipoDeEntrada(nodos) {
  const tipos = nodos.map((n) => String(n?.type ?? ''));
  if (tipos.some((t) => t.includes('executeWorkflowTrigger'))) return 'herramienta';
  if (tipos.some((t) => t.includes('webhook') || t.includes('chatTrigger'))) return 'webhook';
  if (tipos.some((t) => t.includes('scheduleTrigger') || t.includes('cron') || t.includes('interval'))) return 'cron';
  if (tipos.some((t) => /trigger$/i.test(t))) return 'trigger';
  return null; // que lo complete una persona: adivinar acá sería inventar el contrato
}

function inferirServicios(nodos) {
  const servicios = new Set();
  for (const nodo of nodos) {
    const tipo = String(nodo?.type ?? '');
    // n8n-nodes-base.telegram → telegram · @n8n/n8n-nodes-langchain.lmChatOpenAi → lmChatOpenAi
    const corto = tipo.split('.').pop();
    if (!corto) continue;
    if (/^(set|if|switch|merge|code|noOp|stickyNote|splitInBatches|filter|itemLists|aggregate|executeWorkflow|executeWorkflowTrigger|manualTrigger)$/i.test(corto)) continue;
    servicios.add(corto);
  }
  return [...servicios].sort();
}

function inferirCredenciales(nodos) {
  const referencias = new Set();
  for (const nodo of nodos) {
    const credenciales = nodo?.credentials;
    if (!credenciales || typeof credenciales !== 'object') continue;
    for (const [tipo, ref] of Object.entries(credenciales)) {
      // Si el artefacto ya viene simbolizado, la referencia se respeta tal cual.
      // Si no, se deriva del nombre visible. El id NUNCA entra al manifiesto:
      // es el campo 7 completo, "nunca el ID de la credencial".
      if (typeof ref?.referencia === 'string') {
        referencias.add(ref.referencia);
        continue;
      }
      const nombre = typeof ref === 'string' ? ref : ref?.name;
      referencias.add(simbolizar(nombre ?? tipo));
    }
  }
  return [...referencias].sort();
}

function simbolizar(nombre) {
  const base = sinAcentos(nombre)
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .toUpperCase();
  return `CRED_${base || 'DESCONOCIDA'}`;
}

function inferirSubworkflows(nodos) {
  const invocados = [];
  for (const nodo of nodos) {
    const tipo = String(nodo?.type ?? '');
    if (!TIPOS_DE_SUBWORKFLOW.some((t) => tipo.includes(t))) continue;
    // El `workflowId` es un id de instancia: no se copia al manifiesto. Lo que
    // corresponde acá es el nombre lógico del workflow invocado, y eso lo pone
    // una persona. Se deja el nombre del nodo como pista.
    invocados.push({ nodo: nodo?.name ?? null, nombre_logico: null });
  }
  return invocados;
}

/**
 * Arma el esqueleto del manifiesto a partir del workflow.
 *
 * Lo que se puede derivar del JSON sin interpretar nada, se deriva. Todo lo
 * demás queda en `null` para que `validarManifiesto` lo reclame.
 *
 * @param {object} workflow  workflow de n8n (crudo o normalizado)
 * @param {object} [extras]  valores que ya se conocen (nombre_logico, owner, entorno, ...)
 */
export function generarManifiesto(workflow, extras = {}) {
  if (workflow === null || typeof workflow !== 'object') {
    throw new TypeError('generarManifiesto espera un objeto de workflow de n8n.');
  }
  const nodos = Array.isArray(workflow.nodes) ? workflow.nodes : [];

  const esqueleto = {
    nombre_logico: null, //  1 — nadie puede inferir el nombre lógico desde el lienzo
    nombre_en_runtime: workflow.name ?? null, // auxiliar, no cuenta entre los 11
    owner: null, //  2 — una persona, y la elige una persona
    entorno: null, //  3
    estado: null, //  4 — inferirlo desde `active` sería exactamente el error que el campo previene
    contrato: {
      //  5
      entrada: { tipo: inferirTipoDeEntrada(nodos), esquema: null },
      salida: { esquema: null, estados: null },
    },
    dependencias: {
      //  6
      workflows: inferirSubworkflows(nodos),
      datos: null, // qué tablas toca no se ve en el JSON con confianza suficiente
      servicios: inferirServicios(nodos),
    },
    credenciales: inferirCredenciales(nodos), //  7
    clasificacion_datos: null, //  8
    origen: { procedencia: null, revisado_por: null, fecha_revision: null }, //  9
    evidencia_test: { fixtures: null, resultado: null, fecha: null }, // 10
    rollback: { artefacto: null, hash_sha256: null, verificado: null }, // 11
  };

  return fusionar(esqueleto, extras);
}

/** Fusión superficial por nivel: los extras pisan sólo lo que traen. */
function fusionar(base, extras) {
  const salida = { ...base };
  for (const [clave, valor] of Object.entries(extras ?? {})) {
    if (valor !== null && typeof valor === 'object' && !Array.isArray(valor) && typeof base[clave] === 'object' && base[clave] !== null && !Array.isArray(base[clave])) {
      salida[clave] = fusionar(base[clave], valor);
    } else {
      salida[clave] = valor;
    }
  }
  return salida;
}

/**
 * Valida un manifiesto.
 *
 * @returns {{valido:boolean, faltantes:string[], errores:Array<{campo:string, problema:string}>}}
 *   `faltantes` = está vacío o no está. `errores` = está, pero mal.
 *   La distinción importa: un faltante se completa, un error se corrige, y el
 *   segundo caso es el que suele indicar un problema de seguridad.
 */
export function validarManifiesto(manifiesto) {
  const faltantes = [];
  const errores = [];

  if (manifiesto === null || typeof manifiesto !== 'object' || Array.isArray(manifiesto)) {
    return { valido: false, faltantes: CAMPOS_DEL_MANIFIESTO.map((c) => c.clave), errores: [{ campo: '(raíz)', problema: 'El manifiesto no es un objeto.' }] };
  }

  // --- Presencia de los 11 campos y de sus subclaves obligatorias ---
  for (const campo of CAMPOS_DEL_MANIFIESTO) {
    const valor = manifiesto[campo.clave];
    if (estaVacio(valor)) {
      faltantes.push(campo.clave);
      continue;
    }
    for (const sub of campo.requiere ?? []) {
      if (estaVacio(leerRuta(valor, sub))) faltantes.push(`${campo.clave}.${sub}`);
    }
  }

  // --- Campo 4: estado de ciclo de vida ---
  const estado = manifiesto.estado;
  if (!estaVacio(estado) && !ESTADOS_DE_CICLO_DE_VIDA.includes(estado)) {
    errores.push({
      campo: 'estado',
      problema: `"${estado}" no es un estado de ciclo de vida. Válidos: ${ESTADOS_DE_CICLO_DE_VIDA.join(' | ')}.`,
    });
  }

  // --- Campo 3: entorno ---
  const entorno = manifiesto.entorno;
  if (!estaVacio(entorno) && !ENTORNOS.includes(entorno)) {
    errores.push({ campo: 'entorno', problema: `"${entorno}" no es un entorno válido. Válidos: ${ENTORNOS.join(' | ')}.` });
  }

  // --- Coherencia entre 3 y 4: la regla que más se viola ---
  if (entorno === 'prod' && (estado === 'draft' || estado === 'test')) {
    errores.push({
      campo: 'estado',
      problema: `Un workflow en "${estado}" no puede declararse en entorno prod. Es la regla que se rompió con el errorWorkflow marcado [TEST] y activo.`,
    });
  }

  // --- Campo 8: clasificación de datos ---
  const clasificacion = manifiesto.clasificacion_datos;
  if (!estaVacio(clasificacion) && !CLASIFICACIONES_DE_DATOS.includes(sinAcentos(clasificacion))) {
    errores.push({
      campo: 'clasificacion_datos',
      problema: `"${clasificacion}" no es una clasificación válida. Válidas: ${CLASIFICACIONES_DE_DATOS.join(' | ')}.`,
    });
  }

  // --- Campo 5: los estados de salida son una lista cerrada ---
  const estadosDeSalida = leerRuta(manifiesto, 'contrato.salida.estados');
  if (!estaVacio(estadosDeSalida) && !Array.isArray(estadosDeSalida)) {
    errores.push({ campo: 'contrato.salida.estados', problema: 'Los estados de salida deben ser una lista cerrada, no texto libre.' });
  }
  const tipoDeEntrada = leerRuta(manifiesto, 'contrato.entrada.tipo');
  if (!estaVacio(tipoDeEntrada) && !TIPOS_DE_ENTRADA.includes(tipoDeEntrada)) {
    errores.push({ campo: 'contrato.entrada.tipo', problema: `"${tipoDeEntrada}" no es un tipo de entrada. Válidos: ${TIPOS_DE_ENTRADA.join(' | ')}.` });
  }

  // --- Campo 7: credenciales por referencia simbólica, nunca por valor ni por ID ---
  errores.push(...validarCredenciales(manifiesto.credenciales));

  // --- Campo 11: el hash tiene que ser un sha256 ---
  const hash = leerRuta(manifiesto, 'rollback.hash_sha256');
  if (!estaVacio(hash) && !/^[0-9a-f]{64}$/i.test(String(hash))) {
    errores.push({ campo: 'rollback.hash_sha256', problema: 'No parece un SHA-256 (64 caracteres hexadecimales).' });
  }

  return { valido: faltantes.length === 0 && errores.length === 0, faltantes, errores };
}

/**
 * El campo 7 es el que convierte un manifiesto en publicable o en una fuga.
 * Regla: cada credencial es un símbolo `CRED_*`. Ni el id, ni el valor, ni un
 * objeto con datos adentro.
 */
function validarCredenciales(credenciales) {
  const errores = [];
  if (estaVacio(credenciales)) return errores;

  if (!Array.isArray(credenciales)) {
    return [{ campo: 'credenciales', problema: 'Las credenciales deben ser una lista de referencias simbólicas.' }];
  }

  credenciales.forEach((cred, i) => {
    const campo = `credenciales[${i}]`;
    if (typeof cred !== 'string') {
      errores.push({
        campo,
        problema: 'La credencial no es una referencia simbólica: es un objeto. Un objeto acá suele traer el id o el valor adentro.',
      });
      return;
    }
    if (!/^CRED_[A-Z0-9_]+$/.test(cred)) {
      errores.push({
        campo,
        problema: 'La referencia debe tener la forma CRED_NOMBRE_LOGICO. Un id de credencial o un nombre visible del runtime no sirven: atan el artefacto a una instancia.',
      });
    }
  });

  return errores;
}

/** Reporte legible de la validación. */
export function formatearValidacion(resultado, etiqueta = 'manifiesto') {
  const lineas = [];
  lineas.push(resultado.valido ? `OK  ${etiqueta}: los 11 campos están y son coherentes.` : `FALLA  ${etiqueta}`);
  if (resultado.faltantes.length > 0) {
    lineas.push(`  Faltan ${resultado.faltantes.length} campo(s):`);
    for (const f of resultado.faltantes) lineas.push(`    - ${f}`);
  }
  if (resultado.errores.length > 0) {
    lineas.push(`  ${resultado.errores.length} error(es):`);
    for (const e of resultado.errores) lineas.push(`    - ${e.campo}: ${e.problema}`);
  }
  return lineas.join('\n');
}

// ---------------------------------------------------------------------------
// Emisor de YAML
//
// Sólo emite: no parsea. Es la mitad barata del problema y evita la dependencia.
// Alcanza para volcar el manifiesto en el MANIFIESTO.md con el formato de la
// plantilla del repositorio.
// ---------------------------------------------------------------------------

function citarSiHaceFalta(texto) {
  const t = String(texto);
  if (t === '') return "''";
  // Se cita cuando el texto podría leerse como otra cosa (número, booleano,
  // fecha) o cuando tiene caracteres con significado en YAML.
  if (/[:#\-?{}[\],&*!|>'"%@`]/.test(t) || /^\s|\s$/.test(t) || /^(true|false|null|yes|no|on|off|~)$/i.test(t) || /^[\d.+-]/.test(t)) {
    return `"${t.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
  }
  return t;
}

function valorYaml(valor, sangria) {
  const pad = ' '.repeat(sangria);
  if (valor === null || valor === undefined) return '';
  if (typeof valor === 'boolean' || typeof valor === 'number') return ` ${valor}`;
  if (typeof valor === 'string') return ` ${citarSiHaceFalta(valor)}`;
  if (Array.isArray(valor)) {
    if (valor.length === 0) return ' []';
    return `\n${valor
      .map((v) => {
        if (v !== null && typeof v === 'object') {
          const cuerpo = manifiestoAYaml(v, sangria + 4).replace(/^\s+/, '');
          return `${pad}  - ${cuerpo}`;
        }
        return `${pad}  - ${String(valorYaml(v, sangria + 2)).trim()}`;
      })
      .join('\n')}`;
  }
  return `\n${manifiestoAYaml(valor, sangria + 2)}`;
}

/** Convierte el manifiesto (objeto plano) en YAML legible. */
export function manifiestoAYaml(objeto, sangria = 0) {
  const pad = ' '.repeat(sangria);
  return Object.entries(objeto)
    .map(([clave, valor]) => `${pad}${clave}:${valorYaml(valor, sangria)}`)
    .join('\n');
}
