/* /api/auth/* — sign up, log in, who am I, log out.
 *
 * Clients (the web demo now, the iOS app later) send the session token as
 *   Authorization: Bearer <token>
 * so nothing here depends on browser cookies.
 */
const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('./db');

const router = express.Router();
const SESSION_DAYS = 30;

const USER_COLUMNS = 'user_id, username, email, photo_url, is_demo, created_at, last_login_at, login_count';

class ApiError extends Error {
  constructor(status, code, message, fields) { super(message); this.status = status; this.code = code; this.fields = fields; }
}

const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');

/** The shape every endpoint returns for a user. camelCase so JS and Swift clients read it naturally. */
const toUser = (r) => ({
  id: r.user_id,
  username: r.username,
  email: r.email,
  photoUrl: r.photo_url,
  isDemo: r.is_demo,
  createdAt: r.created_at,
  lastLoginAt: r.last_login_at,
  loginCount: r.login_count,
});

async function createSession(userId, req) {
  const token = crypto.randomBytes(32).toString('hex');
  await db.query(
    `INSERT INTO sessions (user_id, token_hash, device_label, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(days => $4))`,
    [userId, sha256(token), String(req.get('user-agent') || '').slice(0, 200), SESSION_DAYS],
  );
  return token;
}

/** Records a login: this is the database update for the vertical slice. Returns the updated row. */
async function recordLogin(userId) {
  const { rows } = await db.query(
    `UPDATE users SET last_login_at = now(), login_count = login_count + 1
     WHERE user_id = $1 RETURNING ${USER_COLUMNS}`,
    [userId],
  );
  return rows[0];
}

function validateSignup({ username, email, password }) {
  const fields = {};
  if (!/^[a-zA-Z0-9_.]{3,20}$/.test(username)) fields.username = 'Use 3–20 letters, numbers, dots or underscores.';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) fields.email = 'Enter a valid email address.';
  if (password.length < 8) fields.password = 'Use at least 8 characters.';
  if (Object.keys(fields).length) throw new ApiError(400, 'invalid', 'Fix the highlighted fields.', fields);
}

/** Middleware: loads req.user from the Bearer token, or answers 401. */
async function requireUser(req, res, next) {
  try {
    const token = (req.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (!token) throw new ApiError(401, 'no_token', 'Log in first.');
    const { rows } = await db.query(
      `SELECT s.session_id, ${USER_COLUMNS.split(', ').map((c) => `u.${c}`).join(', ')}
       FROM sessions s JOIN users u ON u.user_id = s.user_id
       WHERE s.token_hash = $1 AND s.expires_at > now()`,
      [sha256(token)],
    );
    if (!rows.length) throw new ApiError(401, 'bad_token', 'Your session expired. Log in again.');
    req.user = rows[0];
    req.sessionId = rows[0].session_id;
    next();
  } catch (e) { next(e); }
}

// POST /api/auth/register  { username, email, password, photoUrl? }  ->  201 { token, user }
router.post('/register', async (req, res, next) => {
  try {
    const username = String(req.body.username || '').trim();
    const email = String(req.body.email || '').trim();
    const password = String(req.body.password || '');
    validateSignup({ username, email, password });

    const taken = await db.query(
      'SELECT lower(username) = lower($1) AS same_user, lower(email) = lower($2) AS same_email FROM users WHERE lower(username) = lower($1) OR lower(email) = lower($2)',
      [username, email],
    );
    const fields = {};
    if (taken.rows.some((r) => r.same_user)) fields.username = 'That username is taken. Try another.';
    if (taken.rows.some((r) => r.same_email)) fields.email = 'An account already uses that email. Log in instead.';
    if (Object.keys(fields).length) throw new ApiError(409, 'taken', 'Fix the highlighted fields.', fields);

    const hash = await bcrypt.hash(password, 10);
    const { rows } = await db.query(
      'INSERT INTO users (username, email, password_hash, photo_url) VALUES ($1, $2, $3, $4) RETURNING user_id',
      [username, email, hash, req.body.photoUrl || null],
    );
    const user = await recordLogin(rows[0].user_id);
    const token = await createSession(user.user_id, req);
    res.status(201).json({ token, user: toUser(user) });
  } catch (e) { next(e); }
});

// POST /api/auth/login  { identifier, password }  ->  200 { token, user, previousLoginAt }
// identifier is a username (with or without @) or an email.
router.post('/login', async (req, res, next) => {
  try {
    const identifier = String(req.body.identifier || '').trim().replace(/^@/, '');
    const password = String(req.body.password || '');
    if (!identifier) throw new ApiError(400, 'invalid', 'Enter your username or email.', { identifier: 'Required' });

    const { rows } = await db.query(
      'SELECT user_id, password_hash, last_login_at FROM users WHERE lower(username) = lower($1) OR lower(email) = lower($1)',
      [identifier],
    );
    if (!rows.length) throw new ApiError(404, 'not_found', 'No account matches that username or email.', { identifier: 'No account found' });
    if (!(await bcrypt.compare(password, rows[0].password_hash))) {
      throw new ApiError(401, 'bad_password', 'That password is incorrect.', { password: 'Incorrect password' });
    }

    const user = await recordLogin(rows[0].user_id);
    const token = await createSession(user.user_id, req);
    res.json({ token, user: toUser(user), previousLoginAt: rows[0].last_login_at });
  } catch (e) { next(e); }
});

// GET /api/auth/me  ->  200 { user }   (used on page load to restore the session from the database)
router.get('/me', requireUser, (req, res) => res.json({ user: toUser(req.user) }));

// POST /api/auth/logout  ->  204   (deletes this device's session row)
router.post('/logout', requireUser, async (req, res, next) => {
  try {
    await db.query('DELETE FROM sessions WHERE session_id = $1', [req.sessionId]);
    res.status(204).end();
  } catch (e) { next(e); }
});

module.exports = { router, requireUser, ApiError };
