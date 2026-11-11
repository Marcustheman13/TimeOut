/* TimeOut web demo — Home (Screen 1). */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  const prevScores = {};
  const activeChallenge = new Map();

  const followed = () => TO.data.settings.sports?.length ? TO.data.settings.sports : S.REAL_LEAGUES;
  const offDay = () => TO.store.get('timeout.offDay', false);
  const activeFilter = () => ['pred', 'todo', 'sim', 'live'].includes(TO.data.feedFilter) ? 'all' : (TO.data.feedFilter || 'all');
  // The Live switch on its own line. It narrows whichever sport is picked.
  const liveOnly = () => !!TO.data.feedLive;
  const filterName = () => { const f = activeFilter(); return f === 'all' ? 'all sports' : f === 'ncaaf' ? 'College Football' : S.LEAGUES[f].short; };
  const sportsOnly = (challenge) => challenge.kind === 'race' || (challenge.kind === 'sports' && challenge.picks.every((pick) => pick.gameId && S.game(pick.gameId)?.league !== 'sim'));

  // Which day the board shows: 0 = today, 1 = tomorrow. Live games are always today.
  let feedDay = 0;
  const activeDay = () => (liveOnly() ? 0 : feedDay);

  function boardGames(day = activeDay(), peek = false) {
    return S.board(TO.now(), { offDay: offDay(), day, peek, leagues: S.LEAGUE_ORDER.filter((l) => l !== 'sim' && followed().includes(l)) }).filter((g) => !g.simulated && g.league !== 'sim');
  }

  function dayLabel(offset) {
    if (offset === 0) return 'Today';
    if (offset === 1) return 'Tomorrow';
    const d = new Date(TO.now() + offset * TO.DAY);
    return `${d.toLocaleDateString([], { weekday: 'short' })} ${d.getMonth() + 1}/${d.getDate()}`;
  }

  /** Today and tomorrow. Counts are games still to be played that day, in the sports being shown. */
  function dayBar(lead = '') {
    if (liveOnly() || TO.live.offline) return lead ? `<div class="hscroll day-bar" data-hkey="days">${lead}</div>` : '';
    const f = activeFilter();
    const chips = lead ? [lead] : [];
    for (let i = 0; i <= TO.live.days; i++) {
      const games = boardGames(i, true).filter((g) => g.state !== 'final' && (f === 'all' || g.league === f));
      const n = games.length;
      chips.push(`<button class="chip sm day-chip ${feedDay === i ? 'on' : ''}" data-act="feed-day" data-day="${i}" aria-pressed="${feedDay === i}">${esc(dayLabel(i))}${n ? `<span class="n">${n}</span>` : ''}</button>`);
    }
    return `<div class="hscroll day-bar" data-hkey="days" aria-label="Pick a day">${chips.join('')}</div>`;
  }

  function myOpenChallengeOn(ref) {
    return TO.data.challenges.filter((b) => b.status === 'open' && b.picks.some((l) => l.gameId === ref || l.predId === ref || l.raceId === ref));
  }

  // ---------- Wallet header (PRD: screen time + current pledges always at the top) ----------
  function walletCard(wl) {
    if (wl.lockedOut || wl.balance <= 0) {
      return `<div class="card wallet locked" style="border-color:rgba(255,90,95,.45)">
        <div class="lockhead">${icon('lock', 14)} OUT OF PLEDGE MINUTES</div>
        <div class="bold" style="margin-top:8px;font-size:16px">Pledges are paused. They reopen at midnight.</div>
        <div class="bigcd" style="margin-top:6px">${ui.countdownEl(TO.nextMidnight())}</div>
        <div class="small muted" style="margin-top:4px">Active challenges still resolve and update tomorrow's phone time.</div>
        ${statsRow(wl)}
      </div>`;
    }
    const pct = Math.min(100, (wl.balance / (TO.RULES.daily + wl.bonusToday)) * 100);
    return `<div class="card wallet">
      <div class="row-layout" style="align-items:flex-end">
        <div>
          <div class="row-layout" style="justify-content:flex-start;gap:8px"><div class="eyebrow">Available minutes today</div>${wl.bonusToday ? `<span class="tiny green bold">+${wl.bonusToday} min ${esc(wl.tier.title)} bonus included</span>` : ''}</div>
          <div class="big" style="margin-top:4px">${wl.balance}<small>min</small></div>
        </div>
        <div style="text-align:right">
          <div class="eyebrow" style="color:var(--faint)">Resets in</div>
          ${ui.countdownEl(TO.nextMidnight(), 'cd')}
        </div>
      </div>
      <div class="bar" style="margin-top:12px"><i style="width:${pct}%"></i></div>
      ${statsRow(wl)}
      <button class="explain" data-act="how">${icon('info', 14)} Pledges use tomorrow's phone time. How it works</button>
    </div>`;
  }

  function statsRow(wl) {
    const tomorrowDelta = wl.tomorrowLimit - TO.RULES.daily;
    const tColor = tomorrowDelta > 0 ? 'green' : tomorrowDelta < 0 ? 'red' : '';
    const pColor = wl.appsLocked ? 'red' : wl.phoneLeft <= TO.data.settings.lowWarn ? 'yellow' : '';
    return `<div class="wallet-stats">
      <div><b class="${pColor}">${TO.data.settings.enforce ? `${wl.phoneLeft} min` : 'Off'}</b><span>Phone time left</span></div>
      <div><b class="${wl.atRisk ? 'yellow' : ''}">${wl.atRisk} min</b><span>Committed to active challenges</span></div>
      <div><b class="${tColor}">${wl.tomorrowLimit} min</b><span>Tomorrow's limit</span></div>
    </div>`;
  }

  function statusStrip(wl) {
    const parts = [ui.tierBadge(wl.tier.id)];
    parts.push(`<span class="sp ${wl.streak ? 'yellow' : 'faint'}">${icon('flame', 14)}${wl.streak ? `${wl.streak}-day streak` : 'No streak yet'}</span>`);
    if (wl.multiplier > 1) parts.push(`<span class="sp green">${icon('trend', 14)}${TO.state.fmtMult(wl.multiplier)} wins</span>`);
    if (wl.boostsLeft > 0) parts.push(`<span class="sp blue">${icon('bolt', 14)}${wl.boostsLeft} boost${wl.boostsLeft === 1 ? '' : 's'}</span>`);
    return `<button class="status-strip" data-act="settings" data-section="status">${parts.join('')}<span style="margin-left:auto" class="faint">${icon('chevR', 16)}</span></button>`;
  }

  function miniChallenge(challenge) {
    const title = challenge.kind === 'todo' ? `To-do Combo Goal (${challenge.picks.length})` : challenge.picks.length > 1 ? `${challenge.picks.length}-pick Combo Goal` : challenge.picks[0].label;
    let line = '';
    const pick = challenge.picks.find((l) => l.result === 'pending') || challenge.picks[0];
    if (challenge.kind === 'todo') line = `${challenge.picks.filter((l) => l.result === 'won').length}/${challenge.picks.length} done · due midnight`;
    else if (pick.kind === 'pred') line = `Resolves in ${TO.fmtIn(pick.start - TO.now())}`;
    else if (pick.kind === 'race') {
      const race = TO.races.get(pick.raceId);
      line = race && race.status === 'running' ? `<span class="live">LIVE</span> Virtual Race #${race.number}` : `Virtual Race #${String(pick.raceId).replace('race-', '')} · ${race && race.status === 'final' ? 'Finished' : 'Starting soon'}`;
    }
    else {
      const g = S.game(pick.gameId);
      if (!g) line = 'Loading the latest score…';
      else if (g.state === 'live') line = `<span class="live">LIVE</span> ${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore} · ${esc(g.clock)}`;
      else if (g.state === 'scheduled') line = `${g.away.abbr} @ ${g.home.abbr} · ${TO.fmtTime(g.start)}`;
      else line = `${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore} · ${esc(g.statusText)}`;
    }
    const bottom = `<div class="row-s small bold"><span class="muted">${challenge.pledgeMinutes} min</span>${icon('chevR', 12)}<span class="green">${Math.round(challenge.pledgeMinutes * challenge.decimal) - challenge.pledgeMinutes > 0 ? `win ${Math.round((Math.round(challenge.pledgeMinutes * challenge.decimal) - challenge.pledgeMinutes) * (challenge.multiplier || 1))} min` : ''}</span></div>`;
    return `<button class="card tight mini-challenge" data-act="tab" data-tab="challenges">
      <div class="row-layout"><span class="t ellipsis">${esc(title)}</span><span class="display muted" style="font-size:15px">${TO.multiplierText(TO.pointValue.fromDecimal(challenge.decimal))}</span></div>
      <div class="small muted row-s ellipsis" style="font-weight:600">${line}</div>
      <div style="margin-top:auto">${bottom}</div>
    </button>`;
  }

  function openChallengesStrip() {
    const open = TO.data.challenges.filter((b) => b.status === 'open' && sportsOnly(b)).sort((a, b) => b.placedAt - a.placedAt);
    return `<div class="stack-s open-challenges">
      <div class="section-title"><div class="row-s"><h2>Active challenges</h2><span class="count-pill ${open.length ? '' : 'off'}">${open.length}</span></div>${open.length ? `<button class="link-btn" data-act="tab" data-tab="challenges">See all</button>` : ''}</div>
      ${open.length
        ? `<div class="hscroll mini-challenges" data-hkey="minichallenges">${open.map(miniChallenge).join('')}</div>`
        : `<div class="card tight small muted" style="margin:0 16px">No active challenges. Choose a matchup target below to begin.</div>`}
    </div>`;
  }

  // ---------- Filters ----------
  function filterBar(games) {
    const f = activeFilter();
    const on = liveOnly();
    // With Live on, each sport's number is how many games it has live right now.
    const today = boardGames(0, true);
    const liveNow = today.filter((g) => g.state === 'live' && (f === 'all' || g.league === f)).length;
    const chip = (key, label, n, ic) => `<button class="chip ${f === key ? 'on' : ''}" data-act="filter" data-f="${key}">${ic ? icon(ic, 14) : ''}${esc(label)}${n ? `<span class="n">${n}</span>` : ''}</button>`;
    const chips = [chip('all', 'All', 0, 'grid')];
    for (const l of S.LEAGUE_ORDER) {
      if (l === 'sim' || !followed().includes(l)) continue;
      const n = on ? today.filter((g) => g.league === l && g.state === 'live').length : games.filter((g) => g.league === l && g.state !== 'final').length;
      chips.push(chip(l, l === 'ncaaf' ? 'College Football' : S.LEAGUES[l].short === 'SIM' ? 'Sim League' : S.LEAGUES[l].short, n));
    }
    chips.push(`<button class="chip dashed" data-act="settings" data-section="sports">${icon('sliders', 14)}Edit</button>`);
    const cfb = (f === 'ncaaf' || f === 'all') && !TO.live.offline ? `<label class="cfb-select-label" for="cfb-group">College Football</label><select id="cfb-group" class="cfb-select" aria-label="College football conference">${TO.live.groups.map(([id, name]) => `<option value="${id}" ${TO.live.selectedGroup() === id ? 'selected' : ''}>${esc(name)}</option>`).join('')}</select>` : '';
    const liveTile = `<button class="live-tile ${on ? 'on' : ''}" data-act="feed-live" aria-pressed="${on}" aria-label="Live games only, ${liveNow} live now in ${esc(filterName())}"><i></i>Live${liveNow ? `<span class="n">${liveNow}</span>` : ''}</button>`;
    return `<div class="filterbar"><div class="hscroll" data-hkey="filters">${chips.join('')}</div>${dayBar(liveTile)}${cfb}</div>`;
  }

  // ---------- Game card ----------
  function scoreCls(g, side) {
    const key = `${g.id}-${side}`;
    const val = side === 'home' ? g.homeScore : g.awayScore;
    const changed = prevScores[key] !== undefined && prevScores[key] !== val;
    prevScores[key] = val;
    return changed ? 'bump' : '';
  }

  function gameCard(g) {
    const o = S.pointValue(g.id);
    const bettable = (g.state === 'live' || g.state === 'scheduled') && !o.suspended;
    const mine = myOpenChallengeOn(g.id);
    let body;
    if (bettable) {
      const tabs = [['winner','Match Winner',o.winner],['margin','Margin',o.margin],['total','Total Points',o.total]].filter(([, , choices]) => choices.length >= 2);
      const chosen = activeChallenge.get(g.id) || tabs[0]?.[0];
      const current = tabs.find(([key]) => key === chosen) || tabs[0];
      const choices = current ? current[2].filter((sel) => sel.side !== 'draw').slice(0, 2) : [];
      const choiceLabel = (sel) => {
        if (sel.market === 'winner') return `${sel.side === 'away' ? g.away.name : g.home.name} to win`;
        if (sel.market === 'margin') {
          const team = sel.side === 'away' ? g.away.name : g.home.name;
          return sel.line < 0 ? `${team} to win by ${Math.ceil(Math.abs(sel.line))}+` : `${team} to stay within ${Math.floor(sel.line)}`;
        }
        return `Combined score ${sel.side === 'higher' ? 'above' : 'below'} ${sel.line}`;
      };
      const statusLine = g.state === 'live' ? `<span class="live">LIVE</span> · ${g.awayScore}–${g.homeScore} · ${esc(g.clock)}` : `${esc(TO.fmtDay(g.start))} · ${esc(TO.fmtTime(g.start))}`;
      body = `<div class="matchup-head">
        <button class="matchup-team" data-act="open-game" data-id="${g.id}">${ui.teamBadge(g.away, 30)}<span>${esc(g.away.name)}</span>${g.state === 'live' ? `<b>${g.awayScore}</b>` : ''}</button>
        <span class="matchup-at">@</span>
        <button class="matchup-team" data-act="open-game" data-id="${g.id}">${ui.teamBadge(g.home, 30)}<span>${esc(g.home.name)}</span>${g.state === 'live' ? `<b>${g.homeScore}</b>` : ''}</button>
      </div><div class="matchup-time">${statusLine}</div>
      <div class="challenge-tabs" role="tablist" aria-label="Challenge type">${tabs.map(([key,label]) => `<button role="tab" aria-selected="${current?.[0] === key}" class="${current?.[0] === key ? 'on' : ''}" data-act="challenge-tab" data-game="${esc(g.id)}" data-market="${key}">${label}</button>`).join('')}</div>
      ${tabs.length ? `<div class="challenge-choices">${choices.map((sel) => ui.challengeChoiceButton(sel, { suspended: false, big: true, label: choiceLabel(sel) })).join('')}</div>` : '<div class="tiny faint" style="margin-top:6px">Challenge targets are not available for this game yet.</div>'}`;
    } else {
      const row = (team, score, won) => `<button class="gc-team" style="width:100%" data-act="open-game" data-id="${g.id}">${ui.teamBadge(team)}<span class="nm" style="${won ? '' : 'color:var(--text-2)'}">${esc(team.name)}</span>${g.state === 'final' || g.state === 'live' ? `<span class="sc ${won ? '' : 'trail'}">${score}</span>` : ''}</button>`;
      body = row(g.away, g.awayScore, g.awayScore >= g.homeScore) + row(g.home, g.homeScore, g.homeScore >= g.awayScore);
      if (g.state === 'postponed') body += `<div class="note warn" style="margin-top:6px">${icon('info', 15)}<span>This game was postponed. Any related pledge will be returned.</span></div>`;
    }
    const status = `${ui.gameStatus(g)}${o.suspended && g.state === 'live' ? `<span class="tag">${icon('lock', 10)} Challenges closed</span>` : ''}`;
    return `<div class="card game-card" data-game="${g.id}">
      <div class="gc-status">${status}<span class="lg">${g.otherConferenceLive ? `LIVE · ${esc(g.conferenceName || 'UNRANKED')}` : g.simulated ? 'SIMULATED' : esc(S.LEAGUES[g.league].short)}</span></div>
      ${body}
      <div class="gc-more">${mine.length ? `<span class="your-challenge">${icon('target', 14)} ${mine.length} active challenge${mine.length === 1 ? '' : 's'} here</span>` : '<span></span>'}<button class="row-s link-btn" style="font-size:12.5px" data-act="open-game" data-id="${g.id}">Stats & challenge details ${icon('chevR', 14)}</button></div>
    </div>`;
  }

  function emptyBoard(f) {
    const day = activeDay();
    const when = day === 0 ? 'today' : day === 1 ? 'tomorrow' : `on ${dayLabel(day)}`;
    const loading = day > 0 && TO.live.upcomingLoading;
    const isLive = liveOnly();
    const title = isLive ? (f === 'all' ? 'No live games right now' : `No live ${esc(filterName())} games right now`) : loading ? 'Loading the schedule…' : `Sorry, no games are happening for this sport ${when}.`;
    const next = !isLive && !loading ? Array.from({ length: TO.live.days + 1 }, (_, i) => i).find((i) => i !== day && boardGames(i, true).some((g) => f === 'all' || g.league === f)) : null;
    if (TO.live.failed) {
      return `<div class="empty">${icon('alert', 40)}<h3>Sports couldn’t load</h3><p>Check your connection and try again.</p><button class="btn primary" data-act="refresh-live">Try again</button></div>`;
    }
    return `<div class="empty">
      ${icon(loading ? 'clock' : 'target', 40)}
      <h3>${title}</h3>
      ${isLive ? '<p>Check back when a game is underway.</p><button class="btn primary" data-act="feed-live-off">Show all games</button>' : ''}
      ${next != null ? `<button class="btn primary" data-act="feed-day" data-day="${next}">See games ${next === 1 ? 'tomorrow' : `on ${esc(dayLabel(next))}`}</button>` : ''}
    </div>`;
  }

  function buildComboControl() {
    const builder = TO.comboGoalBuilder;
    if (!builder.comboGoalMode) return `<button class="build-combo-goal" data-act="toggle-combo-goal">${icon('target', 18)}<span><b>Build a Combo Goal</b><small>Link choices from up to four matchups</small></span>${icon('chevR', 18)}</button>`;
    return `<div class="build-combo-goal active"><span class="lr-icon">${icon('target', 18)}</span><span class="grow"><b>Choose Combo Goal picks</b><small>${builder.selectedPicks.length} of ${TO.RULES.maxMatchupPicks} choices · one per matchup</small></span><button class="link-btn" data-act="toggle-combo-goal">Cancel</button></div>`;
  }

  function feed(games) {
    const f = activeFilter();
    let list = f === 'all' ? games : games.filter((g) => g.league === f);
    if (liveOnly()) list = list.filter((g) => g.state === 'live');
    if (!list.length && f !== 'pred' && f !== 'todo') return emptyBoard(f);
    if (f === 'all') {
      const groups = S.LEAGUE_ORDER.filter((l) => l !== 'sim' && list.some((g) => g.league === l)).map((l) => {
        const lg = list.filter((g) => g.league === l);
        return `<div class="league-head"><h3>${esc(S.LEAGUES[l].title)}</h3>${S.LEAGUES[l].simulated ? '<span class="tag">Simulated</span>' : ''}<span class="cnt">${lg.filter((g) => g.state === 'live').length} live · ${lg.length} games</span></div>${lg.map(gameCard).join('')}`;
      });
      return groups.join('');
    }
    return list.map(gameCard).join('');
  }

  /** The big prompt at the top of Home until app limits are set up. A browser can't block apps, so the real block is in the iPhone app. */
  function setupBanner() {
    const s = TO.data.settings;
    const hasLocks = s.lockedApps.length > 0 || s.deviceLockPoints > 0;
    if (s.enforce && hasLocks) return '';
    const title = hasLocks ? 'App limits are off' : 'Set up your app limits';
    const text = hasLocks
      ? 'Your apps won\'t lock when your phone time runs out, and your tier stays at Rookie.'
      : 'Choose the apps TimeOut locks when your phone time runs out. It takes about 30 seconds. Real blocking happens in the TimeOut iPhone app.';
    const action = hasLocks ? 'Turn limits back on' : 'Choose apps';
    return `<div class="setup-banner"><div class="row" style="align-items:flex-start"><span class="sb-icon">${icon('shield', 20)}</span><div class="grow"><b>${title}</b><p>${text}</p></div></div><button class="btn primary full" data-act="${hasLocks ? 'setup-limits-on' : 'locked-apps'}">${action}</button></div>`;
  }

  function render() {
    const wl = TO.state.wallet();
    const games = boardGames();
    const lock = wl.appsLocked
      ? `<button class="app-lock" data-act="settings" data-section="screentime">${icon('phone', 22, 'red')}<span class="grow"><b class="red">Your locked apps are blocked</b><div class="small muted">You've used all ${wl.todayLimit} min of today's phone time. Emergency unlocks are in Settings.</div></span>${icon('chevR', 16)}</button>`
      : '';
    return `<div class="stack home" style="padding-top:2px">
      ${setupBanner()}
      ${walletCard(wl)}
      ${lock}
      ${statusStrip(wl)}
      ${openChallengesStrip()}
      <div class="stack feed" style="gap:12px">
        ${filterBar(games)}
        ${buildComboControl()}
        ${TO.live.offline ? `<div class="note blue simulated-note">${icon('info', 16)}<span>Live matchup targets can't be reached here, so these are simulated games with real team names. Everything else works the same.</span></div>` : ''}
        ${feed(games)}
      </div>
    </div>`;
  }

  function syncNode(current, fresh) {
    if (!current || !fresh || current.nodeType !== fresh.nodeType
      || (current.nodeType === 1 && current.tagName !== fresh.tagName)) {
      current?.parentNode?.replaceChild(fresh.cloneNode(true), current);
      return;
    }
    if (current.nodeType === 3) {
      if (current.nodeValue !== fresh.nodeValue) current.nodeValue = fresh.nodeValue;
      return;
    }
    const currentAttrs = [...current.attributes];
    for (const attr of currentAttrs) if (!fresh.hasAttribute(attr.name)) current.removeAttribute(attr.name);
    for (const attr of [...fresh.attributes]) if (current.getAttribute(attr.name) !== attr.value) current.setAttribute(attr.name, attr.value);
    const next = [...fresh.childNodes];
    for (let i = 0; i < next.length; i++) {
      const old = current.childNodes[i];
      if (!old) current.appendChild(next[i].cloneNode(true));
      else syncNode(old, next[i]);
    }
    while (current.childNodes.length > next.length) current.lastChild.remove();
  }

  function refreshLive() {
    const view = document.getElementById('view');
    if (!view || TO.app.tab !== 'home' || !view.firstElementChild) return;
    const next = document.createElement('div');
    next.innerHTML = render();
    if (next.firstElementChild) syncNode(view.firstElementChild, next.firstElementChild);
  }

  TO.views.home = { render, gameCard, refreshLive, boardGames, dayBar };

  // ---------- Actions ----------
  const A = TO.actions;
  A['challenge-tab'] = (el) => { activeChallenge.set(el.dataset.game, el.dataset.market); TO.app.renderView(); };
  A['feed-day'] = (el) => {
    feedDay = Number(el.dataset.day) || 0;
    TO.app.render();
    if (TO.ui.pageOpen('combo-goal')) TO.ui.refreshPage('combo-goal');
    const v = document.getElementById('view');
    const fb = v && v.querySelector('.filterbar');
    if (fb && v.scrollTop > fb.offsetTop) v.scrollTop = fb.offsetTop;
  };
  A.filter = (el) => { TO.data.feedFilter = el.dataset.f; TO.state.save(); TO.app.render(); const v = document.getElementById('view'); const fb = v.querySelector('.filterbar'); if (fb && v.scrollTop > fb.offsetTop) v.scrollTop = fb.offsetTop; };
  const setLive = (on) => {
    TO.data.feedLive = on;
    TO.state.save();
    TO.app.render();
    const v = document.getElementById('view');
    const fb = v && v.querySelector('.filterbar');
    if (fb && v.scrollTop > fb.offsetTop) v.scrollTop = fb.offsetTop;
  };
  A['feed-live'] = () => setLive(!liveOnly());
  A['feed-live-off'] = () => setLive(false);
  A['setup-limits-on'] = () => { TO.state.setSetting('enforce', true); TO.app.render(); };
  A['refresh-live'] = () => TO.live.refresh(TO.now(), true);
  A['go-sim'] = () => {
    if (!followed().includes('sim')) TO.state.setSetting('sports', [...followed(), 'sim']);
    TO.data.feedFilter = 'sim';
    TO.state.save();
    TO.app.render();
  };
  A.how = () => TO.views.settings.howItWorks();
})(window.TO);
