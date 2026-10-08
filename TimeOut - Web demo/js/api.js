/* TimeOut Supabase client. The publishable key is designed for browser use; protect tables with RLS. */
(function (TO) {
  'use strict';
  const TOKEN_KEY = 'timeout.supabase.session';
  const api = (TO.api = { online: false, database: 'supabase', configured: false });
  let saveTimer = null;
  let pendingState = null;
  let lastSaveAt = 0;
  let lastSettingsSnapshot = '';
  let supportsAppPreferences = true;
  let lastSyncAlertAt = 0;
  const placing = new Set();
  const settling = new Set();

  const config = window.TIMEOUT_SUPABASE || {};
  api.configured = !!(config.url && config.publishableKey);
  api.online = api.configured;

  const token = () => TO.store.get(TOKEN_KEY, null)?.access_token || null;
  const tokenUserId = () => {
    const t = token();
    if (!t) return null;
    try { return JSON.parse(decodeURIComponent(escape(atob(t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))))).sub; }
    catch (e) { return null; }
  };
  const authHeaders = (withAuth = true) => ({ apikey: config.publishableKey, authorization: `Bearer ${withAuth ? token() || config.publishableKey : config.publishableKey}`, 'content-type': 'application/json' });
  async function ensureFreshSession() {
    const session = TO.store.get(TOKEN_KEY, null);
    if (!session?.refresh_token) return;
    const expiresAt = session.expires_at || (session.expires_in ? Math.floor(Date.now() / 1000) + session.expires_in : 0);
    if (expiresAt > Math.floor(Date.now() / 1000) + 60) return;
    const fresh = await authRequest('token?grant_type=refresh_token', { refresh_token: session.refresh_token });
    saveSession(fresh);
  }
  async function parseResponse(res) {
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const message = json.msg || json.message || json.error_description || json.error || `Supabase request failed (${res.status}).`;
      const fields = {};
      if (/username/i.test(message)) fields.username = message;
      else if (/email/i.test(message)) fields.email = message;
      else if (/password/i.test(message)) fields.password = message;
      throw new TO.AppError(res.status === 409 ? 'taken' : 'supabase_error', message, { status: res.status, fields });
    }
    return json;
  }
  async function authRequest(path, body, withAuth = false) {
    const res = await fetch(`${config.url}/auth/v1/${path}`, { method: 'POST', headers: authHeaders(withAuth), body: JSON.stringify(body) });
    return parseResponse(res);
  }
  async function rest(path, options = {}) {
    await ensureFreshSession();
    const res = await fetch(`${config.url}/rest/v1/${path}`, { ...options, headers: { ...authHeaders(true), ...(options.headers || {}) } });
    return parseResponse(res);
  }
  function saveSession(session) {
    if (session?.access_token) TO.store.set(TOKEN_KEY, { ...session, expires_at: session.expires_at || Math.floor(Date.now() / 1000) + Number(session.expires_in || 3600) });
  }

  api.init = async () => api.configured;
  api.hasToken = () => !!token();
  api.clearToken = () => TO.store.del(TOKEN_KEY);
  api.login = async (email, password) => {
    const session = await authRequest('token?grant_type=password', { email: String(email || '').trim(), password });
    saveSession(session);
    lastSettingsSnapshot = '';
    supportsAppPreferences = true;
    const user = await api.me();
    return { user, previousLoginAt: null };
  };
  api.register = async ({ username, email, password, photoUrl }) => {
    if (!/^[a-zA-Z0-9_.]{3,20}$/.test(username)) throw new TO.AppError('invalid', 'Use 3–20 letters, numbers, dots or underscores.', { fields: { username: 'Use 3–20 letters, numbers, dots or underscores.' } });
    const result = await authRequest('signup', { email: String(email || '').trim(), password, data: { username, display_name: username, avatar_url: photoUrl || null } });
    if (!result.session?.access_token) throw new TO.AppError('email_confirmation', 'Check your email to confirm your account, then log in.');
    saveSession(result.session);
    lastSettingsSnapshot = '';
    supportsAppPreferences = true;
    const user = await api.me();
    const state = await api.loadState();
    return { user, state };
  };
  api.me = async () => {
    await ensureFreshSession();
    const res = await fetch(`${config.url}/auth/v1/user`, { headers: authHeaders(true) });
    const user = await parseResponse(res);
    const profileRows = await rest(`profiles?select=username,display_name,avatar_url,created_at&id=eq.${encodeURIComponent(user.id)}&limit=1`);
    const profile = profileRows[0] || {};
    return { id: user.id, username: profile.username || user.user_metadata?.username || user.email?.split('@')[0] || 'player', email: user.email,
      photoUrl: profile.avatar_url || user.user_metadata?.avatar_url || null, createdAt: profile.created_at || user.created_at, isDemo: false };
  };
  api.loadState = async () => {
    const id = tokenUserId();
    if (!id) return null;
    const safeId = encodeURIComponent(id);
    const [betRows, walletRows] = await Promise.all([
      rest(`bets?select=*,bet_legs(*)&user_id=eq.${safeId}&order=placed_at.desc`),
      rest(`wallets?select=balance_minutes,current_day,is_locked,streak&user_id=eq.${safeId}&limit=1`),
    ]);
    let settingsRows;
    try {
      settingsRows = await rest(`user_settings?select=followed_sports,timezone,notifications_enabled,app_preferences&user_id=eq.${safeId}&limit=1`);
      supportsAppPreferences = true;
    } catch (e) {
      if (!/app_preferences.*does not exist|column .*app_preferences/i.test(e.message || '')) throw e;
      supportsAppPreferences = false;
      settingsRows = await rest(`user_settings?select=followed_sports,timezone,notifications_enabled&user_id=eq.${safeId}&limit=1`);
    }
    const status = { pending: 'open', won: 'won', lost: 'lost', pushed: 'push', voided: 'void', cancelled: 'void' };
    const result = { pending: 'pending', win: 'won', loss: 'lost', push: 'push', void: 'void' };
    const bets = betRows.map((row) => {
      const legs = (row.bet_legs || []).map((leg) => ({
        selId: `${leg.espn_event_id}|${leg.market}|${leg.side}`, kind: 'game', gameId: leg.espn_event_id, league: leg.league, market: leg.market, side: leg.side,
        line: leg.line == null ? null : Number(leg.line), price: Number(leg.accepted_odds), label: `${leg.market} · ${leg.side}${leg.line == null ? '' : ` ${leg.line}`}`,
        marketLabel: leg.market, matchup: leg.matchup, result: result[leg.result] || 'pending', final: null,
      }));
      const decimal = Number(row.combined_odds);
      return { id: `supabase-${row.id}`, supabaseId: row.id, kind: 'sports', placedAt: Date.parse(row.placed_at), dayKey: row.placed_at.slice(0, 10),
        stake: Number(row.stake_minutes), legs, decimal, american: TO.odds.fromDecimal(decimal), friend: null, boosted: false, insured: false,
        multiplier: 1, status: status[row.status] || 'open', payout: Number(row.actual_payout_minutes || 0), potentialPayout: Number(row.potential_payout_minutes || 0),
        settledAt: row.settled_at ? Date.parse(row.settled_at) : null, supabaseSynced: row.status !== 'pending' };
    });
    const wallet = walletRows[0];
    const settings = settingsRows[0];
    return {
      bets,
      ...(wallet ? { wallet: { balance: Number(wallet.balance_minutes), dayKey: wallet.current_day, lockedOut: !!wallet.is_locked, streakDays: Number(wallet.streak || 0) } } : {}),
      ...(settings ? { settings: { ...(settings.app_preferences || {}), sports: settings.followed_sports || [] }, appPreferencesReady: supportsAppPreferences } : {}),
    };
  };
  api.queueStateSave = (data) => {
    if (!api.configured || !token()) return;
    pendingState = JSON.parse(JSON.stringify(data));
    if (!saveTimer) saveTimer = setTimeout(() => {
      saveTimer = null;
      api.flushState().catch((e) => {
        console.warn('Could not sync TimeOut data to Supabase:', e.message);
        if (Date.now() - lastSyncAlertAt > 15000 && TO.ui?.toast) {
          lastSyncAlertAt = Date.now();
          TO.ui.toast({ kind: 'loss', title: 'Couldn’t save to Supabase', msg: e.message });
        }
      });
    }, Math.max(0, 1500 - (Date.now() - lastSaveAt)));
  };
  api.flushState = async () => {
    clearTimeout(saveTimer); saveTimer = null;
    if (!pendingState || !token()) return;
    const data = pendingState;
    pendingState = null;
    const id = tokenUserId();
    if (!id) { pendingState = data; throw new TO.AppError('bad_token', 'Your session is invalid. Log in again.'); }
    try {
      const settingsValue = { followed_sports: data.settings?.sports || [], timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Denver', notifications_enabled: Object.values(data.settings?.notify || {}).some(Boolean) };
      if (supportsAppPreferences) settingsValue.app_preferences = data.settings || {};
      const settingsSnapshot = JSON.stringify(settingsValue);
      if (settingsSnapshot !== lastSettingsSnapshot) {
        await rest(`user_settings?user_id=eq.${encodeURIComponent(id)}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: settingsSnapshot });
        lastSettingsSnapshot = settingsSnapshot;
      }
      for (const bet of data.bets || []) {
        if (bet.kind !== 'sports' || bet.friend || !Number(bet.stake) || !bet.legs?.length || bet.legs.some((leg) => leg.kind !== 'game' || !leg.gameId)) continue;
        if (!bet.supabaseId && !placing.has(bet.id)) {
          placing.add(bet.id);
          try {
            const payout = Number(bet.payout) > 0 ? Number(bet.payout) : Math.max(0, Math.round(Number(bet.stake) * Number(bet.decimal) * Number(bet.multiplier || 1)));
            const saved = await rest('rpc/timeout_place_bet', { method: 'POST', body: JSON.stringify({
              p_stake_minutes: Number(bet.stake), p_combined_odds: Number(bet.decimal), p_potential_payout: payout,
              p_current_day: data.wallet?.dayKey || bet.dayKey,
              p_legs: bet.legs.map((leg) => ({ espn_event_id: String(leg.gameId), league: leg.league || 'unknown', matchup: leg.matchup || '', market: leg.market || 'moneyline', side: leg.side || '', line: leg.line, accepted_odds: Number(leg.price) })),
            }) });
            const betId = typeof saved === 'string' ? saved : saved.id;
            if (!betId) throw new Error('Supabase did not return the saved bet ID.');
            bet.supabaseId = betId;
            bet.supabaseSynced = false;
            const current = TO.data?.bets?.find((b) => b.id === bet.id);
            if (current) { current.supabaseId = betId; current.supabaseSynced = false; TO.store.set(`timeout.data.${TO.account.id}`, TO.data); }
          } finally { placing.delete(bet.id); }
        }
        if (bet.supabaseId && bet.status !== 'open' && !bet.supabaseSynced && !settling.has(bet.supabaseId)) {
          settling.add(bet.supabaseId);
          try {
            const settled = await rest('rpc/timeout_settle_bet', { method: 'POST', body: JSON.stringify({
              p_bet_id: bet.supabaseId, p_status: ({ push: 'pushed', void: 'voided' })[bet.status] || bet.status,
              p_actual_payout: Number(bet.payout || 0),
              p_leg_results: bet.legs.map((leg) => ({ espn_event_id: String(leg.gameId), market: leg.market, side: leg.side, line: leg.line, result: leg.result })),
            }) });
            bet.supabaseSynced = settled !== false;
            const current = TO.data?.bets?.find((b) => b.supabaseId === bet.supabaseId);
            if (current) { current.supabaseSynced = bet.supabaseSynced; TO.store.set(`timeout.data.${TO.account.id}`, TO.data); }
          } finally { settling.delete(bet.supabaseId); }
        }
      }
      lastSaveAt = Date.now();
      api.syncError = null;
    } catch (e) { pendingState = data; throw e; }
  };
  api.updateProfile = async (patch) => {
    await ensureFreshSession();
    const userId = tokenUserId();
    if (!userId) throw new TO.AppError('bad_token', 'Your session is invalid. Log in again.');
    const body = { id: userId };
    if (patch.username != null) body.username = patch.username;
    if (patch.photoUrl != null) body.avatar_url = patch.photoUrl;
    if (Object.keys(body).length > 1) await rest(`profiles?id=eq.${encodeURIComponent(userId)}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ username: body.username, avatar_url: body.avatar_url }) });
    if (patch.email || patch.password) {
      const res = await fetch(`${config.url}/auth/v1/user`, { method: 'PUT', headers: authHeaders(true), body: JSON.stringify({ ...(patch.email ? { email: patch.email } : {}), ...(patch.password ? { password: patch.password } : {}) }) });
      await parseResponse(res);
    }
  };
  api.logout = async () => {
    await api.flushState().catch(() => {});
    if (token()) {
      try { const res = await fetch(`${config.url}/auth/v1/logout`, { method: 'POST', headers: authHeaders(true) }); await parseResponse(res); } catch (e) { /* session can already be expired */ }
    }
    api.clearToken();
    lastSettingsSnapshot = '';
  };
})(window.TO);
