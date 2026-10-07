/* TimeOut web demo — tester console. Not part of the app: it lets testers trigger situations from the PRD on demand. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  const CHECKLIST = [
    ['login', 'Log in (demo account or your own)'],
    ['signup', 'Create an account with a photo'],
    ['place', 'Place a bet from Home in 3 taps or fewer'],
    ['odds', 'See odds change on your slip and accept the new odds'],
    ['overstake', 'Try to stake more minutes than you have'],
    ['settle', 'Watch a bet settle (finish a live game)'],
    ['void', 'See a postponed game void a bet'],
    ['zero', 'Run your balance to 0 and see the midnight countdown'],
    ['midnight', 'Jump to midnight and check tomorrow\'s limit'],
    ['share', 'Share a bet as an image'],
    ['friend', 'Send or accept a friend bet with a custom stake'],
    ['search', 'Search a username that doesn\'t exist'],
    ['team', 'Create a team with start and end dates'],
    ['emergency', 'Use an emergency unlock'],
    ['todo', 'Place a to-do parlay'],
    ['pred', 'Bet on a prediction market'],
    ['sports', 'Change which sports show on Home'],
    ['offday', 'Turn on "no real games" and find the Sim League'],
    ['tier', 'Check your tier and clean streak'],
  ];
  const KEY = 'timeout.checklist';
  const done = () => TO.store.get(KEY, {});

  function mark(k) {
    const d = done();
    if (d[k]) return;
    d[k] = TO.now();
    TO.store.set(KEY, d);
    render();
  }

  function panelHtml(inApp) {
    const loggedIn = !!TO.account;
    const d = done();
    const off = TO.store.get('timeout.offDay', false);
    const now = new Date(TO.now());
    const shifted = Math.round(TO.clock.offset / TO.MIN);
    const dis = loggedIn ? '' : 'disabled';
    const b = (act, ic, label, extra = '') => `<button class="tbtn ${extra}" data-act="${act}" ${dis}>${icon(ic, 15)}<span>${label}</span></button>`;
    return `${inApp ? `<div class="note warn">${icon('flask', 16)}<span>These tools aren't part of TimeOut. They let testers trigger situations from the spec without waiting.</span></div>` : ''}
      <div class="tgroup"><h3>Demo clock</h3>
        <div class="clockface"><span>${now.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })} <b>${now.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })}</b></span><span class="faint">${shifted ? `+${TO.fmtIn(TO.clock.offset)}` : 'real time'}</span></div>
        <div class="tgrid">
          ${b('t-skip', 'ff', 'Skip 5 min')}${b('t-skip15', 'ff', 'Skip 15 min')}
          ${b('t-1159', 'moon', 'Jump to 11:59 PM')}${b('t-midnight', 'moon', 'Jump past midnight')}
          <button class="tbtn wide" data-act="t-real">${icon('refresh', 15)}<span>Back to real time</span></button>
        </div>
      </div>
      <div class="tgroup"><h3>Games & odds</h3>
        <div class="tgrid">
          ${b('t-finish', 'check', 'Finish games I bet on', 'wide')}
          ${b('t-postpone', 'alert', 'Postpone a game I bet on', 'wide')}
          ${b('t-odds', 'trend', 'Move odds on my bet slip', 'wide')}
          <button class="tbtn wide ${off ? 'on' : ''}" data-act="t-offday">${icon('moon', 15)}<span>${off ? 'No real games today: ON' : 'Simulate a day with no real games'}</span></button>
        </div>
      </div>
      <div class="tgroup"><h3>Screen time</h3>
        <div class="tgrid">
          ${b('t-use', 'phone', 'Use phone +10 min')}${b('t-use30', 'phone', 'Use phone +30 min')}
          ${b('t-zero', 'lock', 'Set betting balance to 0', 'wide')}
        </div>
      </div>
      <div class="tgroup"><h3>Friends</h3>
        <div class="tgrid">
          ${b('t-fr', 'userPlus', 'Get a friend request')}${b('t-ch', 'target', 'Get a bet challenge')}
        </div>
      </div>
      <div class="tgroup"><h3>Data</h3>
        <div class="tgrid">
          ${b('t-reset', 'refresh', 'Reset my bets & wallet', 'wide')}
          <button class="tbtn wide" data-act="t-wipe">${icon('trash', 15)}<span>Erase every account on this device</span></button>
        </div>
        <div class="creds">Demo login: <b>${esc(TO.state.DEMO.username)}</b> / <b>${esc(TO.state.DEMO.password)}</b></div>
      </div>
      <div class="tgroup"><h3>Test checklist · ${Object.keys(d).length}/${CHECKLIST.length}</h3>
        ${CHECKLIST.map(([k, t]) => `<button class="check-item ${d[k] ? 'done' : ''}" data-act="t-check" data-k="${k}"><span class="checkbox ${d[k] ? 'on' : ''}">${icon('check', 12)}</span><span>${esc(t)}</span></button>`).join('')}
        <button class="tbtn" data-act="t-check-clear">${icon('x', 15)}<span>Clear checklist</span></button>
      </div>`;
  }

  function render() {
    const host = document.getElementById('tester-body');
    if (host) {
      const st = host.scrollTop;
      host.innerHTML = panelHtml(false);
      host.scrollTop = st;
    }
    if (ui.pageOpen('settings') && document.querySelector('[data-page="settings"] .page-top .t').textContent === 'Tester tools') ui.refreshPage('settings');
  }

  function myGames() {
    const ids = new Set();
    TO.data.bets.filter((b) => b.status === 'open').forEach((b) => b.legs.forEach((l) => { if (l.gameId && l.result === 'pending') ids.add(l.gameId); }));
    return [...ids];
  }

  function after(msg) {
    TO.app.tick(true);
    if (msg) ui.toast(Object.assign({ kind: 'info' }, msg));
    render();
  }

  const A = TO.actions;
  A['t-skip'] = () => { TO.clock.add(5 * TO.MIN); after({ title: 'Skipped ahead 5 minutes' }); };
  A['t-skip15'] = () => { TO.clock.add(15 * TO.MIN); after({ title: 'Skipped ahead 15 minutes' }); };
  A['t-1159'] = () => {
    const target = TO.nextMidnight() - 60 * 1000;
    if (target > TO.now()) TO.clock.set(target);
    after({ title: 'It\'s 11:59 PM', msg: 'Watch the countdown hit zero.' });
  };
  A['t-midnight'] = () => {
    TO.clock.set(TO.nextMidnight() + 5000);
    after();
    mark('midnight');
  };
  A['t-real'] = () => {
    TO.clock.reset();
    // Moving back in time can't un-settle bets, so the wallet just follows the current day.
    after({ title: 'Back to real time' });
  };
  A['t-finish'] = () => {
    const ids = myGames().filter((id) => S.game(id).state !== 'postponed');
    if (!ids.length) { ui.toast({ kind: 'warn', title: 'No open game bets', msg: 'Place a bet on a game first.' }); return; }
    const now = TO.now();
    for (const id of ids) {
      const g = S.game(id, now);
      const warp = (S.overrides()[id] || {}).warp || 0;
      S.setOverride(id, { warp: warp + (g.end - now) + 1000 });
    }
    after({ title: `Finished ${ids.length} game${ids.length === 1 ? '' : 's'}`, msg: 'Bets settle within seconds.' });
    mark('settle');
  };
  A['t-postpone'] = () => {
    const ids = myGames().filter((id) => { const g = S.game(id); return g.state === 'scheduled' || g.state === 'live'; });
    const id = ids[0];
    if (!id) { ui.toast({ kind: 'warn', title: 'No open game bets', msg: 'Place a bet on a game that hasn\'t ended.' }); return; }
    S.setOverride(id, { state: 'postponed' });
    const g = S.game(id);
    after({ title: `${g.away.abbr} @ ${g.home.abbr} postponed`, msg: 'Bets on it are voided and stakes returned.' });
    mark('void');
  };
  A['t-odds'] = () => {
    const legs = TO.slip.legs.filter((l) => !l.ref.startsWith('pm-'));
    if (!legs.length) { ui.toast({ kind: 'warn', title: 'Add a game pick to your slip first', msg: 'Then tap this to move its odds.' }); return; }
    for (const l of legs) {
      const n = (S.overrides()[l.ref] || {}).nudge || 0;
      S.setOverride(l.ref, { nudge: n + (Math.random() < 0.5 ? -0.3 : 0.3) });
    }
    after({ title: 'Odds moved', msg: 'Your slip now asks you to accept the new odds.' });
  };
  A['t-offday'] = () => {
    const v = !TO.store.get('timeout.offDay', false);
    TO.store.set('timeout.offDay', v);
    if (v) { TO.data.feedFilter = 'all'; TO.state.save(); }
    TO.app.go('home');
    after({ title: v ? 'No real games today' : 'Real games are back' });
  };
  A['t-use'] = () => { TO.state.addUsage(10); after(); };
  A['t-use30'] = () => { TO.state.addUsage(30); after(); };
  A['t-zero'] = () => {
    const w = TO.data.wallet;
    w.balance = 0; w.lockedOut = true;
    TO.state.save();
    TO.app.go('home');
    after({ kind: 'loss', title: 'Betting balance is 0', msg: 'Betting is locked until midnight.' });
    mark('zero');
  };
  A['t-fr'] = () => {
    const candidates = TO.state.PEOPLE.filter((p) => TO.state.relation(p.username) === 'none');
    const p = candidates[Math.floor(Math.random() * candidates.length)];
    if (!p) { ui.toast({ kind: 'warn', title: 'Everyone is already your friend' }); return; }
    TO.data.requestsIn.push({ id: TO.uid('fr'), from: p.username, at: TO.now() });
    TO.state.save();
    after({ title: `@${p.username} sent you a friend request`, msg: 'See it in Social > Requests.' });
  };
  A['t-ch'] = () => {
    const from = TO.data.friends[Math.floor(Math.random() * TO.data.friends.length)] || 'mike_t';
    const ch = TO.state.incomingChallenge(from);
    if (!ch) { ui.toast({ kind: 'warn', title: 'No upcoming games to challenge on' }); return; }
    after({ title: `@${from} challenged you`, msg: `${ch.theirPick} · "${ch.terms}". See Social > Requests.` });
  };
  A['t-reset'] = async () => {
    if (!(await ui.confirm({ title: 'Reset your bets and wallet?', body: TO.account.demo ? 'The demo account goes back to its starting bets, friends and history.' : 'Your bets, wallet and streak start fresh. Friends and settings stay.', confirm: 'Reset', danger: true }))) return;
    TO.slip.clear();
    TO.store.set('timeout.gameOverrides', {});
    TO.state.resetMyData();
    ui.closeAllSheets();
    after({ title: 'Data reset' });
  };
  A['t-wipe'] = async () => {
    if (!(await ui.confirm({ title: 'Erase every account?', body: TO.api.online ? 'Logs you out and removes all bets and settings saved in this browser, then reloads. Accounts in the database stay (use npm run db:reset for those).' : 'Removes all TimeOut accounts, bets and settings saved in this browser, then reloads.', confirm: 'Erase everything', danger: true }))) return;
    try {
      Object.keys(localStorage).filter((k) => k.startsWith('timeout.')).forEach((k) => localStorage.removeItem(k));
    } catch (e) { /* ignore */ }
    location.reload();
  };
  A['t-check'] = (el) => {
    const d = done();
    if (d[el.dataset.k]) delete d[el.dataset.k]; else d[el.dataset.k] = TO.now();
    TO.store.set(KEY, d);
    render();
  };
  A['t-check-clear'] = () => { TO.store.set(KEY, {}); render(); };

  TO.tester = { mark, render, panelHtml };
})(window.TO);
