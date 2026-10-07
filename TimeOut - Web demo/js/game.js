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
    } else if (g.state === 'postponed') {
      mid = `<div class="tag yellow" style="height:26px;font-size:12px">Postponed</div>`;
    } else {
      mid = `<div class="display" style="font-size:26px">${TO.fmtTime(g.start)}</div><div class="sb-clock">${TO.fmtDay(g.start)} · in ${TO.fmtIn(g.start - TO.now())}</div>`;
    }
    const team = (t) => `<div class="sb-team">${ui.teamBadge(t, 52)}<div class="nm">${esc(t.city === t.name ? t.name : `${t.city} ${t.name}`)}</div><div class="rec">${S.record(g.league, t)}</div></div>`;
    return `<div class="card scoreboard">
      <div class="spread tiny bold faint" style="margin-bottom:12px"><span>${esc(S.LEAGUES[g.league].title)}${g.simulated ? ' · Simulated' : ''}</span><span>Away @ Home</span></div>
      <div class="sb-grid">${team(g.away)}<div class="sb-mid">${mid}</div>${team(g.home)}</div>
    </div>`;
  }

  function banner(g, o) {
    if (g.state === 'postponed') return `<div class="note warn">${icon('alert', 16)}<span><b>This game was postponed.</b> All bets on it are void, and every stake has been returned in full. It no longer counts toward anyone's record.</span></div>`;
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
    const age = Math.max(0, Math.round((TO.now() - o.updatedAt) / 1000));
    const every = g.state === 'live' ? 15 : 120;
    return `<div class="card stack">
      <div class="spread"><h2 style="margin:0;font-size:17px">Pick a side</h2><span class="tiny faint bold">${g.state === 'live' ? `Odds refresh every 15 sec · ${Math.max(every - age, 0)}s` : 'Pre-game odds'}</span></div>
      ${block('Moneyline · who wins', o.moneyline, (s) => name(s.side))}
      ${o.spread.length ? block(`${Sp.spreadLabel} · win by more than the line`, o.spread, (s) => name(s.side)) : ''}
      ${block(`Total ${Sp.unit} · both teams combined`, o.total, (s) => (s.side === 'over' ? 'Over' : 'Under'))}
      <div class="tiny faint">Fair odds with no house cut. Tap a price to add it to your bet slip.</div>
    </div>`;
  }

  function statsCard(g) {
    const rows = S.stats(g);
    if (!rows.length) return '';
    return `<div class="card stack">
      <div class="spread"><h2 style="margin:0;font-size:17px">${g.state === 'live' ? 'Live stats' : 'Final stats'}</h2><span class="row-s tiny bold faint">${ui.teamBadge(g.away, 18)} vs ${ui.teamBadge(g.home, 18)}</span></div>
      ${rows.map((r) => {
        const tot = (r.a + r.h) || 1;
        const aBetter = r.lowerBetter ? r.a < r.h : r.a > r.h;
        const hBetter = r.lowerBetter ? r.h < r.a : r.h > r.a;
        const suf = r.suffix || '';
        const at = r.text ? r.text[0] : `${r.a}${suf}`, ht = r.text ? r.text[1] : `${r.h}${suf}`;
        return `<div class="cmp-row"><span class="v" style="${aBetter ? '' : 'color:var(--text-2)'}">${at}</span>
          <div class="mid"><span class="lab">${esc(r.label)}</span><div class="cmp-bars"><span><i style="width:${(r.a / tot) * 100}%;background:${g.away.color}"></i></span><span><i style="width:${(r.h / tot) * 100}%;background:${g.home.color}"></i></span></div></div>
          <span class="v r" style="${hBetter ? '' : 'color:var(--text-2)'}">${ht}</span></div>`;
      }).join('')}
    </div>`;
  }

  function playsCard(g) {
    const list = S.plays(g);
    if (!list.length) return g.state === 'live' ? `<div class="card small muted">No scoring yet. Scoring plays show up here as they happen.</div>` : '';
    return `<div class="card"><h2 style="margin:0 0 6px;font-size:17px">Scoring plays</h2>${list.slice(0, 8).map((p) => `<div class="play">${ui.teamBadge(p.team, 24)}<div><div class="k">${esc(p.kind)}</div><div class="c">${esc(p.clock)}</div></div><div class="s">${esc(p.score)}</div></div>`).join('')}</div>`;
  }

  function researchCard(g) {
    const r = S.research(g);
    const dots = (f) => `<span class="form-dots">${f.map((x) => `<i class="${x}">${x}</i>`).join('')}</span>`;
    return `<div class="card stack">
      <h2 style="margin:0;font-size:17px">Matchup research</h2>
      <div class="research">
        <span class="row-s bold">${ui.teamBadge(g.away, 22)}${esc(g.away.abbr)}</span><span class="c"></span><span class="r row-s bold">${esc(g.home.abbr)}${ui.teamBadge(g.home, 22)}</span>
        <span class="v">${r.away.record}</span><span class="c">Record</span><span class="v r">${r.home.record}</span>
        <span>${dots(r.away.form)}</span><span class="c">Last 5</span><span class="r">${dots(r.home.form)}</span>
        <span class="v">${r.away.pf}</span><span class="c">${esc(r.unit)} scored / game</span><span class="v r">${r.home.pf}</span>
        <span class="v">${r.away.pa}</span><span class="c">${esc(r.unit)} allowed / game</span><span class="v r">${r.home.pa}</span>
      </div>
      <div class="small muted">Last meeting: <b style="color:var(--text)">${esc(r.lastMeeting)}</b></div>
    </div>`;
  }

  function render() {
    const g = S.game(currentId);
    const o = S.odds(currentId);
    return {
      title: `${esc(g.away.abbr)} @ ${esc(g.home.abbr)}`,
      body: `${scoreboard(g)}${banner(g, o)}${myBets(g)}${markets(g, o)}${statsCard(g)}${playsCard(g)}${researchCard(g)}`,
    };
  }

  function open(id) {
    currentId = id;
    ui.openPage('game', { render });
  }

  TO.views.game = { open, refresh: () => ui.refreshPage('game') };
  TO.actions['open-game'] = (el) => open(el.dataset.id);
})(window.TO);
