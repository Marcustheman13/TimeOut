/* TimeOut web demo — app shell, navigation, live refresh loop and event wiring. */
(function (TO) {
  'use strict';
  const { esc, icon, brandMark } = TO;
  const ui = TO.ui;
  const St = TO.state;

  const app = (TO.app = { tab: 'home', pressing: false });
  const TABS = [
    ['home', 'Home', 'home'],
    ['challenges', 'My Challenges', 'target'],
    ['social', 'Social', 'users'],
  ];

  /** The app shell. The browser version (web.js) swaps in its own layout. */
  app.shellHtml = () => `<div class="app" id="shell">
      <header class="topbar" id="topbar"></header>
      <main class="view" id="view" tabindex="-1"></main>
      <div id="commitment-bar-host"></div>
      <nav class="tabbar" id="tabbar" aria-label="Main"></nav>
    </div>`;

  app.boot = () => {
    ui.closeAllSheets();
    ui.closeAllPages();
    TO.views.settings.closeDrawer();
    const body = document.getElementById('app-body');
    if (!St.loadSession()) {
      body.innerHTML = '';
      TO.views.auth.show('welcome');
      return;
    }
    if (!TO.data.onboarded) {
      body.innerHTML = '';
      TO.views.auth.startOnboarding();
      return;
    }
    body.innerHTML = app.shellHtml();
    app.tab = 'home';
    app.render();
    TO.live.refresh();
    if (St.refreshTeams) St.refreshTeams();
    if (TO.invites) TO.invites.offer();
  };

  const inShell = () => !!document.getElementById('shell') && !!TO.data;

  app.renderChrome = () => {
    if (!inShell()) return;
    const wl = St.wallet();
    const locked = wl.lockedOut || wl.balance <= 0;
    const socialBadge = TO.views.social.badge();
    document.getElementById('topbar').innerHTML = `
      <button class="icon-btn" data-act="menu" aria-label="Menu and settings">${icon('menu', 22)}${wl.appsLocked ? '<span class="dotbadge"></span>' : ''}</button>
      <div class="brand">${brandMark(18, 'brand-mark')}<span class="brand-word">TIME<b>OUT</b></span></div>
      <button class="bal-pill ${locked ? 'locked' : ''}" data-act="settings" data-section="screentime" aria-label="${locked ? 'New pledges resume at midnight' : `${wl.balance} minutes available to pledge`}">${icon(locked ? 'lock' : 'hourglass', 15)}${locked ? 'Locked' : `${wl.balance} min`}</button>`;
    const open = TO.data.bets.filter((b) => b.status === 'open' && (b.kind === 'sports' || b.kind === 'race') && b.legs.length && b.legs.every((leg) => leg.kind === 'race' || leg.kind === 'game' || (leg.kind === 'sports' && leg.gameId))).length;
    document.getElementById('tabbar').innerHTML = TABS.map(([k, label, ic]) => {
      const badge = k === 'challenges' && open ? `<span class="badge green">${open}</span>` : k === 'social' && socialBadge ? `<span class="badge">${socialBadge}</span>` : '';
      return `<button class="tab ${app.tab === k ? 'on' : ''}" data-act="tab" data-tab="${k}" aria-current="${app.tab === k ? 'page' : 'false'}">${icon(ic, 23)}<span>${label}</span>${badge}</button>`;
    }).join('');
    app.refreshSlipbar();
  };

  app.refreshSlipbar = () => {
    if (!inShell()) return;
    const host = document.getElementById('commitment-bar-host');
    const commitment = TO.comboGoalBuilder;
    let markup = '';
    if (commitment.comboGoalMode && commitment.selectedPicks.length && !ui.sheetOpen('commitment')) {
      const st = commitment.status();
      const dec = commitment.selectedPicks.reduce((p, l) => p * TO.convertOddsToMultiplier(l.price), 1);
      const detail = st.closed ? 'Choice unavailable' : st.changed ? 'Target updated' : `${dec.toFixed(2)}x Target`;
      const title = commitment.selectedPicks.length > 1 ? 'Review Combo Goal' : 'Review Single Matchup Pledge';
      markup = `<button class="commitment-bar combo-goal-finalize" data-act="open-commitment" aria-label="${title}"><span class="n">${commitment.selectedPicks.length}</span><span>${title}</span><span class="o">${detail}</span></button>`;
    } else if (commitment.selectedPicks.length && !commitment.comboGoalMode && !ui.sheetOpen('commitment')) {
      const st = commitment.status();
      const dec = commitment.selectedPicks.reduce((p, l) => p * TO.odds.decimal(l.price), 1);
      markup = `<button class="commitment-bar" data-act="open-commitment"><span class="n">${commitment.selectedPicks.length}</span><span>Daily Commitment</span>${st.changed || st.closed ? `<span class="o row-s" style="font-family:var(--font-body);font-size:13px;color:var(--warn)">${icon('alert', 15)} ${st.closed ? 'Choice unavailable' : 'Target updated'}</span>` : `<span class="o">${TO.convertOddsToMultiplier(commitment.selectedPicks[0].price).toFixed(2)}x Target</span>`}</button>`;
    }
    if (host.innerHTML !== markup) host.innerHTML = markup;
  };

  app.renderView = () => {
    if (!inShell()) return;
    const view = document.getElementById('view');
    const h = {};
    view.querySelectorAll('[data-hkey]').forEach((el) => { h[el.dataset.hkey] = el.scrollLeft; });
    const st = view.scrollTop;
    view.innerHTML = TO.views[app.tab].render();
    view.scrollTop = st;
    view.querySelectorAll('[data-hkey]').forEach((el) => { if (h[el.dataset.hkey]) el.scrollLeft = h[el.dataset.hkey]; });
  };

  app.render = () => { app.renderChrome(); app.renderView(); };
  app.refreshOddsButtons = () => {
    app.renderView();
    if (ui.pageOpen('game')) TO.views.game.refresh();
    if (ui.pageOpen('combo-goal')) ui.refreshPage('combo-goal');
  };

  app.go = (tab) => {
    ui.closeAllPages();
    TO.views.settings.closeDrawer();
    app.tab = tab;
    app.render();
    const v = document.getElementById('view');
    if (v) v.scrollTop = 0;
  };

  // ---------- Live loop ----------
  let lastFull = 0;
  let lastSlipUiSig = '';
  function betTitle(b) { return TO.views.bets.betTitle(b); }

  function refreshSlip() {
    const commitment = TO.comboGoalBuilder;
    if (!commitment.selectedPicks.length) { lastSlipUiSig = ''; return; }
    const sig = commitment.selectedPicks.map((leg) => {
      const cur = TO.sim.currentSelection(leg.selId);
      return cur?.sel ? `${cur.sel.price}|${cur.sel.line}|${cur.open}` : 'x';
    }).join(',');
    if (sig !== lastSlipUiSig) {
      lastSlipUiSig = sig;
      commitment.update();
    }
  }

  function notifySettled(list) {
    const n = TO.data.settings.notify;
    for (const b of list) {
      if (!n.settled) continue;
      if (b.status === 'won') ui.toast({ kind: 'win', title: `Challenge complete: ${betTitle(b)}`, msg: `+${b.payout - b.stake} earned minutes added to tomorrow's phone time.` });
      else if (b.status === 'lost') ui.toast({ kind: 'loss', title: `Challenge missed: ${betTitle(b)}`, msg: `${b.stake} committed minutes deducted from tomorrow's phone time.` });
      else ui.toast({ kind: 'info', title: `Challenge returned: ${betTitle(b)}`, msg: `${b.insurancePaid ? 'Miss-one protection returned your minutes.' : 'The game was postponed.'} ${b.stake} minutes are available again.` });
    }
  }

  app.tick = (force) => {
    const now = TO.now();
    // Every second: clocks and countdowns.
    document.querySelectorAll('[data-countdown]').forEach((el) => { el.textContent = TO.countdown(Number(el.dataset.countdown) - now); });
    if (!force && Date.now() - lastFull < 5000) return;
    lastFull = Date.now();
    if (!inShell()) return;

    TO.live.refresh();

    // Midnight reset, pledges settlement and friend activity.
    const rolledOver = St.rollover(now);
    if (rolledOver) {
      St.save();
      ui.toast({ kind: 'info', title: 'Your daily minutes refreshed', msg: `Today's phone limit is ${St.wallet().todayLimit} min after yesterday's challenge results.` });
    }
    const settled = St.settle(now);
    notifySettled(settled);
    const socialEvents = St.socialTick(now);
    for (const ev of socialEvents) {
      if (ev.type === 'friend' && TO.data.settings.notify.friends) ui.toast({ kind: 'win', title: `@${ev.username} accepted your friend request` });
    }
    St.checkPhoneTime();

    const commitment = TO.comboGoalBuilder;
    if (commitment.selectedPicks.length) {
      refreshSlip();
    }

    const stateChanged = rolledOver || settled.length || socialEvents.length;
    if (stateChanged && !app.pressing && !isTyping()) {
      app.renderChrome();
      app.renderView();
      if (ui.pageOpen('game')) TO.views.game.refresh();
      if (ui.pageOpen('combo-goal')) ui.refreshPage('combo-goal');
      const sp = document.querySelector('[data-page="settings"] .page-top .t');
      if (sp && ['Screen time', 'Tier & streak'].includes(sp.textContent)) ui.refreshPage('settings');
    } else {
      app.refreshSlipbar();
    }
  };

  function isTyping() {
    const a = document.activeElement;
    return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA') && a.type !== 'checkbox';
  }

  // ---------- Connection ----------
  /** Red banner while offline; the commitment refuses pledges until the connection returns. */
  function renderNet() {
    const root = ui.root();
    if (!root) return;
    let el = document.getElementById('net-banner');
    if (!el) {
      el = document.createElement('div');
      el.id = 'net-banner';
      el.className = 'net-banner';
      el.setAttribute('role', 'alert');
      el.innerHTML = `${icon('wifiOff', 17)}<span><b>No internet connection.</b> New pledges pause until you're back online.</span>`;
      root.appendChild(el);
    }
    const off = !TO.net.online();
    el.hidden = !off;
    document.body.classList.toggle('is-offline', off);
  }
  app.netChanged = () => {
    renderNet();
    if (ui.sheetOpen('commitment')) ui.refreshSheet('commitment', ['body', 'foot']);
    if (TO.net.online()) ui.toast({ kind: 'win', title: 'Back online', msg: 'Matchup targets are updating again.' });
  };
  window.addEventListener('online', app.netChanged);
  window.addEventListener('offline', app.netChanged);

  // ---------- Core actions ----------
  const A = TO.actions;
  A.tab = (el) => { ui.closeAllSheets(); app.go(el.dataset.tab); };
  A['close-sheet'] = (el) => {
    if (el.dataset.name === 'commitment') {
      TO.comboGoalBuilder.clear();
      ui.closeSheet('commitment');
      app.render();
      return;
    }
    ui.closeSheet(el.dataset.name);
  };
  A['close-page'] = (el) => { ui.closePage(el.dataset.name); app.render(); };

  // ---------- Event wiring ----------
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-act]');
    if (!el || el.disabled) return;
    const fn = A[el.dataset.act];
    if (!fn) return;
    if (el.tagName === 'A' && el.dataset.act !== 'share-saved') e.preventDefault();
    // A click on a label wrapper shouldn't also fire the nested control's action twice.
    fn(el, e);
  });
  document.addEventListener('change', (e) => {
    if (e.target.id === 'cfb-group') TO.live.setGroup(e.target.value);
  });
  TO.on('live:updated', () => {
    if (!inShell()) return;
    const settled = St.settle(TO.now());
    notifySettled(settled);
    if (settled.length) app.renderChrome();
    if (app.tab === 'home') TO.views.home.refreshLive();
    if (app.tab === 'challenges') app.renderView();
    if (ui.pageOpen('game')) TO.views.game.refresh();
    refreshSlip();
    app.refreshSlipbar();
  });
  TO.on('live:details-updated', () => {
    if (inShell() && app.tab === 'challenges') app.renderView();
  });
  document.addEventListener('input', (e) => { const fn = TO.inputs[e.target.id]; if (fn) fn(e.target); });
  document.addEventListener('change', (e) => { const k = e.target.dataset && e.target.dataset.change; if (k && TO.changes[k]) TO.changes[k](e.target); });
  document.addEventListener('submit', (e) => {
    const form = e.target.closest('form[data-form]');
    if (!form) return;
    e.preventDefault();
    TO.views.auth.submit(form);
  });
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    const layer = ui.layer();
    const last = layer.lastElementChild;
    if (!last) return;
    if (last.dataset.sheet) ui.closeSheet(last.dataset.sheet);
    else if (last.dataset.drawer) TO.views.settings.closeDrawer();
    else if (last.dataset.page) { ui.closePage(last.dataset.page); app.render(); }
  });
  document.addEventListener('pointerdown', () => { app.pressing = true; });
  document.addEventListener('pointerup', () => { setTimeout(() => { app.pressing = false; }, 60); });
  document.addEventListener('pointercancel', () => { app.pressing = false; });

  /** Server mode: the database decides who is logged in. Re-reads the user on every page load,
   *  so values the server changed (last login, login count) survive a refresh. */
  async function restoreServerSession() {
    if (!TO.api.hasToken()) { St.logout(); return; }
    try {
      const user = await TO.api.me();
      St.adoptServerUser(user, await TO.api.loadState());
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      if (e.status === 401) TO.api.clearToken();
      St.logout();
      if (e.status !== 401) ui.toast({ kind: 'loss', title: 'Couldn\'t load your account', msg: e.message });
    }
  }

  // A browser session can stay open while pledges are placed in another one. Refresh the
  // shared account snapshot when this tab returns and periodically while it is visible.
  let remoteSyncAt = 0;
  let remoteSync = null;
  function syncRemoteState(force = false) {
    if (!inShell() || document.hidden || !TO.api.configured || !TO.api.hasToken() || !TO.account?.server) return;
    if (remoteSync) return remoteSync;
    if (!force && Date.now() - remoteSyncAt < 30000) return;
    remoteSyncAt = Date.now();
    remoteSync = TO.api.loadState().then((state) => {
      if (!state || !inShell()) return;
      St.adoptServerUser(TO.account.server, state);
      app.render();
    }).catch((error) => {
      console.warn('Could not refresh TimeOut data from Supabase:', error.message);
    }).finally(() => { remoteSync = null; });
    return remoteSync;
  }
  document.addEventListener('visibilitychange', () => { if (!document.hidden) syncRemoteState(true); });
  window.addEventListener('focus', () => syncRemoteState(true));

  async function start() {
    renderNet();
    if (TO.invites) TO.invites.capture();
    // Arriving from the link in a confirmation email: the URL carries the new session (or why it failed).
    const redirect = TO.api.configured && TO.api.consumeAuthRedirect ? TO.api.consumeAuthRedirect() : null;
    if (await TO.api.init()) await restoreServerSession();
    else St.ensureDemoAccount();
    app.boot();
    if (redirect && redirect.signedIn && TO.account) {
      ui.toast({ kind: 'win', title: 'Email verified', msg: `You're logged in as @${TO.account.username}.` });
    } else if (redirect && redirect.error && !TO.account) {
      TO.views.auth.show('login');
      ui.toast({ kind: 'loss', title: 'That link didn\'t work', msg: `${redirect.error}. Log in, or create your account again to get a new link.`, ms: 8000 });
    }
    setInterval(() => app.tick(false), 1000);
    setInterval(() => syncRemoteState(), 30000);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})(window.TO);
