/* TimeOut web demo — Game detail (Screen 2): live score, stats, research and every market. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  let currentId = null;

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
      <div class="spread tiny bold faint" style="margin-bottom:12px"><span>${esc(S.LEAGUES[g.league].title)}${g.simulated ? ' · Simulated' : ''}</span><span>Away @ Home</span></div>
      <div class="sb-grid">${team(g.away)}<div class="sb-mid">${mid}</div>${team(g.home)}</div>
    </div>`;
  }

  function banner(g, o) {
    if (g.state === 'postponed') return `<div class="note warn">${icon('alert', 16)}<span><b>This game was postponed.</b> All bets on it are void, and every stake has been returned in full. It no longer counts toward anyone's record.</span></div>`;
    if (g.state === 'canceled') return `<div class="note warn">${icon('alert', 16)}<span>This game was canceled. Bets on it will be voided.</span></div>`;
    if (g.state === 'final') return `<div class="note">${icon('lock', 16)}<span><b>Final: ${esc(g.away.abbr)} ${g.awayScore}, ${esc(g.home.abbr)} ${g.homeScore}${g.ot ? ` (${g.ot.label === '10' ? '10 innings' : 'OT'})` : ''}.</b> Betting is closed on this game.</span></div>`;
    if (o.suspended) return `<div class="note">${icon('lock', 16)}<span>Betting is closed for the final moments of this game.</span></div>`;
    return '';
  }

  function myBets(g) {
    const bets = TO.data.bets.filter((b) => b.legs.some((l) => l.gameId === g.id)).sort((a, b) => (a.status === 'open' ? -1 : 1) - (b.status === 'open' ? -1 : 1));
    if (!bets.length) return '';
    return `<div class="stack-s"><div class="eyebrow">Your bets on this game</div>${bets.map((b) => TO.views.bets.betCard(b, { compact: true })).join('')}</div>`;
  }

  function markets(g, o) {
    if (g.state !== 'live' && g.state !== 'scheduled') return '';
    const Sp = S.SPORTS[g.sport];
    const name = (side) => (side === 'home' ? g.home.name : side === 'away' ? g.away.name : 'Draw');
    const block = (title, sels, labelFn) => `<div class="market"><h4>${esc(title)}</h4><div class="opts">${sels.map((s) => ui.oddsBtn(s, { suspended: o.suspended, move: o.move[s.id], big: true, label: labelFn(s) })).join('')}</div></div>`;
    const moneyline = o.moneyline.length
      ? `${block('Moneyline · who wins', o.moneyline, (s) => name(s.side))}${g.sport === 'soccer' && !o.moneyline.some((s) => s.side === 'draw') ? '<div class="market"><h4>Draw</h4><div class="opts"><span class="tag">N/A</span></div></div>' : ''}`
      : '<div class="market"><h4>Moneyline · who wins</h4><div class="opts"><span class="tag">Moneyline N/A</span></div></div>';
    const available = [
      moneyline,
      o.spread.length ? block(`${Sp.spreadLabel} · win by more than the line`, o.spread, (s) => name(s.side)) : '',
      o.total.length ? block(`Total ${Sp.unit} · both teams combined`, o.total, (s) => (s.side === 'over' ? 'Over' : 'Under')) : '',
    ].filter(Boolean);
    if (!available.length) return `<div class="card small muted">ESPN betting lines are not available for this game yet.</div>`;
    return `<div class="card stack">
      <div class="spread"><h2 style="margin:0;font-size:17px">Pick a side</h2><span class="tiny faint bold">ESPN odds refresh every 25 seconds</span></div>
      ${available.join('')}
      <div class="tiny faint">ESPN lines and prices. Tap a price to add it to your bet slip.</div>
    </div>`;
  }

  function statsCard(g) {
    if (!g.eventID) return '';
    const rows = TO.live.stats(g);
    if (!rows.length) return `<div class="card small muted">ESPN live stats are not available for this game yet.</div>`;
    return `<div class="card stack">
      <div class="spread"><h2 style="margin:0;font-size:17px">${g.state === 'live' ? 'Live stats' : 'Final stats'}</h2><span class="row-s tiny bold faint">${ui.teamBadge(g.away, 18)} vs ${ui.teamBadge(g.home, 18)}</span></div>
      ${rows.map((r) => {
        return `<div class="cmp-row"><span class="v">${esc(r.awayValue)}</span><div class="mid"><span class="lab">${esc(r.label)}</span></div><span class="v r">${esc(r.homeValue)}</span></div>`;
      }).join('')}
    </div>`;
  }

  function researchCard(g) {
    const teams = g.eventID ? [g.away, g.home].filter((team) => team.rank || team.record) : [];
    if (!teams.length) return '';
    return `<div class="card stack"><h2 style="margin:0;font-size:17px">ESPN team information</h2>${teams.map((team) => `<div class="spread"><span class="row-s bold">${ui.teamBadge(team, 22)}${esc(team.name)}</span><span class="small muted">${[team.rank ? `#${team.rank}` : '', team.record || ''].filter(Boolean).map(esc).join(' · ')}</span></div>`).join('')}</div>`;
  }

  function render() {
    const g = S.game(currentId);
    const o = S.odds(currentId);
    return {
      title: `${esc(g.away.abbr)} @ ${esc(g.home.abbr)}`,
      body: `${scoreboard(g)}${banner(g, o)}${myBets(g)}${markets(g, o)}${statsCard(g)}${researchCard(g)}`,
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
})(window.TO);
