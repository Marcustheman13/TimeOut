/* TimeOut web demo — accounts, screen-time wallet, pledges, resolution, tiers/streaks and friends.
 * All data lives in this browser's localStorage. Passwords are hashed only to keep them out of plain sight;
 * this is a mockup, not real security.
 */
(function (TO) {
  'use strict';
  const S = TO.sim;
  const MIN = TO.MIN, HOUR = TO.HOUR, DAY = TO.DAY;

  const RULES = {
    daily: 60,
    maxPicks: 10,
    maxMatchupPicks: 4,
    maxAllowedMinutes: 120,
    overrideMinutes: 15,
    overridePenalty: 30,
    maxOverrides: 2,
    todoMaxPledge: 20,
    boostPercent: 0.1,
  };
  TO.RULES = RULES;
  const MAX_ALLOWED_MINUTES = 120;
  TO.MAX_ALLOWED_MINUTES = MAX_ALLOWED_MINUTES;

  // ---------- Tiers & streaks (carried over from the iOS app) ----------
  const TIERS = [
    { id: 'rookie', title: 'Rookie', min: 0, color: '#8C96A8', icon: 'user', bonus: 0, boosts: 0, insurance: 0 },
    { id: 'starter', title: 'Starter', min: 1, color: '#4FB3FF', icon: 'star', bonus: 5, boosts: 0, insurance: 0 },
    { id: 'allstar', title: 'All-Star', min: 4, color: '#22D66E', icon: 'star', bonus: 5, boosts: 1, insurance: 0 },
    { id: 'mvp', title: 'MVP', min: 8, color: '#FFC940', icon: 'trophy', bonus: 10, boosts: 2, insurance: 0 },
    { id: 'hof', title: 'Hall of Fame', min: 12, color: '#C58CFF', icon: 'crown', bonus: 10, boosts: 2, insurance: 1 },
  ];
  const tierPerks = (t) => {
    const list = [];
    if (t.bonus) list.push(`+${t.bonus} pledge min a day`);
    if (t.boosts) list.push(`${t.boosts} allowance boost${t.boosts === 1 ? '' : 's'} a day (+10% earned minutes)`);
    if (t.insurance) list.push('Miss-one protection once a week');
    return list.length ? list : ['Lock apps to earn perks'];
  };
  const tierById = (id) => TIERS.find((t) => t.id === id) || TIERS[0];
  const tierForPoints = (pts) => [...TIERS].reverse().find((t) => pts >= t.min) || TIERS[0];
  const streakMultiplier = (days) => (days >= 7 ? 1.25 : days >= 3 ? 1.1 : 1);
  const nextStreakMilestone = (days) => (days < 3 ? { days: 3, mult: 1.1 } : days < 7 ? { days: 7, mult: 1.25 } : null);
  const fmtMult = (m) => `×${m % 1 === 0 ? m : m.toFixed(2).replace(/0$/, '')}`;

  const LOCKABLE = [
    { id: 'instagram', name: 'Instagram', kind: 'App', pts: 1, color: '#D6417B' },
    { id: 'tiktok', name: 'TikTok', kind: 'App', pts: 1, color: '#25F4EE' },
    { id: 'youtube', name: 'YouTube', kind: 'App', pts: 1, color: '#FF0033' },
    { id: 'snapchat', name: 'Snapchat', kind: 'App', pts: 1, color: '#FFFC00' },
    { id: 'x', name: 'X', kind: 'App', pts: 1, color: '#E7E9EA' },
    { id: 'reddit', name: 'Reddit', kind: 'App', pts: 1, color: '#FF4500' },
    { id: 'netflix', name: 'Netflix', kind: 'App', pts: 1, color: '#E50914' },
    { id: 'discord', name: 'Discord', kind: 'App', pts: 1, color: '#5865F2' },
    { id: 'site-youtube', name: 'youtube.com', kind: 'Website', pts: 1, color: '#FF0033' },
    { id: 'site-reddit', name: 'reddit.com', kind: 'Website', pts: 1, color: '#FF4500' },
    { id: 'cat-social', name: 'Social', kind: 'Category', pts: 3, color: '#4FB3FF', note: 'Every social app on your phone' },
    { id: 'cat-ent', name: 'Entertainment', kind: 'Category', pts: 3, color: '#C58CFF', note: 'Streaming and video apps' },
    { id: 'cat-games', name: 'Games', kind: 'Category', pts: 3, color: '#FFC940', note: 'Every game on your phone' },
  ];

  // ---------- Other people (fake users for the Social demo) ----------
  const PEOPLE = [
    { username: 'mike_t', name: 'Mike Torres', color: '#2F6FDE', w: 34, l: 27, net: 48, tier: 'allstar', streak: 5, share: { record: true, minutes: true, challenges: true } },
    { username: 'jess.plays', name: 'Jess Park', color: '#D0467A', w: 41, l: 30, net: 73, tier: 'mvp', streak: 9, share: { record: true, minutes: false, challenges: true } },
    { username: 'coach_dan', name: 'Dan Reeves', color: '#E08A1E', w: 22, l: 29, net: -36, tier: 'starter', streak: 0, share: { record: true, minutes: true, challenges: true } },
    { username: 'lily_k', name: 'Lily Kim', color: '#7B5CE0', w: 18, l: 12, net: 25, tier: 'allstar', streak: 3, share: { record: true, minutes: true, challenges: false } },
    { username: 'tbone22', name: 'Tyler Bonner', color: '#1E9E7A', w: 51, l: 55, net: -12, tier: 'rookie', streak: 1, share: { record: false, minutes: false, challenges: false } },
    { username: 'priya_p', name: 'Priya Patel', color: '#C2410C', w: 12, l: 9, net: 19, tier: 'starter', streak: 2, share: { record: true, minutes: true, challenges: true } },
    { username: 'sam_the_fan', name: 'Sam Ortiz', color: '#0E7490', w: 60, l: 58, net: 4, tier: 'mvp', streak: 6, share: { record: true, minutes: true, challenges: false } },
    { username: 'ava.r', name: 'Ava Russo', color: '#BE185D', w: 9, l: 4, net: 22, tier: 'allstar', streak: 4, share: { record: true, minutes: true, challenges: true } },
    { username: 'big_ben', name: 'Ben Hall', color: '#4D7C0F', w: 27, l: 33, net: -41, tier: 'rookie', streak: 0, share: { record: true, minutes: false, challenges: false } },
    { username: 'nate_w', name: 'Nate Walker', color: '#6D28D9', w: 15, l: 15, net: 0, tier: 'starter', streak: 1, share: { record: true, minutes: true, challenges: true } },
    { username: 'coop_24', name: 'Cooper James', color: '#B45309', w: 38, l: 22, net: 91, tier: 'hof', streak: 12, share: { record: true, minutes: true, challenges: true } },
    { username: 'maria.g', name: 'Maria Garcia', color: '#DB2777', w: 20, l: 21, net: -3, tier: 'starter', streak: 2, share: { record: true, minutes: true, challenges: false } },
  ];
  PEOPLE.forEach((p) => { p.photo = TO.initialsAvatar(p.name, p.color); p.fake = true; });

  // ---------- Events ----------
  const listeners = {};
  TO.on = (name, fn) => { (listeners[name] = listeners[name] || []).push(fn); };
  TO.emit = (name, payload) => (listeners[name] || []).forEach((fn) => { try { fn(payload); } catch (e) { console.error(e); } });

  class AppError extends Error {
    constructor(code, message, extra) { super(message); this.code = code; Object.assign(this, extra || {}); }
  }
  TO.AppError = AppError;

  // ---------- Accounts ----------
  const ACC_KEY = 'timeout.accounts';
  const accounts = () => TO.store.get(ACC_KEY, {});
  const saveAccounts = (a) => TO.store.set(ACC_KEY, a);
  const dataKey = (id) => `timeout.data.${id}`;

  function findAccount(identifier) {
    const q = String(identifier || '').trim().toLowerCase().replace(/^@/, '');
    return Object.values(accounts()).find((a) => a.username.toLowerCase() === q || a.email.toLowerCase() === q) || null;
  }
  const findAccountByUsername = (u) => Object.values(accounts()).find((a) => a.username.toLowerCase() === String(u).toLowerCase()) || null;

  function validateUsername(username, exceptId) {
    if (!/^[a-zA-Z0-9_.]{3,20}$/.test(username)) return 'Use 3–20 letters, numbers, dots or underscores.';
    const taken = Object.values(accounts()).some((a) => a.id !== exceptId && a.username.toLowerCase() === username.toLowerCase())
      || PEOPLE.some((p) => p.username.toLowerCase() === username.toLowerCase());
    return taken ? 'That username is taken. Try another.' : null;
  }
  function validateEmail(email, exceptId) {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return 'Enter a valid email address.';
    const taken = Object.values(accounts()).some((a) => a.id !== exceptId && a.email.toLowerCase() === email.toLowerCase());
    return taken ? 'An account already uses that email. Log in instead.' : null;
  }
  const validatePassword = (pw) => (String(pw).length < 8 ? 'Use at least 8 characters.' : null);

  function createAccount({ username, email, password, photo }, opts = {}) {
    username = username.trim(); email = email.trim();
    const errors = {};
    const u = validateUsername(username); if (u) errors.username = u;
    const e = validateEmail(email); if (e) errors.email = e;
    const p = validatePassword(password); if (p) errors.password = p;
    if (Object.keys(errors).length) throw new AppError('invalid', 'Fix the highlighted fields.', { fields: errors });
    const id = TO.uid('u');
    const salt = TO.uid('s');
    const acc = { id, username, email, salt, pw: TO.pwHash(password, salt), photo: photo || TO.initialsAvatar(username), createdAt: TO.now(), demo: !!opts.demo };
    const all = accounts(); all[id] = acc; saveAccounts(all);
    TO.store.set(dataKey(id), opts.data || freshData(TO.now()));
    return acc;
  }

  function login(identifier, password) {
    if (!String(identifier).trim()) throw new AppError('invalid', 'Enter your username or email.', { fields: { identifier: 'Required' } });
    const acc = findAccount(identifier);
    if (!acc) throw new AppError('not_found', 'No account matches that username or email.', { fields: { identifier: 'No account found' } });
    if (acc.pw !== TO.pwHash(password, acc.salt)) throw new AppError('bad_password', 'That password is incorrect.', { fields: { password: 'Incorrect password' } });
    startSession(acc.id);
    return acc;
  }

  /** Server mode: copies the database user into this browser so the features still saved here keep working.
   *  acc.server always holds the latest values from the database (last login, login count...). */
  function adoptServerUser(user, remoteState = null) {
    const id = `srv_${user.id}`;
    const all = accounts();
    const acc = all[id] || { id, salt: null, pw: null };
    Object.assign(acc, {
      username: user.username, email: user.email, demo: !!user.isDemo, createdAt: Date.parse(user.createdAt), server: user,
      photo: user.photoUrl || acc.photo || TO.initialsAvatar(user.isDemo ? 'Demo User' : user.username, user.isDemo ? '#1AA560' : undefined),
    });
    all[id] = acc; saveAccounts(all);
    if (remoteState) {
      const cached = TO.store.get(dataKey(id), null);
      if (cached) {
        const remoteChallenges = remoteState.challenges || [];
        const mergedChallenges = new Map(remoteChallenges.map((challenge) => [challenge.supabaseId ? `db:${challenge.supabaseId}` : `id:${challenge.id}`, challenge]));
        for (const challenge of cached.challenges || []) {
          const key = challenge.supabaseId ? `db:${challenge.supabaseId}` : `id:${challenge.id}`;
          const saved = mergedChallenges.get(key);
          const combined = saved ? Object.assign({}, saved, challenge) : challenge;
          // Another device already resolved it: the server's result beats a local copy that is still open.
          if (saved && challenge.status === 'open' && saved.status !== 'open') {
            Object.assign(combined, { status: saved.status, reward: saved.reward, resolvedAt: saved.resolvedAt, supabaseSynced: true });
            combined.picks = (challenge.picks || []).map((pick) => {
              const match = (saved.picks || []).find((p) => p.gameId === pick.gameId && p.market === pick.market && p.side === pick.side);
              return match ? { ...pick, result: match.result } : pick;
            });
          }
          mergedChallenges.set(key, combined);
        }
        const hasUnsyncedChallenges = (cached.challenges || []).some((challenge) => challenge.kind === 'sports' && !challenge.supabaseId);
        const remoteHasPreferences = remoteState.appPreferencesReady && Object.keys(remoteState.settings || {}).length > 1;
        const preferences = remoteHasPreferences
          ? Object.assign({}, cached.settings || {}, remoteState.settings || {})
          : Object.assign({}, remoteState.settings || {}, cached.settings || {});
        const savedSports = [
          ...(Array.isArray(cached.settings?.sports) ? cached.settings.sports : []),
          ...(Array.isArray(remoteState.settings?.sports) ? remoteState.settings.sports : []),
        ].filter((league) => S.REAL_LEAGUES.includes(league));
        if (savedSports.length) preferences.sports = [...new Set(savedSports)];
        remoteState = Object.assign({}, cached, remoteState, { challenges: [...mergedChallenges.values()], settings: preferences });
        // The new day starts on the device. The server's wallet only moves to a new day when a challenge is
        // placed, so a lagging server day must never pull this wallet back: that would close the same day
        // again and bump the streak on every sync.
        if (hasUnsyncedChallenges || !remoteState.wallet || remoteState.wallet.dayKey !== TO.dayKey()) remoteState.wallet = cached.wallet;
        else if (cached.wallet) {
          // Supabase currently owns the balance fields, while clean-day history is local-only.
          // Keep those local streak and usage ledgers when refreshing the server wallet.
          const serverWallet = remoteState.wallet;
          const localWallet = cached.wallet;
          remoteState.wallet = Object.assign({}, localWallet, serverWallet);
          for (const key of ['streakDays', 'netByDay', 'penaltyByDay', 'overridesByDay', 'usageByDay', 'bonusDay', 'bonusGranted', 'warned']) {
            if (localWallet[key] !== undefined) remoteState.wallet[key] = localWallet[key];
          }
          for (const key of ['boostsByDay', 'insuranceByWeek']) {
            const serverCounts = serverWallet[key] || {};
            const localCounts = localWallet[key] || {};
            remoteState.wallet[key] = Object.fromEntries([...new Set([...Object.keys(serverCounts), ...Object.keys(localCounts)])]
              .map((day) => [day, Math.max(Number(serverCounts[day] || 0), Number(localCounts[day] || 0))]));
          }
          // The server may not have credited today's local tier bonus yet. Keep
          // that uncredited portion in the visible balance; the pledges RPC applies
          // the same amount atomically before it checks the pledge.
          const serverDay = serverWallet.dayKey;
          const localBonus = localWallet.bonusDay === serverDay ? Number(localWallet.bonusGranted || 0) : 0;
          const serverBonus = serverWallet.bonusDay === serverDay ? Number(serverWallet.bonusGranted || 0) : 0;
          const uncreditedBonus = Math.max(localBonus - serverBonus, 0);
          remoteState.wallet.balance = Number(serverWallet.balance || 0) + uncreditedBonus;
          if (uncreditedBonus > 0 && remoteState.wallet.balance > 0) remoteState.wallet.lockedOut = false;
          if (localBonus || serverBonus) {
            remoteState.wallet.bonusDay = serverDay;
            remoteState.wallet.bonusGranted = Math.max(localBonus, serverBonus);
          }
        }
      }
      else if (remoteState.wallet && remoteState.wallet.dayKey !== TO.dayKey()) {
        // A wallet from an earlier day has nothing to say about today's balance.
        Object.assign(remoteState.wallet, { dayKey: TO.dayKey(), balance: RULES.daily, lockedOut: false, bonusDay: null, bonusGranted: 0 });
      }
      delete remoteState.appPreferencesReady;
      TO.store.set(dataKey(id), remoteState);
    }
    else if (!TO.store.get(dataKey(id), null)) TO.store.set(dataKey(id), user.isDemo ? seedDemoData(TO.now()) : freshData(TO.now()));
    startSession(id);
    return acc;
  }

  function startSession(id) {
    TO.store.set('timeout.session', id);
    loadSession();
  }

  function logout() {
    TO.store.del('timeout.session');
    TO.account = null; TO.data = null;
  }

  function loadSession() {
    const id = TO.store.get('timeout.session', null);
    const acc = id && accounts()[id];
    if (!acc) { TO.account = null; TO.data = null; return false; }
    TO.account = acc;
    TO.data = migrate(TO.store.get(dataKey(id), null) || freshData(TO.now()));
    rollover(TO.now());
    grantTierBonus();
    save();
    return true;
  }

  function updateAccount(patch) {
    const all = accounts();
    const acc = all[TO.account.id];
    if (patch.username != null && patch.username !== acc.username) {
      const err = validateUsername(patch.username.trim(), acc.id);
      if (err) throw new AppError('invalid', err, { fields: { username: err } });
      renameEverywhere(acc.username, patch.username.trim());
      acc.username = patch.username.trim();
    }
    if (patch.email != null && patch.email !== acc.email) {
      const err = validateEmail(patch.email.trim(), acc.id);
      if (err) throw new AppError('invalid', err, { fields: { email: err } });
      acc.email = patch.email.trim();
    }
    if (patch.photo) acc.photo = patch.photo;
    if (patch.newPassword != null) {
      if (acc.pw !== TO.pwHash(patch.currentPassword || '', acc.salt)) throw new AppError('bad_password', 'Your current password is incorrect.', { fields: { currentPassword: 'Incorrect password' } });
      const err = validatePassword(patch.newPassword);
      if (err) throw new AppError('invalid', err, { fields: { newPassword: err } });
      acc.pw = TO.pwHash(patch.newPassword, acc.salt);
    }
    saveAccounts(all);
    TO.account = acc;
  }

  function renameEverywhere(oldName, newName) {
    for (const acc of Object.values(accounts())) {
      if (acc.id === TO.account.id) continue;
      mutateData(acc.id, (d) => {
        d.friends = d.friends.map((f) => (f === oldName ? newName : f));
        d.teams.forEach((t) => { t.members = t.members.map((m) => (m === oldName ? newName : m)); });
      });
    }
    TO.data.teams.forEach((t) => { t.members = t.members.map((m) => (m === oldName ? newName : m)); if (t.owner === oldName) t.owner = newName; });
  }

  function deleteAccount() {
    const all = accounts();
    delete all[TO.account.id];
    saveAccounts(all);
    TO.store.del(dataKey(TO.account.id));
    logout();
  }

  function mutateData(id, fn) {
    if (TO.account && id === TO.account.id) { fn(TO.data); save(); return; }
    const d = TO.store.get(dataKey(id), null);
    if (!d) return;
    fn(migrate(d));
    TO.store.set(dataKey(id), d);
  }

  // ---------- User data ----------
  function freshData(now) {
    const day = TO.dayKey(now);
    return {
      v: 1,
      wallet: {
        dayKey: day, balance: RULES.daily, lockedOut: false,
        netByDay: {}, penaltyByDay: {}, overridesByDay: {}, usageByDay: {}, boostsByDay: {}, insuranceByWeek: {},
        bonusDay: null, bonusGranted: 0, streakDays: 0, warned: {},
      },
      challenges: [],
      lastPledge: 5,
      settings: {
        sports: S.REAL_LEAGUES.slice(),
        showPredictions: true,
        showTodos: true,
        enforce: true,
        lockedApps: [],
        minLimit: 0,
        lowWarn: 10,
        notify: { resolved: true, friends: true, lowTime: true },
        privacy: { record: true, minutes: true, challenges: true },
        deviceLockPoints: 0, // lock points from real Screen Time picks in the iPhone app
      },
      onboarded: false,
      friends: [],
      requestsIn: [],
      requestsOut: [],
      teams: [],
      feedLive: false, // the Home "Live games only" switch; it works with whichever sport is picked
      socialProfiles: {}, // friends' shared stats and team results, cached from the server
      teamResults: {},
      socialSynced: false,
    };
  }

  // Reads saves from before the gambling-language rename. The old key names stay here on purpose.
  function renameSavedTerms(d) {
    if (!d || typeof d !== 'object') return d;
    if (d.bets && !d.challenges) d.challenges = d.bets;
    delete d.bets;
    if (d.lastStake != null && d.lastPledge == null) d.lastPledge = d.lastStake;
    delete d.lastStake;
    const market = { ml: 'winner', moneyline: 'winner', spread: 'margin' };
    const side = { over: 'higher', under: 'lower' };
    for (const challenge of d.challenges || []) {
      if (challenge.stake != null && challenge.pledgeMinutes == null) challenge.pledgeMinutes = challenge.stake;
      delete challenge.stake;
      if (challenge.payout != null && challenge.reward == null) challenge.reward = challenge.payout;
      delete challenge.payout;
      if (challenge.potentialPayout != null && challenge.potentialReward == null) challenge.potentialReward = challenge.potentialPayout;
      delete challenge.potentialPayout;
      if (challenge.legs && !challenge.picks) challenge.picks = challenge.legs;
      delete challenge.legs;
      if (challenge.settledAt != null && challenge.resolvedAt == null) challenge.resolvedAt = challenge.settledAt;
      delete challenge.settledAt;
      if (challenge.status === 'push') challenge.status = 'tie';
      for (const pick of challenge.picks || []) {
        if (market[pick.market]) pick.market = market[pick.market];
        if (side[pick.side]) pick.side = side[pick.side];
        if (pick.result === 'push') pick.result = 'tie';
      }
    }
    const privacy = d.settings && d.settings.privacy;
    if (privacy && privacy.bets != null && privacy.challenges == null) privacy.challenges = privacy.bets;
    if (privacy) delete privacy.bets;
    const notify = d.settings && d.settings.notify;
    if (notify && notify.settled != null && notify.resolved == null) notify.resolved = notify.settled;
    if (notify) delete notify.settled;
    return d;
  }

  /** The day a result counts for. The next day's limit moves, so a challenge on a later game pays when that game ends.
   *  To-do combos belong to the day they were due. */
  function creditDay(challenge) {
    if (challenge.kind !== 'todo' && challenge.resolvedAt) return TO.dayKey(Number(challenge.resolvedAt));
    return challenge.dayKey || (Number.isFinite(Number(challenge.placedAt)) ? TO.dayKey(Number(challenge.placedAt)) : null);
  }

  function migrate(d) {
    renameSavedTerms(d);
    const f = freshData(TO.now());
    for (const k of Object.keys(f)) if (d[k] === undefined) d[k] = f[k];
    for (const k of Object.keys(f.wallet)) if (d.wallet[k] === undefined) d.wallet[k] = f.wallet[k];
    for (const k of Object.keys(f.settings)) if (d.settings[k] === undefined) d.settings[k] = f.settings[k];
    // The lock flag is a cached mirror of the balance. Older server/local state can
    // leave it true after minutes were restored, so derive it from the balance.
    d.wallet.balance = Math.max(0, Number(d.wallet.balance) || 0);
    d.wallet.lockedOut = d.wallet.balance <= 0;
    if (!Array.isArray(d.settings.sports) || d.settings.sports.length === 0) d.settings.sports = S.REAL_LEAGUES.slice();
    d.challenges = (d.challenges || []).filter((challenge) => !challenge.friend);
    // Server wallets don't store the daily pledges-result ledger. Rebuild it from resolved pledges
    // so previous-day results continue to determine today's screen-time balance after sync.
    const resolvedNetByDay = {};
    for (const challenge of d.challenges || []) {
      if (challenge.status === 'open') continue;
      const day = creditDay(challenge);
      if (!day) continue;
      resolvedNetByDay[day] = (resolvedNetByDay[day] || 0) + (Number(challenge.reward || 0) - Number(challenge.pledgeMinutes || 0));
    }
    d.wallet.netByDay = resolvedNetByDay;
    if (!d.settings.lockedApps.length && !(d.settings.deviceLockPoints > 0)) d.settings.enforce = false; // nothing to block, so limits can't be on
    // "Live" used to be one of the sport chips.
    if (d.feedFilter === 'live') { d.feedFilter = 'all'; d.feedLive = true; }
    delete d.challengesIn;
    if (d.settings.notify) delete d.settings.notify.challenges;
    return d;
  }

  function save() {
    if (TO.account && TO.data) {
      TO.store.set(dataKey(TO.account.id), TO.data);
      if (TO.account.server && TO.api && TO.api.queueStateSave) TO.api.queueStateSave(TO.data);
    }
  }

  // ---------- Wallet ----------
  const W = () => TO.data.wallet;
  const today = () => W().dayKey;

  function lockPoints(d = TO.data) {
    if (!d.settings.enforce) return 0;
    const listed = d.settings.lockedApps.reduce((sum, id) => sum + ((LOCKABLE.find((x) => x.id === id) || {}).pts || 0), 0);
    return Math.max(listed, Number(d.settings.deviceLockPoints) || 0); // the higher of this list and the real picks on an iPhone
  }
  const tier = (d = TO.data) => tierForPoints(lockPoints(d));

  /** Phone screen time allowed on a day: 60 + the day before's pledges results − emergency penalties (never below the user's floor). */
  function baseLimitFor(day, d = TO.data) {
    const w = d.wallet;
    const net = w.netByDay[TO.addDays(day, -1)] || 0;
    const penalty = w.penaltyByDay[day] || 0;
    return Math.max(RULES.daily + net - penalty, d.settings.minLimit || 0, 0);
  }
  const emergencyMinutes = (day, d = TO.data) => (d.wallet.overridesByDay[day] || 0) * RULES.overrideMinutes;
  const limitFor = (day, d = TO.data) => baseLimitFor(day, d) + emergencyMinutes(day, d);

  function wallet() {
    const w = W(), day = today(), tomorrow = TO.addDays(day, 1);
    const balance = Math.max(0, Number(w.balance) || 0);
    const used = w.usageByDay[day] || 0;
    const todayLimit = limitFor(day);
    const open = TO.data.challenges.filter((b) => b.status === 'open');
    const t = tier();
    return {
      day, balance, lockedOut: balance <= 0,
      todayLimit, tomorrowLimit: baseLimitFor(tomorrow),
      yesterdayNet: w.netByDay[TO.addDays(day, -1)] || 0,
      todayNet: w.netByDay[day] || 0,
      penaltyToday: w.penaltyByDay[day] || 0,
      penaltyTomorrow: w.penaltyByDay[tomorrow] || 0,
      emergencyToday: emergencyMinutes(day),
      overridesUsed: w.overridesByDay[day] || 0,
      used, phoneLeft: Math.max(todayLimit - used, 0),
      appsLocked: TO.data.settings.enforce && used >= todayLimit,
      atRisk: open.reduce((s, b) => s + b.pledgeMinutes, 0),
      openCount: open.length,
      tier: t, points: lockPoints(),
      streak: w.streakDays, multiplier: streakMultiplier(w.streakDays),
      boostsLeft: Math.max(t.boosts - (w.boostsByDay[day] || 0), 0),
      insuranceLeft: Math.max(t.insurance - (w.insuranceByWeek[TO.weekKey(TO.dayStart(day) + 12 * TO.HOUR)] || 0), 0),
      bonusToday: w.bonusDay === day ? w.bonusGranted : 0,
    };
  }

  function grantTierBonus() {
    const w = W(), day = today();
    if (w.bonusDay !== day) { w.bonusDay = day; w.bonusGranted = 0; }
    const owed = tier().bonus - w.bonusGranted;
    if (owed > 0) {
      w.balance += owed;
      w.bonusGranted = tier().bonus;
      if (w.balance > 0) w.lockedOut = false;
    }
  }

  /** Starts a new day at local midnight: closes out the old day, updates the streak, resets the challenge balance. */
  function rollover(now) {
    const w = W();
    const target = TO.dayKey(now);
    if (w.dayKey === target) return false;
    if (w.dayKey > target) { w.dayKey = target; return false; } // The local date moved backward.
    let guard = 0;
    while (w.dayKey < target && guard++ < 400) {
      const day = w.dayKey;
      closeTodos(day, now);
      const clean = TO.data.settings.enforce && (w.usageByDay[day] || 0) <= limitFor(day) && !(w.overridesByDay[day] > 0);
      w.streakDays = clean ? w.streakDays + 1 : 0;
      w.dayKey = TO.addDays(day, 1);
    }
    w.balance = RULES.daily;
    w.lockedOut = false;
    w.bonusDay = null; w.bonusGranted = 0;
    grantTierBonus();
    prune();
    TO.emit('newday', { day: w.dayKey });
    return true;
  }

  function prune() {
    const cutoff = TO.addDays(today(), -60);
    const w = W();
    for (const k of ['netByDay', 'penaltyByDay', 'overridesByDay', 'usageByDay', 'boostsByDay']) {
      for (const day of Object.keys(w[k])) if (day < cutoff) delete w[k][day];
    }
  }

  function addUsage(minutes) {
    const w = W(), day = today();
    w.usageByDay[day] = Math.max(0, (w.usageByDay[day] || 0) + minutes);
    save();
    checkPhoneTime();
  }

  function checkPhoneTime() {
    const wl = wallet();
    const w = W();
    w.warned = w.warned || {};
    if (!TO.data.settings.enforce) return;
    if (wl.appsLocked && w.warned.locked !== wl.day) {
      w.warned.locked = wl.day;
      TO.emit('toast', { kind: 'loss', title: 'Locked apps are blocked', msg: 'You used all of today\'s phone time. Use an emergency unlock in Settings if you really need it.' });
    } else if (!wl.appsLocked && wl.phoneLeft <= TO.data.settings.lowWarn && w.warned.low !== wl.day && TO.data.settings.notify.lowTime) {
      w.warned.low = wl.day;
      TO.emit('toast', { kind: 'warn', title: `${wl.phoneLeft} min of phone time left`, msg: 'Your locked apps close when it runs out.' });
    }
    save();
  }

  function useEmergencyUnlock() {
    const w = W(), day = today();
    if ((w.overridesByDay[day] || 0) >= RULES.maxOverrides) throw new AppError('limit', `You've used both emergency unlocks today. They reset at midnight.`);
    w.overridesByDay[day] = (w.overridesByDay[day] || 0) + 1;
    const tomorrow = TO.addDays(day, 1);
    w.penaltyByDay[tomorrow] = (w.penaltyByDay[tomorrow] || 0) + RULES.overridePenalty;
    w.streakDays = 0;
    w.warned.locked = null;
    save();
  }

  function setSetting(path, value) {
    const parts = path.split('.');
    let o = TO.data.settings;
    while (parts.length > 1) o = o[parts.shift()];
    const hadLocks = TO.data.settings.lockedApps.length > 0;
    o[parts[0]] = value;
    // App limits need something to block: they switch off with the last locked app and back on with the first.
    if (path === 'lockedApps') TO.data.settings.enforce = (value.length > 0 && (TO.data.settings.enforce || !hadLocks)) || (TO.data.settings.enforce && TO.data.settings.deviceLockPoints > 0);
    if (path === 'lockedApps' || path === 'enforce') grantTierBonus();
    save();
  }

  // ---------- pledges ----------
  function pickFromSelection(sel, now) {
    if (sel.kind === 'pred' || sel.market === 'pred') {
      const p = S.prediction(sel.predId, now);
      return { selId: sel.id, kind: 'pred', predId: sel.predId, market: 'pred', side: sel.side, line: null, price: sel.price,
        label: S.selectionLabel(sel), marketLabel: 'Prediction', matchup: p.q, league: 'pred', start: p.resolves, result: 'pending', final: null };
    }
    if (sel.kind === 'race' || sel.market === 'race') {
      const race = TO.races.get(sel.raceId);
      const horse = TO.races.horse(sel.horseId || sel.side);
      return { selId: sel.id, kind: 'race', raceId: sel.raceId, horseId: horse.id, market: 'race', side: String(horse.id), price: sel.price,
        label: horse.name, marketLabel: 'Race winner', matchup: `Virtual Race #${race.number}`, league: 'race', start: race.startedAt || now, result: 'pending', final: null };
    }
    const g = S.game(sel.gameId, now);
    return { selId: sel.id, kind: 'game', gameId: sel.gameId, market: sel.market, side: sel.side, line: sel.line, price: sel.price,
      label: S.selectionLabel(sel, g), marketLabel: S.marketLabel(sel, g), matchup: `${g.away.name} @ ${g.home.name}`,
      short: `${g.away.abbr} @ ${g.home.abbr}`, league: g.league, start: g.start, result: 'pending', final: null };
  }

  const combine = (picks) => {
    const dec = picks.reduce((p, l) => p * TO.pointValue.decimal(l.price), 1);
    return { decimal: dec, american: TO.pointValue.fromDecimal(dec) };
  };

  /** Saves a daily commitment from selected matchup choices. */
  function submitPledge({ picks, pledgeMinutes, boost, insure }, now = TO.now()) {
    rollover(now);
    const w = W();
    if (!picks.length) throw new AppError('empty', 'Add a pick to your challenge commitment.');
    if (picks.length > RULES.maxMatchupPicks) throw new AppError('too_many', `Combo Goals can include up to ${RULES.maxMatchupPicks} matchup choices.`);
    // Every pick must still be open and at the price the user saw.
    const changed = [];
    const built = picks.map((p) => {
      const cur = S.currentSelection(p.selId, now);
      if (!cur || !cur.sel || !cur.open) throw new AppError('closed', 'One of your picks is no longer available. Remove it to continue.');
      if (cur.sel.price !== p.price || cur.sel.line !== p.line) changed.push(p.selId);
      return pickFromSelection(cur.sel, now);
    });
    const matchupIds = built.map((pick) => pick.gameId).filter(Boolean);
    if (new Set(matchupIds).size !== matchupIds.length) throw new AppError('duplicate_matchup', 'Choose only one target from each matchup.');
    if (changed.length) throw new AppError('value_changed', 'A challenge target changed. Review it and confirm again.', { changed });
    if (built.some((pick) => pick.kind === 'race') && built.length !== 1) {
      throw new AppError('race_single', 'Virtual race picks can only be placed as a single challenge.');
    }

    if (w.lockedOut || w.balance <= 0) throw new AppError('locked', 'You\'re out of pledge minutes for today. Pledges reopen at midnight.');
    if (!Number.isInteger(pledgeMinutes) || pledgeMinutes < 1) throw new AppError('pledge', 'Enter a pledge of at least 1 minute.');
    if (pledgeMinutes > w.balance) throw new AppError('not_enough', `Not enough screentime. You have ${w.balance} min left to challenge today.`, { remaining: w.balance });

    const wl = wallet();
    const { decimal, american } = combine(built);
    const challenge = {
      id: TO.uid('pledge'), kind: built[0].kind === 'race' ? 'race' : 'sports', placedAt: now, dayKey: w.dayKey,
      pledgeMinutes, picks: built, decimal, american,
      boosted: false, insured: false, multiplier: 1, targetMultiplier: +decimal.toFixed(2), maxAllowedMinutes: MAX_ALLOWED_MINUTES, status: 'open', reward: 0, resolvedAt: null,
    };
    let mult = wl.multiplier;
    if (boost && wl.boostsLeft > 0) {
      challenge.boosted = true;
      mult *= 1 + RULES.boostPercent;
      w.boostsByDay[w.dayKey] = (w.boostsByDay[w.dayKey] || 0) + 1;
    }
    if (insure && built.length > 1 && wl.insuranceLeft > 0) {
      challenge.insured = true;
      const wk = TO.weekKey(now);
      w.insuranceByWeek[wk] = (w.insuranceByWeek[wk] || 0) + 1;
    }
    challenge.multiplier = +mult.toFixed(4);
    w.balance -= pledgeMinutes;
    TO.data.lastPledge = pledgeMinutes;
    if (w.balance <= 0) { w.balance = 0; w.lockedOut = true; }
    TO.data.challenges.push(challenge);
    if (challenge.kind === 'race') TO.races.startForChallenge(challenge, now);
    save();
    return challenge;
  }

  /** To-do Combo Goal (Could-have): pledge minutes on finishing up to 3 tasks before midnight. */
  const TODO_VALUE = { easy: 50, medium: 100, hard: 200 };
  function placeTodoCombo({ tasks, pledgeMinutes }, now = TO.now()) {
    rollover(now);
    const w = W();
    const clean = tasks.map((t) => ({ text: String(t.text || '').trim(), difficulty: t.difficulty })).filter((t) => t.text);
    if (!clean.length) throw new AppError('empty', 'Add at least one task.');
    if (clean.length > RULES.maxPicks) throw new AppError('too_many', `To-do combos can have up to ${RULES.maxPicks} tasks.`);
    if (w.lockedOut || w.balance <= 0) throw new AppError('locked', 'You\'re out of pledge minutes for today. Pledges reopen at midnight.');
    if (!Number.isInteger(pledgeMinutes) || pledgeMinutes < 1) throw new AppError('pledge', 'Enter a pledge of at least 1 minute.');
    if (pledgeMinutes > RULES.todoMaxPledge) throw new AppError('pledge', `To-do combos are capped at ${RULES.todoMaxPledge} minutes.`);
    if (pledgeMinutes > w.balance) throw new AppError('not_enough', `Not enough screentime. You have ${w.balance} min left to challenge today.`, { remaining: w.balance });
    const picks = clean.map((t, i) => ({ selId: `todo-${i}`, kind: 'todo', market: 'todo', text: t.text, difficulty: t.difficulty, price: TODO_VALUE[t.difficulty] || 100,
      label: t.text, marketLabel: `To-do · ${t.difficulty}`, matchup: 'Finish before midnight', result: 'pending', final: null }));
    const { decimal, american } = combine(picks);
    const challenge = { id: TO.uid('pledge'), kind: 'todo', placedAt: now, dayKey: w.dayKey, deadline: TO.nextMidnight(now), pledgeMinutes, picks, decimal, american,
      boosted: false, insured: false, multiplier: wallet().multiplier, status: 'open', reward: 0, resolvedAt: null };
    w.balance -= pledgeMinutes;
    if (w.balance <= 0) { w.balance = 0; w.lockedOut = true; }
    TO.data.challenges.push(challenge);
    save();
    return challenge;
  }

  function completeTodo(challengeId, pickIndex) {
    const challenge = TO.data.challenges.find((b) => b.id === challengeId);
    if (!challenge || challenge.status !== 'open') return null;
    const pick = challenge.picks[pickIndex];
    pick.result = 'won'; pick.final = `Done ${TO.fmtTime(TO.now())}`;
    const resolved = finishIfDone(challenge);
    save();
    return resolved;
  }

  function closeTodos(day, now) {
    for (const challenge of TO.data.challenges) {
      if (challenge.kind !== 'todo' || challenge.status !== 'open' || challenge.dayKey !== day) continue;
      challenge.picks.forEach((l) => { if (l.result === 'pending') { l.result = 'lost'; l.final = 'Not done by midnight'; } });
      finishIfDone(challenge, now);
    }
  }

  function outcome(challenge) {
    const picks = challenge.picks;
    const lost = picks.filter((l) => l.result === 'lost').length;
    const pending = picks.some((l) => l.result === 'pending');
    if (lost) {
      if (challenge.insured) {
        if (pending) return { status: 'open' };
        if (lost === 1) return { status: 'tie', reward: challenge.pledgeMinutes, insurancePaid: true };
      }
      return { status: 'lost', reward: 0 };
    }
    if (pending) return { status: 'open' };
    const won = picks.filter((l) => l.result === 'won');
    if (!won.length) return { status: picks.every((l) => l.result === 'void') ? 'void' : 'tie', reward: challenge.pledgeMinutes };
    const dec = won.reduce((p, l) => p * TO.convertPointValueToMultiplier(l.price), 1);
    let reward = Math.round(challenge.pledgeMinutes * dec);
    reward = challenge.pledgeMinutes + Math.round((reward - challenge.pledgeMinutes) * (challenge.multiplier || 1));
    reward = Math.min(reward, challenge.maxAllowedMinutes || MAX_ALLOWED_MINUTES);
    return { status: 'won', reward };
  }

  function finishIfDone(challenge, now = TO.now()) {
    const res = outcome(challenge);
    if (res.status === 'open') return null;
    challenge.status = res.status;
    challenge.reward = res.reward;
    challenge.insurancePaid = !!res.insurancePaid;
    challenge.resolvedAt = now;
    const w = W();
    const day = creditDay(challenge);
    w.netByDay[day] = (w.netByDay[day] || 0) + (challenge.reward - challenge.pledgeMinutes);
    // Voids and pushes return the pledge; wins and losses only affect the next day's limit.
    if (challenge.dayKey === w.dayKey && (challenge.status === 'void' || challenge.status === 'tie')) w.balance += challenge.reward;
    return challenge;
  }

  /** Grades every open pledges against the latest scores. Runs on every tick, so pledges resolve seconds after a game ends. */
  function resolve(now = TO.now()) {
    const resolved = [];
    for (const challenge of TO.data.challenges) {
      if (challenge.status !== 'open' || challenge.kind === 'todo') continue;
      let changed = false;
      for (const pick of challenge.picks) {
        if (pick.result !== 'pending') continue;
        const r = S.grade(pick, now);
        if (r === 'pending') continue;
        pick.result = r;
        changed = true;
        if (pick.kind === 'pred') {
          const p = S.prediction(pick.predId, now);
          pick.final = `Resolved ${p.outcome === 'yes' ? 'YES' : 'NO'}`;
        } else if (pick.kind === 'race') {
          const race = TO.races.get(pick.raceId);
          pick.final = race && race.winnerId ? `Winner: ${TO.races.horse(race.winnerId).name}` : 'Race finished';
        } else {
          const g = S.game(pick.gameId, now);
          pick.final = g.state === 'postponed' ? 'Postponed' : `${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore}${g.ot ? ` (${g.ot.label === '10' ? '10 inn' : 'OT'})` : ''}`;
        }
      }
      if (changed && finishIfDone(challenge, now)) resolved.push(challenge);
    }
    if (resolved.length) save();
    return resolved;
  }

  // ---------- Record / stats ----------
  function statsFor(challenges) {
    const resolved = challenges.filter((b) => b.status !== 'open');
    const won = resolved.filter((b) => b.status === 'won');
    const lost = resolved.filter((b) => b.status === 'lost');
    const voids = resolved.filter((b) => b.status === 'void' || b.status === 'tie');
    const net = resolved.reduce((s, b) => s + (b.reward - b.pledgeMinutes), 0);
    const bySport = {};
    for (const b of resolved) {
      const key = b.kind === 'todo' ? 'todo' : b.kind === 'race' ? 'race' : b.picks.length > 1 ? 'combo-goal' : b.picks[0].league;
      bySport[key] = bySport[key] || { w: 0, l: 0, net: 0 };
      if (b.status === 'won') bySport[key].w++;
      if (b.status === 'lost') bySport[key].l++;
      bySport[key].net += b.reward - b.pledgeMinutes;
    }
    return {
      w: won.length, l: lost.length, v: voids.length, net,
      pct: won.length + lost.length ? Math.round((100 * won.length) / (won.length + lost.length)) : null,
      best: won.reduce((m, b) => Math.max(m, b.reward - b.pledgeMinutes), 0),
      bySport,
      recent: resolved.filter((b) => b.status === 'won' || b.status === 'lost').sort((a, b) => b.resolvedAt - a.resolvedAt).slice(0, 5).map((b) => (b.status === 'won' ? 'W' : 'L')),
    };
  }
  const myStats = () => statsFor(TO.data.challenges);

  // ---------- People & friends ----------
  // Real accounts get real people only. Demo profiles are for offline mode, where there is no server to find anyone on.
  const usesServerSocial = () => !!(TO.account && TO.account.server);

  function person(username) {
    if (usesServerSocial()) {
      const p = (TO.data.socialProfiles || {})[String(username).toLowerCase()];
      return p ? { ...p, photo: p.photo || TO.initialsAvatar(p.username), remote: true } : null;
    }
    const fake = PEOPLE.find((p) => p.username.toLowerCase() === String(username).toLowerCase());
    if (fake) return fake;
    const acc = findAccountByUsername(username);
    if (!acc) return null;
    const d = acc.id === (TO.account && TO.account.id) ? TO.data : migrate(TO.store.get(dataKey(acc.id), null) || freshData(TO.now()));
    const st = statsFor(d.challenges);
    return { username: acc.username, name: acc.username, photo: acc.photo, w: st.w, l: st.l, net: st.net, tier: tier(d).id, streak: d.wallet.streakDays,
      share: d.settings.privacy, local: true, accountId: acc.id, openChallenges: d.challenges.filter((b) => b.status === 'open') };
  }

  /** Open picks a friend has shared (fake friends pick from the live board). */
  function sharedPicks(p, now = TO.now()) {
    if (!p || !p.share.challenges) return [];
    if (p.remote) return p.picks || [];
    if (p.local) return (p.openChallenges || []).slice(0, 3).map((b) => ({ label: b.picks.map((l) => l.label).join(' + '), matchup: b.picks.length > 1 ? `${b.picks.length}-pick Combo Goal` : b.picks[0].matchup, price: b.american, pledgeMinutes: b.pledgeMinutes }));
    const games = S.board(now).filter((g) => (g.state === 'live' || g.state === 'scheduled') && !g.simulated);
    const rand = TO.rng(`${p.username}-${Math.floor(now / S.SLOT)}`);
    const picks = [];
    const count = 1 + Math.floor(rand() * 2);
    for (let i = 0; i < count && games.length; i++) {
      const g = games[Math.floor(rand() * games.length)];
      const o = S.pointValue(g.id, now);
      const sel = o.all[Math.floor(rand() * o.all.length)];
      picks.push({ label: S.selectionLabel(sel, g), matchup: `${g.away.name} @ ${g.home.name}`, price: sel.price, pledgeMinutes: 5 + Math.floor(rand() * 4) * 5, gameId: g.id });
    }
    return picks;
  }

  const sameUser = (a, b) => String(a || '').toLowerCase() === String(b || '').toLowerCase();

  function searchPeople(query) {
    const q = String(query || '').trim().toLowerCase().replace(/^@/, '');
    if (!q || usesServerSocial()) return [];
    const me = TO.account.username.toLowerCase();
    const locals = Object.values(accounts()).filter((a) => a.username.toLowerCase() !== me).map((a) => ({ username: a.username, name: a.username, photo: a.photo, local: true }));
    return [...PEOPLE, ...locals].filter((p) => {
      const username = p.username.toLowerCase();
      return username !== me && (username.includes(q) || (p.name || '').toLowerCase().includes(q));
    }).slice(0, 8);
  }

  const relation = (username) => {
    const d = TO.data;
    if (d.friends.some((f) => sameUser(f, username))) return 'friend';
    if (d.requestsOut.some((r) => sameUser(r.to, username))) return 'requested';
    if (d.requestsIn.some((r) => sameUser(r.from, username))) return 'incoming';
    return 'none';
  };

  /** An invite link is a yes from the sender, so this connects both people when the other account is on this device. */
  function addFriend(username) {
    const u = String(username || '').trim().replace(/^@/, '');
    if (!u || sameUser(u, TO.account.username) || !/^[a-zA-Z0-9_.]{1,20}$/.test(u)) return false;
    if (!TO.data.friends.some((f) => sameUser(f, u))) TO.data.friends.push(u);
    TO.data.requestsIn = TO.data.requestsIn.filter((r) => !sameUser(r.from, u));
    TO.data.requestsOut = TO.data.requestsOut.filter((r) => !sameUser(r.to, u));
    const acc = findAccountByUsername(u);
    if (acc) {
      mutateData(acc.id, (d) => {
        if (!d.friends.some((f) => sameUser(f, TO.account.username))) d.friends.push(TO.account.username);
        d.requestsOut = d.requestsOut.filter((r) => !sameUser(r.to, TO.account.username));
        d.requestsIn = d.requestsIn.filter((r) => !sameUser(r.from, TO.account.username));
      });
    }
    save();
    return true;
  }

  function sendFriendRequest(username, now = TO.now()) {
    const rel = relation(username);
    if (rel === 'friend' || rel === 'requested') return;
    if (rel === 'incoming') {
      const incoming = TO.data.requestsIn.find((r) => sameUser(r.from, username));
      if (incoming) acceptFriendRequest(incoming.id);
      return;
    }
    const p = person(username);
    const req = { id: TO.uid('fr'), to: username, at: now };
    if (p && p.fake) req.acceptAt = now + 6000; // fake people accept after a few seconds
    TO.data.requestsOut.push(req);
    if (p && p.local) {
      mutateData(p.accountId, (d) => { if (!d.requestsIn.some((r) => r.from === TO.account.username)) d.requestsIn.push({ id: req.id, from: TO.account.username, at: now }); });
    }
    save();
  }

  function acceptFriendRequest(id) {
    const d = TO.data;
    const req = d.requestsIn.find((r) => r.id === id);
    if (!req) return;
    d.requestsIn = d.requestsIn.filter((r) => r.id !== id);
    if (!d.friends.includes(req.from)) d.friends.push(req.from);
    const acc = findAccountByUsername(req.from);
    if (acc) {
      mutateData(acc.id, (o) => {
        o.requestsOut = o.requestsOut.filter((r) => r.to !== TO.account.username);
        if (!o.friends.includes(TO.account.username)) o.friends.push(TO.account.username);
      });
    }
    save();
  }

  function declineFriendRequest(id) {
    const d = TO.data;
    const req = d.requestsIn.find((r) => r.id === id);
    d.requestsIn = d.requestsIn.filter((r) => r.id !== id);
    const acc = req && findAccountByUsername(req.from);
    if (acc) mutateData(acc.id, (o) => { o.requestsOut = o.requestsOut.filter((r) => r.to !== TO.account.username); });
    save();
  }

  /** Resending is allowed once an hour per request. Returns ms until it can be sent again (0 = now). */
  const RESEND_WAIT = TO.HOUR;
  const resendWait = (req, now = TO.now()) => Math.max(0, req.at + RESEND_WAIT - now);

  /** Replaces this browser's friends and requests with what the server says, and reports what's new since last time. */
  function applySocial(state) {
    const d = TO.data;
    if (!d || !usesServerSocial() || !state) return { newRequests: [], newFriends: [] };
    const friendsBefore = new Set(d.friends.map((u) => String(u).toLowerCase()));
    const requestsBefore = new Set(d.requestsIn.map((r) => String(r.from).toLowerCase()));
    // The first sync isn't news: it just brings the account up to date.
    const changes = d.socialSynced ? {
      newRequests: state.requestsIn.map((r) => r.username).filter((u) => !requestsBefore.has(u.toLowerCase())),
      newFriends: state.friends.map((f) => f.username).filter((u) => !friendsBefore.has(u.toLowerCase())),
    } : { newRequests: [], newFriends: [] };
    d.friends = state.friends.map((f) => f.username);
    d.socialProfiles = {};
    for (const f of state.friends) d.socialProfiles[f.username.toLowerCase()] = f;
    for (const r of [...state.requestsIn, ...state.requestsOut]) {
      const key = r.username.toLowerCase();
      if (!d.socialProfiles[key]) d.socialProfiles[key] = { username: r.username, name: r.name, photo: r.photo, w: 0, l: 0, net: 0, tier: 'rookie', streak: 0, share: { record: false, minutes: false, challenges: false }, picks: [] };
    }
    d.requestsIn = state.requestsIn.map((r) => ({ id: r.id, from: r.username, at: r.at }));
    d.requestsOut = state.requestsOut.map((r) => ({ id: r.id, to: r.username, at: r.at }));
    d.socialSynced = true;
    saveQuiet();
    return changes;
  }

  function resendFriendRequest(username, now = TO.now()) {
    const req = TO.data.requestsOut.find((r) => r.to === username);
    if (!req) return false;
    if (resendWait(req, now) > 0) throw new AppError('too_soon', `You can send @${username} another request in ${TO.fmtIn(resendWait(req, now))}.`);
    req.at = now;
    const acc = findAccountByUsername(username);
    if (acc) mutateData(acc.id, (o) => { const r = o.requestsIn.find((x) => x.from === TO.account.username); if (r) r.at = now; });
    save();
    return true;
  }

  function cancelFriendRequest(username) {
    TO.data.requestsOut = TO.data.requestsOut.filter((r) => r.to !== username);
    const acc = findAccountByUsername(username);
    if (acc) mutateData(acc.id, (o) => { o.requestsIn = o.requestsIn.filter((r) => r.from !== TO.account.username); });
    save();
  }

  function removeFriend(username) {
    TO.data.friends = TO.data.friends.filter((f) => f !== username);
    const acc = findAccountByUsername(username);
    if (acc) mutateData(acc.id, (o) => { o.friends = o.friends.filter((f) => f !== TO.account.username); });
    save();
  }

  /** Background social events: fake friends accept requests after a few seconds. */
  function socialTick(now = TO.now()) {
    const d = TO.data;
    const events = [];
    for (const r of d.requestsOut.slice()) {
      if (r.acceptAt && now >= r.acceptAt) {
        d.requestsOut = d.requestsOut.filter((x) => x.id !== r.id);
        if (!d.friends.includes(r.to)) d.friends.push(r.to);
        events.push({ type: 'friend', username: r.to });
      }
    }
    if (events.length) save();
    return events;
  }

  // ---------- Teams ----------
  function teamStatus(t, now = TO.now()) {
    const start = TO.dayStart(t.start), end = TO.dayStart(t.end) + DAY;
    if (now < start) return 'upcoming';
    if (now >= end) return 'ended';
    return 'active';
  }

  function teamStandings(t, now = TO.now()) {
    const start = TO.dayStart(t.start), end = TO.dayStart(t.end) + DAY;
    const lastDay = TO.dayKey(Math.min(now, end - 1));
    return t.members.map((u) => {
      const mine = sameUser(u, TO.account.username);
      const result = !mine && ((TO.data.teamResults || {})[t.id] || []).find((r) => sameUser(r.username, u));
      if (result) return { username: u, me: false, net: result.net, w: result.w, l: result.l, hidden: !!result.hidden, photo: result.photo || TO.initialsAvatar(u), tier: result.tier || 'rookie' };
      const p = mine ? null : person(u);
      // A username from search that isn't a demo profile or an account on this device
      // still belongs on the roster. Don't borrow the current user's record for them.
      if (!mine && !p) {
        return { username: u, me: false, net: 0, w: 0, l: 0, hidden: true, photo: TO.initialsAvatar(u), tier: 'rookie' };
      }
      let net = 0, w = 0, l = 0, hidden = false;
      if (!p || p.local) {
        const challenges = p ? migrate(TO.store.get(dataKey(p.accountId), null) || freshData(now)).challenges : TO.data.challenges;
        for (const b of challenges) {
          if (b.status === 'open' || b.placedAt < start || b.placedAt >= end) continue;
          net += b.reward - b.pledgeMinutes;
          if (b.status === 'won') w++;
          if (b.status === 'lost') l++;
        }
        if (p && !p.share.minutes) hidden = true;
      } else {
        if (now >= start) {
          for (let day = t.start; day <= lastDay; day = TO.addDays(day, 1)) {
            const r = TO.unit(`${t.id}-${u}-${day}`);
            net += Math.round(10 * r + (p.net > 0 ? 2 : -1));
            const games = 1 + Math.floor(TO.u01(`${t.id}-${u}-${day}-n`) * 3);
            const wins = Math.round(games * (0.5 + 0.3 * r));
            w += wins; l += games - wins;
          }
        }
        if (!p.share.minutes) hidden = true;
      }
      return { username: u, me: mine, net, w, l, hidden, photo: p ? p.photo : TO.account.photo, tier: p ? p.tier : tier().id };
    }).sort((a, b) => (a.hidden - b.hidden) || b.net - a.net);
  }

  function saveQuiet() {
    if (TO.account && TO.data) TO.store.set(dataKey(TO.account.id), TO.data);
  }

  function newShareKey() {
    const bytes = new Uint8Array(16);
    if (globalThis.crypto && globalThis.crypto.getRandomValues) globalThis.crypto.getRandomValues(bytes);
    else for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
    return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
  }

  function touch(team) {
    team.rev = (team.rev || 0) + 1;
    return team.rev;
  }

  function applyRemote(local, remote) {
    if (remote.name) local.name = remote.name;
    if (remote.start) local.start = String(remote.start).slice(0, 10);
    if (remote.end) local.end = String(remote.end).slice(0, 10);
    if (remote.owner) local.owner = remote.owner;
    if (Array.isArray(remote.members) && remote.members.length) local.members = remote.members.slice();
    local.remote = true;
  }

  function ensureTeamKey(team) {
    if (!team) return null;
    if (!team.shareKey) {
      team.shareKey = newShareKey();
      touch(team);
      save();
      publishTeam(team);
    }
    return team.shareKey;
  }

  function publishTeam(team) {
    if (!team.shareKey || !TO.api || !TO.api.publishTeam) return;
    TO.api.publishTeam(team).then((remote) => {
      const current = TO.data && TO.data.teams.find((t) => t.id === team.id);
      if (!current || !remote) return;
      current.remote = true;
      saveQuiet();
    }).catch(() => {});
  }

  /** Copies the team onto every member who has an account saved in this browser. */
  function syncTeamCopies(team) {
    const copy = JSON.parse(JSON.stringify(team));
    for (const u of team.members) {
      if (sameUser(u, TO.account.username)) continue;
      const acc = findAccountByUsername(u);
      if (!acc) continue;
      mutateData(acc.id, (d) => {
        const existing = d.teams.find((x) => x.id === team.id);
        if (existing) {
          existing.name = copy.name;
          existing.start = copy.start;
          existing.end = copy.end;
          existing.owner = copy.owner;
          existing.members = copy.members.slice();
        } else d.teams.push(JSON.parse(JSON.stringify(copy)));
      });
    }
  }

  function createTeam({ name, start, end, members }) {
    name = String(name || '').trim();
    const errors = {};
    if (!name) errors.name = 'Give your team a name.';
    if (!start) errors.start = 'Pick a start date.';
    if (!end) errors.end = 'Pick an end date.';
    if (start && end && end < start) errors.end = 'End date must be on or after the start date.';
    if (Object.keys(errors).length) throw new AppError('invalid', 'Fix the highlighted fields.', { fields: errors });
    const invited = [];
    const seen = new Set([TO.account.username.toLowerCase()]);
    for (const raw of members || []) {
      const u = String(raw || '').trim();
      const key = u.toLowerCase();
      if (!u || seen.has(key)) continue;
      seen.add(key);
      invited.push(u);
    }
    const team = { id: TO.uid('team'), name, start, end, members: [TO.account.username, ...invited], owner: TO.account.username, createdAt: TO.now(), shareKey: newShareKey(), remote: false, rev: 1 };
    TO.data.teams.push(team);
    syncTeamCopies(team);
    save();
    publishTeam(team);
    return team;
  }

  function leaveTeam(id, opts = {}) {
    const t = TO.data.teams.find((x) => x.id === id);
    const shareKey = t && t.shareKey;
    const username = TO.account.username;
    TO.data.teams = TO.data.teams.filter((x) => x.id !== id);
    if (t) {
      for (const u of t.members) {
        if (sameUser(u, username)) continue;
        const acc = findAccountByUsername(u);
        if (!acc) continue;
        mutateData(acc.id, (d) => {
          const existing = d.teams.find((x) => x.id === id);
          if (!existing) return;
          existing.members = existing.members.filter((m) => !sameUser(m, username));
          if (!existing.members.length) d.teams = d.teams.filter((x) => x.id !== id);
        });
      }
    }
    save();
    if (opts.remote !== false && shareKey && TO.api && TO.api.leaveTeamRemote) TO.api.leaveTeamRemote({ id, shareKey }, username).catch(() => {});
  }

  function inviteToTeam(id, members) {
    const t = TO.data.teams.find((x) => x.id === id);
    if (!t) return;
    const added = [];
    for (const raw of members || []) {
      const u = String(raw || '').trim();
      if (!u || t.members.some((m) => sameUser(m, u))) continue;
      t.members.push(u);
      added.push(u);
    }
    if (!added.length) return;
    touch(t);
    syncTeamCopies(t);
    save();
    if (t.shareKey && TO.api && TO.api.addTeamMember) added.forEach((u) => { TO.api.addTeamMember(t, u).catch(() => {}); });
  }

  /** Join a team from its link. Adds you, and the server roster when the link has a key. */
  function joinTeam(snapshot) {
    const id = String(snapshot.id || '').trim();
    const name = String(snapshot.name || '').trim();
    const start = String(snapshot.start || '').slice(0, 10);
    const end = String(snapshot.end || '').slice(0, 10);
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(id) || !name || !/^\d{4}-\d{2}-\d{2}$/.test(start) || !/^\d{4}-\d{2}-\d{2}$/.test(end) || end < start) {
      throw new AppError('invalid', 'That team link is missing a name or its dates.');
    }
    let team = TO.data.teams.find((t) => t.id === id);
    if (!team) {
      team = { id, name, start, end, members: [], owner: snapshot.owner || TO.account.username, createdAt: TO.now(), shareKey: snapshot.shareKey || null, remote: false, rev: 0 };
      TO.data.teams.push(team);
    }
    if (snapshot.shareKey) team.shareKey = snapshot.shareKey;
    team.name = name;
    team.start = start;
    team.end = end;
    if (snapshot.owner) team.owner = snapshot.owner;
    const add = (u) => { if (u && !team.members.some((m) => sameUser(m, u))) team.members.push(u); };
    add(snapshot.owner);
    for (const raw of snapshot.members || []) add(String(raw || '').trim());
    add(TO.account.username);
    const rev = touch(team);
    syncTeamCopies(team);
    save();
    if (team.shareKey && TO.api && TO.api.addTeamMember) {
      const key = team.shareKey;
      TO.api.addTeamMember(team, TO.account.username).then((remote) => {
        const current = TO.data && TO.data.teams.find((t) => t.id === id);
        if (!current || !remote || (current.rev || 0) !== rev) return;
        applyRemote(current, remote);
        current.shareKey = key;
        syncTeamCopies(current);
        saveQuiet();
      }).catch(() => {});
    }
    return team;
  }

  /** Pull rosters that were saved on the server. A failed request leaves the local team alone. */
  function refreshTeams() {
    if (!TO.data || !TO.api || !TO.api.fetchTeam) return Promise.resolve(false);
    const revs = new Map(TO.data.teams.map((t) => [t.id, t.rev || 0]));
    let changed = false;
    const pulls = TO.data.teams.filter((t) => t.shareKey && t.remote).map(async (team) => {
      const remote = await TO.api.fetchTeam(team.id, team.shareKey);
      const current = TO.data && TO.data.teams.find((t) => t.id === team.id);
      if (!current || (current.rev || 0) !== revs.get(team.id) || remote === null) return;
      if (remote === false || !(remote.members || []).some((m) => sameUser(m, TO.account.username))) {
        leaveTeam(team.id, { remote: false });
        changed = true;
        return;
      }
      applyRemote(current, remote);
      current.shareKey = team.shareKey;
      syncTeamCopies(current);
      changed = true;
    });
    const mine = TO.api.myTeams ? TO.api.myTeams() : Promise.resolve(null);
    return Promise.all([mine, ...pulls]).then(([listed]) => {
      if (Array.isArray(listed) && TO.data) {
        const seen = new Set();
        for (const remote of listed) {
          if (!remote || !remote.id) continue;
          seen.add(remote.id);
          let local = TO.data.teams.find((t) => t.id === remote.id);
          if (!local) {
            local = { id: remote.id, name: remote.name, start: String(remote.start).slice(0, 10), end: String(remote.end).slice(0, 10), members: remote.members || [TO.account.username], owner: remote.owner || TO.account.username, createdAt: TO.now(), remote: true, rev: 1 };
            TO.data.teams.push(local);
            changed = true;
          } else if ((local.rev || 0) === revs.get(local.id)) {
            const key = local.shareKey;
            applyRemote(local, remote);
            if (key) local.shareKey = key;
            changed = true;
          }
        }
        const kept = TO.data.teams.filter((t) => t.shareKey || !t.remote || seen.has(t.id));
        if (kept.length !== TO.data.teams.length) { TO.data.teams = kept; changed = true; }
      }
      // Real results for everyone on each roster, for the team's dates.
      const standings = TO.data && TO.api.teamStandings ? TO.data.teams.filter((t) => t.shareKey && t.remote).map(async (team) => {
        const rows = await TO.api.teamStandings(team.id, team.shareKey);
        if (rows && TO.data) { TO.data.teamResults[team.id] = rows; changed = true; }
      }) : [];
      return Promise.all(standings).then(() => {
        if (changed) {
          saveQuiet();
          if (TO.app) TO.app.render();
          if (TO.ui && TO.ui.sheetOpen && TO.ui.sheetOpen('team')) TO.ui.refreshSheet('team');
        }
        return changed;
      });
    }).catch(() => false);
  }

  // ---------- Leaderboard ----------
  function leaderboard() {
    const me = myStats();
    const rows = [{ username: TO.account.username, me: true, photo: TO.account.photo, w: me.w, l: me.l, net: me.net, tier: tier().id, streak: W().streakDays,
      share: { record: true, minutes: true, challenges: true } }];
    for (const f of TO.data.friends) {
      const p = person(f);
      if (p) rows.push({ username: p.username, me: false, photo: p.photo, w: p.w, l: p.l, net: p.net, tier: p.tier, streak: p.streak, share: p.share, name: p.name });
    }
    return rows.sort((a, b) => (!a.share.minutes - !b.share.minutes) || b.net - a.net);
  }

  // ---------- Demo account ----------
  function seedDemoData(now) {
    const d = freshData(now);
    const day = TO.dayKey(now);
    d.onboarded = true;
    d.settings.lockedApps = ['instagram', 'tiktok', 'youtube', 'cat-social'];
    d.friends = ['mike_t', 'jess.plays', 'coach_dan', 'lily_k', 'tbone22'];
    d.requestsIn = [{ id: TO.uid('fr'), from: 'priya_p', at: now - 20 * MIN }];
    // Still waiting on these two: one can be resent, the other was sent too recently.
    d.requestsOut = [{ id: TO.uid('fr'), to: 'sam_the_fan', at: now - 3 * HOUR }, { id: TO.uid('fr'), to: 'ava.r', at: now - 25 * MIN }];
    d.teams = [{ id: 'team_sunday', name: 'Sunday Squad', start: TO.addDays(day, -3), end: TO.addDays(day, 4), members: ['demo', 'mike_t', 'jess.plays', 'lily_k'], owner: 'mike_t', createdAt: now - 3 * DAY }];

    // pledges history from real (simulated) past games, graded with the same rules as live pledges.
    const rand = TO.rng('demo-history');
    const leagues = S.REAL_LEAGUES;
    const w = d.wallet;
    for (let back = 6; back >= 1; back--) {
      const dk = TO.addDays(day, -back);
      w.usageByDay[dk] = 25 + Math.floor(rand() * 25);
      for (let k = 0; k < 2 + (back % 2); k++) {
        const picksN = rand() < 0.25 ? 2 : 1;
        const picks = [];
        const placedAt = TO.dayStart(dk) + (12 + k * 3) * TO.HOUR + Math.floor(rand() * 40) * MIN;
        for (let j = 0; j < picksN; j++) {
          const league = leagues[Math.floor(rand() * leagues.length)];
          const L = S.LEAGUES[league];
          const slot = Math.floor((placedAt - L.offset) / S.SLOT) + 1;
          const id = `${league}-${slot}-${j % L.perSlot}`;
          const g0 = S.game(id, now);
          if (!g0 || g0.state === 'postponed' || picks.some((l) => l.gameId === id)) continue;
          const o = S.pointValue(id, g0.start - 60000);
          const pool = o.all.filter((s) => s.side !== 'draw');
          const sel = pool[Math.floor(rand() * pool.length)];
          const pick = pickFromSelection(sel, g0.start - 60000);
          pick.result = S.grade(pick, now);
          const g = S.game(id, now);
          pick.final = `${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore}`;
          picks.push(pick);
        }
        if (!picks.length) continue;
        const pledgeMinutes = 5 + Math.floor(rand() * 3) * 5;
        const { decimal, american } = combine(picks);
        const challenge = { id: TO.uid('pledge'), kind: 'sports', placedAt, dayKey: dk, pledgeMinutes, picks, decimal, american,
          boosted: false, insured: false, multiplier: 1, status: 'open', reward: 0, resolvedAt: null };
        const res = outcome(challenge);
        challenge.status = res.status; challenge.reward = res.reward; challenge.resolvedAt = Math.max(...picks.map((l) => (S.game(l.gameId, now) || {}).end || placedAt));
        w.netByDay[dk] = (w.netByDay[dk] || 0) + (challenge.reward - challenge.pledgeMinutes);
        d.challenges.push(challenge);
      }
    }
    w.streakDays = 4;
    w.usageByDay[day] = 22;

    // Open pledges on today's board.
    TO.data = d; // temporarily so wallet helpers work
    grantTierBonus();
    const board = S.board(now).filter((g) => !g.simulated);
    const live = board.filter((g) => g.state === 'live' && g.progress < 0.7);
    const upcoming = board.filter((g) => g.state === 'scheduled' && g.start - now > 4 * MIN);
    const mk = (g, pickFn) => { const o = S.pointValue(g.id, now); return pickFn(o); };
    if (live[0]) {
      const sel = mk(live[0], (o) => o.winner.find((s) => s.side === 'home'));
      pushOpen(d, [pickFromSelection(sel, now)], 10, now - 3 * MIN);
    }
    if (upcoming.length >= 2) {
      const a = mk(upcoming[0], (o) => o.total[0]);
      const b = mk(upcoming[1], (o) => (o.margin[1] || o.winner[1]));
      pushOpen(d, [pickFromSelection(a, now), pickFromSelection(b, now)], 5, now - MIN);
    } else if (live[1]) {
      const sel = mk(live[1], (o) => o.total[1]);
      pushOpen(d, [pickFromSelection(sel, now)], 5, now - MIN);
    }
    return d;
  }

  function pushOpen(d, picks, pledgeMinutes, placedAt) {
    const { decimal, american } = combine(picks);
    d.challenges.push({ id: TO.uid('pledge'), kind: 'sports', placedAt, dayKey: d.wallet.dayKey, pledgeMinutes, picks, decimal, american,
      boosted: false, insured: false, multiplier: streakMultiplier(d.wallet.streakDays), status: 'open', reward: 0, resolvedAt: null });
    d.wallet.balance -= pledgeMinutes;
  }

  const DEMO = { username: 'demo', email: 'demo@timeout.app', password: 'timeout123' };

  function ensureDemoAccount() {
    let acc = findAccountByUsername(DEMO.username);
    if (acc) return acc;
    const saved = TO.data, savedAcc = TO.account;
    const data = seedDemoData(TO.now());
    TO.data = saved; TO.account = savedAcc;
    acc = createAccount({ username: DEMO.username, email: DEMO.email, password: DEMO.password, photo: TO.initialsAvatar('Demo User', '#1AA560') }, { demo: true, data });
    return acc;
  }

  function loginDemo() {
    const acc = ensureDemoAccount();
    startSession(acc.id);
    return acc;
  }

  function resetMyData() {
    const now = TO.now();
    if (TO.account.demo) {
      const data = seedDemoData(now);
      TO.data = data;
    } else {
      const d = freshData(now);
      d.onboarded = true;
      d.settings = TO.data.settings;
      TO.data = d;
      grantTierBonus();
    }
    save();
  }

  TO.state = {
    RULES, TIERS, LOCKABLE, PEOPLE, DEMO, TODO_VALUE,
    tierById, tierForPoints, tierPerks, streakMultiplier, nextStreakMilestone, fmtMult,
    accounts, findAccount, createAccount, login, logout, loadSession, startSession, updateAccount, deleteAccount, adoptServerUser,
    validateUsername, validateEmail, validatePassword,
    save, wallet, rollover, grantTierBonus, addUsage, checkPhoneTime, useEmergencyUnlock, setSetting, limitFor, baseLimitFor, lockPoints, tier,
    submitPledge, placeTodoCombo, completeTodo, resolve, outcome, combine, pickFromSelection,
    myStats, statsFor, person, sharedPicks, searchPeople, relation,
    sendFriendRequest, addFriend, acceptFriendRequest, declineFriendRequest, cancelFriendRequest, resendFriendRequest, resendWait, removeFriend,
    socialTick, usesServerSocial, applySocial,
    teamStatus, teamStandings, createTeam, leaveTeam, inviteToTeam, joinTeam, refreshTeams, ensureTeamKey, sameUser, leaderboard,
    ensureDemoAccount, loginDemo, resetMyData, seedDemoData,
  };
})(window.TO);
