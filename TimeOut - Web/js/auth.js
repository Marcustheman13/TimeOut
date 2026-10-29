/* TimeOut web demo — welcome, log in, create account and onboarding. */
(function (TO) {
  'use strict';
  const { esc, icon, brandIcon } = TO;
  const S = TO.sim;
  const ui = TO.ui;
  const St = TO.state;

  const av = { screen: 'welcome', errors: {}, formError: '', values: {}, photo: null, step: 1, sports: null, locks: [] };

  function ticker() {
    const games = S.board(TO.now()).filter((g) => g.state === 'live' && !g.simulated).slice(0, 8);
    if (!games.length) return '';
    const items = games.map((g) => `<span class="tk"><span class="live"></span>${esc(g.away.abbr)} <b>${g.awayScore}</b> ${esc(g.home.abbr)} <b>${g.homeScore}</b> <span class="faint">${esc(g.clock)}</span></span>`).join('');
    return `<div class="ticker" aria-hidden="true"><div class="ticker-track">${items}${items}</div></div>`;
  }

  function welcome() {
    return `<div class="auth">
      <div class="welcome-hero">
        ${ticker()}
        <div style="margin-top:auto"></div>
        ${brandIcon(64)}
        <div class="wordmark">TIME<b>OUT</b></div>
        <div class="tagline">Build healthier screen-time habits with sports challenges.</div>
        <div class="welcome-points">
          <div>${icon('hourglass', 18)}<span>60 pledge minutes a day. Successful challenges add phone time tomorrow.</span></div>
          <div>${icon('radio', 18)}<span>Live scores and matchup targets for NFL, NBA, MLB, NHL, college football and soccer.</span></div>
          <div>${icon('users', 18)}<span>Compare screen-time records and compete on teams.</span></div>
        </div>
      </div>
      <div class="auth-inner" style="flex:none;gap:10px">
        <button class="btn primary full" data-act="auth-go" data-s="login">Log in</button>
        <button class="btn ghost full" data-act="auth-go" data-s="signup">Create account</button>
        ${TO.api.configured ? '' : `<button class="btn quiet full sm" data-act="auth-demo">${icon('flask', 16)} Try the demo account</button>`}
      </div>
    </div>`;
  }

  function back() {
    return `<button type="button" class="icon-btn" style="margin-left:-10px" data-act="auth-go" data-s="welcome" aria-label="Back">${icon('chevL', 22)}</button>`;
  }

  function login() {
    const v = av.values;
    return `<div class="auth"><form class="auth-inner" data-form="login" novalidate>
      ${back()}
      ${brandIcon(52)}
      <h1>Welcome back</h1>
      <p class="sub">Log in with your email and password.</p>
      ${av.formError ? `<div class="form-error">${esc(av.formError)}</div>` : ''}
      ${ui.field({ id: 'li-id', label: 'Email', type: 'email', value: v['li-id'] || '', err: av.errors.identifier || av.errors.email, attrs: 'autocomplete="email" autocapitalize="off" spellcheck="false"' })}
      ${ui.field({ id: 'li-pw', label: 'Password', type: 'password', value: '', err: av.errors.password, attrs: 'autocomplete="current-password"' })}
      <button type="submit" class="btn primary full">Log in</button>
      <button type="button" class="btn quiet sm" data-act="forgot">Forgot password?</button>
      <div class="divider"></div>
      ${TO.api.configured ? '' : `<button type="button" class="btn ghost full" data-act="auth-demo">${icon('flask', 16)} Log in with the demo account</button>`}
      <div class="small muted" style="text-align:center">New here? <button type="button" class="link-btn" data-act="auth-go" data-s="signup">Create an account</button></div>
    </form></div>`;
  }

  function signup() {
    const v = av.values;
    const photo = av.photo || TO.initialsAvatar(v['su-user'] || '?', '#1d2430');
    return `<div class="auth"><form class="auth-inner" data-form="signup" novalidate>
      ${back()}
      ${brandIcon(52)}
      <h1>Create your account</h1>
      <p class="sub">Friends find you by your username.</p>
      ${av.formError ? `<div class="form-error">${esc(av.formError)}</div>` : ''}
      <div class="photo-pick">
        <label class="ph" for="su-photo" style="cursor:pointer"><img id="su-photo-img" src="${esc(photo)}" alt="Profile photo"><span class="cam">${icon('camera', 15)}</span></label>
        <div><b>Profile photo</b><div class="small muted">${av.photo ? 'Looking good. Tap to change it.' : 'Tap to add a photo. Optional, but it helps friends find you.'}</div>${av.errors.photo ? `<div class="small red bold">${esc(av.errors.photo)}</div>` : ''}</div>
        <input type="file" id="su-photo" accept="image/*" class="sr" data-change="su-photo">
      </div>
      ${ui.field({ id: 'su-user', label: 'Username', value: v['su-user'] || '', err: av.errors.username, hint: '3–20 letters, numbers, dots or underscores', attrs: 'autocomplete="username" autocapitalize="off" spellcheck="false" maxlength="20"' })}
      ${ui.field({ id: 'su-email', label: 'Email', type: 'email', value: v['su-email'] || '', err: av.errors.email, attrs: 'autocomplete="email"' })}
      ${ui.field({ id: 'su-pw', label: 'Password', type: 'password', value: v['su-pw'] || '', err: av.errors.password, hint: 'At least 8 characters', attrs: 'autocomplete="new-password"' })}
      ${ui.field({ id: 'su-pw2', label: 'Confirm password', type: 'password', value: v['su-pw2'] || '', err: av.errors.confirm, attrs: 'autocomplete="new-password"' })}
      <button type="submit" class="btn primary full">Create account</button>
      <div class="tiny faint" style="text-align:center">${TO.api.configured ? 'Accounts and pledges are saved securely with Supabase.' : 'Offline demo: accounts are saved in this browser, not on a server.'}</div>
      <div class="small muted" style="text-align:center">Already have an account? <button type="button" class="link-btn" data-act="auth-go" data-s="login">Log in</button></div>
    </form></div>`;
  }

  function onboard() {
    const step = av.step;
    const steps = `<div class="steps">${[1, 2, 3].map((i) => `<i class="${i <= step ? 'on' : ''}"></i>`).join('')}</div>`;
    let body, next;
    if (step === 1) {
      body = `<h1>Here's the deal, @${esc(TO.account.username)}</h1>
        <div class="how-card"><span class="n">1</span><div><h3>You get 60 pledge minutes a day</h3><p>They reset every night at midnight.</p></div></div>
        <div class="how-card"><span class="n">2</span><div><h3>Challenges guide tomorrow's phone time</h3><p>Successful challenges add minutes to tomorrow's allowance.</p></div></div>
        <div class="how-card"><span class="n">3</span><div><h3>No money, ever</h3><p>Commit screen-time minutes to an outcome and track your streak.</p></div></div>`;
      next = `<button class="btn primary full" data-act="ob-next">Next</button>`;
    } else if (step === 2) {
      const sel = av.sports;
      body = `<h1>Pick your sports</h1><p class="sub">These show up on your Home feed. You can change them in Settings.</p>
        <div class="list">${S.LEAGUE_ORDER.map((l) => `<button class="list-row" data-act="ob-sport" data-id="${l}"><span class="sport-opt"><span class="sq">${esc(S.LEAGUES[l].short)}</span></span><span class="lr-main"><div class="lr-title">${esc(S.LEAGUES[l].title)}</div><div class="lr-sub">${l === 'sim' ? 'Simulated games for days without sports' : esc(S.LEAGUES[l].sport[0].toUpperCase() + S.LEAGUES[l].sport.slice(1))}</div></span><span class="checkbox ${sel.includes(l) ? 'on' : ''}">${icon('check', 15)}</span></button>`).join('')}</div>`;
      next = `<button class="btn primary full" data-act="ob-next" ${sel.length ? '' : 'disabled'}>${sel.length ? 'Next' : 'Pick at least one'}</button>`;
    } else {
      const pts = av.locks.reduce((s, id) => s + St.LOCKABLE.find((x) => x.id === id).pts, 0);
      const t = St.tierForPoints(pts);
      body = `<h1>Lock your time-wasters</h1><p class="sub">When today's phone time runs out, these apps lock. Lock more to reach a higher tier with bonus minutes and allowance boosts.</p>
        <div class="card tight margins"><span class="bold">${pts} lock points</span>${ui.tierBadge(t.id)}</div>
        <div class="list">${St.LOCKABLE.filter((x) => x.kind !== 'Website').map((x) => `<button class="list-row" data-act="ob-lock" data-id="${x.id}"><span class="lr-icon" style="background:${x.color}22;color:${x.color}">${icon(x.kind === 'Category' ? 'grid' : 'phone', 17)}</span><span class="lr-main"><div class="lr-title">${esc(x.name)}</div><div class="lr-sub">${x.kind} · ${x.pts} pt${x.pts === 1 ? '' : 's'}</div></span><span class="checkbox ${av.locks.includes(x.id) ? 'on' : ''}">${icon('check', 15)}</span></button>`).join('')}</div>`;
      next = `<button class="btn primary full" data-act="ob-finish">Start betting</button><button class="btn quiet sm" data-act="ob-finish" data-skip="1">Skip for now</button>`;
    }
    return `<div class="auth"><div class="auth-inner">${steps}${step > 1 ? `<button class="icon-btn" style="margin-left:-10px" data-act="ob-back" aria-label="Back">${icon('chevL', 22)}</button>` : ''}${body}<div class="stack-s" style="margin-top:auto">${next}</div></div></div>`;
  }

  // ---------- Verify email (after Create account, until the link in the email is opened) ----------
  const VERIFY_POLL_MS = 5000;
  const VERIFY_GIVE_UP_MS = 30 * TO.MIN;
  const RESEND_WAIT_MS = 60 * 1000;
  // The password is kept in memory only, so this page can log in by itself once the email is confirmed.
  const pending = { email: '', password: '', since: 0, resentAt: 0, timer: null, checking: false, note: '' };

  function verify() {
    const wait = Math.max(0, pending.resentAt + RESEND_WAIT_MS - Date.now());
    const stopped = Date.now() - pending.since > VERIFY_GIVE_UP_MS;
    return `<div class="auth"><div class="auth-inner verify-email">
      <button type="button" class="icon-btn" style="margin-left:-10px" data-act="verify-cancel" aria-label="Back">${icon('chevL', 22)}</button>
      <span class="verify-ic">${icon('send', 30)}</span>
      <h1>Verify your email</h1>
      <p class="sub">We sent a confirmation link to <b style="color:var(--text)">${esc(pending.email)}</b>. Open it to finish creating your account.</p>
      ${av.formError ? `<div class="form-error">${esc(av.formError)}</div>` : ''}
      <div class="note ${stopped ? '' : 'green'}">${stopped ? icon('clock', 16) : '<span class="verify-dot"></span>'}<span>${stopped
        ? 'Still waiting. Once you\'ve opened the link, tap the button below.'
        : 'Waiting for you to confirm. You\'ll be logged in automatically as soon as you do, on this page or from the link.'}</span></div>
      ${pending.note ? `<div class="small muted" style="text-align:center">${esc(pending.note)}</div>` : ''}
      <button type="button" class="btn primary full" data-act="verify-check" ${pending.checking ? 'disabled' : ''}>${pending.checking ? 'Checking…' : 'I\'ve confirmed my email'}</button>
      <button type="button" class="btn ghost full" data-act="verify-resend" ${wait ? 'disabled' : ''}>${icon('refresh', 16)} ${wait ? `Resend email in ${Math.ceil(wait / 1000)}s` : 'Resend email'}</button>
      <div class="small muted" style="text-align:center">Can't find it? Check spam or promotions. Wrong email? <button type="button" class="link-btn" data-act="verify-cancel">Start over</button></div>
    </div></div>`;
  }

  function stopVerifyPolling() {
    clearInterval(pending.timer);
    pending.timer = null;
  }

  /** Tries to log in with the new account. Supabase refuses with "Email not confirmed" until the link is opened. */
  async function checkVerified(manual) {
    if (pending.checking || !pending.email) return;
    if (!manual && (document.hidden || Date.now() - pending.since > VERIFY_GIVE_UP_MS)) return;
    pending.checking = true;
    if (manual) render();
    try {
      // Another tab may already have signed in from the email link.
      if (TO.api.hasToken()) { await finishVerified(await TO.api.me()); return; }
      const { user } = await TO.api.login(pending.email, pending.password);
      await finishVerified(user);
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      const unconfirmed = /not confirmed|confirm/i.test(e.message);
      if (manual) av.formError = unconfirmed ? 'Your email isn\'t confirmed yet. Open the link we sent, then try again.' : e.message;
    } finally {
      pending.checking = false;
      if (av.screen === 'verify') render();
    }
  }

  async function finishVerified(user) {
    stopVerifyPolling();
    pending.password = '';
    St.adoptServerUser(user, await TO.api.loadState());
    av.values = {}; av.photo = null;
    av.screen = 'onboard';
    TO.app.boot(); // new accounts land in onboarding
    ui.toast({ kind: 'win', title: 'Email verified', msg: `Welcome to TimeOut, @${user.username}.` });
  }

  function startVerify(email, password) {
    stopVerifyPolling();
    Object.assign(pending, { email, password, since: Date.now(), resentAt: Date.now(), checking: false, note: '' });
    av.screen = 'verify'; av.errors = {}; av.formError = '';
    render();
    pending.timer = setInterval(() => {
      if (av.screen !== 'verify') { stopVerifyPolling(); return; }
      checkVerified(false);
      render(); // keeps the resend countdown current
    }, VERIFY_POLL_MS);
  }

  // The email link signs in whichever tab it opens in. When that tab saves the session, this one follows.
  window.addEventListener('storage', (e) => {
    if (av.screen === 'verify' && e.key === TO.api.sessionKey && e.newValue) checkVerified(true);
  });

  function render() {
    const root = document.getElementById('app-body');
    const map = { welcome, login, signup, onboard, verify };
    root.innerHTML = map[av.screen]();
    const first = root.querySelector('input:not([type=file])');
    if (first && av.screen !== 'welcome' && !av.errors.password && av.screen !== 'onboard') setTimeout(() => { try { first.focus({ preventScroll: true }); } catch (e) { /* ignore */ } }, 50);
  }

  function show(screen) {
    if (screen !== 'verify') { stopVerifyPolling(); pending.password = ''; }
    av.screen = screen; av.errors = {}; av.formError = '';
    if (screen === 'welcome') { av.values = {}; av.photo = null; }
    render();
  }

  function startOnboarding() {
    av.screen = 'onboard'; av.step = 1; av.sports = TO.data.settings.sports.slice(); av.locks = [];
    render();
  }

  function collect(form) {
    form.querySelectorAll('input:not([type=file])').forEach((i) => { av.values[i.id] = i.value; });
  }

  function showError(e) {
    if (!(e instanceof TO.AppError)) throw e;
    Object.assign(av.errors, e.fields || {});
    av.formError = e.message;
    render();
  }

  function setBusy(form, label) {
    const btn = form.querySelector('button[type=submit]');
    if (btn) { btn.disabled = true; btn.textContent = label; }
  }

  /** Vertical slice: POST /api/auth/login -> server updates users.last_login_at and login_count -> show them. */
  async function serverLogin(email, password) {
    const { user } = await TO.api.login(email, password);
    St.adoptServerUser(user, await TO.api.loadState());
    av.values = {};
    TO.app.boot();
    ui.toast({
      kind: 'win',
      title: `Logged in as @${user.username}`,
      msg: 'Your bets and settings are synced to Supabase.',
    });
  }

  async function submit(form) {
    collect(form);
    av.errors = {}; av.formError = '';
    if (!TO.net.online()) { av.formError = 'No internet connection. Check your Wi-Fi or data and try again.'; render(); return; }
    const v = av.values;
    if (form.dataset.form === 'login') {
      try {
        if (TO.api.online) {
          setBusy(form, 'Logging in…');
          await serverLogin(v['li-id'] || '', v['li-pw'] || '');
          return;
        }
        St.login(v['li-id'], v['li-pw']);
        av.values = {};
        TO.app.boot();
      } catch (e) {
        av.errors = {};
        showError(e);
      }
      return;
    }
    // signup
    if (v['su-pw'] !== v['su-pw2']) av.errors.confirm = 'Passwords don\'t match.';
    if (TO.api.online) {
      try {
        if (av.errors.confirm) throw new TO.AppError('invalid', 'Fix the highlighted fields.');
        setBusy(form, 'Creating account…');
        const result = await TO.api.register({ username: (v['su-user'] || '').trim(), email: (v['su-email'] || '').trim(), password: v['su-pw'] || '', photoUrl: av.photo });
        if (result.needsConfirmation) { startVerify(result.email, v['su-pw'] || ''); return; }
        const { user, state } = result;
        St.adoptServerUser(user, state);
        av.values = {}; av.photo = null;
        startOnboarding();
      } catch (e) { showError(e); }
      return;
    }
    try {
      if (av.errors.confirm) {
        // Still report other field errors in the same pass.
        const probe = { username: St.validateUsername((v['su-user'] || '').trim()), email: St.validateEmail((v['su-email'] || '').trim()), password: St.validatePassword(v['su-pw'] || '') };
        for (const k of Object.keys(probe)) if (probe[k]) av.errors[k] = probe[k];
        throw new TO.AppError('invalid', 'Fix the highlighted fields.');
      }
      const acc = St.createAccount({ username: v['su-user'] || '', email: v['su-email'] || '', password: v['su-pw'] || '', photo: av.photo });
      St.startSession(acc.id);
      av.values = {}; av.photo = null;
      startOnboarding();
    } catch (e) { showError(e); }
  }

  TO.views.auth = { render, show, startOnboarding, submit };

  const A = TO.actions;
  A['auth-go'] = (el) => show(el.dataset.s);
  A['verify-check'] = () => checkVerified(true);
  A['verify-cancel'] = () => { av.values = { 'su-user': av.values['su-user'], 'su-email': pending.email }; show('signup'); };
  A['verify-resend'] = async () => {
    if (Date.now() < pending.resentAt + RESEND_WAIT_MS) return;
    try {
      await TO.api.resendConfirmation(pending.email);
      pending.resentAt = Date.now();
      pending.note = `Sent a new link to ${pending.email}.`;
      av.formError = '';
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      av.formError = e.message;
    }
    render();
  };
  A['auth-demo'] = async (el) => {
    if (TO.api.configured) return;
    if (!TO.net.online()) { ui.toast({ kind: 'loss', title: 'No internet connection', msg: 'Check your Wi-Fi or data and try again.' }); return; }
    if (!TO.api.online) { St.loginDemo(); TO.app.boot(); return; }
    el.disabled = true;
    try {
      await serverLogin(St.DEMO.username, St.DEMO.password);
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      el.disabled = false;
      ui.toast({ kind: 'loss', title: 'Couldn\'t log in to the demo account', msg: e.message });
    }
  };
  A.forgot = () => ui.confirm({ title: 'Reset your password', body: TO.api.online ? 'Password reset emails aren\'t built yet. Log in with the demo account or create a new account.' : 'In this demo, accounts live only in this browser, so there\'s no email reset. Create a new account or log in with the demo account.', confirm: 'OK', cancel: null });
  A['toggle-pw'] = (el) => {
    const input = document.getElementById(el.dataset.for);
    if (!input) return;
    input.type = input.type === 'password' ? 'text' : 'password';
    el.innerHTML = icon(input.type === 'password' ? 'eye' : 'eyeOff', 18);
  };
  A['ob-next'] = () => { av.step++; render(); };
  A['ob-back'] = () => { av.step--; render(); };
  A['ob-sport'] = (el) => { const id = el.dataset.id; av.sports = av.sports.includes(id) ? av.sports.filter((x) => x !== id) : [...av.sports, id]; render(); };
  A['ob-lock'] = (el) => { const id = el.dataset.id; av.locks = av.locks.includes(id) ? av.locks.filter((x) => x !== id) : [...av.locks, id]; render(); };
  A['ob-finish'] = (el) => {
    St.setSetting('sports', S.LEAGUE_ORDER.filter((l) => av.sports.includes(l)));
    if (!el.dataset.skip) St.setSetting('lockedApps', av.locks.slice());
    TO.data.onboarded = true;
    St.grantTierBonus();
    St.save();
    TO.app.boot();
    ui.toast({ kind: 'win', title: `Welcome to TimeOut, @${TO.account.username}`, msg: `You have ${TO.data.wallet.balance} pledge minutes today. Choose a matchup challenge to start.` });
  };
  TO.changes['su-photo'] = async (el) => {
    try {
      const form = el.closest('form');
      if (form) collect(form);
      av.photo = await ui.readPhoto(el.files[0]);
      av.errors.photo = null;
    } catch (e) { av.errors.photo = e.message; }
    render();
  };
})(window.TO);
