/* TimeOut API server.
 *
 *   npm start   ->  http://localhost:3000        the web demo
 *                   http://localhost:3000/api/*  the REST API (also what the iOS app will call)
 */
const path = require('path');
const fs = require('fs');
const express = require('express');
const db = require('./db');
const auth = require('./auth');

const PORT = Number(process.env.PORT) || 3000;
const WEB_DIR = path.join(__dirname, '..', '..', 'TimeOut - Web demo');
const SQL_DIR = path.join(__dirname, '..', 'db');

const app = express();
app.use(express.json({ limit: '2mb' })); // profile photos arrive as data: URLs

app.get('/api/health', async (req, res, next) => {
  try {
    await db.query('SELECT 1');
    res.json({ ok: true, database: (await db.connect()).kind });
  } catch (e) { next(e); }
});
app.use('/api/auth', auth.router);
app.use('/api', (req, res) => res.status(404).json({ error: { code: 'not_found', message: `No API route for ${req.method} ${req.originalUrl}` } }));

// Every error leaves as { error: { code, message, fields? } } so clients can show it next to the right input.
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
  if (err instanceof auth.ApiError) return res.status(err.status).json({ error: { code: err.code, message: err.message, fields: err.fields } });
  if (err.type === 'entity.too.large') return res.status(413).json({ error: { code: 'too_large', message: 'That upload is too big.' } });
  console.error(err);
  res.status(500).json({ error: { code: 'server_error', message: 'Something went wrong on the server.' } });
});

app.use(express.static(WEB_DIR));

/** First run on a fresh database: create the tables and sample rows so `npm start` just works. */
async function setupIfEmpty() {
  const { rows } = await db.query("SELECT to_regclass('public.users') IS NOT NULL AS ready");
  if (rows[0].ready) return;
  console.log('Empty database: creating tables and sample data...');
  await db.exec(fs.readFileSync(path.join(SQL_DIR, 'schema.sql'), 'utf8'));
  await db.exec(fs.readFileSync(path.join(SQL_DIR, 'seed.sql'), 'utf8'));
}

async function main() {
  db.assertServerNotRunning();
  await db.connect();
  db.holdLock();
  await setupIfEmpty();
  app.listen(PORT, () => {
    console.log(`TimeOut is running at http://localhost:${PORT}`);
    console.log(`Database: ${db.describe()}`);
  });
}

main().catch((e) => {
  console.error('Could not start the server:', e.message);
  process.exit(1);
});
