/* TimeOut web demo — welcome, log in, create account and onboarding. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
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
        <div class="wordmark">Time<b>Out</b></div>
        <div class="tagline">Bet your screen time, not your money.</div>
        <div class="welcome-points">
          <div>${icon('hourglass', 18)}<span>60 betting minutes a day. Win and you get more phone time tomorrow.</span></div>
          <div>${icon('radio', 18)}<span>Live scores and odds for NFL, NBA, MLB, NHL, college football and soccer.</span></div>
          <div>${icon('users', 18)}<span>Challenge friends and play for anything but cash.</span></div>
        </div>
      </div>
      <div class="auth-inner" style="flex:none;gap:10px">
        <button class="btn primary full" data-act="auth-go" data-s="signup">Create account</button>
        <button class="btn ghost full" data-act="auth-go" data-s="login">Log in</button>
        <button class="btn quiet full sm" data-act="auth-demo">${icon('flask', 16)} Try the demo account</button>
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
      <h1>Welcome back</h1>
      <p class="sub">Log in with your username or email.</p>
      ${av.formError ? `<div class="form-error">${esc(av.formError)}</div>` : ''}
      ${ui.field({ id: 'li-id', label: 'Username or email', value: v['li-id'] || '', err: av.errors.identifier, attrs: 'autocomplete="username" autocapitalize="off" spellcheck="false"' })}
      ${ui.field({ id: 'li-pw', label: 'Password', type: 'password', value: '', err: av.errors.password, attrs: 'autocomplete="current-password"' })}
      <button type="submit" class="btn primary full">Log in</button>
      <button type="button" class="btn quiet sm" data-act="forgot">Forgot password?</button>
      <div class="divider"></div>
      <button type="button" class="btn ghost full" data-act="auth-demo">${icon('flask', 16)} Log in with the demo account</button>
      <div class="small muted" style="text-align:center">New here? <button type="button" class="link-btn" data-act="auth-go" data-s="signup">Create an account</button></div>
    </form></div>`;
  }

  function signup() {
    const v = av.values;
    const photo = av.photo || TO.initialsAvatar(v['su-user'] || '?', '#1d2430');
    return `<div class="auth"><form class="auth-inner" data-form="signup" novalidate>
      ${back()}
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
      <div class="tiny faint" style="text-align:center">${TO.api.online ? 'Your account is saved in the TimeOut database.' : 'Offline demo: accounts are saved in this browser, not on a server.'}</div>
      <div class="small muted" style="text-align:center">Already have an account? <button type="button" class="link-btn" data-act="auth-go" data-s="login">Log in</button></div>
    </form></div>`;
  }

  function onboard() {
    const step = av.step;
    const steps = `<div class="steps">${[1, 2, 3].map((i) => `<i class="${i <= step ? 'on' : ''}"></i>`).join('')}</div>`;
    let body, next;
    if (step === 1) {
      body = `<h1>Here's the deal, @${esc(TO.account.username)}</h1>
        <div class="how-card"><span class="n">1</span><div><h3>You get 60 betting minutes a day</h3><p>They reset every night at midnight.</p></div></div>
        <div class="how-card"><span class="n">2</span><div><h3>You're betting tomorrow's phone time</h3><p>Win and tomorrow's limit goes up. Lose and it goes down.</p></div></div>
        <div class="how-card"><span class="n">3</span><div><h3>No money, ever</h3><p>Not now, not later. Just minutes, bragging rights, and whatever you bet your friends.</p></div></div>`;
      next = `<button class="btn primary full" data-act="ob-next">Next</button>`;
    } else if (step === 2) {
      const sel = av.sports;
      body = `<h1>Pick your sports</h1><p class="sub">These show up on your Home feed. You can change them in Settings.</p>
        <div class="list">${S.LEAGUE_ORDER.map((l) => `<button class="list-row" data-act="ob-sport" data-id="${l}"><span class="sport-opt"><span class="sq">${esc(S.LEAGUES[l].short)}</span></span><span class="lr-main"><div class="lr-title">${esc(S.LEAGUES[l].title)}</div><div class="lr-sub">${l === 'sim' ? 'Simulated games for days without sports' : esc(S.LEAGUES[l].sport[0].toUpperCase() + S.LEAGUES[l].sport.slice(1))}</div></span><span class="checkbox ${sel.includes(l) ? 'on' : ''}">${icon('check', 15)}</span></button>`).join('')}</div>`;
      next = `<button class="btn primary full" data-act="ob-next" ${sel.length ? '' : 'disabled'}>${sel.length ? 'Next' : 'Pick at least one'}</button>`;
    } else {
      const pts = av.locks.reduce((s, id) => s + St.LOCKABLE.find((x) => x.id === id).pts, 0);
      const t = St.tierForPoints(pts);
      body = `<h1>Lock your time-wasters</h1><p class="sub">When today's phone time runs out, these apps lock. Lock more to reach a higher tier with bonus minutes and odds boosts.</p>
        <div class="card tight spread"><span class="bold">${pts} lock points</span>${ui.tierBadge(t.id)}</div>
        <div class="list">${St.LOCKABLE.filter((x) => x.kind !== 'Website').map((x) => `<button class="list-row" data-act="ob-lock" data-id="${x.id}"><span class="lr-icon" style="background:${x.color}22;color:${x.color}">${icon(x.kind === 'Category' ? 'grid' : 'phone', 17)}</span><span class="lr-main"><div class="lr-title">${esc(x.name)}</div><div class="lr-sub">${x.kind} · ${x.pts} pt${x.pts === 1 ? '' : 's'}</div></span><span class="checkbox ${av.locks.includes(x.id) ? 'on' : ''}">${icon('check', 15)}</span></button>`).join('')}</div>`;
      next = `<button class="btn primary full" data-act="ob-finish">Start betting</button><button class="btn quiet sm" data-act="ob-finish" data-skip="1">Skip for now</button>`;
    }
    return `<div class="auth"><div class="auth-inner">${steps}${step > 1 ? `<button class="icon-btn" style="margin-left:-10px" data-act="ob-back" aria-label="Back">${icon('chevL', 22)}</button>` : ''}${body}<div class="stack-s" style="margin-top:auto">${next}</div></div></div>`;
  }

  function render() {
    const root = document.getElementById('app-body');
    const map = { welcome, login, signup, onboard };
    root.innerHTML = map[av.screen]();
    const first = root.querySelector('input:not([type=file])');
    if (first && av.screen !== 'welcome' && !av.errors.password && av.screen !== 'onboard') setTimeout(() => { try { first.focus({ preventScroll: true }); } catch (e) { /* ignore */ } }, 50);
  }

  function show(screen) {
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
  async function serverLogin(identifier, password) {
    const { user, previousLoginAt } = await TO.api.login(identifier, password);
    St.adoptServerUser(user);
    av.values = {};
    TO.tester.mark('login');
    TO.app.boot();
    ui.toast({
      kind: 'win',
      title: `Logged in as @${user.username}`,
      msg: `Login #${user.loginCount}, saved to the database. ${previousLoginAt ? `Previous login: ${TO.fmtDate(Date.parse(previousLoginAt))}, ${TO.fmtTime(Date.parse(previousLoginAt))}.` : 'First login.'}`,
    });
  }

  async function submit(form) {
    collect(form);
    av.errors = {}; av.formError = '';
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
        const { user } = await TO.api.register({ username: (v['su-user'] || '').trim(), email: (v['su-email'] || '').trim(), password: v['su-pw'] || '', photoUrl: av.photo });
        St.adoptServerUser(user);
        av.values = {}; av.photo = null;
        TO.tester.mark('signup');
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
      TO.tester.mark('signup');
      startOnboarding();
    } catch (e) { showError(e); }
  }

  TO.views.auth = { render, show, startOnboarding, submit };

  const A = TO.actions;
  A['auth-go'] = (el) => show(el.dataset.s);
  A['auth-demo'] = async (el) => {
    if (!TO.api.online) { St.loginDemo(); TO.tester.mark('login'); TO.app.boot(); return; }
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
    ui.toast({ kind: 'win', title: `Welcome to TimeOut, @${TO.account.username}`, msg: `You have ${TO.data.wallet.balance} betting minutes today. Tap any odds to start.` });
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
