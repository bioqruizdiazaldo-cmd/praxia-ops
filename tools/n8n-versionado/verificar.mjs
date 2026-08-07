/**
 * verificar.mjs — la compuerta antes de publicar (paso 3 del pipeline).
 *
 * Escanea un workflow normalizado buscando secretos, credenciales embebidas y
 * datos personales. Es lo último que corre antes de que un JSON entre a un
 * repositorio, porque un secreto commiteado sigue expuesto aunque después se
 * borre el archivo: queda en el historial. La respuesta correcta a un hallazgo
 * tardío no es borrar, es ROTAR.
 *
 * Dos decisiones de diseño que importan:
 *
 * 1. Los hallazgos informan RUTA y TIPO, jamás el valor. Si el reporte imprimiera
 *    el token encontrado, el reporte pasaría a ser el nuevo lugar donde está el
 *    token: en la salida de CI, en el log del pipeline, en el ticket.
 *
 * 2. Esto detecta patrones conocidos. Que no encuentre nada NO prueba que no haya
 *    nada. Es una red, no una garantía.
 */

/** Severidades, de mayor a menor. Sólo `alta` corta el pipeline por default. */
export const SEVERIDADES = ['alta', 'media', 'baja'];

/**
 * Dominios que se aceptan como ficticios y no cuentan como dato personal.
 * `example.*` e `invalid` están reservados por la RFC 2606 justamente para esto:
 * no se pueden registrar, así que nunca corresponden a una persona real.
 */
export const DOMINIOS_DE_EJEMPLO = [
  'example.com',
  'example.org',
  'example.net',
  'example.edu',
  'ejemplo.com',
  'ejemplo.org',
  'localhost',
  'localhost.localdomain',
];

const SUFIJOS_DE_EJEMPLO = ['.invalid', '.example', '.localhost', '.test'];

/**
 * Detectores por expresión regular sobre valores de tipo string.
 *
 * Cada patrón es deliberadamente específico. Un patrón laxo (por ejemplo
 * "cualquier cadena de 32 caracteres alfanuméricos") genera tantos falsos
 * positivos que el equipo aprende a ignorar la salida, y una compuerta que se
 * ignora es peor que no tener compuerta.
 */
