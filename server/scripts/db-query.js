/* npm run db:query -- "SELECT username, login_count FROM users"
 * Runs one SQL statement and prints the rows as a table. Handy because the embedded database has no psql.
 * With no SQL it shows the users table, which is what the login vertical slice changes. */
const db = require('../src/db');

const sql = process.argv.slice(2).join(' ').trim()
  || 'SELECT user_id, username, email, login_count, last_login_at FROM users ORDER BY user_id';

(async () => {
  db.assertServerNotRunning();
  const { rows } = await db.query(sql);
  if (rows && rows.length) console.table(rows);
  else console.log('(no rows)');
  await db.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
