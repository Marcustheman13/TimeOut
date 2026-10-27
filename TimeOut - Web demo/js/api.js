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
  let supportsTierBonusColumns = null;
  let supportsTierPerkColumns = null;
  let lastSyncAlertAt = 0;
  let lastOutOfMinutesAlertAt = 0;
  let lastTierBonusMigrationAlertAt = 0;
  let lastTierPerkMigrationAlertAt = 0;
  const placing = new Set();
  const settling = new Set();
  const isPersistableGameLeg = (leg) => leg?.kind === 'game' || (leg?.kind === 'sports' && !!leg.gameId);

  function isOutOfBettingMinutes(error) {
    return /insufficient|not enough|out of (betting )?(minutes|balance)|betting minutes/i.test(String(error?.message || ''));
  }
  function isTierSystemRpcUnavailable(error) {
    const message = String(error?.message || '');
    return /timeout_place_bet_with_tiers/i.test(message) && /schema cache|function.*(not found|does not exist|could not find)/i.test(message);
  }
  function isTierPerkRpcUnavailable(error) {
    const message = String(error?.message || '');
    return /timeout_place_bet_with_perks/i.test(message) && /schema cache|function.*(not found|does not exist|could not find)/i.test(message);
  }
  function isTierPerkLimitError(error) {
    return /no odds boosts left|no parlay insurance left/i.test(String(error?.message || ''));
  }
  function notifyOutOfBettingMinutes() {
    if (Date.now() - lastOutOfMinutesAlertAt < 15000 || !TO.ui?.toast) return;
    lastOutOfMinutesAlertAt = Date.now();
    TO.ui.toast({ kind: 'loss', title: 'Out of betting minutes', msg: 'Betting reopens at midnight.' });
  }
  function notifyTierBonusMigrationRequired() {
    if (Date.now() - lastTierBonusMigrationAlertAt < 15000 || !TO.ui?.toast) return;
    lastTierBonusMigrationAlertAt = Date.now();
    TO.ui.toast({ kind: 'loss', title: 'Tier setup needed in Supabase', msg: 'This parlay was not saved. Run the tier system migration in Supabase SQL Editor, then reload the app.' });
  }
  function notifyTierPerkMigrationRequired() {
    if (Date.now() - lastTierPerkMigrationAlertAt < 15000 || !TO.ui?.toast) return;
    lastTierPerkMigrationAlertAt = Date.now();
    TO.ui.toast({ kind: 'loss', title: 'Tier perks need Supabase setup', msg: 'This bet was not saved with its boost or insurance. Run the updated tier system migration, then reload the app.' });
  }
  function notifyTierPerkAlreadyUsed() {
    if (Date.now() - lastTierPerkMigrationAlertAt < 15000 || !TO.ui?.toast) return;
    lastTierPerkMigrationAlertAt = Date.now();
    TO.ui.toast({ kind: 'warn', title: 'Tier perk already used', msg: 'This boost or insurance was already used on another device.' });
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

  /** Where the confirmation email sends people back to: the app or browser page they signed up on.
   *  Supabase only allows it if it matches a Redirect URL in Authentication > URL Configuration. */
  const returnUrl = () => `${location.origin}${location.pathname}`;

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
      if (!/tier_boosts_by_day|tier_insurance_by_week|column .*does not exist/i.test(error.message || '')) throw error;
      hasTierPerkColumns = false;
      return rest(`wallets?select=${bonusWalletFields}&user_id=eq.${safeId}&limit=1`).catch((bonusError) => {
        if (!/tier_bonus_day|tier_bonus_minutes|column .*does not exist/i.test(bonusError.message || '')) throw bonusError;
        hasTierBonusColumns = false;
        return rest(`wallets?select=${baseWalletFields}&user_id=eq.${safeId}&limit=1`);
      });
    });
    const [betRows, walletRows] = await Promise.all([
      rest(`bets?select=*,bet_legs(*)&user_id=eq.${safeId}&order=placed_at.desc`),
      walletRequest,
    ]);
    supportsTierBonusColumns = hasTierBonusColumns;
    supportsTierPerkColumns = hasTierPerkColumns;
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
      const placedAt = Date.parse(row.placed_at);
      return { id: `supabase-${row.id}`, supabaseId: row.id, kind: 'sports', placedAt, dayKey: TO.dayKey(placedAt),
        stake: Number(row.stake_minutes), legs, decimal, american: TO.odds.fromDecimal(decimal), boosted: !!row.boosted, insured: !!row.insured,
        multiplier: Number(row.multiplier || 1), status: status[row.status] || 'open', payout: Number(row.actual_payout_minutes || 0), potentialPayout: Number(row.potential_payout_minutes || 0),
        settledAt: row.settled_at ? Date.parse(row.settled_at) : null, supabaseSynced: row.status !== 'pending' };
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
    const storedSports = [
      ...(Array.isArray(settings?.followed_sports) ? settings.followed_sports : []),
      ...(Array.isArray(appPreferences.sports) ? appPreferences.sports : []),
    ];
    const followedSports = [...new Set(storedSports.filter((league) => TO.sim.REAL_LEAGUES.includes(league)))];
    const remotePreferences = { ...appPreferences };
    if (followedSports.length) remotePreferences.sports = followedSports;
    return {
      bets,
      ...(walletState ? { wallet: walletState } : {}),
      ...(settings ? { settings: remotePreferences, appPreferencesReady: supportsAppPreferences } : {}),
    };
  };
  api.queueStateSave = (data) => {
    if (!api.configured || !token()) return;
    pendingState = JSON.parse(JSON.stringify(data));
    if (!saveTimer) saveTimer = setTimeout(() => {
      saveTimer = null;
      api.flushState().catch((e) => {
        if (e.outOfBettingMinutes || isOutOfBettingMinutes(e)) {
          notifyOutOfBettingMinutes();
          return;
        }
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
        if (bet.kind !== 'sports' || !Number(bet.stake) || !bet.legs?.length || bet.legs.some((leg) => !isPersistableGameLeg(leg) || !leg.gameId)) continue;
        if (!bet.supabaseId && !placing.has(bet.id)) {
          placing.add(bet.id);
          try {
            const payout = Number(bet.payout) > 0 ? Number(bet.payout) : Math.max(0,
              Number(bet.stake) + Math.round((Math.round(Number(bet.stake) * Number(bet.decimal)) - Number(bet.stake)) * Number(bet.multiplier || 1)));
            const bonusToday = data.wallet?.bonusDay === (data.wallet?.dayKey || bet.dayKey) ? Number(data.wallet?.bonusGranted || 0) : 0;
            const betArgs = {
              p_stake_minutes: Number(bet.stake), p_combined_odds: Number(bet.decimal), p_potential_payout: payout,
              p_current_day: data.wallet?.dayKey || bet.dayKey,
              p_use_boost: !!bet.boosted, p_use_insurance: !!bet.insured,
              p_multiplier: Number(bet.multiplier || 1),
              p_legs: bet.legs.map((leg) => ({ espn_event_id: String(leg.gameId), league: leg.league || 'unknown', matchup: leg.matchup || '', market: leg.market || 'moneyline', side: leg.side || '', line: leg.line, accepted_odds: Number(leg.price) })),
            };
            const legacyBetArgs = {
              p_stake_minutes: betArgs.p_stake_minutes, p_combined_odds: betArgs.p_combined_odds,
              p_potential_payout: betArgs.p_potential_payout, p_current_day: betArgs.p_current_day, p_legs: betArgs.p_legs,
            };
            let saved;
            try {
              if ((bet.boosted || bet.insured) && supportsTierPerkColumns === false) {
                const migrationError = new Error('The tier perk migration is not installed.');
                migrationError.tierPerkMigrationMissing = true;
                migrationError.failedBetId = bet.id;
                throw migrationError;
              }
              saved = await rest('rpc/timeout_place_bet_with_perks', { method: 'POST', body: JSON.stringify(betArgs) });
            } catch (error) {
              if (error.tierPerkMigrationMissing) throw error;
              if (isTierPerkRpcUnavailable(error)) {
                if (bet.boosted || bet.insured) {
                  error.tierPerkMigrationMissing = true;
                  error.failedBetId = bet.id;
                  throw error;
                }
                const fallbackRpc = bonusToday > 0 ? 'timeout_place_bet_with_tiers' : 'timeout_place_bet';
                try {
                  saved = await rest(`rpc/${fallbackRpc}`, { method: 'POST', body: JSON.stringify(legacyBetArgs) });
                } catch (fallbackError) {
                  if (isOutOfBettingMinutes(fallbackError)) {
                    fallbackError.outOfBettingMinutes = true;
                    if (supportsTierBonusColumns === false && bonusToday > 0) fallbackError.tierBonusMigrationMissing = true;
                  }
                  fallbackError.failedBetId = bet.id;
                  throw fallbackError;
                }
              } else if (isTierSystemRpcUnavailable(error) && !(bet.boosted || bet.insured)) {
                const fallbackRpc = 'timeout_place_bet';
                try {
                  saved = await rest(`rpc/${fallbackRpc}`, { method: 'POST', body: JSON.stringify(legacyBetArgs) });
                } catch (fallbackError) {
                  if (isOutOfBettingMinutes(fallbackError)) fallbackError.outOfBettingMinutes = true;
                  if (isOutOfBettingMinutes(fallbackError) && supportsTierBonusColumns === false && bonusToday > 0) fallbackError.tierBonusMigrationMissing = true;
                  fallbackError.failedBetId = bet.id;
                  throw fallbackError;
                }
              } else {
                if (isOutOfBettingMinutes(error)) error.outOfBettingMinutes = true;
                if (isOutOfBettingMinutes(error) && supportsTierBonusColumns === false && bonusToday > 0) error.tierBonusMigrationMissing = true;
                if (isTierPerkLimitError(error)) error.tierPerkExhausted = true;
                error.failedBetId = bet.id;
                throw error;
              }
            }
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
    } catch (e) {
      if (e.outOfBettingMinutes || e.tierBonusMigrationMissing || e.tierPerkMigrationMissing || e.tierPerkExhausted) {
        const rejectedId = e.failedBetId;
        const rejected = (data.bets || []).find((bet) => bet.id === rejectedId);
        pendingState = null;
        data.bets = (data.bets || []).filter((bet) => bet.id !== rejectedId);
        if (rejected && data.wallet) {
          data.wallet.balance = Math.max(0, Number(data.wallet.balance || 0) + Number(rejected.stake || 0));
          data.wallet.lockedOut = data.wallet.balance <= 0;
        }
        if (TO.data) {
          TO.data.bets = TO.data.bets.filter((bet) => bet.id !== rejectedId);
          if (rejected && TO.data.wallet) {
            TO.data.wallet.balance = Math.max(0, Number(TO.data.wallet.balance || 0) + Number(rejected.stake || 0));
            TO.data.wallet.lockedOut = TO.data.wallet.balance <= 0;
          }
          if (TO.account) TO.store.set(`timeout.data.${TO.account.id}`, TO.data);
        }
        if (e.tierPerkMigrationMissing) notifyTierPerkMigrationRequired();
        else if (e.tierPerkExhausted) notifyTierPerkAlreadyUsed();
        else if (e.tierBonusMigrationMissing) notifyTierBonusMigrationRequired();
        else notifyOutOfBettingMinutes();
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
          const like = safe.replace(/[_\\*]/g, (ch) => `\\${ch}`);
          const rows = await rest(`profiles?select=username,display_name,avatar_url&username=ilike.*${encodeURIComponent(like)}*&limit=8`, { signal: AbortSignal.timeout(4000) });
          if (Array.isArray(rows)) for (const r of rows) add(r.username, r.display_name, r.avatar_url);
        } catch (e) { /* RLS or a slow network: local results still show */ }
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
