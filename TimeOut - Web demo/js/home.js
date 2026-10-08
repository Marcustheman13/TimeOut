/* TimeOut web demo — Home (Screen 1). */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  const prevScores = {};

  const followed = () => TO.data.settings.sports;
  const offDay = () => TO.store.get('timeout.offDay', false);
  const activeFilter = () => ['pred', 'todo', 'sim'].includes(TO.data.feedFilter) ? 'all' : (TO.data.feedFilter || 'all');
  const sportsOnly = (bet) => bet.kind === 'sports' && bet.legs.every((leg) => leg.gameId && S.game(leg.gameId)?.league !== 'sim');

  function boardGames() {
    return S.board(TO.now(), { offDay: offDay(), leagues: S.LEAGUE_ORDER.filter((l) => l !== 'sim' && followed().includes(l)) }).filter((g) => !g.simulated && g.league !== 'sim');
  }

  function myOpenBetOn(ref) {
    return TO.data.bets.filter((b) => b.status === 'open' && b.legs.some((l) => l.gameId === ref || l.predId === ref));
  }

  // ---------- Wallet header (PRD: screen time + current bets always at the top) ----------
  function walletCard(wl) {
    if (wl.lockedOut || wl.balance <= 0) {
      return `<div class="card wallet locked" style="border-color:rgba(255,90,95,.45)">
        <div class="lockhead">${icon('lock', 14)} OUT OF BETTING MINUTES</div>
        <div class="bold" style="margin-top:8px;font-size:16px">Betting is locked. It reopens at midnight.</div>
        <div class="bigcd" style="margin-top:6px">${ui.countdownEl(TO.nextMidnight())}</div>
        <div class="small muted" style="margin-top:4px">Your open bets still settle and count toward tomorrow's phone time.</div>
        ${statsRow(wl)}
      </div>`;
    }
    const pct = Math.min(100, (wl.balance / (TO.RULES.daily + wl.bonusToday)) * 100);
    return `<div class="card wallet">
      <div class="spread" style="align-items:flex-end">
        <div>
          <div class="eyebrow">Betting balance today</div>
          <div class="big" style="margin-top:4px">${wl.balance}<small>min</small></div>
        </div>
        <div style="text-align:right">
          <div class="eyebrow" style="color:var(--muted)">Resets in</div>
          ${ui.countdownEl(TO.nextMidnight(), 'cd')}
        </div>
      </div>
      <div class="bar" style="margin-top:12px"><i style="width:${pct}%"></i></div>
      ${statsRow(wl)}
      <button class="explain" data-act="how">${icon('info', 14)} You bet with tomorrow's phone time. How it works</button>
    </div>`;
  }

  function statsRow(wl) {
    const tomorrowDelta = wl.tomorrowLimit - TO.RULES.daily;
    const tColor = tomorrowDelta > 0 ? 'green' : tomorrowDelta < 0 ? 'red' : '';
    const pColor = wl.appsLocked ? 'red' : wl.phoneLeft <= TO.data.settings.lowWarn ? 'yellow' : '';
    return `<div class="wallet-stats">
      <div><b class="${pColor}">${TO.data.settings.enforce ? `${wl.phoneLeft} min` : 'Off'}</b><span>Phone time left</span></div>
      <div><b class="${wl.atRisk ? 'yellow' : ''}">${wl.atRisk} min</b><span>In open bets</span></div>
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

  function miniBet(bet) {
    const title = bet.kind === 'todo' ? `To-do parlay (${bet.legs.length})` : bet.legs.length > 1 ? `${bet.legs.length}-pick parlay` : bet.legs[0].label;
    let line = '';
    const leg = bet.legs.find((l) => l.result === 'pending') || bet.legs[0];
    if (bet.kind === 'todo') line = `${bet.legs.filter((l) => l.result === 'won').length}/${bet.legs.length} done · due midnight`;
    else if (leg.kind === 'pred') line = `Resolves in ${TO.fmtIn(leg.start - TO.now())}`;
    else {
      const g = S.game(leg.gameId);
      if (g.state === 'live') line = `<span class="live">LIVE</span> ${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore} · ${esc(g.clock)}`;
      else if (g.state === 'scheduled') line = `${g.away.abbr} @ ${g.home.abbr} · ${TO.fmtTime(g.start)}`;
      else line = `${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore} · ${esc(g.statusText)}`;
    }
    const bottom = bet.friend
      ? `<div class="row-s yellow small bold ellipsis">${icon('users', 14)}${esc(bet.friend.terms)}</div>`
      : `<div class="row-s small bold"><span class="muted">${bet.stake} min</span>${icon('chevR', 12)}<span class="green">${Math.round(bet.stake * bet.decimal) - bet.stake > 0 ? `win ${Math.round((Math.round(bet.stake * bet.decimal) - bet.stake) * (bet.multiplier || 1))} min` : ''}</span></div>`;
    return `<button class="card tight mini-bet" data-act="tab" data-tab="bets">
      <div class="spread"><span class="t ellipsis">${esc(title)}</span><span class="display muted" style="font-size:15px">${TO.odds.fmt(bet.american)}</span></div>
      <div class="small muted row-s ellipsis" style="font-weight:600">${line}</div>
      <div style="margin-top:auto">${bottom}</div>
    </button>`;
  }

  function openBetsStrip() {
    const open = TO.data.bets.filter((b) => b.status === 'open' && sportsOnly(b)).sort((a, b) => b.placedAt - a.placedAt);
    return `<div class="stack-s">
      <div class="section-title"><div class="row-s"><h2>Open bets</h2><span class="count-pill ${open.length ? '' : 'off'}">${open.length}</span></div>${open.length ? `<button class="link-btn" data-act="tab" data-tab="bets">See all</button>` : ''}</div>
      ${open.length
        ? `<div class="hscroll mini-bets" data-hkey="minibets">${open.map(miniBet).join('')}</div>`
        : `<div class="card tight small muted" style="margin:0 16px">No open bets. Tap any odds below to start one.</div>`}
    </div>`;
  }

  // ---------- Filters ----------
  function filterBar(games) {
    const f = activeFilter();
    const live = games.filter((g) => g.state === 'live').length;
    const chip = (key, label, n, ic) => `<button class="chip ${f === key ? 'on' : ''}" data-act="filter" data-f="${key}">${ic ? icon(ic, 14) : ''}${esc(label)}${n ? `<span class="n">${n}</span>` : ''}</button>`;
    const chips = [chip('live', 'Live', live, 'radio'), chip('all', 'All', 0, 'grid')];
    for (const l of S.LEAGUE_ORDER) {
      if (l === 'sim' || !followed().includes(l)) continue;
      const n = games.filter((g) => g.league === l && g.state !== 'final').length;
      chips.push(chip(l, l === 'ncaaf' ? 'College Football' : S.LEAGUES[l].short === 'SIM' ? 'Sim League' : S.LEAGUES[l].short, n));
    }
    chips.push(`<button class="chip dashed" data-act="settings" data-section="sports">${icon('sliders', 14)}Edit</button>`);
    const cfb = f === 'ncaaf' || f === 'all' ? `<label class="cfb-select-label" for="cfb-group">College Football</label><select id="cfb-group" class="cfb-select" aria-label="College football conference">${TO.live.groups.map(([id, name]) => `<option value="${id}" ${TO.live.selectedGroup() === id ? 'selected' : ''}>${esc(name)}</option>`).join('')}</select>` : '';
    return `<div class="filterbar"><div class="hscroll" data-hkey="filters">${chips.join('')}</div>${cfb}</div>`;
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
    const o = S.odds(g.id);
    const bettable = g.state === 'live' || g.state === 'scheduled';
    const mine = myOpenBetOn(g.id);
    const Sp = S.SPORTS[g.sport];
    let body;
    if (bettable) {
      if (g.eventID) {
        const sides = [
          ['away', g.away, g.awayScore, g.homeScore],
          ['home', g.home, g.homeScore, g.awayScore],
        ];
        const teamLine = (side, team, score, opponent) => `<div class="gc-live-team">
          <button class="gc-live-team-open" data-act="open-game" data-id="${g.id}" aria-label="Open ${esc(team.name)} game stats">
            <span class="gc-live-logo">${team.logo ? `<img src="${esc(team.logo)}" alt="" onerror="this.style.display='none';this.nextElementSibling.style.display='grid'">` : ''}<span style="${team.logo ? 'display:none' : ''}">${esc(team.abbr)}</span></span>
            <span class="gc-live-name">${esc(team.name)}</span>
          </button>
          <span class="gc-live-score ${g.state === 'live' && score < opponent ? 'trail' : ''} ${g.state === 'live' ? scoreCls(g, side) : ''}">${g.state === 'scheduled' ? '–' : score}</span>
        </div>`;
        const picks = [
          [o.spread.find((sel) => sel.side === 'away'), `Away · ${g.away.abbr}`],
          [o.spread.find((sel) => sel.side === 'home'), `Home · ${g.home.abbr}`],
          [o.total.find((sel) => sel.side === 'over'), 'Over'],
          [o.total.find((sel) => sel.side === 'under'), 'Under'],
          [o.moneyline.find((sel) => sel.side === 'away'), `Away ML · ${g.away.abbr}`, true],
          [o.moneyline.find((sel) => sel.side === 'home'), `Home ML · ${g.home.abbr}`, true],
        ];
        if (g.sport === 'soccer') picks.push([o.moneyline.find((sel) => sel.side === 'draw'), 'Draw', true]);
        body = `<div class="gc-live-layout">
          <div class="gc-live-teams">${sides.map(([side, team, score, opponent]) => teamLine(side, team, score, opponent)).join('')}</div>
          <div class="gc-live-bets">${picks.map(([sel, label, isMoneyline]) => sel
            ? ui.oddsBtn(sel, { suspended: o.suspended, move: o.move[sel.id], big: true, label })
            : `<button class="odds-btn locked big" disabled aria-label="${esc(label)} unavailable"><span class="lbl">${esc(label)}</span><span class="pr">${isMoneyline ? 'N/A' : '—'}</span></button>`).join('')}</div>
        </div>`;
      } else {
      const cols = [];
      if (o.spread.length === 2) cols.push([Sp.spreadLabel, o.spread]);
      if (o.total.length === 2) cols.push(['Total', o.total]);
      if (o.moneyline.length === 2) cols.push(['Money', o.moneyline]);
      const teamRow = (team, side, row) => {
        const score = side === 'home' ? g.homeScore : g.awayScore;
        const opp = side === 'home' ? g.awayScore : g.homeScore;
        return `<button class="gc-team" data-act="open-game" data-id="${g.id}">
            ${ui.teamBadge(team)}
            <span style="min-width:0"><span class="nm" style="display:block">${esc(g.state === 'live' ? team.abbr : team.name)}</span></span>
            ${g.state === 'live' ? `<span class="sc ${score < opp ? 'trail' : ''} ${scoreCls(g, side)}">${score}</span>` : ''}
          </button>
          ${cols.map(([, sels]) => ui.oddsBtn(sels[row], { suspended: o.suspended, move: o.move[sels[row].id], label: team.name })).join('')}`;
      };
      const draw = o.moneyline.find((s) => s.side === 'draw');
        body = `<div class="gc-grid ${cols.length === 2 ? 'two' : ''}" style="grid-template-columns:minmax(0,1fr) repeat(${cols.length},60px)">
          <span></span>${cols.map(([h]) => `<span class="colh">${esc(h)}</span>`).join('')}
          ${teamRow(g.away, 'away', 0)}
          ${teamRow(g.home, 'home', 1)}
          ${draw ? `<span class="gc-team muted bold" style="height:40px">Draw</span>${cols.length === 2 ? '<span></span>' : '<span></span><span></span>'}${ui.oddsBtn(draw, { suspended: o.suspended, move: o.move[draw.id], label: 'Draw' })}` : ''}
        </div>${cols.length ? '' : '<div class="tiny faint" style="margin:6px 2px 0">Betting lines are not available for this game yet.</div>'}`;
      }
    } else {
      const row = (team, score, won) => `<button class="gc-team" style="width:100%" data-act="open-game" data-id="${g.id}">${ui.teamBadge(team)}<span class="nm" style="${won ? '' : 'color:var(--text-2)'}">${esc(team.name)}</span>${g.state === 'final' ? `<span class="sc ${won ? '' : 'trail'}">${score}</span>` : ''}</button>`;
      body = row(g.away, g.awayScore, g.awayScore > g.homeScore) + row(g.home, g.homeScore, g.homeScore > g.awayScore);
      if (g.state === 'postponed') body += `<div class="note warn" style="margin-top:6px">${icon('info', 15)}<span>This game was postponed. Every bet on it is void and the full stake goes back to the bettor.</span></div>`;
    }
    const status = `${ui.gameStatus(g)}${o.suspended && g.state === 'live' ? `<span class="tag">${icon('lock', 10)} Betting closed</span>` : ''}`;
    return `<div class="card game-card" data-game="${g.id}">
      <div class="gc-status">${status}<span class="lg">${g.otherConferenceLive ? `LIVE · ${esc(g.conferenceName || 'UNRANKED')}` : g.simulated ? 'SIMULATED' : esc(S.LEAGUES[g.league].short)}</span></div>
      ${body}
      <div class="gc-more">${mine.length ? `<span class="yourbet">${icon('ticket', 14)} You have ${mine.length === 1 ? 'a bet' : `${mine.length} bets`} on this game</span>` : '<span></span>'}<button class="row-s link-btn" style="font-size:12.5px" data-act="open-game" data-id="${g.id}">Stats & all odds ${icon('chevR', 14)}</button></div>
    </div>`;
  }

  function emptyBoard(f) {
    const title = f === 'live' ? 'No live games right now' : 'Sorry, no games are happening for this sport today.';
    return `<div class="empty">
      ${icon('target', 40)}
      <h3>${title}</h3>
      ${f === 'live' ? '<p>Check back when a game is underway.</p>' : ''}
    </div>`;
  }

  function buildParlayControl() {
    const slip = TO.slip;
    if (!slip.parlayMode) return `<button class="build-parlay" data-act="toggle-parlay">${icon('ticket', 18)}<span><b>Build parlay</b><small>Select picks from multiple games</small></span>${icon('chevR', 18)}</button>`;
    return `<div class="build-parlay active"><span class="lr-icon">${icon('ticket', 18)}</span><span class="grow"><b>Choose your parlay picks</b><small>${slip.legs.length} of ${TO.RULES.maxLegs} picks · choose one bet per game</small></span><button class="link-btn" data-act="toggle-parlay">Cancel</button></div>`;
  }

  function feed(games) {
    const f = activeFilter();
    let list = games;
    if (f === 'live') list = games.filter((g) => g.state === 'live');
    else if (f !== 'all') list = games.filter((g) => g.league === f);
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

  function render() {
    const wl = TO.state.wallet();
    const games = boardGames();
    const lock = wl.appsLocked
      ? `<button class="app-lock" data-act="settings" data-section="screentime">${icon('phone', 22, 'red')}<span class="grow"><b class="red">Your locked apps are blocked</b><div class="small muted">You've used all ${wl.todayLimit} min of today's phone time. Emergency unlocks are in Settings.</div></span>${icon('chevR', 16)}</button>`
      : '';
    return `<div class="stack" style="padding-top:2px">
      ${walletCard(wl)}
      ${lock}
      ${statusStrip(wl)}
      ${openBetsStrip()}
      <div class="stack" style="gap:12px">
        ${filterBar(games)}
        ${buildParlayControl()}
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

  TO.views.home = { render, gameCard, refreshLive };

  // ---------- Actions ----------
  const A = TO.actions;
  A.filter = (el) => { TO.data.feedFilter = el.dataset.f; TO.state.save(); TO.app.render(); const v = document.getElementById('view'); const fb = v.querySelector('.filterbar'); if (fb && v.scrollTop > fb.offsetTop) v.scrollTop = fb.offsetTop; };
  A['go-sim'] = () => {
    if (!followed().includes('sim')) TO.state.setSetting('sports', [...followed(), 'sim']);
    TO.data.feedFilter = 'sim';
    TO.state.save();
    TO.tester.mark('offday');
    TO.app.render();
  };
  A.how = () => TO.views.settings.howItWorks();
})(window.TO);
