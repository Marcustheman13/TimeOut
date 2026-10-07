/* npm run db:reset — drops every table, recreates them from db/schema.sql and loads db/seed.sql. */
const fs = require('fs');
const path = require('path');
const db = require('../src/db');

(async () => {
  db.assertServerNotRunning();
  const sql = (f) => fs.readFileSync(path.join(__dirname, '..', 'db', f), 'utf8');
  await db.exec(sql('schema.sql'));
  await db.exec(sql('seed.sql'));
  const { rows } = await db.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name");
  for (const { table_name: t } of rows) {
    const c = await db.query(`SELECT count(*)::int AS n FROM "${t}"`);
    console.log(`  ${t.padEnd(24)} ${c.rows[0].n} rows`);
  }
  console.log(`Reset ${db.describe()}`);
  await db.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
