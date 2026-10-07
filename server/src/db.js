/* Database connection.
 *
 * - DATABASE_URL set in server/.env  -> connects to that PostgreSQL server (Supabase, Neon, local Postgres...).
 * - DATABASE_URL not set             -> runs PGlite, a real PostgreSQL compiled to WebAssembly, saved in
 *                                       server/.data/pglite. Nothing to install; good for working solo.
 *
 * Both expose the same two functions, so the rest of the server doesn't care which one is running:
 *   query(sql, params) -> { rows }    one statement with $1, $2... placeholders
 *   exec(sql)                         a whole .sql file (several statements, no params)
 */
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

const DATA_DIR = path.join(__dirname, '..', '.data', 'pglite');
const LOCK_FILE = path.join(__dirname, '..', '.data', 'server.pid');

let driver = null;

async function connect() {
  if (driver) return driver;
  if (process.env.DATABASE_URL) {
    const { Pool } = require('pg');
    const pool = new Pool({ connectionString: process.env.DATABASE_URL });
    await pool.query('SELECT 1');
    driver = {
      kind: 'postgres',
      query: (sql, params) => pool.query(sql, params),
      exec: (sql) => pool.query(sql),
      close: () => pool.end(),
    };
  } else {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    const { PGlite } = await import('@electric-sql/pglite');
    const db = new PGlite(DATA_DIR);
    await db.waitReady;
    driver = {
      kind: 'pglite',
      query: (sql, params) => db.query(sql, params),
      exec: (sql) => db.exec(sql),
      close: () => db.close(),
    };
  }
  return driver;
}

const describe = () => (process.env.DATABASE_URL
  ? `PostgreSQL at ${new URL(process.env.DATABASE_URL).host}`
  : `embedded PostgreSQL (PGlite) in ${path.relative(process.cwd(), DATA_DIR) || DATA_DIR}`);

/** PGlite is one process at a time. Scripts call this so they don't open the files while the server has them. */
function assertServerNotRunning() {
  if (process.env.DATABASE_URL || !fs.existsSync(LOCK_FILE)) return;
  const pid = Number(fs.readFileSync(LOCK_FILE, 'utf8'));
  try {
    process.kill(pid, 0);
  } catch (e) {
    return; // stale lock from a crashed server
  }
  console.error(`The server is running (pid ${pid}) and has the embedded database open. Stop it (Ctrl+C) and try again.`);
  process.exit(1);
}

function holdLock() {
  if (process.env.DATABASE_URL) return;
  fs.mkdirSync(path.dirname(LOCK_FILE), { recursive: true });
  fs.writeFileSync(LOCK_FILE, String(process.pid));
  const release = () => { try { fs.unlinkSync(LOCK_FILE); } catch (e) { /* already gone */ } };
  process.on('exit', release);
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => process.exit(0));
}

async function query(sql, params) { return (await connect()).query(sql, params); }
async function exec(sql) { return (await connect()).exec(sql); }
async function close() { if (driver) await driver.close(); driver = null; }

module.exports = { connect, query, exec, close, describe, assertServerNotRunning, holdLock };
