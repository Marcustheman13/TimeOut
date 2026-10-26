/* GET /api/users/search?q=  — find accounts by username so Social search can add friends.
 * Returns username and photo only. Email and password never leave this file.
 */
const express = require('express');
const db = require('./db');

const router = express.Router();

router.get('/search', async (req, res, next) => {
  try {
    const q = String(req.query.q || '').trim().replace(/^@/, '').slice(0, 20);
    if (!q.replace(/[%_\\]/g, '')) return res.json({ users: [] });
    // Escape LIKE wildcards so a search for mike_t matches that username, not mike + any character + t.
    const safe = q.replace(/[\\%_]/g, (ch) => `\\${ch}`);
    const { rows } = await db.query(
      `SELECT username, photo_url FROM users
       WHERE username ILIKE $1 ESCAPE '\\'
       ORDER BY username
       LIMIT 8`,
      [`%${safe}%`],
    );
    res.json({ users: rows.map((r) => ({ username: r.username, photoUrl: r.photo_url || null })) });
  } catch (e) { next(e); }
});

module.exports = { router };
