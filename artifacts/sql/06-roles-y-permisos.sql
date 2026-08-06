-- =============================================================================
--  PraxIA Ops · artifacts/sql/06-roles-y-permisos.sql
--
--  RECONSTRUCCIÓN DIDÁCTICA SINTÉTICA. NO ES UN DUMP DE PRODUCCIÓN.
--
--  Roles y permisos de los esquemas `praxia` y `praxia_finanzas`. El nombre
--  `praxia_finanzas_rw` y el hecho de que NO tenga permiso DELETE son parte
--  del diseño verificado; el resto de los GRANTs es una reconstrucción
--  razonable. No hay contraseñas: los roles son de grupo (NOLOGIN) y los roles
--  de login viven fuera de este repositorio.
--
--  Motor:   PostgreSQL 16
--  Requiere: 01, 03, 04 y 05
--  Ejecutar como superusuario o como un rol con CREATEROLE.
--  Corte:   2026-08-05
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Por qué el permiso es la primera línea de defensa
-- -----------------------------------------------------------------------------
-- Un sistema con agentes de IA tiene tres capas posibles de control, y no
-- valen lo mismo:
--
--   1. El prompt      — "no borres nada".        Se rodea reformulando.
--   2. La aplicación  — no hay endpoint DELETE.  Se rodea con otro cliente.
--   3. El permiso     — el rol no puede borrar.  No se rodea.
--
-- El permiso es lo único que sigue valiendo cuando el modelo alucina, cuando
-- alguien se conecta con psql "para arreglar una cosita" o cuando un bug hace
-- lo que nadie pidió. Por eso la regla de no borrar se implementa en las tres
-- capas, pero la que realmente la sostiene es esta.
--
-- Corolario práctico: la aplicación no se conecta como dueña del esquema. El
-- dueño puede hacer DDL; la aplicación sólo puede leer, insertar y actualizar.
-- Un agente que puede correr una migración es un agente que puede borrar todo
-- con dos pasos.
-- -----------------------------------------------------------------------------

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Roles de grupo (sin login, sin contraseña)
-- -----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'praxia_finanzas_rw') THEN
        CREATE ROLE praxia_finanzas_rw NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'praxia_finanzas_ro') THEN
        CREATE ROLE praxia_finanzas_ro NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'praxia_memoria_rw') THEN
        CREATE ROLE praxia_memoria_rw NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'praxia_memoria_ro') THEN
        CREATE ROLE praxia_memoria_ro NOLOGIN;
    END IF;
END;
$$;

COMMENT ON ROLE praxia_finanzas_rw IS
    'Rol de la API financiera. Puede leer, insertar y actualizar. NO puede '
    'borrar ni truncar. No es dueño del esquema, así que tampoco puede hacer DDL.';
COMMENT ON ROLE praxia_finanzas_ro IS
    'Rol de sólo lectura: reportes, dashboard en modo consulta y la capa de '
    'lectura fiscal. Es el rol que corresponde a un agente que sólo mira.';
COMMENT ON ROLE praxia_memoria_rw IS
    'Rol de los workflows de memoria. Lee, inserta y actualiza en el esquema '
    'praxia. Tampoco borra: la memoria usa baja lógica.';
COMMENT ON ROLE praxia_memoria_ro IS
    'Rol de sólo lectura del esquema praxia, para el camino de consulta.';

-- -----------------------------------------------------------------------------
-- 2. Cerrar lo que viene abierto por defecto
-- -----------------------------------------------------------------------------
-- PUBLIC tiene privilegios sobre las funciones nuevas. Cerrarlo explícitamente
-- es barato y evita sorpresas.

REVOKE ALL ON SCHEMA praxia            FROM PUBLIC;
REVOKE ALL ON SCHEMA praxia_finanzas   FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA praxia          FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA praxia_finanzas FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA praxia          FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA praxia_finanzas FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 3. Esquema praxia_finanzas — rol de escritura SIN DELETE
-- -----------------------------------------------------------------------------

GRANT USAGE ON SCHEMA praxia_finanzas TO praxia_finanzas_rw;

-- Nótese qué NO está en esta lista: DELETE y TRUNCATE.
GRANT SELECT, INSERT, UPDATE
    ON ALL TABLES IN SCHEMA praxia_finanzas
    TO praxia_finanzas_rw;

GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA praxia_finanzas
    TO praxia_finanzas_rw;

GRANT EXECUTE
    ON ALL FUNCTIONS IN SCHEMA praxia_finanzas
    TO praxia_finanzas_rw;

-- Cinturón y tiradores: si alguna tabla llegara con DELETE heredado, se saca.
REVOKE DELETE, TRUNCATE
    ON ALL TABLES IN SCHEMA praxia_finanzas
    FROM praxia_finanzas_rw;

-- Lo mismo para las tablas que se creen DESPUÉS. Sin esto, la próxima
-- migración crea una tabla con DELETE otorgado y nadie se entera hasta que
-- alguien borra algo.
ALTER DEFAULT PRIVILEGES IN SCHEMA praxia_finanzas
    GRANT SELECT, INSERT, UPDATE ON TABLES TO praxia_finanzas_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA praxia_finanzas
    GRANT USAGE, SELECT ON SEQUENCES TO praxia_finanzas_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA praxia_finanzas
    GRANT EXECUTE ON FUNCTIONS TO praxia_finanzas_rw;

-- -----------------------------------------------------------------------------
-- 4. Esquema praxia_finanzas — rol de sólo lectura
-- -----------------------------------------------------------------------------

GRANT USAGE  ON SCHEMA praxia_finanzas TO praxia_finanzas_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA praxia_finanzas TO praxia_finanzas_ro;
GRANT EXECUTE ON FUNCTION praxia_finanzas.fx_vigente(char, char, date) TO praxia_finanzas_ro;

ALTER DEFAULT PRIVILEGES IN SCHEMA praxia_finanzas
    GRANT SELECT ON TABLES TO praxia_finanzas_ro;

-- -----------------------------------------------------------------------------
-- 5. Esquema praxia (memoria)
-- -----------------------------------------------------------------------------

GRANT USAGE ON SCHEMA praxia TO praxia_memoria_rw, praxia_memoria_ro;

GRANT SELECT, INSERT, UPDATE
    ON ALL TABLES IN SCHEMA praxia
    TO praxia_memoria_rw;

GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA praxia
    TO praxia_memoria_rw;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA praxia TO praxia_memoria_rw;

REVOKE DELETE, TRUNCATE
    ON ALL TABLES IN SCHEMA praxia
    FROM praxia_memoria_rw;

GRANT SELECT ON ALL TABLES IN SCHEMA praxia TO praxia_memoria_ro;
GRANT EXECUTE ON FUNCTION praxia.normalizar(text) TO praxia_memoria_ro;

ALTER DEFAULT PRIVILEGES IN SCHEMA praxia
    GRANT SELECT, INSERT, UPDATE ON TABLES TO praxia_memoria_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA praxia
    GRANT SELECT ON TABLES TO praxia_memoria_ro;

-- -----------------------------------------------------------------------------
-- 6. Lectura entre esquemas
-- -----------------------------------------------------------------------------
-- El camino de consulta financiera de Oppenheimer necesita leer finanzas, no
-- escribirlas. Se resuelve con el rol de sólo lectura, no ampliando el de
-- escritura.

GRANT praxia_finanzas_ro TO praxia_memoria_ro;

COMMIT;

-- =============================================================================
-- Verificación (ejecutar después). Todas deben dar `f`:
--
--   SELECT has_table_privilege('praxia_finanzas_rw',
--            'praxia_finanzas.movimientos', 'DELETE');
--   SELECT has_table_privilege('praxia_finanzas_ro',
--            'praxia_finanzas.movimientos', 'INSERT');
--   SELECT has_table_privilege('praxia_memoria_rw',
--            'praxia.memory_facts', 'DELETE');
--
-- Y esta debe dar `t`:
--
--   SELECT has_table_privilege('praxia_finanzas_rw',
--            'praxia_finanzas.movimientos', 'UPDATE');
--
-- Los roles de login (los que efectivamente usan la API y n8n) se crean fuera
-- de este repositorio, con contraseñas que viven en el gestor de secretos, y
-- se les otorga la pertenencia al rol de grupo que corresponda:
--
--   GRANT praxia_finanzas_rw TO <rol_de_login>;
-- =============================================================================
