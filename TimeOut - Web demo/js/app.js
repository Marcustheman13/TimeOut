/* TimeOut web demo — app shell, navigation, live refresh loop and event wiring. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const ui = TO.ui;
  const St = TO.state;

  const app = (TO.app = { tab: 'home', pressing: false });
  const TABS = [
    ['home', 'Home', 'home'],
    ['bets', 'My Bets', 'ticket'],
    ['social', 'Social', 'users'],
  ];

  const shellHtml = () => `<div class="app" id="shell">
      <header class="topbar" id="topbar"></header>
      <main class="view" id="view" tabindex="-1"></main>
      <div id="slipbar-host"></div>
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
      TO.tester.render();
      return;
    }
    if (!TO.data.onboarded) {
      body.innerHTML = '';
      TO.views.auth.startOnboarding();
      TO.tester.render();
      return;
    }
    body.innerHTML = shellHtml();
    app.tab = 'home';
    app.render();
    TO.tester.render();
  };

  const inShell = () => !!document.getElementById('shell') && !!TO.data;

  app.renderChrome = () => {
    if (!inShell()) return;
    const wl = St.wallet();
    const locked = wl.lockedOut || wl.balance <= 0;
    const socialBadge = TO.views.social.badge();
    document.getElementById('topbar').innerHTML = `
      <button class="icon-btn" data-act="menu" aria-label="Menu and settings">${icon('menu', 22)}${wl.appsLocked ? '<span class="dotbadge"></span>' : ''}</button>
      <div class="brand">${icon('hourglass', 20, 'brand-mark')}<span class="brand-word">Time<b>Out</b></span></div>
      <button class="bal-pill ${locked ? 'locked' : ''}" data-act="settings" data-section="screentime" aria-label="${locked ? 'Betting locked until midnight' : `${wl.balance} minutes available to bet`}">${icon(locked ? 'lock' : 'hourglass', 15)}${locked ? 'Locked' : `${wl.balance} min`}</button>`;
    const open = TO.data.bets.filter((b) => b.status === 'open').length;
    document.getElementById('tabbar').innerHTML = TABS.map(([k, label, ic]) => {
      const badge = k === 'bets' && open ? `<span class="badge green">${open}</span>` : k === 'social' && socialBadge ? `<span class="badge">${socialBadge}</span>` : '';
      return `<button class="tab ${app.tab === k ? 'on' : ''}" data-act="tab" data-tab="${k}" aria-current="${app.tab === k ? 'page' : 'false'}">${icon(ic, 23)}<span>${label}</span>${badge}</button>`;
    }).join('');
    const host = document.getElementById('slipbar-host');
    const slip = TO.slip;
    if (slip.legs.length && !ui.sheetOpen('slip')) {
      const st = slip.status();
      const dec = slip.legs.reduce((p, l) => p * TO.odds.decimal(l.price), 1);
      host.innerHTML = `<button class="slipbar" data-act="open-slip"><span class="n">${slip.legs.length}</span><span>${slip.legs.length > 1 ? 'Parlay' : 'Bet Slip'}</span>${st.changed || st.closed ? `<span class="o row-s" style="font-family:var(--font-body);font-size:13px;color:var(--warn)">${icon('alert', 15)} ${st.closed ? 'Pick unavailable' : 'Odds changed'}</span>` : `<span class="o">${TO.odds.fmt(TO.odds.fromDecimal(dec))}</span>`}</button>`;
    } else host.innerHTML = '';
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
  function betTitle(b) { return TO.views.bets.betTitle(b); }

  function notifySettled(list) {
    const n = TO.data.settings.notify;
    for (const b of list) {
      if (b.friend) {
        if (!n.challenges) continue;
        const who = b.friend.with.join(', ');
        if (b.status === 'won') ui.toast({ kind: 'win', title: `You beat @${who}`, msg: `They owe you: "${b.friend.terms}"` });
        else if (b.status === 'lost') ui.toast({ kind: 'loss', title: `@${who} won your friend bet`, msg: `You owe them: "${b.friend.terms}"` });
        else ui.toast({ kind: 'info', title: 'Friend bet voided', msg: `${betTitle(b)} · no winner` });
        continue;
      }
      if (!n.settled) continue;
      if (b.status === 'won') ui.toast({ kind: 'win', title: `Won: ${betTitle(b)}`, msg: `+${b.payout - b.stake} min added to tomorrow's phone time.` });
      else if (b.status === 'lost') ui.toast({ kind: 'loss', title: `Lost: ${betTitle(b)}`, msg: `−${b.stake} min from tomorrow's phone time.` });
      else ui.toast({ kind: 'info', title: `Voided: ${betTitle(b)}`, msg: `${b.insurancePaid ? 'Parlay insurance paid out.' : 'The game was postponed.'} Your ${b.stake} min stake came back.` });
    }
  }

  app.tick = (force) => {
    const now = TO.now();
    // Every second: clocks and countdowns.
    document.querySelectorAll('[data-countdown]').forEach((el) => { el.textContent = TO.countdown(Number(el.dataset.countdown) - now); });
    const sb = document.getElementById('sb-time');
    if (sb) sb.textContent = new Date(now).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }).replace(/\s?[AP]M$/i, '');
    const cf = document.querySelector('#tester-body .clockface b');
    if (cf) cf.textContent = new Date(now).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' });

    if (!force && Date.now() - lastFull < 5000) return;
    lastFull = Date.now();
    if (!inShell()) { TO.tester.render(); return; }

    // Midnight reset, settlement (PRD: within 5 minutes of a game ending; here within seconds) and friend activity.
    if (St.rollover(now)) {
      St.save();
      ui.toast({ kind: 'info', title: 'New day, new 60 minutes', msg: `Today's phone limit is ${St.wallet().todayLimit} min after yesterday's bets.` });
    }
    const settled = St.settle(now);
    notifySettled(settled);
    for (const ev of St.socialTick(now)) {
      if (ev.type === 'friend' && TO.data.settings.notify.friends) ui.toast({ kind: 'win', title: `@${ev.username} accepted your friend request` });
      if (ev.type === 'challenge' && TO.data.settings.notify.challenges) ui.toast({ kind: 'win', title: `@${ev.bet.friend.with.join(', ')} accepted your friend bet`, msg: `"${ev.bet.friend.terms}"` });
    }
    St.checkPhoneTime();

    const slip = TO.slip;
    if (slip.legs.length) {
      const st = slip.status();
      const sig = slip.legs.map((l) => { const c = TO.sim.currentSelection(l.selId); return c && c.sel ? `${c.sel.price}|${c.sel.line}` : 'x'; }).join(',');
      if (st.changed && sig !== slip.notifiedChange) {
        slip.notifiedChange = sig;
        if (TO.data.settings.notify.odds && !ui.sheetOpen('slip')) ui.toast({ kind: 'warn', title: 'Odds changed on your bet slip', msg: 'Open the slip to review and accept the new odds.' });
      }
      slip.update();
    }

    if (!app.pressing && !isTyping()) {
      app.renderChrome();
      app.renderView();
      if (ui.pageOpen('game')) TO.views.game.refresh();
      const sp = document.querySelector('[data-page="settings"] .page-top .t');
      if (sp && ['Screen time', 'Tier & streak'].includes(sp.textContent)) ui.refreshPage('settings');
    } else {
      app.renderChrome();
    }
    TO.tester.render();
  };

  function isTyping() {
    const a = document.activeElement;
    return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA') && a.type !== 'checkbox';
  }

  // ---------- Core actions ----------
  const A = TO.actions;
  A.tab = (el) => { ui.closeAllSheets(); app.go(el.dataset.tab); };
  A['close-sheet'] = (el) => ui.closeSheet(el.dataset.name);
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

  // ---------- Fit the phone frame to the window ----------
  function fit() {
    const slot = document.getElementById('device-slot');
    const device = document.getElementById('device');
    const tester = document.getElementById('tester');
    if (!slot || !device) return;
    if (window.innerWidth <= 560) {
      slot.style.width = slot.style.height = '';
      device.style.transform = '';
      return;
    }
    const scale = Math.min(1, Math.max(0.6, (window.innerHeight - 48) / 852));
    device.style.transform = `scale(${scale})`;
    slot.style.width = `${393 * scale}px`;
    slot.style.height = `${852 * scale}px`;
    if (tester) tester.style.height = `${852 * scale}px`;
  }
  window.addEventListener('resize', fit);

  /** Server mode: the database decides who is logged in. Re-reads the user on every page load,
   *  so values the server changed (last login, login count) survive a refresh. */
  async function restoreServerSession() {
    if (!TO.api.hasToken()) { St.logout(); return; }
    try {
      St.adoptServerUser(await TO.api.me());
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      if (e.status === 401) TO.api.clearToken();
      St.logout();
      if (e.status !== 401) ui.toast({ kind: 'loss', title: 'Couldn\'t load your account', msg: e.message });
    }
  }

  async function start() {
    fit();
    if (await TO.api.init()) await restoreServerSession();
    else St.ensureDemoAccount();
    app.boot();
    setInterval(() => app.tick(false), 1000);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})(window.TO);
