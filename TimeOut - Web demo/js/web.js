/* TimeOut web demo — browser layout. Loaded only by web.html, after app.js.
   Same app, data and actions as the phone version, laid out for a desktop browser: a sidebar instead of the
   tab bar and menu drawer, a wide content area, and the bet slip docked on the right. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const ui = TO.ui;
  const St = TO.state;
  const app = TO.app;
  const A = TO.actions;

  /** Wide enough to dock the bet slip on the right. Below this the slip opens as a dialog, like a sheet on the phone. */
  const wide = window.matchMedia('(min-width: 900px)');
  const isWeb = () => !!document.getElementById('side') && !!TO.data;

  const TABS = [
    ['home', 'Home', 'home'],
    ['bets', 'My Bets', 'ticket'],
    ['social', 'Social', 'users'],
  ];
  // Titles match the settings page titles so the open page can be highlighted.
  const MENU = [
    ['screentime', 'Screen time', 'hourglass'],
    ['status', 'Tier & streak', 'trophy'],
    ['sports', 'Sports on Home', 'grid'],
    ['notifications', 'Notifications', 'bell'],
    ['privacy', 'What friends can see', 'eye'],
    ['account', 'Account', 'user'],
  ];

  app.shellHtml = () => `<div class="app web-shell" id="shell">
      <aside class="side" id="side" aria-label="Main"></aside>
      <div class="side-scrim" data-act="side-toggle"></div>
      <div class="main">
        <header class="topbar web-top" id="topbar"></header>
        <main class="view" id="view" tabindex="-1"></main>
        <div id="slipbar-host"></div>
      </div>
      <aside class="rail" id="rail" aria-label="Bet slip"></aside>
      <nav id="tabbar" hidden></nav>
    </div>`;

  /** Title of the settings page that's open, if any. */
  function openSection() {
    const t = document.querySelector('[data-page="settings"] .page-top .t');
    return t ? t.textContent : null;
  }

  function sideHtml() {
    const wl = St.wallet();
    const open = TO.data.bets.filter((b) => b.status === 'open').length;
    const socialBadge = TO.views.social.badge();
    const section = openSection();
    const tabs = TABS.map(([k, label, ic]) => {
      const on = !section && app.tab === k;
      const n = k === 'bets' ? open : k === 'social' ? socialBadge : 0;
      return `<button class="sn primary ${on ? 'on' : ''}" data-act="tab" data-tab="${k}" title="${label}" aria-current="${on ? 'page' : 'false'}">${icon(ic, 21)}<span class="sn-l">${label}</span>${n ? `<span class="sn-n ${k === 'bets' ? 'green' : ''}">${n}</span>` : ''}</button>`;
    }).join('');
    const subs = { screentime: `${wl.phoneLeft} min left`, status: wl.streak ? `${wl.streak}-day streak` : '' };
    const item = (key, title, ic, cls = '') => {
      const on = section === title;
      return `<button class="sn ${cls} ${on ? 'on' : ''}" data-act="settings" data-section="${key}" title="${title}" aria-current="${on ? 'page' : 'false'}">${icon(ic, 19)}<span class="sn-l">${title}</span>${subs[key] ? `<span class="sn-sub">${subs[key]}</span>` : ''}${key === 'screentime' && wl.appsLocked ? '<span class="sn-dot"></span>' : ''}</button>`;
    };
    return `<div class="side-brand"><div class="brand">${icon('hourglass', 22, 'brand-mark')}<span class="brand-word">Time<b>Out</b></span></div></div>
      <nav class="side-nav">
        ${tabs}
        <div class="side-label eyebrow">Screen time & settings</div>
        ${MENU.map(([k, t, ic]) => item(k, t, ic)).join('')}
        <button class="sn" data-act="how" title="How TimeOut works">${icon('help', 19)}<span class="sn-l">How TimeOut works</span></button>
      </nav>
      <div class="side-foot">
        <button class="side-user" data-act="settings" data-section="account" title="@${esc(TO.account.username)}">${ui.avatar(TO.account.photo)}<span class="sn-l"><b class="ellipsis" style="display:block">@${esc(TO.account.username)}</b><span style="display:block;margin-top:3px">${ui.tierBadge(wl.tier.id, true)}</span></span></button>
        <button class="sn" data-act="logout" title="Log out">${icon('logout', 19)}<span class="sn-l">Log out</span></button>
      </div>`;
  }

  function topHtml() {
    const wl = St.wallet();
    const locked = wl.lockedOut || wl.balance <= 0;
    const now = new Date(TO.now());
    const phoneCls = wl.appsLocked ? 'red' : wl.phoneLeft <= TO.data.settings.lowWarn ? 'yellow' : '';
    return `<button class="icon-btn wt-menu" data-act="side-toggle" aria-label="Open menu" aria-expanded="${document.body.classList.contains('side-open')}">${icon('menu', 22)}</button>
      <div class="wt-when"><b>${now.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' })}</b><span>${now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}${TO.clock.offset ? ' · demo clock' : ''}</span></div>
      <button class="wt-stat opt" data-act="settings" data-section="screentime">${icon('phone', 15)}<span><b class="${phoneCls}">${TO.data.settings.enforce ? `${wl.phoneLeft} min` : 'Off'}</b> phone time left</span></button>
      <span class="wt-stat opt">${icon('clock', 15)}<span>Resets in <b>${ui.countdownEl(TO.nextMidnight())}</b></span></span>
      <button class="bal-pill ${locked ? 'locked' : ''}" data-act="settings" data-section="screentime" aria-label="${locked ? 'Betting locked until midnight' : `${wl.balance} minutes available to bet`}">${icon(locked ? 'lock' : 'hourglass', 16)}${locked ? 'Betting locked' : `${wl.balance} min to bet`}</button>`;
  }

  function railHtml() {
    const wl = St.wallet();
    const locked = wl.lockedOut || wl.balance <= 0;
    const step = (n, t, d) => `<div class="how-card"><span class="n">${n}</span><div><h3>${t}</h3><p>${d}</p></div></div>`;
    return `<div class="rail-head"><h2>Bet Slip</h2></div>
      <div class="rail-body">
        <div class="rail-empty">
          <span class="re-ic">${icon('ticket', 26)}</span>
          <h3>Your slip is empty</h3>
          <p>${locked ? 'Betting is locked until midnight. Your open bets still settle.' : `Click any odds to add a pick. Add up to ${TO.RULES.maxLegs} picks from different games for a parlay.`}</p>
        </div>
        <div class="stack-s">
          <div class="eyebrow">How a bet works</div>
          ${step(1, 'Pick a price', 'Click odds on any game or prediction.')}
          ${step(2, 'Stake minutes', `Up to your ${wl.balance} betting minutes today.`)}
          ${step(3, 'Win phone time', "Wins add to tomorrow's limit. Losses take it away.")}
        </div>
        <div class="rail-limits">
          <div><span>Betting balance</span><b class="${locked ? 'red' : 'green'}">${wl.balance} min</b></div>
          <div><span>In open bets</span><b>${wl.atRisk} min</b></div>
          <div><span>Tomorrow's limit</span><b class="${wl.tomorrowLimit > TO.RULES.daily ? 'green' : wl.tomorrowLimit < TO.RULES.daily ? 'red' : ''}">${wl.tomorrowLimit} min</b></div>
        </div>
      </div>`;
  }

  /** Only touch the DOM when the markup changed, so hover and keyboard focus survive the 5-second refresh. */
  function put(id, html) {
    const el = document.getElementById(id);
    if (el && el._html !== html) { el.innerHTML = html; el._html = html; }
  }

  const phoneChrome = app.renderChrome;
  app.renderChrome = () => {
    phoneChrome();
    if (!isWeb()) return;
    // With room for it, the slip stays docked whenever it has picks. open() re-renders the chrome itself.
    if (wide.matches && TO.slip.legs.length && !ui.sheetOpen('slip')) { TO.slip.open(); return; }
    put('side', sideHtml());
    put('rail', railHtml());
    document.getElementById('topbar').innerHTML = topHtml();
  };

  const phoneView = app.renderView;
  app.renderView = () => {
    const v = document.getElementById('view');
    if (v) v.dataset.tab = app.tab;
    phoneView();
  };

  // Leaving a page or switching tabs shouldn't take the docked slip away.
  ui.closeAllSheets = () => ui.layer().querySelectorAll('[data-sheet]').forEach((w) => {
    if (w.dataset.sheet === 'slip' && wide.matches && isWeb()) return;
    ui.closeSheet(w.dataset.sheet);
  });
  // ---------- Small windows: the sidebar becomes a slide-in menu ----------
  const setSide = (open) => {
    document.body.classList.toggle('side-open', open);
    const b = document.querySelector('.wt-menu');
    if (b) b.setAttribute('aria-expanded', String(open));
  };
  A['side-toggle'] = () => setSide(!document.body.classList.contains('side-open'));
  // Picking anything in the menu closes it (capture phase: runs before the item re-renders the sidebar).
  window.addEventListener('click', (e) => {
    if (document.body.classList.contains('side-open') && e.target.closest('.side [data-act], .side a')) setSide(false);
  }, true);
  window.matchMedia('(max-width: 720px)').addEventListener('change', () => setSide(false));

  const phoneBoot = app.boot;
  app.boot = () => { ui.closeSheet('slip', true); TO.slip.clear(); setSide(false); phoneBoot(); };
  TO.slip.docked = () => wide.matches && isWeb();

  // The sidebar is always on screen, so a settings section can be opened over a game page. Replace it instead.
  const phoneSettings = A.settings;
  A.settings = (el) => { ui.closeAllPages(); phoneSettings(el); app.renderChrome(); };

  // ---------- Demo controls dropdown (in the demo bar above the app, not part of TimeOut) ----------
  const dropBtn = document.getElementById('db-toggle');
  const drop = document.getElementById('db-drop');
  const dropOpen = () => drop.classList.contains('open');
  function setDrop(open) {
    drop.classList.toggle('open', open);
    dropBtn.setAttribute('aria-expanded', String(open));
    if (open) TO.tester.render();
  }
  dropBtn.addEventListener('click', () => setDrop(!dropOpen()));
  // Capture phase: tester buttons re-render the panel, so check where the click landed before that happens.
  window.addEventListener('click', (e) => {
    if (dropOpen() && !drop.contains(e.target) && !dropBtn.contains(e.target)) setDrop(false);
  }, true);

  // Escape closes the dropdown first, then dialogs and pages, but never the docked slip.
  window.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (dropOpen()) { setDrop(false); dropBtn.focus(); e.stopImmediatePropagation(); return; }
    if (document.body.classList.contains('side-open')) { setSide(false); e.stopImmediatePropagation(); return; }
    if (!wide.matches) return;
    const last = ui.layer().lastElementChild;
    if (last && last.dataset.sheet === 'slip') e.stopImmediatePropagation();
  }, true);

  wide.addEventListener('change', () => app.renderChrome());
})(window.TO);
