/* TimeOut web demo — Game detail (Screen 2): live score, stats, research and every market. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  let currentId = null;
  const activeMarket = new Map();

  function scoreboard(g) {
    const live = g.state === 'live', fin = g.state === 'final';
    const showScore = live || fin;
    const aTrail = g.awayScore < g.homeScore, hTrail = g.homeScore < g.awayScore;
    let mid;
    if (showScore) {
      mid = `<div class="sb-score"><span class="${aTrail ? 'trail' : ''}">${g.awayScore}</span><span class="dash">–</span><span class="${hTrail ? 'trail' : ''}">${g.homeScore}</span></div>
        <div class="sb-clock">${live ? `<span class="live">LIVE</span>${esc(g.clock)}` : esc(g.statusText)}</div>`;
    } else if (g.state === 'postponed' || g.state === 'canceled') {
      mid = `<div class="tag yellow" style="height:26px;font-size:12px">${g.state === 'canceled' ? 'Canceled' : 'Postponed'}</div>`;
    } else {
      mid = `<div class="display" style="font-size:26px">${TO.fmtTime(g.start)}</div><div class="sb-clock">${TO.fmtDay(g.start)} · in ${TO.fmtIn(g.start - TO.now())}</div>`;
    }
    const team = (t) => `<div class="sb-team">${ui.teamBadge(t, 52)}<div class="nm">${esc(!t.city || t.city === t.name ? t.name : `${t.city} ${t.name}`)}</div>${t.rank ? `<div class="rec">#${t.rank}</div>` : ''}</div>`;
    return `<div class="card scoreboard">
      <div class="row-layout tiny bold faint" style="margin-bottom:12px"><span>${esc(S.LEAGUES[g.league].title)}${g.simulated ? ' · Simulated' : ''}</span><span>Away @ Home</span></div>
      <div class="sb-grid">${team(g.away)}<div class="sb-mid">${mid}</div>${team(g.home)}</div>
    </div>`;
  }

  function banner(g, o) {
    if (g.state === 'postponed') return `<div class="note warn">${icon('alert', 16)}<span><b>This game was postponed.</b> Related pledges will be returned in full and won't affect your record.</span></div>`;
    if (g.state === 'canceled') return `<div class="note warn">${icon('alert', 16)}<span>This game was canceled. Related pledges will be returned.</span></div>`;
    if (g.state === 'final') return `<div class="note">${icon('lock', 16)}<span><b>Final: ${esc(g.away.abbr)} ${g.awayScore}, ${esc(g.home.abbr)} ${g.homeScore}${g.ot ? ` (${g.ot.label === '10' ? '10 innings' : 'OT'})` : ''}.</b> Challenges are closed on this game.</span></div>`;
    if (o.suspended) return `<div class="note">${icon('lock', 16)}<span>Challenges are closed for the final moments of this game.</span></div>`;
    return '';
  }

  function myBets(g) {
    const bets = TO.data.bets.filter((b) => b.legs.some((l) => l.gameId === g.id)).sort((a, b) => (a.status === 'open' ? -1 : 1) - (b.status === 'open' ? -1 : 1));
    if (!bets.length) return '';
    return `<div class="stack-s"><div class="eyebrow">Your pledges on this game</div>${bets.map((b) => TO.views.bets.betCard(b, { compact: true })).join('')}</div>`;
  }

  function markets(g, o) {
    if (g.state !== 'live' && g.state !== 'scheduled') return '';
    const tabs = [['ml','Match Winner',o.moneyline],['spread','Margin',o.spread],['total','Total Points',o.total]].filter(([, , sels]) => sels.filter((s) => s.side !== 'draw').length >= 2);
    const current = tabs.find(([key]) => key === activeMarket.get(g.id)) || tabs[0];
    if (!current) return `<div class="card small muted">Challenge targets are not available for this game yet.</div>`;
    const choices = current[2].filter((s) => s.side !== 'draw').slice(0, 2);
    const label = (s) => {
      const team = s.side === 'away' ? g.away.name : g.home.name;
      if (s.market === 'ml') return `${team} · Outright Winner`;
      if (s.market === 'spread') return s.line < 0 ? `${team} to win by ${Math.ceil(Math.abs(s.line))}+` : `${team} to stay within ${Math.floor(s.line)}`;
      return `${s.side === 'over' ? 'Total Score Over' : 'Total Score Under'} ${s.line}`;
    };
    return `<div class="card stack" id="game-markets">
      <div class="row-layout"><h2 style="margin:0;font-size:17px">Matchup Challenge</h2><span class="tiny faint bold">Targets refresh every 25 seconds</span></div>
      <div class="challenge-tabs" role="tablist" aria-label="Challenge type">${tabs.map(([key,title]) => `<button role="tab" aria-selected="${current[0] === key}" class="${current[0] === key ? 'on' : ''}" data-act="game-challenge-tab" data-game="${esc(g.id)}" data-market="${key}">${title}</button>`).join('')}</div>
      <div class="challenge-choices">${choices.map((s) => ui.challengeChoiceButton(s, { suspended: o.suspended, big: true, label: label(s) })).join('')}</div>
      <div class="tiny faint">Choose an option to add it to your Daily Commitment.</div>
    </div>`;
  }

  function statsCard(g) {
    if (!g.eventID) return '';
    const rows = TO.live.stats(g);
    if (!rows.length) return `<div class="card small muted">ESPN live stats are not available for this game yet.</div>`;
    return `<div class="card stack">
      <div class="row-layout"><h2 style="margin:0;font-size:17px">${g.state === 'live' ? 'Live stats' : 'Final stats'}</h2><span class="row-s tiny bold faint">${ui.teamBadge(g.away, 18)} vs ${ui.teamBadge(g.home, 18)}</span></div>
      ${rows.map((r) => {
        return `<div class="cmp-row"><span class="v">${esc(r.awayValue)}</span><div class="mid"><span class="lab">${esc(r.label)}</span></div><span class="v r">${esc(r.homeValue)}</span></div>`;
      }).join('')}
    </div>`;
  }

  function researchCard(g) {
    const teams = g.eventID ? [g.away, g.home].filter((team) => team.rank || team.record) : [];
    if (!teams.length) return '';
    return `<div class="card stack"><h2 style="margin:0;font-size:17px">ESPN team information</h2>${teams.map((team) => `<div class="row-layout"><span class="row-s bold">${ui.teamBadge(team, 22)}${esc(team.name)}</span><span class="small muted">${[team.rank ? `#${team.rank}` : '', team.record || ''].filter(Boolean).map(esc).join(' · ')}</span></div>`).join('')}</div>`;
  }

  /** Floating button: jumps to the challenge targets, or back to the commitment once there's a pick on it. */
  function fab(g, o) {
    if (g.state !== 'live' && g.state !== 'scheduled') return '';
    const n = TO.comboGoalBuilder.selectedPicks.length;
    if (n) return `<div class="page-fab game-fab has-commitment"><button class="btn primary full" data-act="open-commitment">${icon('target', 18)} Open Daily Commitment · ${n} choice${n === 1 ? '' : 's'}</button></div>`;
    return `<div class="page-fab game-fab"><button class="btn primary full" data-act="game-challenge" ${o.suspended ? 'disabled' : ''}>${icon(o.suspended ? 'lock' : 'target', 18)} ${o.suspended ? 'Challenges are closed' : 'Choose a challenge'}</button></div>`;
  }

  function render() {
    const g = S.game(currentId);
    const o = S.odds(currentId);
    return {
      title: `${esc(g.away.abbr)} @ ${esc(g.home.abbr)}`,
      body: `${scoreboard(g)}${banner(g, o)}${myBets(g)}${markets(g, o)}${statsCard(g)}${researchCard(g)}${fab(g, o)}`,
    };
  }

  function open(id) {
    currentId = id;
    ui.openPage('game', { render });
    if (S.game(id)?.eventID) TO.live.loadDetails(id);
  }

  TO.on('live:details-updated', (id) => { if (id === currentId && ui.pageOpen('game')) TO.views.game.refresh(); });

  TO.views.game = { open, refresh: () => ui.refreshPage('game') };
  TO.actions['open-game'] = (el) => open(el.dataset.id);
  TO.actions['game-challenge-tab'] = (el) => { activeMarket.set(el.dataset.game, el.dataset.market); ui.refreshPage('game'); };
  TO.actions['game-challenge'] = () => {
    const m = document.getElementById('game-markets');
    if (!m) return;
    m.scrollIntoView({ behavior: 'smooth', block: 'start' });
    m.classList.remove('flash');
    void m.offsetWidth; // restart the highlight
    m.classList.add('flash');
    ui.toast({ kind: 'info', title: 'Choose a challenge', msg: 'Select an option to add it to your Daily Commitment.', ms: 2600 });
  };
})(window.TO);
