/* TimeOut web demo — accounts, screen-time wallet, bets, settlement, tiers/streaks and friends.
 * All data lives in this browser's localStorage. Passwords are hashed only to keep them out of plain sight;
 * this is a mockup, not real security.
 */
(function (TO) {
  'use strict';
  const S = TO.sim;
  const MIN = TO.MIN, DAY = TO.DAY;

  const RULES = {
    daily: 60,
    maxLegs: 3,
    friendLimit: 100,
    overrideMinutes: 15,
    overridePenalty: 30,
    maxOverrides: 2,
    todoMaxStake: 20,
    boostPercent: 0.1,
  };
  TO.RULES = RULES;

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
    if (t.bonus) list.push(`+${t.bonus} betting min a day`);
    if (t.boosts) list.push(`${t.boosts} odds boost${t.boosts === 1 ? '' : 's'} a day (+10% winnings)`);
    if (t.insurance) list.push('Parlay insurance once a week');
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
    { username: 'mike_t', name: 'Mike Torres', color: '#2F6FDE', w: 34, l: 27, net: 48, tier: 'allstar', streak: 5, share: { record: true, minutes: true, bets: true } },
    { username: 'jess.plays', name: 'Jess Park', color: '#D0467A', w: 41, l: 30, net: 73, tier: 'mvp', streak: 9, share: { record: true, minutes: false, bets: true } },
    { username: 'coach_dan', name: 'Dan Reeves', color: '#E08A1E', w: 22, l: 29, net: -36, tier: 'starter', streak: 0, share: { record: true, minutes: true, bets: true } },
    { username: 'lily_k', name: 'Lily Kim', color: '#7B5CE0', w: 18, l: 12, net: 25, tier: 'allstar', streak: 3, share: { record: true, minutes: true, bets: false } },
    { username: 'tbone22', name: 'Tyler Bonner', color: '#1E9E7A', w: 51, l: 55, net: -12, tier: 'rookie', streak: 1, share: { record: false, minutes: false, bets: false } },
    { username: 'priya_p', name: 'Priya Patel', color: '#C2410C', w: 12, l: 9, net: 19, tier: 'starter', streak: 2, share: { record: true, minutes: true, bets: true } },
    { username: 'sam_the_fan', name: 'Sam Ortiz', color: '#0E7490', w: 60, l: 58, net: 4, tier: 'mvp', streak: 6, share: { record: true, minutes: true, bets: false } },
    { username: 'ava.r', name: 'Ava Russo', color: '#BE185D', w: 9, l: 4, net: 22, tier: 'allstar', streak: 4, share: { record: true, minutes: true, bets: true } },
    { username: 'big_ben', name: 'Ben Hall', color: '#4D7C0F', w: 27, l: 33, net: -41, tier: 'rookie', streak: 0, share: { record: true, minutes: false, bets: false } },
    { username: 'nate_w', name: 'Nate Walker', color: '#6D28D9', w: 15, l: 15, net: 0, tier: 'starter', streak: 1, share: { record: true, minutes: true, bets: true } },
    { username: 'coop_24', name: 'Cooper James', color: '#B45309', w: 38, l: 22, net: 91, tier: 'hof', streak: 12, share: { record: true, minutes: true, bets: true } },
    { username: 'maria.g', name: 'Maria Garcia', color: '#DB2777', w: 20, l: 21, net: -3, tier: 'starter', streak: 2, share: { record: true, minutes: true, bets: false } },
  ];
  PEOPLE.forEach((p) => { p.photo = TO.initialsAvatar(p.name, p.color); p.fake = true; });

  const TERMS_EXAMPLES = ['Loser does the dishes', 'Loser buys lunch', 'Winner picks the movie', 'Loser folds the laundry', 'Loser posts a shoutout'];

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
  function adoptServerUser(user) {
    const id = `srv_${user.id}`;
    const all = accounts();
    const acc = all[id] || { id, salt: null, pw: null };
    Object.assign(acc, {
      username: user.username, email: user.email, demo: !!user.isDemo, createdAt: Date.parse(user.createdAt), server: user,
      photo: user.photoUrl || acc.photo || TO.initialsAvatar(user.isDemo ? 'Demo User' : user.username, user.isDemo ? '#1AA560' : undefined),
    });
    all[id] = acc; saveAccounts(all);
    if (!TO.store.get(dataKey(id), null)) TO.store.set(dataKey(id), user.isDemo ? seedDemoData(TO.now()) : freshData(TO.now()));
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
      bets: [],
      lastStake: 5,
      settings: {
        sports: S.REAL_LEAGUES.slice(),
        showPredictions: true,
        showTodos: true,
        enforce: true,
        lockedApps: [],
        minLimit: 0,
        lowWarn: 10,
        notify: { settled: true, odds: true, friends: true, challenges: true, lowTime: true },
        privacy: { record: true, minutes: true, bets: true },
      },
      onboarded: false,
      friends: [],
      requestsIn: [],
      requestsOut: [],
      challengesIn: [],
      teams: [],
    };
  }

  function migrate(d) {
    const f = freshData(TO.now());
    for (const k of Object.keys(f)) if (d[k] === undefined) d[k] = f[k];
    for (const k of Object.keys(f.wallet)) if (d.wallet[k] === undefined) d.wallet[k] = f.wallet[k];
    for (const k of Object.keys(f.settings)) if (d.settings[k] === undefined) d.settings[k] = f.settings[k];
    return d;
  }

  function save() {
    if (TO.account && TO.data) TO.store.set(dataKey(TO.account.id), TO.data);
  }

  // ---------- Wallet ----------
  const W = () => TO.data.wallet;
  const today = () => W().dayKey;

  function lockPoints(d = TO.data) {
    if (!d.settings.enforce) return 0;
    return d.settings.lockedApps.reduce((sum, id) => sum + ((LOCKABLE.find((x) => x.id === id) || {}).pts || 0), 0);
  }
  const tier = (d = TO.data) => tierForPoints(lockPoints(d));

  /** Phone screen time allowed on a day: 60 + the day before's bet results − emergency penalties (never below the user's floor). */
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
    const used = w.usageByDay[day] || 0;
    const todayLimit = limitFor(day);
    const open = TO.data.bets.filter((b) => b.status === 'open');
    const t = tier();
    return {
      day, balance: w.balance, lockedOut: w.lockedOut,
      todayLimit, tomorrowLimit: baseLimitFor(tomorrow),
      yesterdayNet: w.netByDay[TO.addDays(day, -1)] || 0,
      todayNet: w.netByDay[day] || 0,
      penaltyToday: w.penaltyByDay[day] || 0,
      penaltyTomorrow: w.penaltyByDay[tomorrow] || 0,
      emergencyToday: emergencyMinutes(day),
      overridesUsed: w.overridesByDay[day] || 0,
      used, phoneLeft: Math.max(todayLimit - used, 0),
      appsLocked: TO.data.settings.enforce && used >= todayLimit,
      atRisk: open.filter((b) => !b.friend).reduce((s, b) => s + b.stake, 0),
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
    if (owed > 0 && !w.lockedOut) {
      w.balance += owed;
      w.bonusGranted = tier().bonus;
    }
  }

  /** Starts a new day at local midnight: closes out the old day, updates the streak, resets the betting balance. */
  function rollover(now) {
    const w = W();
    const target = TO.dayKey(now);
    if (w.dayKey === target) return false;
    if (w.dayKey > target) { w.dayKey = target; return false; } // clock moved back (tester reset)
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
    o[parts[0]] = value;
    if (path === 'lockedApps' || path === 'enforce') grantTierBonus();
    save();
  }

  // ---------- Bets ----------
  function legFromSelection(sel, now) {
    if (sel.kind === 'pred' || sel.market === 'pred') {
      const p = S.prediction(sel.predId, now);
      return { selId: sel.id, kind: 'pred', predId: sel.predId, market: 'pred', side: sel.side, line: null, price: sel.price,
        label: S.selectionLabel(sel), marketLabel: 'Prediction', matchup: p.q, league: 'pred', start: p.resolves, result: 'pending', final: null };
    }
    const g = S.game(sel.gameId, now);
    return { selId: sel.id, kind: 'game', gameId: sel.gameId, market: sel.market, side: sel.side, line: sel.line, price: sel.price,
      label: S.selectionLabel(sel, g), marketLabel: S.marketLabel(sel, g), matchup: `${g.away.name} @ ${g.home.name}`,
      short: `${g.away.abbr} @ ${g.home.abbr}`, league: g.league, start: g.start, result: 'pending', final: null };
  }

  const combine = (legs) => {
    const dec = legs.reduce((p, l) => p * TO.odds.decimal(l.price), 1);
    return { decimal: dec, american: TO.odds.fromDecimal(dec) };
  };

  /** Places a bet from bet-slip picks. Each pick carries the price the user accepted. */
  function placeBet({ picks, stake, friend, boost, insure }, now = TO.now()) {
    rollover(now);
    const w = W();
    if (!picks.length) throw new AppError('empty', 'Add a pick to your bet slip.');
    if (picks.length > RULES.maxLegs) throw new AppError('too_many', `Parlays can have up to ${RULES.maxLegs} picks.`);
    // Every pick must still be open and at the price the user saw.
    const changed = [];
    const legs = picks.map((p) => {
      const cur = S.currentSelection(p.selId, now);
      if (!cur || !cur.sel || !cur.open) throw new AppError('closed', 'One of your picks is no longer available. Remove it to continue.');
      if (cur.sel.price !== p.price || cur.sel.line !== p.line) changed.push(p.selId);
      return legFromSelection(cur.sel, now);
    });
    if (changed.length) throw new AppError('odds_changed', 'The odds changed. Review the new odds and confirm again.', { changed });

    const isFriend = !!friend;
    if (isFriend) {
      const terms = String(friend.terms || '').trim();
      if (!friend.with || !friend.with.length) throw new AppError('no_friend', 'Choose a friend to send this bet to.');
      if (!terms) throw new AppError('no_terms', 'Add what\'s on the line, like "loser does the dishes".');
      if (terms.length > RULES.friendLimit) throw new AppError('terms_long', `Keep it to ${RULES.friendLimit} characters.`);
    } else {
      if (w.lockedOut || w.balance <= 0) throw new AppError('locked', 'You\'re out of betting minutes for today. Betting reopens at midnight.');
      if (!Number.isInteger(stake) || stake < 1) throw new AppError('stake', 'Enter a stake of at least 1 minute.');
      if (stake > w.balance) throw new AppError('not_enough', `Not enough screentime. You have ${w.balance} min left to bet today.`, { remaining: w.balance });
    }

    const wl = wallet();
    const { decimal, american } = combine(legs);
    const bet = {
      id: TO.uid('bet'), kind: 'sports', placedAt: now, dayKey: w.dayKey,
      stake: isFriend ? 0 : stake, legs, decimal, american,
      friend: isFriend ? { with: friend.with.slice(), terms: String(friend.terms).trim(), status: 'pending', acceptAt: now + 5000, direction: 'out' } : null,
      boosted: false, insured: false, multiplier: 1, status: 'open', payout: 0, settledAt: null,
    };
    if (!isFriend) {
      let mult = wl.multiplier;
      if (boost && wl.boostsLeft > 0) {
        bet.boosted = true;
        mult *= 1 + RULES.boostPercent;
        w.boostsByDay[w.dayKey] = (w.boostsByDay[w.dayKey] || 0) + 1;
      }
      if (insure && legs.length > 1 && wl.insuranceLeft > 0) {
        bet.insured = true;
        const wk = TO.weekKey(now);
        w.insuranceByWeek[wk] = (w.insuranceByWeek[wk] || 0) + 1;
      }
      bet.multiplier = +mult.toFixed(4);
      w.balance -= stake;
      TO.data.lastStake = stake;
      if (w.balance <= 0) { w.balance = 0; w.lockedOut = true; }
    } else {
      deliverChallenges(bet);
    }
    TO.data.bets.push(bet);
    save();
    return bet;
  }

  /** To-do parlay (Could-have): stake minutes on finishing up to 3 tasks before midnight. */
  const TODO_ODDS = { easy: 50, medium: 100, hard: 200 };
  function placeTodoParlay({ tasks, stake }, now = TO.now()) {
    rollover(now);
    const w = W();
    const clean = tasks.map((t) => ({ text: String(t.text || '').trim(), difficulty: t.difficulty })).filter((t) => t.text);
    if (!clean.length) throw new AppError('empty', 'Add at least one task.');
    if (clean.length > RULES.maxLegs) throw new AppError('too_many', `To-do parlays can have up to ${RULES.maxLegs} tasks.`);
    if (w.lockedOut || w.balance <= 0) throw new AppError('locked', 'You\'re out of betting minutes for today. Betting reopens at midnight.');
    if (!Number.isInteger(stake) || stake < 1) throw new AppError('stake', 'Enter a stake of at least 1 minute.');
    if (stake > RULES.todoMaxStake) throw new AppError('stake', `To-do parlays are capped at ${RULES.todoMaxStake} minutes.`);
    if (stake > w.balance) throw new AppError('not_enough', `Not enough screentime. You have ${w.balance} min left to bet today.`, { remaining: w.balance });
    const legs = clean.map((t, i) => ({ selId: `todo-${i}`, kind: 'todo', market: 'todo', text: t.text, difficulty: t.difficulty, price: TODO_ODDS[t.difficulty] || 100,
      label: t.text, marketLabel: `To-do · ${t.difficulty}`, matchup: 'Finish before midnight', result: 'pending', final: null }));
    const { decimal, american } = combine(legs);
    const bet = { id: TO.uid('bet'), kind: 'todo', placedAt: now, dayKey: w.dayKey, deadline: TO.nextMidnight(now), stake, legs, decimal, american,
      friend: null, boosted: false, insured: false, multiplier: wallet().multiplier, status: 'open', payout: 0, settledAt: null };
    w.balance -= stake;
    if (w.balance <= 0) { w.balance = 0; w.lockedOut = true; }
    TO.data.bets.push(bet);
    save();
    return bet;
  }

  function completeTodo(betId, legIndex) {
    const bet = TO.data.bets.find((b) => b.id === betId);
    if (!bet || bet.status !== 'open') return null;
    const leg = bet.legs[legIndex];
    leg.result = 'won'; leg.final = `Done ${TO.fmtTime(TO.now())}`;
    const settled = finishIfDone(bet);
    save();
    return settled;
  }

  function closeTodos(day, now) {
    for (const bet of TO.data.bets) {
      if (bet.kind !== 'todo' || bet.status !== 'open' || bet.dayKey !== day) continue;
      bet.legs.forEach((l) => { if (l.result === 'pending') { l.result = 'lost'; l.final = 'Not done by midnight'; } });
      finishIfDone(bet, now);
    }
  }

  function outcome(bet) {
    const legs = bet.legs;
    const lost = legs.filter((l) => l.result === 'lost').length;
    const pending = legs.some((l) => l.result === 'pending');
    if (lost) {
      if (bet.insured) {
        if (pending) return { status: 'open' };
        if (lost === 1) return { status: 'push', payout: bet.stake, insurancePaid: true };
      }
      return { status: 'lost', payout: 0 };
    }
    if (pending) return { status: 'open' };
    const won = legs.filter((l) => l.result === 'won');
    if (!won.length) return { status: legs.every((l) => l.result === 'void') ? 'void' : 'push', payout: bet.stake };
    const dec = won.reduce((p, l) => p * TO.odds.decimal(l.price), 1);
    let payout = Math.round(bet.stake * dec);
    payout = bet.stake + Math.round((payout - bet.stake) * (bet.multiplier || 1));
    return { status: 'won', payout };
  }

  function finishIfDone(bet, now = TO.now()) {
    const res = outcome(bet);
    if (res.status === 'open') return null;
    bet.status = res.status;
    bet.payout = bet.friend ? 0 : res.payout;
    bet.insurancePaid = !!res.insurancePaid;
    bet.settledAt = now;
    if (!bet.friend) {
      const w = W();
      w.netByDay[bet.dayKey] = (w.netByDay[bet.dayKey] || 0) + (bet.payout - bet.stake);
      // Winnings and refunds return to today's betting balance if the bet was placed today.
      if (bet.dayKey === w.dayKey) w.balance += bet.payout;
    }
    return bet;
  }

  /** Grades every open bet against the latest scores. Runs on every tick, so bets settle seconds after a game ends. */
  function settle(now = TO.now()) {
    const settled = [];
    for (const bet of TO.data.bets) {
      if (bet.status !== 'open' || bet.kind === 'todo') continue;
      let changed = false;
      for (const leg of bet.legs) {
        if (leg.result !== 'pending') continue;
        const r = S.grade(leg, now);
        if (r === 'pending') continue;
        leg.result = r;
        changed = true;
        if (leg.kind === 'pred') {
          const p = S.prediction(leg.predId, now);
          leg.final = `Resolved ${p.outcome === 'yes' ? 'YES' : 'NO'}`;
        } else {
          const g = S.game(leg.gameId, now);
          leg.final = g.state === 'postponed' ? 'Postponed' : `${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore}${g.ot ? ` (${g.ot.label === '10' ? '10 inn' : 'OT'})` : ''}`;
        }
      }
      if (changed && finishIfDone(bet, now)) settled.push(bet);
    }
    if (settled.length) save();
    return settled;
  }

  // ---------- Record / stats ----------
  function statsFor(bets) {
    const settled = bets.filter((b) => b.status !== 'open');
    const money = settled.filter((b) => !b.friend);
    const won = money.filter((b) => b.status === 'won');
    const lost = money.filter((b) => b.status === 'lost');
    const voids = money.filter((b) => b.status === 'void' || b.status === 'push');
    const net = money.reduce((s, b) => s + (b.payout - b.stake), 0);
    const friendBets = settled.filter((b) => b.friend);
    const bySport = {};
    for (const b of money) {
      const key = b.kind === 'todo' ? 'todo' : b.legs.length > 1 ? 'parlay' : b.legs[0].league;
      bySport[key] = bySport[key] || { w: 0, l: 0, net: 0 };
      if (b.status === 'won') bySport[key].w++;
      if (b.status === 'lost') bySport[key].l++;
      bySport[key].net += b.payout - b.stake;
    }
    return {
      w: won.length, l: lost.length, v: voids.length, net,
      pct: won.length + lost.length ? Math.round((100 * won.length) / (won.length + lost.length)) : null,
      best: won.reduce((m, b) => Math.max(m, b.payout - b.stake), 0),
      fw: friendBets.filter((b) => b.status === 'won').length,
      fl: friendBets.filter((b) => b.status === 'lost').length,
      bySport,
      recent: settled.filter((b) => !b.friend && (b.status === 'won' || b.status === 'lost')).sort((a, b) => b.settledAt - a.settledAt).slice(0, 5).map((b) => (b.status === 'won' ? 'W' : 'L')),
    };
  }
  const myStats = () => statsFor(TO.data.bets);

  // ---------- People & friends ----------
  function person(username) {
    const fake = PEOPLE.find((p) => p.username.toLowerCase() === String(username).toLowerCase());
    if (fake) return fake;
    const acc = findAccountByUsername(username);
    if (!acc) return null;
    const d = acc.id === (TO.account && TO.account.id) ? TO.data : migrate(TO.store.get(dataKey(acc.id), null) || freshData(TO.now()));
    const st = statsFor(d.bets);
    return { username: acc.username, name: acc.username, photo: acc.photo, w: st.w, l: st.l, net: st.net, tier: tier(d).id, streak: d.wallet.streakDays,
      share: d.settings.privacy, local: true, accountId: acc.id, openBets: d.bets.filter((b) => b.status === 'open' && !b.friend) };
  }

  /** Open picks a friend has shared (fake friends pick from the live board). */
  function sharedPicks(p, now = TO.now()) {
    if (!p || !p.share.bets) return [];
    if (p.local) return (p.openBets || []).slice(0, 3).map((b) => ({ label: b.legs.map((l) => l.label).join(' + '), matchup: b.legs.length > 1 ? `${b.legs.length}-pick parlay` : b.legs[0].matchup, price: b.american, stake: b.stake }));
    const games = S.board(now).filter((g) => (g.state === 'live' || g.state === 'scheduled') && !g.simulated);
    const rand = TO.rng(`${p.username}-${Math.floor(now / S.SLOT)}`);
    const picks = [];
    const count = 1 + Math.floor(rand() * 2);
    for (let i = 0; i < count && games.length; i++) {
      const g = games[Math.floor(rand() * games.length)];
      const o = S.odds(g.id, now);
      const sel = o.all[Math.floor(rand() * o.all.length)];
      picks.push({ label: S.selectionLabel(sel, g), matchup: `${g.away.name} @ ${g.home.name}`, price: sel.price, stake: 5 + Math.floor(rand() * 4) * 5, gameId: g.id });
    }
    return picks;
  }

  function searchPeople(query) {
    const q = String(query || '').trim().toLowerCase().replace(/^@/, '');
    if (!q) return [];
    const me = TO.account.username.toLowerCase();
    const locals = Object.values(accounts()).filter((a) => a.username.toLowerCase() !== me).map((a) => ({ username: a.username, name: a.username, photo: a.photo, local: true }));
    return [...PEOPLE, ...locals].filter((p) => p.username.toLowerCase().includes(q) || (p.name || '').toLowerCase().includes(q)).slice(0, 8);
  }

  const relation = (username) => {
    const d = TO.data;
    if (d.friends.includes(username)) return 'friend';
    if (d.requestsOut.some((r) => r.to === username)) return 'requested';
    if (d.requestsIn.some((r) => r.from === username)) return 'incoming';
    return 'none';
  };

  function sendFriendRequest(username, now = TO.now()) {
    const rel = relation(username);
    if (rel === 'friend' || rel === 'requested') return;
    if (rel === 'incoming') { acceptFriendRequest(TO.data.requestsIn.find((r) => r.from === username).id); return; }
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

  // ---------- Challenges (friend bets) ----------
  /** When I send a friend bet to a real local account, it shows up in their Requests with the other side. */
  function deliverChallenges(bet) {
    for (const u of bet.friend.with) {
      const acc = findAccountByUsername(u);
      if (!acc) continue;
      bet.friend.acceptAt = null; // real people accept themselves
      const leg = bet.legs[0];
      mutateData(acc.id, (d) => {
        d.challengesIn.push({ id: TO.uid('ch'), from: TO.account.username, betId: bet.id, fromAccount: TO.account.id, theirPick: bet.legs.map((l) => l.label).join(' + '),
          matchup: bet.legs.length > 1 ? `${bet.legs.length}-pick parlay` : leg.matchup, legs: bet.legs.map((l) => ({ selId: l.selId, price: l.price, line: l.line, market: l.market, side: l.side, gameId: l.gameId, predId: l.predId, kind: l.kind })),
          terms: bet.friend.terms, at: bet.placedAt, status: 'pending' });
      });
    }
  }

  function incomingChallenge(from, now = TO.now()) {
    const games = S.board(now).filter((g) => g.state === 'scheduled' && !g.simulated && g.start - now > 3 * MIN);
    const g = games[Math.floor(Math.random() * games.length)] || S.board(now).find((x) => x.state === 'scheduled');
    if (!g) return null;
    const o = S.odds(g.id, now);
    const theirs = Math.random() < 0.5 ? o.moneyline.find((s) => s.side === 'home') : o.spread[0] || o.moneyline[0];
    const terms = TERMS_EXAMPLES[Math.floor(Math.random() * TERMS_EXAMPLES.length)];
    const ch = { id: TO.uid('ch'), from, theirPick: S.selectionLabel(theirs, g), matchup: `${g.away.name} @ ${g.home.name}`,
      legs: [{ selId: theirs.id, price: theirs.price, line: theirs.line, market: theirs.market, side: theirs.side, gameId: g.id, kind: 'game' }], terms, at: now, status: 'pending' };
    TO.data.challengesIn.push(ch);
    save();
    return ch;
  }

  /** Accepting takes the other side of every pick in the challenge. */
  function acceptChallenge(id, now = TO.now()) {
    const d = TO.data;
    const ch = d.challengesIn.find((c) => c.id === id);
    if (!ch) return null;
    const legs = [];
    for (const l of ch.legs) {
      const opp = S.oppositeSelection({ id: l.selId, market: l.market, side: l.side, line: l.line, gameId: l.gameId, predId: l.predId, kind: l.kind });
      const cur = S.currentSelection(opp.id, now);
      if (!cur || !cur.sel || !cur.open) {
        ch.status = 'expired';
        save();
        throw new AppError('closed', 'This game has already started or ended, so the challenge expired.');
      }
      // Keep the friend's line so both sides are betting on the same number.
      legs.push(legFromSelection(Object.assign({}, cur.sel, { line: opp.line }), now));
    }
    const { decimal, american } = combine(legs);
    const bet = { id: TO.uid('bet'), kind: 'sports', placedAt: now, dayKey: W().dayKey, stake: 0, legs, decimal, american,
      friend: { with: [ch.from], terms: ch.terms, status: 'accepted', direction: 'in' }, boosted: false, insured: false, multiplier: 1, status: 'open', payout: 0, settledAt: null };
    d.bets.push(bet);
    d.challengesIn = d.challengesIn.filter((c) => c.id !== id);
    if (ch.fromAccount) {
      mutateData(ch.fromAccount, (o) => {
        const b = o.bets.find((x) => x.id === ch.betId);
        if (b && b.friend) b.friend.status = 'accepted';
      });
    }
    save();
    return bet;
  }

  function declineChallenge(id) {
    const ch = TO.data.challengesIn.find((c) => c.id === id);
    TO.data.challengesIn = TO.data.challengesIn.filter((c) => c.id !== id);
    if (ch && ch.fromAccount) {
      mutateData(ch.fromAccount, (o) => {
        const b = o.bets.find((x) => x.id === ch.betId);
        if (b && b.friend) b.friend.status = 'declined';
      });
    }
    save();
  }

  /** Resends an existing pick to friends with a custom stake instead of minutes. */
  function sendBetToFriends(betId, friends, terms, now = TO.now()) {
    const src = TO.data.bets.find((b) => b.id === betId);
    if (!src) return null;
    terms = String(terms || '').trim();
    if (!friends.length) throw new AppError('no_friend', 'Choose at least one friend.');
    if (!terms) throw new AppError('no_terms', 'Add what\'s on the line, like "loser does the dishes".');
    if (terms.length > RULES.friendLimit) throw new AppError('terms_long', `Keep it to ${RULES.friendLimit} characters.`);
    if (src.status !== 'open') throw new AppError('closed', 'This bet is already settled. Send an open bet instead.');
    const bet = JSON.parse(JSON.stringify(src));
    Object.assign(bet, { id: TO.uid('bet'), placedAt: now, stake: 0, payout: 0, boosted: false, insured: false, multiplier: 1,
      friend: { with: friends.slice(), terms, status: 'pending', acceptAt: now + 5000, direction: 'out' } });
    deliverChallenges(bet);
    TO.data.bets.push(bet);
    save();
    return bet;
  }

  /** Background social events: fake friends accept requests and challenges after a few seconds. */
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
    for (const b of d.bets) {
      if (b.friend && b.friend.status === 'pending' && b.friend.acceptAt && now >= b.friend.acceptAt) {
        b.friend.status = 'accepted';
        events.push({ type: 'challenge', bet: b });
      }
    }
    // Expire challenges whose games already started.
    for (const c of d.challengesIn) {
      if (c.status !== 'pending') continue;
      const open = c.legs.every((l) => { const cur = S.currentSelection(l.selId, now); return cur && cur.open; });
      if (!open) c.status = 'expired';
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
      const p = u === TO.account.username ? null : person(u);
      let net = 0, w = 0, l = 0, hidden = false;
      if (!p || p.local) {
        const bets = p ? migrate(TO.store.get(dataKey(p.accountId), null) || freshData(now)).bets : TO.data.bets;
        for (const b of bets) {
          if (b.friend || b.status === 'open' || b.placedAt < start || b.placedAt >= end) continue;
          net += b.payout - b.stake;
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
      return { username: u, me: !p, net, w, l, hidden, photo: p ? p.photo : TO.account.photo, tier: p ? p.tier : tier().id };
    }).sort((a, b) => (a.hidden - b.hidden) || b.net - a.net);
  }

  function createTeam({ name, start, end, members }) {
    name = String(name || '').trim();
    const errors = {};
    if (!name) errors.name = 'Give your team a name.';
    if (!start) errors.start = 'Pick a start date.';
    if (!end) errors.end = 'Pick an end date.';
    if (start && end && end < start) errors.end = 'End date must be on or after the start date.';
    if (!members.length) errors.members = 'Invite at least one friend.';
    if (Object.keys(errors).length) throw new AppError('invalid', 'Fix the highlighted fields.', { fields: errors });
    const team = { id: TO.uid('team'), name, start, end, members: [TO.account.username, ...members], owner: TO.account.username, createdAt: TO.now() };
    TO.data.teams.push(team);
    for (const u of members) {
      const acc = findAccountByUsername(u);
      if (acc) mutateData(acc.id, (d) => d.teams.push(JSON.parse(JSON.stringify(team))));
    }
    save();
    return team;
  }

  function leaveTeam(id) {
    TO.data.teams = TO.data.teams.filter((t) => t.id !== id);
    save();
  }

  function inviteToTeam(id, members) {
    const t = TO.data.teams.find((x) => x.id === id);
    if (!t) return;
    for (const u of members) if (!t.members.includes(u)) t.members.push(u);
    save();
  }

  // ---------- Leaderboard ----------
  function leaderboard() {
    const me = myStats();
    const rows = [{ username: TO.account.username, me: true, photo: TO.account.photo, w: me.w, l: me.l, net: me.net, tier: tier().id, streak: W().streakDays,
      share: { record: true, minutes: true, bets: true } }];
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
    d.teams = [{ id: 'team_sunday', name: 'Sunday Squad', start: TO.addDays(day, -3), end: TO.addDays(day, 4), members: ['demo', 'mike_t', 'jess.plays', 'lily_k'], owner: 'mike_t', createdAt: now - 3 * DAY }];

    // Bet history from real (simulated) past games, graded with the same rules as live bets.
    const rand = TO.rng('demo-history');
    const leagues = S.REAL_LEAGUES;
    const w = d.wallet;
    for (let back = 6; back >= 1; back--) {
      const dk = TO.addDays(day, -back);
      w.usageByDay[dk] = 25 + Math.floor(rand() * 25);
      for (let k = 0; k < 2 + (back % 2); k++) {
        const legsN = rand() < 0.25 ? 2 : 1;
        const legs = [];
        const placedAt = TO.dayStart(dk) + (12 + k * 3) * TO.HOUR + Math.floor(rand() * 40) * MIN;
        for (let j = 0; j < legsN; j++) {
          const league = leagues[Math.floor(rand() * leagues.length)];
          const L = S.LEAGUES[league];
          const slot = Math.floor((placedAt - L.offset) / S.SLOT) + 1;
          const id = `${league}-${slot}-${j % L.perSlot}`;
          const g0 = S.game(id, now);
          if (!g0 || g0.state === 'postponed' || legs.some((l) => l.gameId === id)) continue;
          const o = S.odds(id, g0.start - 60000);
          const pool = o.all.filter((s) => s.side !== 'draw');
          const sel = pool[Math.floor(rand() * pool.length)];
          const leg = legFromSelection(sel, g0.start - 60000);
          leg.result = S.grade(leg, now);
          const g = S.game(id, now);
          leg.final = `${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore}`;
          legs.push(leg);
        }
        if (!legs.length) continue;
        const stake = 5 + Math.floor(rand() * 3) * 5;
        const { decimal, american } = combine(legs);
        const bet = { id: TO.uid('bet'), kind: 'sports', placedAt, dayKey: dk, stake, legs, decimal, american, friend: null,
          boosted: false, insured: false, multiplier: 1, status: 'open', payout: 0, settledAt: null };
        const res = outcome(bet);
        bet.status = res.status; bet.payout = res.payout; bet.settledAt = Math.max(...legs.map((l) => (S.game(l.gameId, now) || {}).end || placedAt));
        w.netByDay[dk] = (w.netByDay[dk] || 0) + (bet.payout - bet.stake);
        d.bets.push(bet);
      }
    }
    // One settled friend bet so the history shows both kinds.
    const fb = d.bets.find((b) => b.legs.length === 1 && b.status === 'won') || d.bets[0];
    if (fb) {
      const copy = JSON.parse(JSON.stringify(fb));
      Object.assign(copy, { id: TO.uid('bet'), stake: 0, payout: 0, friend: { with: ['mike_t'], terms: 'Loser buys Cafe Rio', status: 'accepted', direction: 'out' } });
      d.bets.push(copy);
    }
    w.streakDays = 4;
    w.usageByDay[day] = 22;

    // Open bets on today's board.
    TO.data = d; // temporarily so wallet helpers work
    grantTierBonus();
    const board = S.board(now).filter((g) => !g.simulated);
    const live = board.filter((g) => g.state === 'live' && g.progress < 0.7);
    const upcoming = board.filter((g) => g.state === 'scheduled' && g.start - now > 4 * MIN);
    const mk = (g, pickFn) => { const o = S.odds(g.id, now); return pickFn(o); };
    if (live[0]) {
      const sel = mk(live[0], (o) => o.moneyline.find((s) => s.side === 'home'));
      pushOpen(d, [legFromSelection(sel, now)], 10, now - 3 * MIN);
    }
    if (upcoming.length >= 2) {
      const a = mk(upcoming[0], (o) => o.total[0]);
      const b = mk(upcoming[1], (o) => (o.spread[1] || o.moneyline[1]));
      pushOpen(d, [legFromSelection(a, now), legFromSelection(b, now)], 5, now - MIN);
    } else if (live[1]) {
      const sel = mk(live[1], (o) => o.total[1]);
      pushOpen(d, [legFromSelection(sel, now)], 5, now - MIN);
    }
    // A pending challenge from a friend.
    const chGame = upcoming[2] || upcoming[0];
    if (chGame) {
      const o = S.odds(chGame.id, now);
      const theirs = o.moneyline.find((s) => s.side === 'home');
      d.challengesIn.push({ id: TO.uid('ch'), from: 'mike_t', theirPick: S.selectionLabel(theirs, chGame), matchup: `${chGame.away.name} @ ${chGame.home.name}`,
        legs: [{ selId: theirs.id, price: theirs.price, line: null, market: 'ml', side: 'home', gameId: chGame.id, kind: 'game' }], terms: 'Loser does the dishes tonight', at: now - 10 * MIN, status: 'pending' });
    }
    return d;
  }

  function pushOpen(d, legs, stake, placedAt) {
    const { decimal, american } = combine(legs);
    d.bets.push({ id: TO.uid('bet'), kind: 'sports', placedAt, dayKey: d.wallet.dayKey, stake, legs, decimal, american, friend: null,
      boosted: false, insured: false, multiplier: streakMultiplier(d.wallet.streakDays), status: 'open', payout: 0, settledAt: null });
    d.wallet.balance -= stake;
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
    RULES, TIERS, LOCKABLE, PEOPLE, TERMS_EXAMPLES, DEMO, TODO_ODDS,
    tierById, tierForPoints, tierPerks, streakMultiplier, nextStreakMilestone, fmtMult,
    accounts, findAccount, createAccount, login, logout, loadSession, startSession, updateAccount, deleteAccount, adoptServerUser,
    validateUsername, validateEmail, validatePassword,
    save, wallet, rollover, grantTierBonus, addUsage, checkPhoneTime, useEmergencyUnlock, setSetting, limitFor, baseLimitFor, lockPoints, tier,
    placeBet, placeTodoParlay, completeTodo, settle, outcome, combine, legFromSelection,
    myStats, statsFor, person, sharedPicks, searchPeople, relation,
    sendFriendRequest, acceptFriendRequest, declineFriendRequest, cancelFriendRequest, removeFriend,
    incomingChallenge, acceptChallenge, declineChallenge, sendBetToFriends, socialTick,
    teamStatus, teamStandings, createTeam, leaveTeam, inviteToTeam, leaderboard,
    ensureDemoAccount, loginDemo, resetMyData, seedDemoData,
  };
})(window.TO);