export const DETECTORES = [
  {
    tipo: 'token_de_bot_telegram',
    severidad: 'alta',
    patron: /\b\d{6,12}:[A-Za-z0-9_-]{30,}\b/g,
    porque: 'Formato de token de bot de Telegram (<id numérico>:<secreto>). Da control total del bot.',
  },
  {
    tipo: 'clave_estilo_openai',
    severidad: 'alta',
    patron: /\bsk-[A-Za-z0-9_-]{16,}\b/g,
    porque: 'Formato de API key con prefijo sk-. Es una credencial facturable.',
  },
  {
    tipo: 'token_de_github',
    severidad: 'alta',
    patron: /\bgh[pousr]_[A-Za-z0-9]{20,}\b/g,
    porque: 'Token personal o de instalación de GitHub.',
  },
  {
    tipo: 'token_de_slack',
    severidad: 'alta',
    patron: /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/g,
    porque: 'Token de Slack.',
  },
  {
    tipo: 'clave_de_acceso_aws',
    severidad: 'alta',
    patron: /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/g,
    porque: 'Access key de AWS.',
  },
  {
    tipo: 'jwt',
    severidad: 'alta',
    patron: /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g,
    porque: 'JSON Web Token. Aunque esté vencido, revela claims y estructura de la sesión.',
  },
  {
    tipo: 'clave_privada',
    severidad: 'alta',
    patron: /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/g,
    porque: 'Bloque PEM de clave privada.',
  },
  {
    tipo: 'cadena_de_conexion_con_contrasena',
    severidad: 'alta',
    patron: /\b(?:postgres|postgresql|mysql|mariadb|mongodb(?:\+srv)?|redis|rediss|amqp|amqps|ftp|sftp):\/\/[^\s:/@"']+:[^\s@"']+@/g,
    porque: 'URI de base de datos o servicio con usuario y contraseña embebidos.',
  },
  {
    tipo: 'secreto_en_query_string',
    severidad: 'alta',
    patron: /[?&](?:token|api_?key|access_?token|auth|password|passwd|pwd|secret|signature)=[^&\s"'#]{8,}/gi,
    porque: 'Credencial pasada por query string. Además de estar en el JSON, queda en logs de acceso.',
  },
  {
    tipo: 'cabecera_authorization_literal',
    severidad: 'alta',
    patron: /\b(?:Bearer|Basic)\s+[A-Za-z0-9+/_.=-]{20,}/g,
    porque: 'Valor literal de una cabecera Authorization. Debería resolverse desde una credencial.',
  },
  {
    tipo: 'direccion_ip',
    severidad: 'media',
    patron: /\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\b/g,
    porque: 'Dirección IP literal. Revela topología y ata el artefacto a una instancia.',
    // Loopback y comodines no dicen nada de la infraestructura real.
    ignorar: (valor) => ['127.0.0.1', '0.0.0.0', '255.255.255.255', '1.1.1.1', '8.8.8.8'].includes(valor),
  },
];

/** Nombres de parámetro que no deberían tener nunca un valor literal. */
const CLAVES_SENSIBLES =
  /^(api_?key|apikey|access_?token|refresh_?token|token|password|passwd|pwd|secret|client_?secret|passphrase|private_?key|authorization|auth_?token|bearer)$/i;

/** Encabezados HTTP cuyo valor tampoco debería ser literal. */
const NOMBRES_DE_CABECERA_SENSIBLES =
  /^(authorization|x-api-key|api-key|x-auth-token|proxy-authorization|cookie)$/i;

/**
 * Un valor que empieza con `=` es una expresión de n8n: no es el secreto, es la
 * referencia al lugar donde vive. Igual con `{{ ... }}` y con los placeholders
 * evidentes que la gente deja en las plantillas.
 */
function esReferenciaOPlaceholder(valor) {
  if (typeof valor !== 'string') return true;
  const v = valor.trim();
  if (v.length < 8) return true;
  if (v.startsWith('=')) return true;
  if (/^\{\{[\s\S]*\}\}$/.test(v)) return true;
  if (/^\$\{?[A-Z_][A-Z0-9_]*\}?$/.test(v)) return true; // $VAR / ${VAR}
  if (/^(x{3,}|\*{3,}|\.{3,}|-{3,})$/i.test(v)) return true;
  if (/^<.*>$/.test(v)) return true;
  if (/^(tu[-_ ]|your[-_ ]|reemplaz|placeholder|cambiar|todo:|pegar)/i.test(v)) return true;
  return false;
}

/** Verificador del dígito de control de un CUIT/CUIL argentino (módulo 11). */
export function esCuitValido(texto) {
  const digitos = String(texto).replace(/[^0-9]/g, '');
  if (digitos.length !== 11) return false;
  const pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  let suma = 0;
  for (let i = 0; i < 10; i += 1) suma += Number(digitos[i]) * pesos[i];
  const resto = suma % 11;
  const verificador = resto === 0 ? 0 : resto === 1 ? 9 : 11 - resto;
  return verificador === Number(digitos[10]);
}

function dominioEsDeEjemplo(dominio) {
  const d = dominio.toLowerCase();
  if (DOMINIOS_DE_EJEMPLO.includes(d)) return true;
  return SUFIJOS_DE_EJEMPLO.some((s) => d.endsWith(s));
}

function ultimoSegmento(ruta) {
  const partes = String(ruta).split('.');
  return partes[partes.length - 1].replace(/\[\d+\]$/, '');
}

function hallazgo(ruta, tipo, severidad, porque, coincidencias = 1) {
  // Nunca, en ningún caso, el valor encontrado. Sólo dónde y de qué tipo.
  return { ruta, tipo, severidad, porque, coincidencias };
}

/** Aplica los detectores de patrón a un único valor de tipo string. */
export function detectarEnCadena(ruta, texto) {
  const hallazgos = [];
  for (const det of DETECTORES) {
    const encontrados = String(texto).match(det.patron) ?? [];
    const filtrados = det.ignorar ? encontrados.filter((m) => !det.ignorar(m)) : encontrados;
    if (filtrados.length > 0) {
      hallazgos.push(hallazgo(ruta, det.tipo, det.severidad, det.porque, filtrados.length));
    }
  }

  // Correos: sólo cuentan los que no son de un dominio reservado para ejemplos.
  const correos = String(texto).match(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g) ?? [];
  const correosReales = correos.filter((c) => !dominioEsDeEjemplo(c.split('@')[1]));
  if (correosReales.length > 0) {
    hallazgos.push(
      hallazgo(
        ruta,
        'correo_electronico',
        'alta',
        'Dirección de correo que no pertenece a un dominio reservado para ejemplos. Es dato personal.',
        correosReales.length,
      ),
    );
  }

  // CUIT: sólo si el dígito verificador cierra. Sin esa comprobación, cualquier
  // secuencia de once dígitos daría falso positivo.
  const posiblesCuit = String(texto).match(/\b(?:20|23|24|27|30|33|34)-?\d{8}-?\d\b/g) ?? [];
  const cuits = posiblesCuit.filter(esCuitValido);
  if (cuits.length > 0) {
    hallazgos.push(
      hallazgo(ruta, 'cuit', 'alta', 'CUIT/CUIL con dígito verificador válido. Identifica a una persona o empresa.', cuits.length),
    );
  }

  return hallazgos;
}

/** Detecta chat_id de Telegram, que identifican a una persona o a un grupo. */
function detectarChatId(ruta, valor) {
  const clave = ultimoSegmento(ruta);
  if (!/^(chat_?id|from_?id|user_?id|group_?id)$/i.test(clave)) return [];
  const texto = String(valor);
  if (esReferenciaOPlaceholder(texto) && !/^-?\d+$/.test(texto)) return [];
  if (!/^-?\d{6,}$/.test(texto)) return [];
  return [
    hallazgo(
      ruta,
      'identificador_de_conversacion',
      'alta',
      'Identificador numérico de chat o usuario embebido. Es dato personal y ata el workflow a una conversación real.',
    ),
  ];
}

/** Detecta un secreto literal puesto directamente como valor de un parámetro. */
function detectarClaveSensible(ruta, valor) {
  const clave = ultimoSegmento(ruta);
  if (!CLAVES_SENSIBLES.test(clave)) return [];
  if (esReferenciaOPlaceholder(valor)) return [];
  return [
    hallazgo(
      ruta,
      'secreto_en_parametro',
      'alta',
      `El parámetro "${clave}" tiene un valor literal en vez de una expresión o una credencial.`,
    ),
  ];
}

/**
 * n8n guarda cabeceras y query params como pares {name, value} dentro de arrays.
 * Ahí el nombre del campo es siempre "value", así que la detección por nombre de
 * clave no alcanza: hay que mirar el hermano `name`.
 */
function detectarParNombreValor(ruta, objeto) {
  if (typeof objeto?.name !== 'string' || typeof objeto?.value !== 'string') return [];
  if (!NOMBRES_DE_CABECERA_SENSIBLES.test(objeto.name.trim()) && !CLAVES_SENSIBLES.test(objeto.name.trim())) return [];
  if (esReferenciaOPlaceholder(objeto.value)) return [];
  return [
    hallazgo(
      `${ruta}.value`,
      'secreto_en_par_nombre_valor',
      'alta',
      `El par nombre/valor "${objeto.name}" lleva un valor literal donde debería ir una credencial.`,
    ),
  ];
}

/** Recorre cualquier estructura acumulando hallazgos, con la ruta a cuestas. */
function recorrer(valor, ruta, hallazgos) {
  if (typeof valor === 'string') {
    hallazgos.push(...detectarEnCadena(ruta, valor));
    hallazgos.push(...detectarChatId(ruta, valor));
    hallazgos.push(...detectarClaveSensible(ruta, valor));
    return;
  }
  if (typeof valor === 'number' || typeof valor === 'bigint') {
    hallazgos.push(...detectarChatId(ruta, valor));
    return;
  }
  if (Array.isArray(valor)) {
    valor.forEach((v, i) => recorrer(v, `${ruta}[${i}]`, hallazgos));
    return;
  }
  if (valor !== null && typeof valor === 'object') {
    hallazgos.push(...detectarParNombreValor(ruta, valor));
    for (const [clave, v] of Object.entries(valor)) {
      recorrer(v, ruta ? `${ruta}.${clave}` : clave, hallazgos);
    }
  }
}

/**
 * Las credenciales deben aparecer SÓLO como referencia: `{id, name}` —o
 * `{referencia}` si el artefacto se simbolizó—. Cualquier clave extra dentro del
 * objeto de credencial es, por definición, el valor de la credencial viajando
 * adentro del JSON.
 */
export function verificarCredenciales(workflow) {
  const hallazgos = [];
  const CLAVES_PERMITIDAS = new Set(['id', 'name', 'referencia']);

  for (const nodo of workflow?.nodes ?? []) {
    const credenciales = nodo?.credentials;
    if (credenciales === undefined || credenciales === null) continue;

    const base = `nodes["${nodo?.name ?? '?'}"].credentials`;

    if (typeof credenciales !== 'object' || Array.isArray(credenciales)) {
      hallazgos.push(hallazgo(base, 'credencial_con_forma_invalida', 'alta', 'El bloque de credenciales no es un objeto {tipo: referencia}.'));
      continue;
    }

    for (const [tipo, ref] of Object.entries(credenciales)) {
      const ruta = `${base}.${tipo}`;

      if (typeof ref === 'string') {
        // Formato viejo de n8n: sólo el nombre. Es una referencia, no un valor:
        // no es una fuga, pero es ambiguo y conviene migrarlo.
        hallazgos.push(hallazgo(ruta, 'credencial_en_formato_antiguo', 'media', 'La credencial es un string suelto. Migrar a {id, name}.'));
        continue;
      }
      if (ref === null || typeof ref !== 'object') {
        hallazgos.push(hallazgo(ruta, 'credencial_con_forma_invalida', 'alta', 'La referencia de credencial no es un objeto.'));
        continue;
      }

      const extras = Object.keys(ref).filter((k) => !CLAVES_PERMITIDAS.has(k));
      if (extras.length > 0) {
        hallazgos.push(
          hallazgo(
            ruta,
            'credencial_con_valor',
            'alta',
            `La credencial trae claves fuera de la referencia (${extras.join(', ')}). El valor de una credencial nunca se versiona.`,
            extras.length,
          ),
        );
      }
    }
  }
  return hallazgos;
}

function ordenarHallazgos(hallazgos) {
  const peso = (s) => SEVERIDADES.indexOf(s);
  return [...hallazgos].sort(
    (a, b) => peso(a.severidad) - peso(b.severidad) || (a.ruta < b.ruta ? -1 : a.ruta > b.ruta ? 1 : 0) || (a.tipo < b.tipo ? -1 : 1),
  );
}

/**
 * Verifica un workflow completo.
 *
 * @param {object} workflow  Preferentemente ya normalizado: sobre un JSON crudo
 *                           el escaneo igual corre, pero `pinData` mete un montón
 *                           de datos reales que ensucian el reporte.
 * @param {object} [opciones]
 * @param {boolean} [opciones.estricto=false] Si es true, `media` también bloquea.
 * @returns {{limpio:boolean, bloquea:boolean, hallazgos:Array, resumen:object}}
 */
export function verificarWorkflow(workflow, opciones = {}) {
  const { estricto = false } = opciones;
  const hallazgos = [];

  // Los nodos se recorren aparte para poder identificarlos por NOMBRE en la ruta.
  // `nodes[7]` no le dice nada a nadie; `nodes["Enviar a Telegram"]` se abre en
  // el lienzo y se arregla.
  const { nodes, ...resto } = workflow ?? {};
  for (const nodo of nodes ?? []) {
    recorrer(nodo, `nodes["${nodo?.name ?? '?'}"]`, hallazgos);
  }
  recorrer(resto, '', hallazgos);
  hallazgos.push(...verificarCredenciales(workflow));

  const ordenados = ordenarHallazgos(hallazgos);
  const resumen = { alta: 0, media: 0, baja: 0 };
  for (const h of ordenados) resumen[h.severidad] += 1;

  return {
    limpio: ordenados.length === 0,
    bloquea: resumen.alta > 0 || (estricto && resumen.media > 0),
    hallazgos: ordenados,
    resumen,
  };
}

/** Reporte legible para consola. No imprime valores: sólo rutas y tipos. */
export function formatearReporte(resultado, etiqueta = 'workflow') {
  const lineas = [];
  if (resultado.limpio) {
    lineas.push(`OK  ${etiqueta}: sin hallazgos.`);
  } else {
    lineas.push(`${resultado.bloquea ? 'BLOQUEA' : 'AVISO  '}  ${etiqueta}: ${resultado.hallazgos.length} hallazgo(s).`);
    for (const h of resultado.hallazgos) {
      lineas.push(`  [${h.severidad.toUpperCase()}] ${h.tipo}`);
      lineas.push(`      ruta: ${h.ruta || '(raíz)'}${h.coincidencias > 1 ? ` (x${h.coincidencias})` : ''}`);
      lineas.push(`      por qué: ${h.porque}`);
    }
    const r = resultado.resumen;
    lineas.push(`  Resumen: alta=${r.alta} media=${r.media} baja=${r.baja}`);
  }
  lineas.push('  Recordatorio: esto detecta patrones conocidos. No prueba que no haya secretos.');
  return lineas.join('\n');
}
