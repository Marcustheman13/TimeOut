/* TimeOut Supabase client. The publishable key is designed for browser use; protect tables with RLS. */
(function (TO) {
  'use strict';
  const TOKEN_KEY = 'timeout.supabase.session';
  const api = (TO.api = { online: false, database: 'supabase', configured: false });
  let saveTimer = null;
  let pendingState = null;
  let lastSaveAt = 0;
  let lastSettingsSnapshot = '';
  let lastLedgerSnapshot = '';
  let supportsSharedLedger = true;
  // Postgres reorders JSON keys, so sort them to compare the saved ledger with this device's.
  const canonical = (value) => JSON.stringify(value, (key, v) => (v && typeof v === 'object' && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort()) : v));
  let supportsAppPreferences = true;
  let supportsTierBonusColumns = null;
  let supportsTierPerkColumns = null;
  let lastSyncAlertAt = 0;
  let lastOutOfMinutesAlertAt = 0;
  let lastTierBonusMigrationAlertAt = 0;
  let lastTierPerkMigrationAlertAt = 0;
  const placing = new Set();
  const settling = new Set();

  // The server's own wording. Never shown to users; the app reads it to recognize specific problems.
  const rawText = (error) => String(error?.debug || error?.message || '');
  function isOutOfPredictingMinutes(error) {
    return /insufficient|not enough|out of (challenging )?(minutes|balance)|challenging minutes/i.test(rawText(error));
  }
  function isTierSystemRpcUnavailable(error) {
    const message = rawText(error);
    return /timeout_place_challenge_with_tiers/i.test(message) && /schema cache|function.*(not found|does not exist|could not find)/i.test(message);
  }
  function isTierPerkRpcUnavailable(error) {
    const message = rawText(error);
    return /timeout_place_challenge_with_perks/i.test(message) && /schema cache|function.*(not found|does not exist|could not find)/i.test(message);
  }
  function isTierPerkLimitError(error) {
    return /no point-value boosts left|no combo protection left/i.test(rawText(error));
  }
  function notifyOutOfPredictingMinutes() {
    if (Date.now() - lastOutOfMinutesAlertAt < 15000 || !TO.ui?.toast) return;
    lastOutOfMinutesAlertAt = Date.now();
    TO.ui.toast({ kind: 'loss', title: 'Out of pledge minutes', msg: 'Pledges reopen at midnight. Your minutes were returned.' });
  }
  function notifyTierBonusMigrationRequired() {
    if (Date.now() - lastTierBonusMigrationAlertAt < 15000 || !TO.ui?.toast) return;
    lastTierBonusMigrationAlertAt = Date.now();
    TO.ui.toast({ kind: 'loss', title: 'Your pledge wasn\'t saved', msg: 'Your minutes were returned. Please try again in a few minutes.' });
  }
  function notifyTierPerkMigrationRequired() {
    if (Date.now() - lastTierPerkMigrationAlertAt < 15000 || !TO.ui?.toast) return;
    lastTierPerkMigrationAlertAt = Date.now();
    TO.ui.toast({ kind: 'loss', title: 'That perk isn\'t available right now', msg: 'Your pledge wasn\'t saved and your minutes were returned. Try it again without the perk.' });
  }
  function notifyTierPerkAlreadyUsed() {
    if (Date.now() - lastTierPerkMigrationAlertAt < 15000 || !TO.ui?.toast) return;
    lastTierPerkMigrationAlertAt = Date.now();
    TO.ui.toast({ kind: 'warn', title: 'Perk already used', msg: 'You already used this perk on another device. Your pledge wasn\'t saved and your minutes were returned.' });
  }

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
  /** Turns Supabase and Postgres errors (like "duplicate key value violates unique constraint") into messages people understand. */
  function friendlyError(raw, errorCode, status) {
    const m = String(raw || '').toLowerCase();
    const code = String(errorCode || '').toLowerCase();
    const err = (c, message, field, fieldText) => new TO.AppError(c, message, { status, fields: field ? { [field]: fieldText || message } : {} });
    if (m.includes('profiles_username_key') || (m.includes('duplicate key') && m.includes('username'))) return err('taken', 'That username is taken. Try another.', 'username');
    if (m.includes('database error saving new user')) return err('taken', 'We couldn\u2019t create your account. That username may already be taken, so try another.', 'username', 'Try a different username.');
    if (code === 'user_already_exists' || code === 'email_exists' || m.includes('user already registered')) return err('taken', 'An account with this email already exists. Log in instead.', 'email', 'An account with this email already exists.');
    if (code === 'email_not_confirmed' || m.includes('email not confirmed')) return err('email_not_confirmed', 'Confirm your email first. Open the link we sent you, or send a new one.');
    if (code === 'invalid_credentials' || m.includes('invalid login credentials')) return err('bad_login', 'That email or password is incorrect.', 'password', 'Check your email and password, then try again.');
    if (m.includes('rate limit') || code.includes('rate_limit')) return err('rate_limit', 'Too many emails or tries in a short time. Wait a few minutes, then try again.');
    if (m.includes('unable to validate email') || m.includes('invalid format') || code === 'email_address_invalid') return err('invalid', 'Enter a valid email address.', 'email');
    if (code === 'weak_password' || m.includes('password should') || m.includes('password is')) return err('invalid', raw, 'password');
    if (m.includes('duplicate key')) return err('taken', 'That\u2019s already taken. Try something else.');
    if (m.includes('jwt')) return err('bad_token', 'Your session expired. Log in again.');
    // Our own database functions explain themselves. Everything else from the database is technical.
    if (code === 'p0001') {
      const known = { 'sign in required': 'Your session expired. Log in again.', 'not enough challenge minutes': 'You\'re out of pledge minutes for today. Pledges reopen at midnight.', 'wallet is not set up': TO.unavailableMessage };
      return new TO.AppError('supabase_error', known[m] || raw, { status, debug: raw, fields: {} });
    }
    if (code.startsWith('pgrst') || /^[0-9a-z]{5}$/.test(code) || status >= 500 || /schema cache|relation |column |function |syntax|permission denied|violates|row-level|supabase|postgres|request failed/.test(m)) {
      return new TO.AppError('supabase_error', TO.unavailableMessage, { status, debug: raw, fields: {} });
    }
    if (status === 401 || status === 403) return err('bad_token', 'Your session expired. Log in again.');
    const fields = {};
    if (/username/i.test(raw)) fields.username = raw;
    else if (/email/i.test(raw)) fields.email = raw;
    else if (/password/i.test(raw)) fields.password = raw;
    return new TO.AppError(status === 409 ? 'taken' : 'supabase_error', raw, { status, fields, debug: raw });
  }
  async function parseResponse(res) {
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const raw = json.msg || json.message || json.error_description || json.error || `Request failed (${res.status}).`;
      throw friendlyError(raw, json.error_code || json.code, res.status);
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

  /** Falls back to the on-device demo accounts when Supabase can't be reached at all, e.g. on a shared page
   *  that isn't allowed to contact other sites. Without internet the offline banner explains things instead. */
  api.init = async () => {
    if (!api.configured || !navigator.onLine) return api.configured;
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 5000);
      await fetch(`${config.url}/auth/v1/health`, { headers: { apikey: config.publishableKey }, signal: ctrl.signal });
      clearTimeout(timer);
    } catch (e) {
      console.warn('Supabase unreachable, using on-device demo accounts:', e.message);
      api.configured = false;
      api.online = false;
    }
    return api.configured;
  };

  /** Live site. Confirmation and password emails always return here when someone signs up
   *  on a local dev server, so the link in Gmail opens the deployed app instead of localhost. */
  const LIVE_SITE = 'https://marcustheman13.github.io/TimeOut/';
  const returnUrl = () => {
    const host = location.hostname;
    const local = host === 'localhost' || host === '127.0.0.1' || host === '0.0.0.0' || location.protocol === 'file:';
    if (local) return LIVE_SITE;
    return `${location.origin}${location.pathname}`;
  };
  api.confirmationReturnUrl = returnUrl;

  api.resendConfirmation = async (email) => {
    await authRequest(`resend?redirect_to=${encodeURIComponent(returnUrl())}`, { type: 'signup', email: String(email || '').trim() });
  };

  /** The confirmation link lands back here with the new session in the URL hash (#access_token=…&refresh_token=…).
   *  Saves it and cleans the URL. Returns 'signed-in', an error message, or null when there's nothing to handle. */
  api.consumeAuthRedirect = () => {
    const hash = new URLSearchParams(location.hash.replace(/^#/, ''));
    const query = new URLSearchParams(location.search);
    const error = hash.get('error_description') || query.get('error_description');
    const access = hash.get('access_token');
    if (!access && !error) return null;
    history.replaceState(null, '', location.pathname);
    if (error) return { error: error.replace(/\+/g, ' ') };
    saveSession({ access_token: access, refresh_token: hash.get('refresh_token'), expires_in: Number(hash.get('expires_in') || 3600), expires_at: Number(hash.get('expires_at')) || undefined, token_type: hash.get('token_type') || 'bearer' });
    lastSettingsSnapshot = '';
    supportsAppPreferences = true;
    return { signedIn: true, type: hash.get('type') };
  };
  api.sessionKey = TOKEN_KEY;
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
    const result = await authRequest(`signup?redirect_to=${encodeURIComponent(returnUrl())}`, { email: String(email || '').trim(), password, data: { username, display_name: username, avatar_url: photoUrl || null } });
    // Supabase answers a sign-up for an email that's already registered with a user that has no identities.
    if (Array.isArray(result.identities) && result.identities.length === 0) {
      throw new TO.AppError('taken', 'An account with this email already exists. Log in instead.', { fields: { email: 'An account with this email already exists.' } });
    }
    // Email confirmation is on: there's no session until the link in the email is opened.
    if (!result.session?.access_token && !result.access_token) return { needsConfirmation: true, email: String(email || '').trim() };
    saveSession(result.session || result);
    lastSettingsSnapshot = '';
    supportsAppPreferences = true;
    const user = await api.me();
    const state = await api.loadState();
    return { user, state };
  };
  /** A readable pick from what the server stores, for challenges placed on another device. */
  function pickLabel(market, side, line, matchup) {
    const teams = String(matchup || '').split(' @ ');
    const team = side === 'away' ? teams[0] : side === 'home' && teams.length > 1 ? teams[teams.length - 1] : null;
    if (market === 'winner') return team ? `${team} to win` : 'Draw';
    if (market === 'margin') return `${team || ''} ${TO.pointValue.fmtLine(Number(line || 0))}`;
    if (market === 'total') return `Combined score ${side === 'higher' ? 'above' : 'below'} ${TO.pointValue.fmtLine(Number(line || 0), false)}`;
    return matchup || '';
  }
  const marketTitle = (market) => ({ winner: 'Winner', margin: 'Margin', total: 'Total', race: 'Race winner' }[market] || market);

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
    let hasTierBonusColumns = true;
    let hasTierPerkColumns = true;
    const baseWalletFields = `balance_minutes,current_day,is_locked,streak`;
    const bonusWalletFields = `${baseWalletFields},tier_bonus_day,tier_bonus_minutes`;
    const walletRequest = rest(`wallets?select=${bonusWalletFields},tier_boosts_by_day,tier_insurance_by_week&user_id=eq.${safeId}&limit=1`).catch((error) => {
      if (!/tier_boosts_by_day|tier_insurance_by_week|column .*does not exist/i.test(rawText(error))) throw error;
      hasTierPerkColumns = false;
      return rest(`wallets?select=${bonusWalletFields}&user_id=eq.${safeId}&limit=1`).catch((bonusError) => {
        if (!/tier_bonus_day|tier_bonus_minutes|column .*does not exist/i.test(rawText(bonusError))) throw bonusError;
        hasTierBonusColumns = false;
        return rest(`wallets?select=${baseWalletFields}&user_id=eq.${safeId}&limit=1`);
      });
    });
    const [challengeRows, walletRows] = await Promise.all([
      rest(`challenges?select=*,challenge_picks(*)&user_id=eq.${safeId}&order=placed_at.desc`),
      walletRequest,
    ]);
    supportsTierBonusColumns = hasTierBonusColumns;
    supportsTierPerkColumns = hasTierPerkColumns;
    let settingsRows;
    try {
      settingsRows = await rest(`user_settings?select=followed_sports,timezone,notifications_enabled,app_preferences&user_id=eq.${safeId}&limit=1`);
      supportsAppPreferences = true;
    } catch (e) {
      if (!/app_preferences.*does not exist|column .*app_preferences/i.test(rawText(e))) throw e;
      supportsAppPreferences = false;
      settingsRows = await rest(`user_settings?select=followed_sports,timezone,notifications_enabled&user_id=eq.${safeId}&limit=1`);
    }
    let shared = null;
    if (supportsSharedLedger) {
      try {
        const rows = await rest(`user_settings?select=shared_ledger&user_id=eq.${safeId}&limit=1`);
        shared = rows?.[0]?.shared_ledger || null;
        if (shared) lastLedgerSnapshot = canonical(shared);
      } catch (e) {
        if (/shared_ledger/i.test(rawText(e))) supportsSharedLedger = false; // server/db/supabase-shared-ledger.sql hasn't been run
      }
    }
    // "pushed" and "push" are the previous database labels.
    const status = { pending: 'open', won: 'won', lost: 'lost', tied: 'tie', pushed: 'tie', voided: 'void', cancelled: 'void' };
    const result = { pending: 'pending', win: 'won', loss: 'lost', tie: 'tie', push: 'tie', void: 'void' };
    const challenges = challengeRows.map((row) => {
      const picks = (row.challenge_picks || []).map((pick) => ({
        selId: `${pick.espn_event_id}|${pick.market}|${pick.side}`, kind: 'game', gameId: pick.espn_event_id, league: pick.league, market: pick.market, side: pick.side,
        line: pick.line == null ? null : Number(pick.line), price: Number(pick.accepted_value), label: pickLabel(pick.market, pick.side, pick.line, pick.matchup),
        marketLabel: marketTitle(pick.market), matchup: pick.matchup, result: result[pick.result] || 'pending', final: null,
      }));
      const decimal = Number(row.combined_value);
      const placedAt = Date.parse(row.placed_at);
      return { id: `supabase-${row.id}`, supabaseId: row.id, kind: 'sports', placedAt, dayKey: TO.dayKey(placedAt),
        pledgeMinutes: Number(row.pledge_minutes), picks, decimal, american: TO.pointValue.fromDecimal(decimal), boosted: !!row.boosted, insured: !!row.insured,
        multiplier: Number(row.multiplier || 1), status: status[row.status] || 'open', reward: Number(row.actual_reward_minutes || 0), potentialReward: Number(row.potential_reward_minutes || 0),
        resolvedAt: row.resolved_at ? Date.parse(row.resolved_at) : null, supabaseSynced: row.status !== 'pending' };
    });
    const wallet = walletRows[0];
    const settings = settingsRows[0];
    const walletState = wallet ? { balance: Number(wallet.balance_minutes), dayKey: wallet.current_day, lockedOut: !!wallet.is_locked, streakDays: Number(wallet.streak || 0) } : null;
    if (walletState && hasTierBonusColumns) {
      walletState.bonusDay = wallet.tier_bonus_day;
      walletState.bonusGranted = Number(wallet.tier_bonus_minutes || 0);
    }
    if (walletState && hasTierPerkColumns) {
      walletState.boostsByDay = wallet.tier_boosts_by_day || {};
      walletState.insuranceByWeek = wallet.tier_insurance_by_week || {};
    }
    const appPreferences = settings?.app_preferences || {};
    const storedSports = Array.isArray(appPreferences.sports) ? appPreferences.sports : (Array.isArray(settings?.followed_sports) ? settings.followed_sports : []);
    const followedSports = [...new Set(storedSports.filter((league) => TO.sim.REAL_LEAGUES.includes(league)))];
    const remotePreferences = { ...appPreferences };
    if (followedSports.length) remotePreferences.sports = followedSports;
    return {
      challenges,
      ...(walletState ? { wallet: walletState } : {}),
      ...(settings ? { settings: remotePreferences, appPreferencesReady: supportsAppPreferences } : {}),
      ...(shared ? { shared } : {}),
    };
  };
  let inviteCode = null;

  api.queueStateSave = (data) => {
    if (!api.configured || !token()) return;
    pendingState = JSON.parse(JSON.stringify(data));
    if (!saveTimer) saveTimer = setTimeout(() => {
      saveTimer = null;
      api.flushState().catch((e) => {
        if (e.outOfPredictingMinutes || isOutOfPredictingMinutes(e)) {
          notifyOutOfPredictingMinutes();
          return;
        }
        console.warn('Could not sync TimeOut data to Supabase:', e.message);
        if (Date.now() - lastSyncAlertAt > 15000 && TO.ui?.toast) {
          lastSyncAlertAt = Date.now();
          TO.ui.toast({ kind: 'warn', title: 'Couldn\'t sync your changes', msg: 'They\'re saved on this device, and TimeOut will try again.' });
        }
      });
    }, Math.max(0, 1500 - (Date.now() - lastSaveAt)));
  };
  /** Per-day highest of the phone's records (they only ever grow within a day), plus every device's challenge totals. */
  function mergeLedgers(mine, server) {
    if (!server || typeof server !== 'object') return mine;
    const out = { ...mine };
    for (const key of ['usageByDay', 'overridesByDay', 'penaltyByDay']) {
      const merged = { ...(server[key] || {}) };
      for (const [day, n] of Object.entries(mine[key] || {})) merged[day] = Math.max(Number(n) || 0, Number(merged[day]) || 0);
      out[key] = merged;
    }
    out.devices = { ...(server.devices || {}), ...(mine.devices || {}) };
    return out;
  }
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
      // Its own column and its own write, so these frequent updates can't overwrite a settings change from another device.
      if (supportsSharedLedger) {
        let ledger = TO.state.sharedLedger(data);
        // Another device may have recorded newer phone usage since this one last read it: never write an older number over it.
        try {
          const rows = await rest(`user_settings?select=shared_ledger&user_id=eq.${encodeURIComponent(id)}&limit=1`);
          ledger = mergeLedgers(ledger, rows?.[0]?.shared_ledger);
        } catch (e) { /* offline or no column yet: write ours as it is */ }
        const ledgerSnapshot = canonical(ledger);
        if (ledgerSnapshot !== lastLedgerSnapshot) {
          try {
            await rest(`user_settings?user_id=eq.${encodeURIComponent(id)}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ shared_ledger: ledger }) });
            lastLedgerSnapshot = ledgerSnapshot;
          } catch (e) {
            if (/shared_ledger/i.test(rawText(e))) supportsSharedLedger = false;
            else console.warn('Could not share daily records with your other devices:', e.message);
          }
        }
      }
      for (const challenge of data.challenges || []) {
        if (!TO.state.syncsToServer(challenge)) continue;
        if (!challenge.supabaseId && !placing.has(challenge.id)) {
          placing.add(challenge.id);
          try {
            const reward = Number(challenge.reward) > 0 ? Number(challenge.reward) : Math.min(TO.MAX_ALLOWED_MINUTES, Math.max(0,
              Number(challenge.pledgeMinutes) + Math.round((Math.round(Number(challenge.pledgeMinutes) * Number(challenge.decimal)) - Number(challenge.pledgeMinutes)) * Number(challenge.multiplier || 1))));
            const bonusToday = data.wallet?.bonusDay === (data.wallet?.dayKey || challenge.dayKey) ? Number(data.wallet?.bonusGranted || 0) : 0;
            const challengeArgs = {
              p_pledge_minutes: Number(challenge.pledgeMinutes), p_combined_value: Number(challenge.decimal), p_potential_reward: reward,
              p_current_day: data.wallet?.dayKey || challenge.dayKey,
              p_use_boost: !!challenge.boosted, p_use_insurance: !!challenge.insured,
              p_multiplier: Number(challenge.multiplier || 1),
              p_picks: challenge.picks.map((pick) => ({ espn_event_id: String(pick.gameId), league: pick.league || 'unknown', matchup: pick.matchup || '', market: pick.market || 'winner', side: pick.side || '', line: pick.line, accepted_value: Number(pick.price) })),
            };
            const legacyChallengeArgs = {
              p_pledge_minutes: challengeArgs.p_pledge_minutes, p_combined_value: challengeArgs.p_combined_value,
              p_potential_reward: challengeArgs.p_potential_reward, p_current_day: challengeArgs.p_current_day, p_picks: challengeArgs.p_picks,
            };
            let saved;
            try {
              if ((challenge.boosted || challenge.insured) && supportsTierPerkColumns === false) {
                const migrationError = new Error('The tier perk migration is not installed.');
                migrationError.tierPerkMigrationMissing = true;
                migrationError.failedChallengeId = challenge.id;
                throw migrationError;
              }
              saved = await rest('rpc/timeout_place_challenge_with_perks', { method: 'POST', body: JSON.stringify(challengeArgs) });
            } catch (error) {
              if (error.tierPerkMigrationMissing) throw error;
              if (isTierPerkRpcUnavailable(error)) {
                if (challenge.boosted || challenge.insured) {
                  error.tierPerkMigrationMissing = true;
                  error.failedChallengeId = challenge.id;
                  throw error;
                }
                const fallbackRpc = bonusToday > 0 ? 'timeout_place_challenge_with_tiers' : 'timeout_place_challenge';
                try {
                  saved = await rest(`rpc/${fallbackRpc}`, { method: 'POST', body: JSON.stringify(legacyChallengeArgs) });
                } catch (fallbackError) {
                  if (isOutOfPredictingMinutes(fallbackError)) {
                    fallbackError.outOfPredictingMinutes = true;
                    if (supportsTierBonusColumns === false && bonusToday > 0) fallbackError.tierBonusMigrationMissing = true;
                  }
                  fallbackError.failedChallengeId = challenge.id;
                  throw fallbackError;
                }
              } else if (isTierSystemRpcUnavailable(error) && !(challenge.boosted || challenge.insured)) {
                const fallbackRpc = 'timeout_place_challenge';
                try {
                  saved = await rest(`rpc/${fallbackRpc}`, { method: 'POST', body: JSON.stringify(legacyChallengeArgs) });
                } catch (fallbackError) {
                  if (isOutOfPredictingMinutes(fallbackError)) fallbackError.outOfPredictingMinutes = true;
                  if (isOutOfPredictingMinutes(fallbackError) && supportsTierBonusColumns === false && bonusToday > 0) fallbackError.tierBonusMigrationMissing = true;
                  fallbackError.failedChallengeId = challenge.id;
                  throw fallbackError;
                }
              } else {
                if (isOutOfPredictingMinutes(error)) error.outOfPredictingMinutes = true;
                if (isOutOfPredictingMinutes(error) && supportsTierBonusColumns === false && bonusToday > 0) error.tierBonusMigrationMissing = true;
                if (isTierPerkLimitError(error)) error.tierPerkExhausted = true;
                error.failedChallengeId = challenge.id;
                throw error;
              }
            }
            const challengeId = typeof saved === 'string' ? saved : saved.id;
            if (!challengeId) throw new TO.AppError('supabase_error', TO.unavailableMessage, { debug: 'No challenge ID came back.' });
            challenge.supabaseId = challengeId;
            challenge.supabaseSynced = false;
            const current = TO.data?.challenges?.find((b) => b.id === challenge.id);
            if (current) { current.supabaseId = challengeId; current.supabaseSynced = false; TO.store.set(`timeout.data.${TO.account.id}`, TO.data); }
          } finally { placing.delete(challenge.id); }
        }
        if (challenge.supabaseId && challenge.status !== 'open' && !challenge.supabaseSynced && !settling.has(challenge.supabaseId)) {
          settling.add(challenge.supabaseId);
          try {
            const resolved = await rest('rpc/timeout_resolve_challenge', { method: 'POST', body: JSON.stringify({
              p_challenge_id: challenge.supabaseId, p_status: ({ tie: 'tied', void: 'voided' })[challenge.status] || challenge.status,
              p_actual_reward: Number(challenge.reward || 0),
              p_pick_results: challenge.picks.map((pick) => ({ espn_event_id: String(pick.gameId), market: pick.market, side: pick.side, line: pick.line, result: pick.result })),
            }) });
            challenge.supabaseSynced = resolved !== false;
            const current = TO.data?.challenges?.find((b) => b.supabaseId === challenge.supabaseId);
            if (current) { current.supabaseSynced = challenge.supabaseSynced; TO.store.set(`timeout.data.${TO.account.id}`, TO.data); }
          } finally { settling.delete(challenge.supabaseId); }
        }
      }
      lastSaveAt = Date.now();
      api.syncError = null;
    } catch (e) {
      if (e.outOfPredictingMinutes || e.tierBonusMigrationMissing || e.tierPerkMigrationMissing || e.tierPerkExhausted) {
        const rejectedId = e.failedChallengeId;
        const rejected = (data.challenges || []).find((challenge) => challenge.id === rejectedId);
        pendingState = null;
        data.challenges = (data.challenges || []).filter((challenge) => challenge.id !== rejectedId);
        if (rejected && data.wallet) {
          data.wallet.balance = Math.max(0, Number(data.wallet.balance || 0) + Number(rejected.pledgeMinutes || 0));
          data.wallet.lockedOut = data.wallet.balance <= 0;
        }
        if (TO.data) {
          TO.data.challenges = TO.data.challenges.filter((challenge) => challenge.id !== rejectedId);
          if (rejected && TO.data.wallet) {
            TO.data.wallet.balance = Math.max(0, Number(TO.data.wallet.balance || 0) + Number(rejected.pledgeMinutes || 0));
            TO.data.wallet.lockedOut = TO.data.wallet.balance <= 0;
          }
          if (TO.account) TO.store.set(`timeout.data.${TO.account.id}`, TO.data);
        }
        if (e.tierPerkMigrationMissing) notifyTierPerkMigrationRequired();
        else if (e.tierPerkExhausted) notifyTierPerkAlreadyUsed();
        else if (e.tierBonusMigrationMissing) notifyTierBonusMigrationRequired();
        else notifyOutOfPredictingMinutes();
        TO.app?.render?.();
        return;
      }
      pendingState = data;
      throw e;
    }
  };
  api.updateProfile = async (patch) => {
    await ensureFreshSession();
    const userId = tokenUserId();
    if (!userId) throw new TO.AppError('bad_token', 'Your session is invalid. Log in again.');
    const body = { id: userId };
    // The name other people see (display_name) is always the username, so it changes with it.
    if (patch.username != null) { body.username = patch.username; body.display_name = patch.username; }
    if (patch.photoUrl != null) body.avatar_url = patch.photoUrl;
    if (Object.keys(body).length > 1) await rest(`profiles?id=eq.${encodeURIComponent(userId)}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ username: body.username, display_name: body.display_name, avatar_url: body.avatar_url }) });
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
    inviteCode = null;
  };

  /** Permanently deletes the signed-in account and its data (server/db/supabase-delete-account.sql). */
  api.deleteAccount = async () => {
    try {
      await rest('rpc/timeout_delete_account', { method: 'POST', body: '{}' });
    } catch (e) {
      if (/timeout_delete_account/i.test(rawText(e)) && /schema cache|function.*(not found|does not exist|could not find)/i.test(rawText(e))) {
        throw new TO.AppError('not_set_up', 'We can\'t delete your account right now. Please try again later, or contact support from the Help page.');
      }
      throw e;
    }
    pendingState = null;
    api.clearToken();
    lastSettingsSnapshot = '';
    inviteCode = null;
  };

  /** Emails a password-reset link. Opening it signs the person in here, where Account can set a new password. */
  api.sendPasswordReset = async (email) => {
    const res = await fetch(`${config.url}/auth/v1/recover?redirect_to=${encodeURIComponent(returnUrl())}`, {
      method: 'POST', headers: authHeaders(false), body: JSON.stringify({ email: String(email).trim() }),
    });
    await parseResponse(res);
  };

  // ---------- Friends ----------
  /** Friends and requests from the server. Null when it can't be reached or doesn't have the friends update yet. */
  api.socialState = async () => {
    if (!api.configured || !token()) return null;
    try {
      const json = await rest('rpc/timeout_social_state', { method: 'POST', signal: AbortSignal.timeout(6000), body: '{}' });
      if (!json || !Array.isArray(json.friends)) return null;
      const request = (r) => ({ id: String(r.id), username: r.username, name: r.name || r.username, photo: r.photo || null, at: Date.parse(r.at) || TO.now() });
      return {
        friends: json.friends.filter((f) => f && f.username).map((f) => ({
          username: f.username, name: f.name || f.username, photo: f.photo || null, w: Number(f.w || 0), l: Number(f.l || 0), net: Number(f.net || 0),
          tier: f.tier || 'rookie', streak: Number(f.streak || 0), share: f.share || { record: false, minutes: false, challenges: false },
          picks: (f.picks || []).map((c) => {
            const legs = c.picks || [];
            return { label: legs.map((k) => pickLabel(k.market, k.side, k.line, k.matchup)).join(' + '), matchup: legs.length > 1 ? `${legs.length}-pick Combo Goal` : (legs[0]?.matchup || ''),
              price: TO.pointValue.fromDecimal(Number(c.combinedValue || 1)), pledgeMinutes: Number(c.pledgeMinutes || 0) };
          }),
        })),
        requestsIn: (json.requestsIn || []).map(request),
        requestsOut: (json.requestsOut || []).map(request),
      };
    } catch (e) { return null; }
  };

  // ---------- Weekly report ----------
  /** The person's published weekly reports, newest first. Null when it can't be reached or the database doesn't have them yet. */
  api.weeklyReports = async () => {
    if (!api.configured || !token()) return null;
    try {
      const rows = await rest('rpc/timeout_my_weekly_reports', { method: 'POST', signal: AbortSignal.timeout(6000), body: JSON.stringify({ p_limit: 12 }) });
      return Array.isArray(rows) ? rows : null;
    } catch (e) { return null; }
  };
  api.markWeeklyReportRead = async (week) => {
    if (!api.configured || !token()) return;
    try { await rest('rpc/timeout_mark_weekly_report_read', { method: 'POST', signal: AbortSignal.timeout(6000), body: JSON.stringify({ p_week: week }) }); } catch (e) { /* it shows as unread again next time */ }
  };

  /** Runs one friends function. Turns "the database doesn't have it yet" into a sentence people can act on. */
  async function friendCall(name, body) {
    try {
      return await rest(`rpc/${name}`, { method: 'POST', signal: AbortSignal.timeout(8000), body: JSON.stringify(body) });
    } catch (e) {
      if (new RegExp(name, 'i').test(rawText(e)) && /schema cache|function.*(not found|does not exist|could not find)/i.test(rawText(e))) {
        throw new TO.AppError('not_set_up', 'Friends aren\'t available right now. Please try again in a few minutes.');
      }
      throw e;
    }
  }
  /** 'requested', or 'friends' when they had already asked you. */
  api.sendFriendRequest = (username) => friendCall('timeout_send_friend_request', { p_username: username });
  api.answerFriendRequest = async (username, accept) => {
    const done = await friendCall('timeout_answer_friend_request', { p_username: username, p_accept: accept });
    // The server answers false when it couldn't find that request. Don't pretend it worked.
    if (done === false) throw new TO.AppError('request_missing', `Couldn't ${accept ? 'accept' : 'decline'} the request from @${username}. Pull to refresh and try again.`);
    return done;
  };
  api.cancelFriendRequest = (username) => friendCall('timeout_cancel_friend_request', { p_username: username });
  api.removeFriend = (username) => friendCall('timeout_remove_friend', { p_username: username });
  /** 'friends', 'requested' (no valid code, so it is an ordinary request) or 'self'. */
  api.acceptFriendInvite = (username, code) => friendCall('timeout_accept_friend_invite', { p_username: username, p_code: code || '' });
  /** The secret for this account's invite links. Null when the server can't provide one; the link then sends a request. */
  api.myInviteCode = async () => {
    if (inviteCode) return inviteCode;
    if (!api.configured || !token()) return null;
    try {
      inviteCode = await rest('rpc/timeout_my_invite_code', { method: 'POST', signal: AbortSignal.timeout(4000), body: '{}' });
      return typeof inviteCode === 'string' ? inviteCode : null;
    } catch (e) { return null; }
  };
  api.teamStandings = async (id, key) => {
    if (!api.configured || !token()) return null;
    try {
      const rows = await rest('rpc/timeout_team_standings', { method: 'POST', signal: AbortSignal.timeout(4000), body: JSON.stringify({ p_id: id, p_key: key }) });
      return Array.isArray(rows) ? rows.filter((r) => r && r.username) : null;
    } catch (e) { return null; }
  };

  /** Usernames that match a query, from Supabase profiles (when signed in) and this app's API.
   *  Either source can be missing — GitHub Pages has no API, and profiles may be hidden — so a failure is just no extra rows. */
  api.searchUsers = async (query) => {
    const safe = String(query || '').trim().replace(/^@/, '').slice(0, 20).replace(/[^a-zA-Z0-9_.]/g, '');
    if (!safe) return [];
    const me = String(TO.account?.username || '').toLowerCase();
    const found = new Map();
    const add = (username, name, photo) => {
      const u = String(username || '').trim();
      const key = u.toLowerCase();
      if (!u || key === me || found.has(key) || !/^[a-zA-Z0-9_.]{1,20}$/.test(u)) return;
      found.set(key, { username: u, name: name || u, photo: photo || null, remote: true });
    };
    const tasks = [];
    if (api.configured && token()) {
      tasks.push((async () => {
        try {
          const rows = await rest('rpc/timeout_search_users', { method: 'POST', signal: AbortSignal.timeout(4000), body: JSON.stringify({ p_query: safe }) });
          if (Array.isArray(rows)) for (const r of rows) add(r.username, r.name, r.photo);
        } catch (searchError) {
          // A database without the friends update: read profiles directly.
          try {
            const like = safe.replace(/[_\\*]/g, (ch) => `\\${ch}`);
            const rows = await rest(`profiles?select=username,display_name,avatar_url&username=ilike.*${encodeURIComponent(like)}*&limit=8`, { signal: AbortSignal.timeout(4000) });
            if (Array.isArray(rows)) for (const r of rows) add(r.username, r.display_name, r.avatar_url);
          } catch (e) { /* RLS or a slow network: local results still show */ }
        }
      })());
    }
    tasks.push((async () => {
      try {
        const res = await fetch(`/api/users/search?q=${encodeURIComponent(safe)}`, { signal: AbortSignal.timeout(4000), headers: { accept: 'application/json' } });
        if (!res.ok) return;
        const json = await res.json().catch(() => ({}));
        for (const r of json.users || []) add(r.username, r.username, r.photoUrl);
      } catch (e) { /* opened as a static page, or the API is down */ }
    })());
    await Promise.all(tasks);
    return [...found.values()].slice(0, 8);
  };

  let expressReady = null;
  async function expressUp() {
    if (expressReady != null) return expressReady;
    try {
      const res = await fetch('/api/health', { signal: AbortSignal.timeout(1500), headers: { accept: 'application/json' } });
      const json = await res.json().catch(() => null);
      expressReady = !!(res.ok && json && json.ok);
    } catch (e) { expressReady = false; }
    return expressReady;
  }

  const teamBody = (team, extra) => JSON.stringify({ ...extra, key: team.shareKey });

  async function expressTeam(path, options) {
    const res = await fetch(path, { ...options, signal: AbortSignal.timeout(4000), headers: { 'content-type': 'application/json', accept: 'application/json', ...(options.headers || {}) } });
    if (res.status === 404) return false;
    if (!res.ok) return null;
    const json = await res.json().catch(() => null);
    return json && Object.prototype.hasOwnProperty.call(json, 'team') ? json.team : null;
  }

  /** Save one new team. A repeat with the same link returns the roster and does not add people again. */
  api.publishTeam = async (team) => {
    if (!team?.shareKey) return null;
    try {
      if (await expressUp()) {
        return await expressTeam('/api/teams', { method: 'POST', body: JSON.stringify({ id: team.id, name: team.name, start: team.start, end: team.end, owner: team.owner, key: team.shareKey, members: team.members }) });
      }
      if (!(api.configured && token())) return null;
      return await rest('rpc/timeout_save_team', { method: 'POST', signal: AbortSignal.timeout(4000), body: JSON.stringify({ p_id: team.id, p_name: team.name, p_start: team.start, p_end: team.end, p_key: team.shareKey, p_members: team.members }) });
    } catch (e) { return null; }
  };

  api.addTeamMember = async (team, username) => {
    if (!team?.shareKey || !username) return null;
    const send = async () => {
      if (await expressUp()) return expressTeam(`/api/teams/${encodeURIComponent(team.id)}/members`, { method: 'POST', body: teamBody(team, { username }) });
      if (!(api.configured && token())) return null;
      return rest('rpc/timeout_add_team_member', { method: 'POST', signal: AbortSignal.timeout(4000), body: JSON.stringify({ p_id: team.id, p_key: team.shareKey, p_username: username }) });
    };
    try {
      let result = await send();
      if (result === false) {
        await api.publishTeam(team);
        result = await send();
      }
      return result === false ? null : result;
    } catch (e) { return null; }
  };

  api.leaveTeamRemote = async (team, username) => {
    if (!team?.shareKey || !username) return null;
    try {
      if (await expressUp()) return expressTeam(`/api/teams/${encodeURIComponent(team.id)}/leave`, { method: 'POST', body: teamBody(team, { username }) });
      if (!(api.configured && token())) return null;
      return await rest('rpc/timeout_leave_team', { method: 'POST', signal: AbortSignal.timeout(4000), body: JSON.stringify({ p_id: team.id, p_key: team.shareKey, p_username: username }) });
    } catch (e) { return null; }
  };

  /** The roster, false when the link is wrong or the team is gone, null when the server can't be reached. */
  api.fetchTeam = async (id, key) => {
    if (!id || !key) return null;
    try {
      if (await expressUp()) return expressTeam(`/api/teams/${encodeURIComponent(id)}?key=${encodeURIComponent(key)}`, { method: 'GET', headers: { accept: 'application/json' } });
      if (!(api.configured && token())) return null;
      const row = await rest('rpc/timeout_get_team', { method: 'POST', signal: AbortSignal.timeout(4000), body: JSON.stringify({ p_id: id, p_key: key }) });
      return row && row.id ? row : false;
    } catch (e) { return null; }
  };

  /** Teams this signed-in Supabase profile is on. Null means "don't change the local list". */
  api.myTeams = async () => {
    if (await expressUp()) return null;
    if (!(api.configured && token())) return null;
    try {
      const rows = await rest('rpc/timeout_my_teams', { method: 'POST', signal: AbortSignal.timeout(4000), body: '{}' });
      return Array.isArray(rows) ? rows : null;
    } catch (e) { return null; }
  };
})(window.TO);
