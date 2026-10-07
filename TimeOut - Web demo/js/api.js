/* TimeOut web demo — client for the TimeOut API in ../server.
 *
 * When the page is served by the server (npm start -> http://localhost:3000), accounts and login go through
 * the API and live in PostgreSQL. When the page is opened as a file (double-clicking index.html or
 * dist/TimeOut.html) there is no server, so the demo falls back to accounts saved in this browser.
 *
 * Everything else (bets, wallet, friends) is still saved in this browser for now. Move features over by
 * adding a route in server/src and a function here.
 */
(function (TO) {
  'use strict';
  const TOKEN_KEY = 'timeout.token';
  const api = (TO.api = { online: false, database: null });

  async function request(method, path, body) {
    const headers = { 'content-type': 'application/json' };
    const token = TO.store.get(TOKEN_KEY, null);
    if (token) headers.authorization = `Bearer ${token}`;
    let res;
    try {
      res = await fetch(`/api${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
    } catch (e) {
      throw new TO.AppError('offline', 'Can\'t reach the TimeOut server. Make sure `npm start` is running.');
    }
    if (res.status === 204) return null;
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = json.error || {};
      throw new TO.AppError(err.code || 'server_error', err.message || `Server error (${res.status}).`, { fields: err.fields, status: res.status });
    }
    return json;
  }

  /** Checks for the server once at startup. */
  api.init = async () => {
    if (!/^https?:$/.test(location.protocol)) return false;
    try {
      const h = await request('GET', '/health');
      api.online = !!h.ok;
      api.database = h.database;
    } catch (e) {
      api.online = false;
    }
    return api.online;
  };

  api.hasToken = () => !!TO.store.get(TOKEN_KEY, null);
  api.clearToken = () => TO.store.del(TOKEN_KEY);

  /** -> { user, previousLoginAt }. The server updates last_login_at and login_count before answering. */
  api.login = async (identifier, password) => {
    const r = await request('POST', '/auth/login', { identifier, password });
    TO.store.set(TOKEN_KEY, r.token);
    return r;
  };

  /** -> { user } */
  api.register = async ({ username, email, password, photoUrl }) => {
    const r = await request('POST', '/auth/register', { username, email, password, photoUrl });
    TO.store.set(TOKEN_KEY, r.token);
    return r;
  };

  /** The logged-in user, read fresh from the database. */
  api.me = async () => (await request('GET', '/auth/me')).user;

  api.logout = async () => {
    try { await request('POST', '/auth/logout'); } catch (e) { /* already logged out on the server */ }
    api.clearToken();
  };
})(window.TO);
