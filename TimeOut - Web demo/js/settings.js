/* TimeOut web demo — menu drawer and Screentime & Settings (Screen 7). */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;
  const St = TO.state;

  const SECTIONS = {
    screentime: { title: 'Screen time', icon: 'hourglass' },
    status: { title: 'Tier & streak', icon: 'trophy' },
    sports: { title: 'Sports on Home', icon: 'grid' },
    notifications: { title: 'Notifications', icon: 'bell' },
    privacy: { title: 'What friends can see', icon: 'eye' },
    account: { title: 'Account', icon: 'user' },
    tester: { title: 'Tester tools', icon: 'flask' },
  };

  // ---------- Drawer ----------
  function openDrawer() {
    closeDrawer();
    const wl = St.wallet();
    const wrap = document.createElement('div');
    wrap.dataset.drawer = '1';
    wrap.style.cssText = 'position:absolute;inset:0';
    const item = (key, sub) => `<button class="dn ${key === 'tester' ? 'dn-tester' : ''}" data-act="settings" data-section="${key}">${icon(SECTIONS[key].icon, 20)}${SECTIONS[key].title}${sub ? `<span class="sub">${sub}</span>` : ''}</button>`;
    wrap.innerHTML = `<div class="scrim" data-act="close-drawer"></div><aside class="drawer" aria-label="Menu">
      <div class="drawer-head">${ui.avatar(TO.account.photo, 'lg')}<div class="grow" style="min-width:0"><b class="ellipsis" style="display:block;font-size:17px">@${esc(TO.account.username)}</b><div class="small muted ellipsis">${esc(TO.account.email)}</div>${TO.account.server ? `<div class="tiny faint ellipsis">Login #${TO.account.server.loginCount} · from the database</div>` : ''}<div style="margin-top:6px">${ui.tierBadge(wl.tier.id, true)}</div></div></div>
      <nav>
        ${item('screentime', `${wl.phoneLeft} min left`)}
        ${item('status', wl.streak ? `${wl.streak}-day streak` : '')}
        ${item('sports')}
        ${item('notifications')}
        ${item('privacy')}
        ${item('account')}
        <button class="dn" data-act="how">${icon('help', 20)}How TimeOut works</button>
        <div class="divider" style="margin:8px 12px"></div>
        ${item('tester')}
        <button class="dn" data-act="logout">${icon('logout', 20)}Log out</button>
      </nav></aside>`;
    ui.layer().appendChild(wrap);
  }
  function closeDrawer() { ui.layer().querySelectorAll('[data-drawer]').forEach((d) => d.remove()); }

  // ---------- Sections ----------
  const listRow = (ic, title, sub, right, attrs = '') => `<label class="list-row" ${attrs}><span class="lr-icon">${icon(ic, 17)}</span><span class="lr-main"><div class="lr-title">${title}</div>${sub ? `<div class="lr-sub">${sub}</div>` : ''}</span>${right}</label>`;
  const brow = (label, value, cls = '') => `<div class="spread small"><span class="muted">${label}</span><b class="num ${cls}">${value}</b></div>`;

  function screentime() {
    const wl = St.wallet();
    const s = TO.data.settings;
    const usedPct = Math.min(100, (wl.used / Math.max(wl.todayLimit, 1)) * 100);
    const overridesLeft = TO.RULES.maxOverrides - wl.overridesUsed;
    return `
      <div class="card stack-s">
        <h2 style="margin:0;font-size:17px">How your screen time works</h2>
        <div class="how-card"><span class="n">1</span><div><h3>${TO.RULES.daily} betting minutes a day</h3><p>Your betting balance starts at ${TO.RULES.daily} minutes${wl.tier.bonus ? ` (plus ${wl.tier.bonus} from your ${esc(wl.tier.title)} tier)` : ''} and resets at midnight, your local time.</p></div></div>
        <div class="how-card"><span class="n">2</span><div><h3>You bet tomorrow's phone time</h3><p>Every minute you win is added to tomorrow's limit. Every minute you lose comes off it.</p></div></div>
        <div class="how-card"><span class="n">3</span><div><h3>The math</h3><p>Tomorrow's limit = ${TO.RULES.daily} min + today's bet results − emergency unlock penalties.</p></div></div>
      </div>

      <div class="card stack-s">
        <div class="spread"><h2 style="margin:0;font-size:17px">Today</h2><span class="tiny faint bold">Resets in ${ui.countdownEl(TO.nextMidnight())}</span></div>
        ${brow('Base limit', `${TO.RULES.daily} min`)}
        ${brow("Yesterday's bets", TO.signedMin(wl.yesterdayNet), wl.yesterdayNet > 0 ? 'green' : wl.yesterdayNet < 0 ? 'red' : '')}
        ${wl.penaltyToday ? brow('Emergency unlock penalty', `−${wl.penaltyToday} min`, 'red') : ''}
        ${s.minLimit && TO.RULES.daily + wl.yesterdayNet - wl.penaltyToday < s.minLimit ? brow('Raised to your minimum', `${s.minLimit} min`) : ''}
        ${wl.emergencyToday ? brow('Emergency unlocks used', `+${wl.emergencyToday} min`, 'yellow') : ''}
        <hr class="divider">
        ${brow('Phone time allowed today', `${wl.todayLimit} min`)}
        <div class="bar" style="height:8px"><i style="width:${usedPct}%;background:${wl.appsLocked ? 'var(--loss)' : usedPct > 80 ? 'var(--warn)' : 'var(--accent)'}"></i></div>
        <div class="spread tiny bold"><span class="muted">${wl.used} min used on locked apps</span><span class="${wl.appsLocked ? 'red' : ''}">${s.enforce ? `${wl.phoneLeft} min left` : 'Limits are off'}</span></div>
      </div>

      <div class="card stack-s">
        <h2 style="margin:0;font-size:17px">Tomorrow, so far</h2>
        ${brow('Base limit', `${TO.RULES.daily} min`)}
        ${brow("Today's settled bets", TO.signedMin(wl.todayNet), wl.todayNet > 0 ? 'green' : wl.todayNet < 0 ? 'red' : '')}
        ${wl.penaltyTomorrow ? brow('Emergency unlock penalty', `−${wl.penaltyTomorrow} min`, 'red') : ''}
        <hr class="divider">
        ${brow("Tomorrow's phone time", `${wl.tomorrowLimit} min`, wl.tomorrowLimit > TO.RULES.daily ? 'green' : wl.tomorrowLimit < TO.RULES.daily ? 'red' : '')}
        ${wl.atRisk ? `<div class="tiny faint">${wl.atRisk} min in open bets will change this when they settle.</div>` : ''}
      </div>

      <div class="card stack-s" style="border-color:rgba(255,201,64,.35)">
        <div class="row"><span class="lr-icon" style="width:36px;height:36px;border-radius:10px;display:grid;place-items:center;background:var(--warn-soft);color:var(--warn)">${icon('unlock', 18)}</span><div class="grow"><h2 style="margin:0;font-size:17px">Emergency unlock</h2><div class="small muted">${overridesLeft} of ${TO.RULES.maxOverrides} left today</div></div></div>
        <div class="small muted">Need your phone right now? Get ${TO.RULES.overrideMinutes} more minutes today. It costs ${TO.RULES.overridePenalty} minutes from tomorrow's limit and resets your clean streak.</div>
        <button class="btn warn" data-act="emergency" ${overridesLeft > 0 ? '' : 'disabled'}>${overridesLeft > 0 ? `Unlock ${TO.RULES.overrideMinutes} minutes now` : 'No unlocks left today'}</button>
      </div>

      <div class="stack-s">
        <div class="eyebrow">Controls</div>
        <div class="list">
          ${listRow('shield', 'Enforce app limits', 'Blocks your locked apps when today\'s phone time runs out', ui.switchEl('set-enforce', s.enforce, 'data-change="set-enforce"'), 'for="set-enforce"')}
          <button class="list-row" data-act="locked-apps"><span class="lr-icon">${icon('lock', 17)}</span><span class="lr-main"><div class="lr-title">Locked apps & sites</div><div class="lr-sub">${s.lockedApps.length} locked · ${St.lockPoints()} lock points</div></span>${icon('chevR', 18, 'chev')}</button>
          <div class="list-row" style="flex-wrap:wrap"><span class="lr-icon">${icon('clock', 17)}</span><span class="lr-main"><div class="lr-title">Minimum phone time per day</div><div class="lr-sub">Losses can't push your limit below this</div></span><div class="seg" style="width:100%;margin-top:4px">${[0, 15, 30].map((v) => `<button class="${s.minLimit === v ? 'on' : ''}" data-act="set-minlimit" data-v="${v}">${v ? `${v} min` : 'None'}</button>`).join('')}</div></div>
          <div class="list-row" style="flex-wrap:wrap"><span class="lr-icon">${icon('bell', 17)}</span><span class="lr-main"><div class="lr-title">Warn me when phone time is low</div><div class="lr-sub">Shows a heads-up before apps lock</div></span><div class="seg" style="width:100%;margin-top:4px">${[5, 10, 15].map((v) => `<button class="${s.lowWarn === v ? 'on' : ''}" data-act="set-lowwarn" data-v="${v}">${v} min left</button>`).join('')}</div></div>
        </div>
        <div class="tiny faint">Changes to limits ask you to confirm first, so nothing changes by accident.</div>
      </div>`;
  }

  function status() {
    const wl = St.wallet();
    const t = wl.tier;
    const next = St.TIERS[St.TIERS.indexOf(t) + 1];
    const ladder = St.TIERS.slice(1).map((r) => {
      const reached = St.TIERS.indexOf(t) >= St.TIERS.indexOf(r);
      return `<div class="row" style="align-items:flex-start"><span style="color:${reached ? r.color : 'var(--muted)'};margin-top:1px">${icon(reached ? 'check' : r.icon, 18)}</span><div class="grow"><div class="row-s"><b style="${reached ? '' : 'color:var(--text-2)'}">${esc(r.title)}</b><span class="tiny faint bold">${r.min}+ pts</span></div><div class="small ${reached ? 'muted' : 'faint'}">${St.tierPerks(r).join(' · ')}</div></div></div>`;
    }).join('');
    const ms = St.nextStreakMilestone(wl.streak);
    return `<div class="card stack">
        <div class="spread"><h2 style="margin:0;font-size:17px">Your tier</h2>${ui.tierBadge(t.id)}</div>
        ${next ? `<div class="stack-s"><div class="spread small"><b>${wl.points} lock point${wl.points === 1 ? '' : 's'}</b><span class="muted">${next.min - wl.points} more for ${esc(next.title)}</span></div><div class="bar"><i style="width:${Math.min(100, ((wl.points - t.min) / (next.min - t.min)) * 100)}%;background:${next.color}"></i></div></div>` : `<div class="bold" style="color:${t.color}">Top tier. ${wl.points} lock points.</div>`}
        ${!TO.data.settings.enforce ? `<div class="note warn">${icon('info', 15)}<span>App limits are off, so your lock points don't count. Turn them on in Screen time.</span></div>` : ''}
        <div class="stack-s">${ladder}</div>
        <div class="tiny faint">Lock more of your real screen time to climb. Apps and websites are 1 point; whole categories (like Social) are 3.</div>
        <button class="btn ghost sm" data-act="locked-apps">${icon('lock', 16)} Choose locked apps</button>
      </div>
      <div class="card stack-s">
        <div class="spread"><div class="row-s">${icon('flame', 20, wl.streak ? 'yellow' : 'faint')}<b style="font-size:16px">${wl.streak ? `${wl.streak}-day clean streak` : 'No clean streak yet'}</b></div>${wl.multiplier > 1 ? `<span class="tag green" style="height:24px;font-size:12px">Wins ${St.fmtMult(wl.multiplier)}</span>` : ''}</div>
        ${ms ? `<div class="bar"><i style="width:${(wl.streak / ms.days) * 100}%;background:var(--warn)"></i></div><div class="small muted bold">${ms.days - wl.streak} more clean day${ms.days - wl.streak === 1 ? '' : 's'} for ${St.fmtMult(ms.mult)} winnings.</div>` : '<div class="small green bold">Max multiplier reached. Keep it going.</div>'}
        <div class="small muted">A clean day means limits were on, you stayed under your phone time, and you didn't use an emergency unlock. Winnings get ×1.1 at 3 days and ×1.25 at 7. An emergency unlock resets the streak.</div>
      </div>`;
  }

  function sports() {
    const s = TO.data.settings;
    const row = (id, title, sub, checked, change) => listRow('grid', title, sub, ui.switchEl(`sp-${id}`, checked, `data-change="${change}" data-id="${id}"`), `for="sp-${id}"`).replace(`<span class="lr-icon">${icon('grid', 17)}</span>`, `<span class="sport-opt"><span class="sq">${esc(id === 'pred' ? 'PRED' : id === 'todo' ? 'TODO' : S.LEAGUES[id] ? S.LEAGUES[id].short : '')}</span></span>`);
    return `<div class="small muted">Choose what shows up on your Home feed. You can change this any time.</div>
      <div class="list">${S.LEAGUE_ORDER.filter((l) => l !== 'sim').map((l) => row(l, esc(S.LEAGUES[l].title), `${S.LEAGUES[l].sport[0].toUpperCase()}${S.LEAGUES[l].sport.slice(1)}`, s.sports.includes(l), 'set-sport')).join('')}</div>`;
  }

  function notifications() {
    const n = TO.data.settings.notify;
    const row = (k, t, sub, ic) => listRow(ic, t, sub, ui.switchEl(`nt-${k}`, n[k], `data-change="set-notify" data-k="${k}"`), `for="nt-${k}"`);
    return `<div class="small muted">In the demo these show as banners at the top of the screen.</div><div class="list">
      ${row('settled', 'Bet results', 'When a bet wins, loses or is voided', 'ticket')}
      ${row('odds', 'Odds changes', 'When odds move on a pick in your bet slip', 'trend')}
      ${row('friends', 'Friend requests', 'When someone adds or accepts you', 'userPlus')}
      ${row('challenges', 'Bet challenges', 'When a friend challenges or accepts a bet', 'target')}
      ${row('lowTime', 'Low phone time', 'Before your locked apps close', 'phone')}
    </div>`;
  }

  function privacy() {
    const p = TO.data.settings.privacy;
    const row = (k, t, sub, ic) => listRow(ic, t, sub, ui.switchEl(`pv-${k}`, p[k], `data-change="set-privacy" data-k="${k}"`), `for="pv-${k}"`);
    return `<div class="small muted">Friends only see what you turn on here. Anything off shows as "Private" to them.</div><div class="list">
      ${row('record', 'My record', 'Wins and losses', 'chart')}
      ${row('minutes', 'Minutes won or lost', 'Your leaderboard number', 'hourglass')}
      ${row('bets', 'My open bets', 'Picks you currently have open', 'ticket')}
    </div>`;
  }

  let acctErr = {};
  const fmtStamp = (iso) => (iso ? `${TO.fmtDate(Date.parse(iso))}, ${TO.fmtTime(Date.parse(iso))}` : 'Never');

  /** Values read from PostgreSQL through GET /api/auth/me — the login vertical slice. */
  function serverAccountCard(s) {
    const line = (k, v, id) => `<div class="spread"><span class="muted">${k}</span><b${id ? ` id="${id}"` : ''}>${esc(String(v))}</b></div>`;
    return `<div class="card stack-s" id="db-account">
      <div class="row-s">${icon('check', 16)}<b>Connected to Supabase</b></div>
      ${line('User ID', s.id)}
      ${line('Member since', TO.fmtDate(Date.parse(s.createdAt)))}
    </div>`;
  }

  function account() {
    const a = TO.account;
    if (TO.api.online && a.server) {
      return `<div class="photo-pick"><span class="ph"><img src="${esc(a.photo)}" alt="Profile photo"></span><div><b>@${esc(a.username)}</b><div class="small muted">${esc(a.email)}</div></div></div>
        ${serverAccountCard(a.server)}
        <div class="card stack">
          <h2 style="margin:0;font-size:17px">Profile</h2>
          ${ui.field({ id: 'acct-username', label: 'Username', value: a.username, err: acctErr.username, attrs: 'autocapitalize="off" spellcheck="false"' })}
          ${ui.field({ id: 'acct-email', label: 'Email', type: 'email', value: a.email, err: acctErr.email })}
          <button class="btn primary" data-act="acct-save">Save changes</button>
        </div>
        <div class="card stack">
          <h2 style="margin:0;font-size:17px">Change password</h2>
          ${ui.field({ id: 'acct-new', label: 'New password', type: 'password', err: acctErr.newPassword, hint: 'At least 8 characters' })}
          <button class="btn ghost" data-act="acct-pw">Update password</button>
        </div>
        <div class="stack-s"><button class="btn ghost" data-act="logout">${icon('logout', 18)} Log out</button></div>`;
    }
    return `<div class="photo-pick"><label class="ph" for="acct-photo" style="cursor:pointer"><img src="${esc(a.photo)}" alt="Profile photo"><span class="cam">${icon('camera', 15)}</span></label><div><b>Profile photo</b><div class="small muted">Tap the photo to change it.</div></div><input type="file" id="acct-photo" accept="image/*" class="sr" data-change="acct-photo"></div>
      <div class="card stack">
        ${ui.field({ id: 'acct-username', label: 'Username', value: a.username, err: acctErr.username, attrs: 'autocapitalize="off" spellcheck="false"' })}
        ${ui.field({ id: 'acct-email', label: 'Email', type: 'email', value: a.email, err: acctErr.email })}
        <button class="btn primary" data-act="acct-save">Save changes</button>
      </div>
      <div class="card stack">
        <h2 style="margin:0;font-size:17px">Change password</h2>
        ${ui.field({ id: 'acct-cur', label: 'Current password', type: 'password', err: acctErr.currentPassword })}
        ${ui.field({ id: 'acct-new', label: 'New password', type: 'password', err: acctErr.newPassword, hint: 'At least 8 characters' })}
        <button class="btn ghost" data-act="acct-pw">Update password</button>
      </div>
      <div class="stack-s">
        <button class="btn ghost" data-act="logout">${icon('logout', 18)} Log out</button>
        <button class="btn quiet" style="color:var(--loss)" data-act="acct-delete">Delete account</button>
        <div class="tiny faint" style="text-align:center">Demo accounts are stored only in this browser.</div>
      </div>`;
  }

  function render(section) {
    const map = { screentime, status, sports, notifications, privacy, account, tester: () => TO.tester.panelHtml(true) };
    return { title: SECTIONS[section].title, body: map[section]() };
  }

  function openSection(section) {
    closeDrawer();
    acctErr = {};
    ui.openPage('settings', { render: () => render(section) });
    if (section === 'status') TO.tester.mark('tier');
  }

  // ---------- How it works ----------
  function howItWorks() {
    ui.sheet('how', {
      render: () => ({
        title: 'How TimeOut works',
        body: `<div class="how-card"><span class="n">1</span><div><h3>Bet screen time, not money</h3><p>You get ${TO.RULES.daily} betting minutes every day. They reset at midnight.</p></div></div>
          <div class="how-card"><span class="n">2</span><div><h3>Winning buys you phone time</h3><p>Win a bet and the minutes you win are added to tomorrow's phone time. Lose and they come off it.</p></div></div>
          <div class="how-card"><span class="n">3</span><div><h3>Bets settle on their own</h3><p>When a game ends, your bet pays out within minutes. Postponed games are voided and you get your stake back.</p></div></div>
          <div class="how-card"><span class="n">4</span><div><h3>Out of minutes? Wait for midnight</h3><p>At 0 minutes, betting locks until the reset. Emergency unlocks exist, but they cost you tomorrow.</p></div></div>
          <div class="how-card"><span class="n">5</span><div><h3>Play friends for anything</h3><p>Send a bet to a friend and put something else on the line, like "loser does the dishes".</p></div></div>`,
        foot: `<button class="btn primary full" data-act="close-sheet" data-name="how">Got it</button>`,
      }),
    });
  }

  // ---------- Locked apps ----------
  let lockDraft = [];
  function lockedAppsSheet() {
    lockDraft = TO.data.settings.lockedApps.slice();
    ui.sheet('locked', {
      tall: true,
      render: () => {
        const pts = lockDraft.reduce((s, id) => s + St.LOCKABLE.find((x) => x.id === id).pts, 0);
        const t = St.tierForPoints(TO.data.settings.enforce ? pts : 0);
        const group = (kind) => St.LOCKABLE.filter((x) => x.kind === kind).map((x) => `<button class="list-row" data-act="lock-toggle" data-id="${x.id}"><span class="lr-icon" style="background:${x.color}22;color:${x.color}">${icon(kind === 'Category' ? 'grid' : kind === 'Website' ? 'globe' : 'phone', 17)}</span><span class="lr-main"><div class="lr-title">${esc(x.name)}</div><div class="lr-sub">${x.note ? `${esc(x.note)} · ` : ''}${x.pts} pt${x.pts === 1 ? '' : 's'}</div></span><span class="checkbox ${lockDraft.includes(x.id) ? 'on' : ''}">${icon('check', 15)}</span></button>`).join('');
        return {
          title: 'Locked apps & sites',
          body: `<div class="small muted">These are the apps TimeOut blocks when your phone time runs out. The more you lock, the higher your tier.</div>
            <div class="card tight spread"><span class="bold">${pts} lock points</span>${ui.tierBadge(t.id)}</div>
            <div class="eyebrow">Categories · 3 pts each</div><div class="list">${group('Category')}</div>
            <div class="eyebrow">Apps · 1 pt each</div><div class="list">${group('App')}</div>
            <div class="eyebrow">Websites · 1 pt each</div><div class="list">${group('Website')}</div>`,
          foot: `<button class="btn primary full" data-act="lock-save">Save locked apps</button>`,
        };
      },
    });
  }

  // ---------- Actions ----------
  const A = TO.actions;
  A.menu = () => openDrawer();
  A['close-drawer'] = () => closeDrawer();
  A.settings = (el) => { ui.closeAllSheets(); openSection(el.dataset.section); };
  A.how = () => { closeDrawer(); howItWorks(); };
  A['locked-apps'] = () => lockedAppsSheet();
  A['lock-toggle'] = (el) => {
    const id = el.dataset.id;
    lockDraft = lockDraft.includes(id) ? lockDraft.filter((x) => x !== id) : [...lockDraft, id];
    ui.refreshSheet('locked');
  };
  A['lock-save'] = async () => {
    const before = TO.data.settings.lockedApps;
    const removed = before.filter((x) => !lockDraft.includes(x));
    const oldTier = St.tier();
    const newTier = St.tierForPoints(TO.data.settings.enforce ? lockDraft.reduce((s, id) => s + St.LOCKABLE.find((x) => x.id === id).pts, 0) : 0);
    const body = `${lockDraft.length} apps, sites and categories will be locked when your phone time runs out.${newTier.id !== oldTier.id ? `<br><br>Your tier changes from <b>${esc(oldTier.title)}</b> to <b>${esc(newTier.title)}</b>.` : ''}${removed.length ? '<br><br>Unlocked apps stop counting right away.' : ''}`;
    if (!(await ui.confirm({ title: 'Update locked apps?', body, confirm: 'Save' }))) return;
    St.setSetting('lockedApps', lockDraft.slice());
    ui.closeSheet('locked');
    ui.toast({ kind: 'win', title: 'Locked apps updated', msg: `You're ${St.tier().title} now.` });
    refresh();
  };
  A.emergency = async () => {
    const wl = St.wallet();
    const ok = await ui.confirm({
      title: `Unlock ${TO.RULES.overrideMinutes} minutes now?`,
      body: `You'll get ${TO.RULES.overrideMinutes} more minutes of phone time today.<br><br><b style="color:var(--loss)">It costs ${TO.RULES.overridePenalty} minutes from tomorrow's limit</b>${wl.streak ? ` and ends your ${wl.streak}-day clean streak` : ''}. You have ${TO.RULES.maxOverrides - wl.overridesUsed} of ${TO.RULES.maxOverrides} unlocks left today.`,
      confirm: 'Unlock now',
      tone: 'warn',
    });
    if (!ok) return;
    try {
      St.useEmergencyUnlock();
      ui.toast({ kind: 'warn', title: `+${TO.RULES.overrideMinutes} min unlocked`, msg: `Tomorrow's limit dropped by ${TO.RULES.overridePenalty} min.` });
      TO.tester.mark('emergency');
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      ui.toast({ kind: 'loss', title: 'No unlocks left', msg: e.message });
    }
    refresh();
  };
  A['set-minlimit'] = async (el) => {
    const v = Number(el.dataset.v);
    if (v === TO.data.settings.minLimit) return;
    const ok = await ui.confirm({ title: 'Change your minimum phone time?', body: v ? `No matter how many bets you lose, you'll always get at least <b>${v} minutes</b> of phone time a day.` : 'Losses will be able to take your phone time all the way to 0 minutes.', confirm: 'Change it' });
    if (!ok) return;
    St.setSetting('minLimit', v);
    refresh();
  };
  A['set-lowwarn'] = (el) => { St.setSetting('lowWarn', Number(el.dataset.v)); refresh(); };
  A.logout = async () => {
    closeDrawer();
    if (!(await ui.confirm({ title: 'Log out?', body: 'Your bets and settings stay saved on this device.', confirm: 'Log out' }))) return;
    TO.slip.clear();
    if (TO.api.online) await TO.api.logout();
    St.logout();
    TO.app.boot();
  };
  A['acct-save'] = async () => {
    acctErr = {};
    try {
      const patch = { username: document.getElementById('acct-username').value, email: document.getElementById('acct-email').value };
      if (TO.account.server) await TO.api.updateProfile(patch);
      St.updateAccount(patch);
      ui.toast({ kind: 'win', title: 'Account saved' });
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      acctErr = e.fields || {};
    }
    refresh();
  };
  A['acct-pw'] = async () => {
    acctErr = {};
    try {
      const newPassword = document.getElementById('acct-new').value;
      const invalid = St.validatePassword(newPassword);
      if (invalid) throw new TO.AppError('invalid', invalid, { fields: { newPassword: invalid } });
      if (TO.account.server) await TO.api.updateProfile({ password: newPassword });
      else St.updateAccount({ currentPassword: document.getElementById('acct-cur').value, newPassword });
      ui.toast({ kind: 'win', title: 'Password updated' });
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      acctErr = e.fields || {};
    }
    refresh();
  };
  A['acct-delete'] = async () => {
    if (!(await ui.confirm({ title: 'Delete your account?', body: 'This removes your account, bets and friends from this device. It can\'t be undone.', confirm: 'Delete account', danger: true }))) return;
    St.deleteAccount();
    TO.slip.clear();
    TO.app.boot();
  };

  const C = TO.changes;
  C['set-enforce'] = async (el) => {
    const want = el.checked;
    el.checked = !want;
    const ok = await ui.confirm(want
      ? { title: 'Turn app limits on?', body: 'Your locked apps will close when today\'s phone time runs out.', confirm: 'Turn on' }
      : { title: 'Turn app limits off?', body: 'Your locked apps won\'t close anymore. Your tier drops to Rookie and today won\'t count as a clean day.', confirm: 'Turn off', danger: true });
    if (!ok) return;
    St.setSetting('enforce', want);
    refresh();
  };
  C['set-sport'] = (el) => {
    const id = el.dataset.id;
    const cur = TO.data.settings.sports;
    St.setSetting('sports', el.checked ? S.LEAGUE_ORDER.filter((l) => l !== 'sim' && (cur.includes(l) || l === id)) : cur.filter((l) => l !== id && l !== 'sim'));
    if (!el.checked && TO.data.feedFilter === id) TO.data.feedFilter = 'all';
    TO.tester.mark('sports');
    TO.app.render();
  };
  C['set-notify'] = (el) => St.setSetting(`notify.${el.dataset.k}`, el.checked);
  C['set-privacy'] = (el) => St.setSetting(`privacy.${el.dataset.k}`, el.checked);
  C['acct-photo'] = async (el) => {
    try {
      const url = await ui.readPhoto(el.files[0]);
      if (TO.account.server) await TO.api.updateProfile({ photoUrl: url });
      St.updateAccount({ photo: url });
      ui.toast({ kind: 'win', title: 'Photo updated' });
      refresh();
      TO.app.renderChrome();
    } catch (e) { ui.toast({ kind: 'loss', title: e.message }); }
  };

  function refresh() {
    ui.refreshPage('settings');
    TO.app.render();
  }

  TO.views.settings = { openSection, howItWorks, closeDrawer, refresh };
})(window.TO);
