/* Team roster.
 *
 * Membership is one row per person. Creating, inviting, joining, and leaving never
 * replace someone else's whole list, so an empty save on one device can't erase a team.
 *
 * The share key in the link is the secret. We store only its SHA-256 hash.
 * Routes:
 *   POST /api/teams                      create, or return the team if the key matches
 *   GET  /api/teams/:id?key=             roster for someone who has the link
 *   POST /api/teams/:id/members          add one username
 *   POST /api/teams/:id/leave            remove one username
 */
const crypto = require('crypto');
const express = require('express');
const db = require('./db');
const { ApiError } = require('./auth');

const router = express.Router();

const hashKey = (key) => crypto.createHash('sha256').update(String(key)).digest('hex');

function cleanId(id) {
  const value = String(id || '');
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(value)) throw new ApiError(400, 'invalid', 'That team link is not valid.');
  return value;
}

function cleanKey(key) {
  const value = String(key || '');
  if (!/^[a-f0-9]{32}$/.test(value)) throw new ApiError(400, 'invalid', 'That team link is not valid.');
  return value;
}

function cleanName(name) {
  const value = String(name || '').trim();
  if (!value || value.length > 30) throw new ApiError(400, 'invalid', 'Give your team a name.', { name: 'Use 1–30 characters.' });
  return value;
}

function cleanDate(value, label) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) throw new ApiError(400, 'invalid', `Pick a ${label} date.`);
  return String(value);
}

function cleanUser(username) {
  const value = String(username || '').trim().replace(/^@/, '');
  if (!/^[a-zA-Z0-9_.]{1,20}$/.test(value)) throw new ApiError(400, 'invalid', 'That username is not valid.');
  return value;
}

function dayOf(value) {
  if (value instanceof Date) {
    const y = value.getUTCFullYear();
    const m = String(value.getUTCMonth() + 1).padStart(2, '0');
    const d = String(value.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(value || '').slice(0, 10);
}

async function readTeam(id) {
  const { rows } = await db.query(
    'SELECT team_id, name, start_date, end_date, owner_username, key_hash FROM teams WHERE team_id = $1',
    [id],
  );
  if (!rows.length) return null;
  const members = await db.query(
    'SELECT username FROM team_members WHERE team_id = $1 ORDER BY joined_at, username',
    [id],
  );
  const row = rows[0];
  return {
    id: row.team_id,
    name: row.name,
    start: dayOf(row.start_date),
    end: dayOf(row.end_date),
    owner: row.owner_username,
    members: members.rows.map((r) => r.username),
    keyHash: row.key_hash,
  };
}

function present(team) {
  return { id: team.id, name: team.name, start: team.start, end: team.end, owner: team.owner, members: team.members };
}

async function teamFromKey(id, key) {
  const team = await readTeam(cleanId(id));
  if (!team || String(team.keyHash || '').trim() !== hashKey(cleanKey(key))) throw new ApiError(404, 'not_found', 'That team link does not match a team.');
  return team;
}

router.post('/', async (req, res, next) => {
  try {
    const id = cleanId(req.body.id);
    const name = cleanName(req.body.name);
    const start = cleanDate(req.body.start, 'start');
    const end = cleanDate(req.body.end, 'end');
    if (end < start) throw new ApiError(400, 'invalid', 'End date must be on or after the start date.');
    const owner = cleanUser(req.body.owner);
    const key = cleanKey(req.body.key);
    const existing = await readTeam(id);
    if (existing) {
      if (String(existing.keyHash || '').trim() !== hashKey(key)) throw new ApiError(403, 'forbidden', 'That team already exists.');
      return res.json({ team: present(existing) });
    }
    const members = [];
    for (const raw of [owner, ...(req.body.members || [])]) {
      const username = cleanUser(raw);
      if (!members.some((m) => m.toLowerCase() === username.toLowerCase())) members.push(username);
    }
    await db.query(
      `INSERT INTO teams (team_id, name, start_date, end_date, owner_username, key_hash)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [id, name, start, end, owner, hashKey(key)],
    );
    for (const username of members) {
      await db.query('INSERT INTO team_members (team_id, username) VALUES ($1, $2)', [id, username]);
    }
    res.status(201).json({ team: present(await readTeam(id)) });
  } catch (e) { next(e); }
});

router.get('/:id', async (req, res, next) => {
  try {
    res.json({ team: present(await teamFromKey(req.params.id, req.query.key)) });
  } catch (e) { next(e); }
});

router.post('/:id/members', async (req, res, next) => {
  try {
    const team = await teamFromKey(req.params.id, req.body.key);
    const username = cleanUser(req.body.username);
    const already = team.members.some((m) => m.toLowerCase() === username.toLowerCase());
    if (!already) await db.query('INSERT INTO team_members (team_id, username) VALUES ($1, $2)', [team.id, username]);
    res.json({ team: present(await readTeam(team.id)) });
  } catch (e) { next(e); }
});

router.post('/:id/leave', async (req, res, next) => {
  try {
    const team = await teamFromKey(req.params.id, req.body.key);
    const username = cleanUser(req.body.username);
    await db.query('DELETE FROM team_members WHERE team_id = $1 AND lower(username) = lower($2)', [team.id, username]);
    const left = await readTeam(team.id);
    if (!left.members.length) {
      await db.query('DELETE FROM teams WHERE team_id = $1', [team.id]);
      return res.json({ team: null });
    }
    if (left.owner.toLowerCase() === username.toLowerCase()) {
      await db.query('UPDATE teams SET owner_username = $2 WHERE team_id = $1', [team.id, left.members[0]]);
    }
    res.json({ team: present(await readTeam(team.id)) });
  } catch (e) { next(e); }
});

module.exports = { router };
