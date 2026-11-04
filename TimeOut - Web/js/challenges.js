/* TimeOut web demo — My pledges (Screen 4), pledges sharing and to-do Combo Goals. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  const view = { tab: 'open', filter: 'all' };

  const toWin = (b) => Math.round((Math.round(b.pledgeMinutes * b.decimal) - b.pledgeMinutes) * (b.multiplier || 1));
  const challengeTitle = (b) => (b.kind === 'todo' ? `To-do Combo Goal · ${b.picks.length} task${b.picks.length === 1 ? '' : 's'}` : b.picks.length > 1 ? `${b.picks.length}-pick Combo Goal` : b.picks[0].label);

  function pickStanding(pick) {
    if (pick.result !== 'pending') return pick.result;
    if (pick.kind === 'todo') return 'upcoming';
    if (pick.kind === 'race') {
      const race = TO.races.get(pick.raceId);
      if (!race || race.status === 'open') return 'upcoming';
      if (race.status === 'running') return race.winnerId === Number(pick.horseId) ? 'winning' : 'losing';
      return 'even';
    }
    return S.liveStanding(pick);
  }

  function standingTag(st) {
    const map = { winning: ['Winning right now', 'trend'], losing: ['Losing right now', 'trend'], even: ['Too close to call', 'minus'], upcoming: ['Not started', 'clock'], void: ['Voided', 'x'] };
    const [t, ic] = map[st] || map.upcoming;
    return `<span class="standing ${st}">${icon(ic, 13)}${t}</span>`;
  }

  function overallStanding(pledge) {
    const sts = pledge.picks.filter((l) => l.result === 'pending').map(pickStanding);
    if (sts.includes('losing')) return 'losing';
    if (sts.length && sts.every((s) => s === 'winning')) return 'winning';
    if (sts.every((s) => s === 'upcoming')) return 'upcoming';
    return 'even';
  }

  /** Live score + key stats for a pick, so users can follow a pledges without leaving My pledges. */
  function liveBox(pick) {
    if (pick.kind === 'race') {
      const race = TO.races.get(pick.raceId);
      const horse = TO.races.horse(pick.horseId);
      const status = !race ? 'Race result unavailable' : race.status === 'open' ? 'Challenges open' : race.status === 'running' ? 'Race in progress' : `Race #${race.number} finished`;
      const leader = race && race.status === 'running' ? TO.races.horse(race.winnerId).name : '';
      return `<div class="livebox"><div class="row-layout small"><b>${esc(horse.name)} · ${esc(pick.matchup)}</b><span class="${race && race.status === 'running' ? 'live' : 'muted'}">${esc(status)}</span></div>${leader ? `<div class="small muted" style="margin-top:4px">Current leader: ${esc(leader)}</div>` : ''}</div>`;
    }
    if (pick.kind === 'pred') {
      const p = S.prediction(pick.predId);
      const chance = Math.round((pick.side === 'yes' ? p.pYes : 1 - p.pYes) * 100);
      return `<div class="livebox"><div class="small muted">${esc(p.q)}</div><div class="row-layout small"><span class="bold">${chance}% chance your side hits</span><span class="faint bold">${p.state === 'resolved' ? `Resolved ${p.outcome.toUpperCase()}` : `Resolves in ${TO.fmtIn(p.resolves - TO.now())}`}</span></div></div>`;
    }
    const g = S.game(pick.gameId);
    if (!g) return `<div class="livebox"><div class="small bold">${esc(pick.matchup || 'Sports game')}</div><div class="small muted">Loading the latest score…</div></div>`;
    let head;
    if (g.state === 'live' || g.state === 'final') {
      head = `<div class="lb-score">${ui.teamBadge(g.away, 22)}<span>${esc(g.away.abbr)}</span><span class="sc">${g.awayScore}</span><span class="faint">–</span><span class="sc">${g.homeScore}</span><span>${esc(g.home.abbr)}</span>${ui.teamBadge(g.home, 22)}<span style="margin-left:auto" class="small ${g.state === 'live' ? '' : 'muted'}">${g.state === 'live' ? `<span class="live">LIVE</span> ${esc(g.clock)}` : esc(g.statusText)}</span></div>`;
    } else if (g.state === 'postponed') {
      head = `<div class="lb-score">${esc(g.away.name)} @ ${esc(g.home.name)}<span class="tag yellow" style="margin-left:auto">Postponed</span></div>`;
    } else {
      head = `<div class="lb-score">${ui.teamBadge(g.away, 22)}${esc(g.away.abbr)} @ ${esc(g.home.abbr)}${ui.teamBadge(g.home, 22)}<span style="margin-left:auto" class="small muted">${TO.fmtDay(g.start)} ${TO.fmtTime(g.start)} · in ${TO.fmtIn(g.start - TO.now())}</span></div>`;
    }
    if (g.eventID) TO.live.loadDetails(g.id);
    const stats = g.eventID ? TO.live.stats(g).slice(0, 3) : [];
    const statsHtml = stats.length && g.state === 'live' ? `<div class="lb-stats">${stats.map((r) => `<span>${esc(r.label)} <b>${esc(r.awayValue)}–${esc(r.homeValue)}</b></span>`).join('')}</div>` : '';
    return `<div class="livebox" data-act="open-game" data-id="${g.id}" style="cursor:pointer">${head}${statsHtml}</div>`;
  }

  function nowPointValue(pick) {
    if (pick.result !== 'pending' || pick.kind === 'todo') return '';
    const cur = S.currentSelection(pick.selId);
    if (!cur || !cur.sel) return '';
    if (!cur.open) return `<span class="tag">Challenging closed</span>`;
    if (cur.sel.price === pick.price && cur.sel.line === pick.line) return `<span class="tag">Target now ${TO.multiplierText(cur.sel.price)}</span>`;
    const improved = TO.convertPointValueToMultiplier(cur.sel.price) > TO.convertPointValueToMultiplier(pick.price);
    return `<span class="tag ${improved ? 'green' : 'red'}">Target now ${TO.multiplierText(cur.sel.price)}</span>`;
  }

  function openCard(pledge, opts) {
    const single = pledge.picks.length === 1;
    const st = pledge.kind === 'todo' ? null : overallStanding(pledge);
    let picks;
    if (pledge.kind === 'todo') {
      picks = pledge.picks.map((l, i) => `<div class="pick" style="align-items:center">
        <button class="checkbox ${l.result === 'won' ? 'on' : ''}" data-act="todo-done" data-pledge="${pledge.id}" data-i="${i}" ${l.result === 'won' ? 'disabled' : ''} aria-label="Mark done">${icon('check', 15)}</button>
        <div class="grow"><div class="lt" style="${l.result === 'won' ? 'text-decoration:line-through;color:var(--text-2)' : ''}">${esc(l.text)}</div><div class="lm">${esc(l.difficulty)} · ${TO.multiplierText(l.price)}${l.result === 'won' ? ` · ${esc(l.final)}` : ''}</div></div></div>`).join('');
      picks += `<div class="note">${icon('clock', 15)}<span>Finish every task before midnight (${ui.countdownEl(pledge.deadline)} left). Tap a box when it's done. Honor system.</span></div>`;
    } else if (single) {
      const pick = pledge.picks[0];
      picks = `${liveBox(pick)}<div class="row-layout">${standingTag(st)}${nowPointValue(pick)}</div>`;
    } else {
      picks = pledge.picks.map((l) => {
        const ls = pickStanding(l);
        const dotIc = { won: 'check', lost: 'x', void: 'minus', tie: 'minus', winning: 'trend', losing: 'trend' }[ls] || 'clock';
        return `<div class="pick"><span class="pick-dot ${ls}">${icon(dotIc, 12)}</span><div class="grow stack-s" style="gap:6px"><div><div class="lt">${esc(l.label)} <span class="faint" style="font-weight:600">${TO.multiplierText(l.price)}</span></div><div class="lm">${esc(l.marketLabel)} · ${esc(l.matchup)}</div></div>${l.result === 'pending' ? liveBox(l) : `<div class="lm bold">${esc(l.final || '')}</div>`}</div></div>`;
      }).join('') + `<div class="row-layout">${standingTag(st)}${pledge.insured ? '<span class="tag" style="color:var(--purple)">Insured</span>' : ''}</div>`;
    }
    const sub = pledge.kind === 'todo' ? 'Personal task goal' : single ? `${esc(pledge.picks[0].marketLabel)} · ${esc(pledge.picks[0].matchup)}` : 'Complete each selected target';
    const pledgeRow = `<div class="pledge-row"><div><b>${pledge.pledgeMinutes}</b><span>Min committed</span></div><div><b class="green">+${toWin(pledge)}</b><span>Target earned minutes</span></div><div><b>${TO.fmtTime(pledge.placedAt)}</b><span>Started ${TO.fmtDay(pledge.placedAt).toLowerCase()}</span></div></div>`;
    const perks = [pledge.boosted ? `<span class="tag blue">${icon('bolt', 10)} Boosted</span>` : '', pledge.multiplier > 1 && !pledge.boosted ? `<span class="tag green">${TO.state.fmtMult(pledge.multiplier)} streak</span>` : ''].join('');
    const actions = opts && opts.compact ? '' : `<div class="pledge-actions">
      ${pledge.kind !== 'todo' ? `<button class="btn sm ghost" data-act="share" data-pledge="${pledge.id}">${icon('share', 16)} Share</button>` : ''}
    </div>`;
    return `<div class="card pledge-card">
      <div class="pledge-top"><div class="grow"><div class="t">${esc(challengeTitle(pledge))}</div><div class="small muted" style="margin-top:2px">${sub}</div></div><div class="multiplier">${TO.multiplierText(TO.pointValue.fromDecimal(pledge.decimal))}</div></div>
      ${perks ? `<div class="row-s">${perks}</div>` : ''}
      ${picks}
      ${pledgeRow}
      ${actions}
    </div>`;
  }

  function historyCard(pledge, opts) {
    const single = pledge.picks.length === 1;
    let result;
    if (pledge.status === 'won') result = `<span class="display green" style="font-size:22px">+${pledge.reward - pledge.pledgeMinutes} min</span>`;
    else if (pledge.status === 'lost') result = `<span class="display red" style="font-size:22px">−${pledge.pledgeMinutes} min</span>`;
    else result = `<span class="small bold muted">${pledge.insurancePaid ? 'Miss-one protection returned your minutes' : 'Committed minutes returned'} · ${pledge.pledgeMinutes} min</span>`;
    const picks = pledge.picks.map((l) => `<div class="pick"><span class="pick-dot ${l.result}">${icon({ won: 'check', lost: 'x' }[l.result] || 'minus', 12)}</span><div class="grow"><div class="lt">${esc(l.label)} <span class="faint" style="font-weight:600">${TO.pointValue.fmt(l.price)}</span></div><div class="lm">${esc(l.kind === 'todo' ? l.marketLabel : l.matchup)}${l.final ? ` · <b>${esc(l.final)}</b>` : ''}</div></div></div>`).join('');
    const why = pledge.status === 'void' ? `<div class="note warn">${icon('info', 15)}<span>${pledge.kind === 'todo' ? '' : 'The game was postponed or cancelled, so your committed minutes were returned.'}</span></div>` : '';
    return `<div class="card pledge-card">
      <div class="pledge-top"><div class="grow"><div class="row-s" style="margin-bottom:4px">${ui.statusPill(pledge.status)}${single ? '' : `<span class="tag">${pledge.kind === 'todo' ? 'To-do' : 'Combo Goal'}</span>`}</div><div class="t">${esc(challengeTitle(pledge))}</div></div><div style="text-align:right"><div class="multiplier" style="font-size:16px">${TO.multiplierText(TO.pointValue.fromDecimal(pledge.decimal))}</div>${result}</div></div>
      ${picks}
      ${why}
      <div class="row-layout tiny faint bold"><span>${pledge.pledgeMinutes} min committed · started ${TO.fmtDay(pledge.placedAt)} ${TO.fmtTime(pledge.placedAt)}</span><span>Updated ${TO.ago(pledge.resolvedAt)}</span></div>
      ${opts && opts.compact ? '' : pledge.kind !== 'todo' ? `<div class="pledge-actions"><button class="btn sm ghost" data-act="share" data-pledge="${pledge.id}">${icon('share', 16)} Share</button></div>` : ''}
    </div>`;
  }

  const challengeCard = (pledge, opts) => (pledge.status === 'open' ? openCard(pledge, opts) : historyCard(pledge, opts));
  const gamePick = (pick) => pick.kind === 'race' || pick.kind === 'game' || (pick.kind === 'sports' && !!pick.gameId);
  const isLiveChallenge = (pledge) => pledge.picks.some((pick) => pick.result === 'pending' && (pick.kind === 'race' ? TO.races.get(pick.raceId)?.status === 'running' : gamePick(pick) && S.game(pick.gameId)?.state === 'live'));

  function recordCard() {
    const st = TO.state.myStats();
    const wl = TO.state.wallet();
    const sports = Object.entries(st.bySport).sort((a, b) => (b[1].w + b[1].l) - (a[1].w + a[1].l)).slice(0, 5);
    const maxAbs = Math.max(1, ...sports.map(([, v]) => Math.abs(v.net)));
    return `<div class="card record-card stack">
      <div class="row-layout"><h2 style="margin:0;font-size:17px">Your record</h2>${st.recent.length ? `<span class="form-dots">${st.recent.map((x) => `<i class="${x}">${x}</i>`).join('')}</span>` : ''}</div>
      <div class="record-big">
        <div><b>${st.w}-${st.l}${st.v ? `-${st.v}` : ''}</b><span>Won-Lost${st.v ? '-Void' : ''}</span></div>
        <div><b>${st.pct === null ? '—' : `${st.pct}%`}</b><span>Win rate</span></div>
        <div><b class="${st.net > 0 ? 'green' : st.net < 0 ? 'red' : ''}">${TO.signed(st.net)}</b><span>Total minutes</span></div>
      </div>
      ${sports.length ? `<div class="sport-bars">${sports.map(([k, v]) => `<div class="sport-bar"><span class="muted">${esc(ui.leagueShort(k))}</span><div class="bar"><i class="${v.net < 0 ? 'neg' : ''}" style="width:${(Math.abs(v.net) / maxAbs) * 100}%"></i></div><span style="text-align:right" class="${v.net > 0 ? 'green' : v.net < 0 ? 'red' : 'muted'}">${TO.signedMin(v.net)}</span></div>`).join('')}</div>` : ''}
      <div class="row-layout small muted"><span>Today: <b class="${wl.todayNet > 0 ? 'green' : wl.todayNet < 0 ? 'red' : ''}">${TO.signedMin(wl.todayNet)}</b> so far</span></div>
    </div>`;
  }

  function render() {
    const challenges = TO.data.challenges.filter((b) => (b.kind === 'sports' || b.kind === 'race') && b.picks.length && b.picks.every(gamePick));
    const open = challenges.filter((b) => b.status === 'open').sort((a, b) => b.placedAt - a.placedAt);
    const liveNow = open.filter(isLiveChallenge);
    const otherOpen = open.filter((b) => !isLiveChallenge(b));
    let resolved = challenges.filter((b) => b.status !== 'open').sort((a, b) => b.resolvedAt - a.resolvedAt);
    const counts = { all: resolved.length, won: 0, lost: 0, void: 0 };
    resolved.forEach((b) => { if (b.status === 'won') counts.won++; else if (b.status === 'lost') counts.lost++; else counts.void++; });
    if (view.filter !== 'all') resolved = resolved.filter((b) => (view.filter === 'void' ? b.status === 'void' || b.status === 'tie' : b.status === view.filter));

    let list;
    if (view.tab === 'open') {
      list = open.length
        ? `${liveNow.length ? `<div class="eyebrow row-s" style="padding:2px 16px;margin-top:4px"><span class="live"></span>Live now <span class="count-pill">${liveNow.length}</span></div>${liveNow.map((b) => openCard(b)).join('')}` : ''}${otherOpen.length ? `<div class="eyebrow" style="padding:2px 16px;margin-top:4px">Upcoming</div>${otherOpen.map((b) => openCard(b)).join('')}` : ''}`
        : `<div class="empty">${icon('target', 40)}<h3>No active challenges</h3><p>Choose a challenge target from a matchup to start a pledge.</p><button class="btn primary" data-act="tab" data-tab="home">Find a matchup</button></div>`;
    } else {
      const chip = (k, t) => `<button class="chip sm ${view.filter === k ? 'on' : ''}" data-act="challenges-filter" data-f="${k}">${t}<span class="n">${counts[k]}</span></button>`;
      list = `<div class="hscroll">${chip('all', 'All')}${chip('won', 'Won')}${chip('lost', 'Lost')}${chip('void', 'Voided')}</div>`
        + (resolved.length ? resolved.map((b) => historyCard(b)).join('') : `<div class="empty">${icon('chart', 40)}<h3>${challenges.length ? 'Nothing here yet' : 'No completed challenges yet'}</h3><p>Completed challenges appear here after the matchup ends.</p>${challenges.length ? '' : '<button class="btn primary" data-act="tab" data-tab="home">Choose your first challenge</button>'}</div>`);
    }
    return `<div class="page-head"><h1>My Challenges</h1><p>Follow active challenges and review your earned minutes.</p></div>
      <div class="stack">
        ${recordCard()}
        <div class="pad"><div class="seg">
          <button class="${view.tab === 'open' ? 'on' : ''}" data-act="challenges-tab" data-t="open">Active <span class="count-pill ${open.length ? '' : 'off'}">${open.length}</span></button>
          <button class="${view.tab === 'history' ? 'on' : ''}" data-act="challenges-tab" data-t="history">Completed <span class="count-pill off">${counts.all}</span></button>
        </div></div>
        ${list}
      </div>`;
  }

  TO.views.challenges = { render, challengeCard, challengeTitle, toWin, view };
  TO.views.challenges = TO.views.challenges;

  // ---------- Share ----------
  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function wrapText(ctx, text, x, y, maxW, lineH, maxLines = 3) {
    const words = String(text).split(' ');
    let line = '', lines = 0;
    for (let i = 0; i < words.length; i++) {
      const test = line ? `${line} ${words[i]}` : words[i];
      if (ctx.measureText(test).width > maxW && line) {
        ctx.fillText(line, x, y); y += lineH; line = words[i]; lines++;
        if (lines >= maxLines - 1) { line = words.slice(i).join(' '); break; }
      } else line = test;
    }
    ctx.fillText(line, x, y);
    return y + lineH;
  }

  /** Draws the share image: teams, pick, challenge targets and pledge (PRD pledges sharing requirement). */
  async function drawShare(pledge) {
    try { await document.fonts.ready; } catch (e) { /* ignore */ }
    const W = 1080, H = 1350;
    const c = document.createElement('canvas');
    c.width = W; c.height = H;
    const ctx = c.getContext('2d');
    const D = '"Barlow Condensed", "Arial Narrow", sans-serif', B = 'Barlow, Arial, sans-serif';
    ctx.fillStyle = '#0a0d12'; ctx.fillRect(0, 0, W, H);
    const glow = ctx.createRadialGradient(W * 0.85, 60, 10, W * 0.85, 60, 700);
    glow.addColorStop(0, 'rgba(34,214,110,0.28)'); glow.addColorStop(1, 'rgba(34,214,110,0)');
    ctx.fillStyle = glow; ctx.fillRect(0, 0, W, H);

    // Wordmark
    ctx.font = `italic 900 84px ${D}`;
    ctx.fillStyle = '#f2f5f9'; ctx.fillText('Time', 80, 150);
    const tw = ctx.measureText('Time').width;
    ctx.fillStyle = '#22d66e'; ctx.fillText('Out', 80 + tw, 150);
    ctx.font = `700 30px ${B}`; ctx.fillStyle = '#8c96a8';
    ctx.fillText(`@${TO.account.username}'s pledge`, 80, 200);

    // Status pill
    const status = pledge.status.toUpperCase();
    const pillColor = { OPEN: '#1d2430', WON: '#22d66e', LOST: '#ff5a5f', VOID: '#5e687a', PUSH: '#5e687a' }[status];
    ctx.font = `900 30px ${B}`;
    const pw = ctx.measureText(status).width + 48;
    roundRect(ctx, W - 80 - pw, 104, pw, 56, 28); ctx.fillStyle = pillColor; ctx.fill();
    ctx.fillStyle = status === 'WON' ? '#03140a' : '#fff'; ctx.fillText(status, W - 80 - pw + 24, 143);

    // Card
    roundRect(ctx, 60, 260, W - 120, 800, 44); ctx.fillStyle = '#141922'; ctx.fill();
    ctx.strokeStyle = '#283141'; ctx.lineWidth = 3; ctx.stroke();

    let y = 340;
    const single = pledge.picks.length === 1 && pledge.picks[0].kind === 'game';
    if (single) {
      const g = S.game(pledge.picks[0].gameId);
      const disc = (team, cx) => {
        ctx.beginPath(); ctx.arc(cx, y + 90, 90, 0, Math.PI * 2); ctx.fillStyle = team.color; ctx.fill();
        ctx.lineWidth = 6; ctx.strokeStyle = 'rgba(255,255,255,0.15)'; ctx.stroke();
        ctx.fillStyle = '#fff'; ctx.font = `900 ${team.abbr.length > 3 ? 52 : 64}px ${D}`; ctx.textAlign = 'center'; ctx.fillText(team.abbr, cx, y + 112);
        ctx.font = `700 34px ${B}`; ctx.fillStyle = '#f2f5f9'; ctx.fillText(team.name, cx, y + 240);
      };
      disc(g.away, 300); disc(g.home, W - 300);
      ctx.font = `900 60px ${D}`; ctx.fillStyle = '#5e687a'; ctx.textAlign = 'center';
      ctx.fillText(g.state === 'live' || g.state === 'final' ? `${g.awayScore} – ${g.homeScore}` : '@', W / 2, y + 112);
      ctx.font = `700 26px ${B}`; ctx.fillStyle = '#8c96a8';
      ctx.fillText(g.state === 'live' ? `LIVE · ${g.clock}` : g.state === 'final' ? g.statusText : g.state === 'postponed' ? 'Postponed' : `${TO.fmtDay(g.start)} ${TO.fmtTime(g.start)}`, W / 2, y + 160);
      ctx.textAlign = 'left';
      y += 320;
      ctx.fillStyle = '#283141'; ctx.fillRect(110, y - 20, W - 220, 3);
      ctx.font = `700 30px ${B}`; ctx.fillStyle = '#8c96a8'; ctx.fillText(`${pledge.picks[0].marketLabel.toUpperCase()} · MY PICK`, 110, y + 40);
      ctx.font = `900 88px ${D}`; ctx.fillStyle = '#f2f5f9';
      y = wrapText(ctx, pledge.picks[0].label, 110, y + 130, W - 220, 90, 2);
    } else {
      ctx.font = `700 30px ${B}`; ctx.fillStyle = '#8c96a8';
      ctx.fillText(pledge.picks.length > 1 ? `${pledge.picks.length}-PICK Combo Goal` : 'MY PICK', 110, y + 10);
      y += 80;
      for (const l of pledge.picks) {
        ctx.font = `900 60px ${D}`; ctx.fillStyle = '#f2f5f9';
        ctx.fillText(l.label, 110, y + 30);
        ctx.font = `600 28px ${B}`; ctx.fillStyle = '#8c96a8';
        y = wrapText(ctx, `${l.marketLabel} · ${l.matchup}`, 110, y + 76, W - 360, 34, 2);
        ctx.font = `900 50px ${D}`; ctx.fillStyle = '#22d66e'; ctx.textAlign = 'right';
        ctx.fillText(TO.pointValue.fmt(l.price), W - 110, y - 60);
        ctx.textAlign = 'left';
        y += 30;
      }
    }

    // Bottom stats
    const by = 900;
    ctx.fillStyle = '#283141'; ctx.fillRect(110, by - 30, W - 220, 3);
    const col = (label, value, x, color) => {
      ctx.font = `700 26px ${B}`; ctx.fillStyle = '#8c96a8'; ctx.fillText(label, x, by + 20);
      ctx.font = `900 76px ${D}`; ctx.fillStyle = color; ctx.fillText(value, x, by + 100);
    };
    col('VALUE', TO.pointValue.fmt(pledge.american), 110, '#f2f5f9');
    col('PLEDGE', `${pledge.pledgeMinutes} min`, 420, '#f2f5f9');
    col(pledge.status === 'lost' ? 'LOST' : pledge.status === 'won' ? 'WON' : 'TO WIN', pledge.status === 'lost' ? `−${pledge.pledgeMinutes}` : `+${pledge.status === 'won' ? pledge.reward - pledge.pledgeMinutes : toWin(pledge)}`, 730, pledge.status === 'lost' ? '#ff5a5f' : '#22d66e');

    ctx.font = `600 30px ${B}`; ctx.fillStyle = '#8c96a8'; ctx.textAlign = 'center';
    ctx.fillText('Challenging screen time, not money.', W / 2, 1160);
    ctx.font = `italic 900 40px ${D}`; ctx.fillStyle = '#22d66e';
    ctx.fillText('TimeOut', W / 2, 1230);
    ctx.textAlign = 'left';
    return c.toDataURL('image/png');
  }

  function shareText(pledge) {
    const picks = pledge.picks.map((l) => `${l.label} (${TO.pointValue.fmt(l.price)}) · ${l.matchup}`).join('\n');
    const pledgeMinutes = `${pledge.pledgeMinutes} min of screen time to earn ${toWin(pledge)} min`;
    return `My TimeOut ${pledge.picks.length > 1 ? 'combo-goal' : 'pledge'}:\n${picks}\nOdds ${TO.pointValue.fmt(pledge.american)} · ${pledgeMinutes}`;
  }

  TO.actions.share = async (el) => {
    const pledge = TO.data.challenges.find((b) => b.id === el.dataset.pledge);
    if (!pledge) return;
    let url = '';
    ui.sheet('share', {
      render: () => ({
        title: 'Share pledge',
        body: `${url ? `<img class="share-img" src="${url}" alt="pledge card image showing the teams, pick, point value and pledge">` : '<div class="card muted small">Creating image…</div>'}
          <div class="small muted">${ui.embedded ? 'To save the image, right-click it or press and hold it.' : 'Save the image and post it anywhere.'}</div>
          <textarea class="textarea sr" id="share-text" readonly>${esc(shareText(pledge))}</textarea>`,
        foot: `${!ui.embedded && url ? `<a class="btn primary full" href="${url}" download="timeout-pledge.png" data-act="share-saved">${icon('share', 18)} Save image</a>` : ''}
          <div class="row"><button class="btn ghost grow" data-act="share-copy">${icon('copy', 16)} Copy pledge text</button></div>`,
      }),
    });
    url = await drawShare(pledge);
    ui.refreshSheet('share');
  };
  TO.actions['share-copy'] = async () => {
    const ok = await ui.copy(document.getElementById('share-text').value);
    ui.toast({ kind: ok ? 'win' : 'info', title: ok ? 'pledge copied' : 'Copy the text manually', msg: ok ? 'Paste it into any chat.' : '' });
  };
  TO.actions['share-saved'] = () => { /* default link behavior downloads the image */ };

  // ---------- My pledges actions ----------
  TO.actions['challenges-tab'] = (el) => { view.tab = el.dataset.t; TO.app.render(); };
  TO.actions['challenges-filter'] = (el) => { view.filter = el.dataset.f; TO.app.render(); };

  // ---------- To-do Combo Goal (Could-have) ----------
  const PRESETS = [['Read 20 pages', 'medium'], ['Wash the dishes', 'easy'], ['Fold laundry', 'easy'], ['Work out for 30 min', 'medium'], ['Study for 1 hour', 'hard'], ['Clean my room', 'medium'], ['No phone after 10 PM', 'hard']];
  const todo = { tasks: [{ text: '', difficulty: 'easy' }], pledgeMinutes: '10', error: '' };

  function todoBody() {
    const wl = TO.state.wallet();
    const picks = todo.tasks.filter((t) => t.text.trim());
    const dec = picks.reduce((p, t) => p * TO.pointValue.decimal(TO.state.TODO_VALUE[t.difficulty]), 1);
    const pledgeMinutes = parseInt(todo.pledgeMinutes, 10) || 0;
    const win = picks.length ? Math.round((Math.round(pledgeMinutes * dec) - pledgeMinutes) * wl.multiplier) : 0;
    return `<div class="small muted">Pledge minutes on getting things done today. Finish every task before midnight and you win; miss one and you lose the pledged minutes. Up to ${TO.RULES.maxPicks} tasks.</div>
      ${todo.tasks.map((t, i) => `<div class="card tight stack-s">
        <div class="row"><input class="input grow" id="todo-${i}" placeholder="Task ${i + 1}, like 'Read 20 pages'" value="${esc(t.text)}" maxlength="60">${todo.tasks.length > 1 ? `<button class="icon-btn" data-act="todo-del" data-i="${i}" aria-label="Remove task">${icon('x', 18)}</button>` : ''}</div>
        <div class="seg">${['easy', 'medium', 'hard'].map((d) => `<button class="${t.difficulty === d ? 'on' : ''}" data-act="todo-diff" data-i="${i}" data-d="${d}">${d[0].toUpperCase() + d.slice(1)} <span class="faint">${TO.pointValue.fmt(TO.state.TODO_VALUE[d])}</span></button>`).join('')}</div>
      </div>`).join('')}
      ${todo.tasks.length < TO.RULES.maxPicks ? `<button class="btn ghost sm" data-act="todo-add">${icon('plus', 16)} Add a task</button>` : ''}
      <div class="field"><span class="label">Quick add</span><div class="hscroll" style="padding:0">${PRESETS.map(([t, d]) => `<button class="chip sm" data-act="todo-preset" data-t="${esc(t)}" data-d="${d}">${esc(t)}</button>`).join('')}</div></div>
      <div class="field"><label for="todo-pledge">Minutes to pledge (max ${TO.RULES.todoMaxPledge})</label><input class="input" id="todo-pledge" type="number" min="1" max="${TO.RULES.todoMaxPledge}" value="${esc(todo.pledgeMinutes)}"></div>
      <div class="outcomes"><div class="w"><span>Finish them all</span><b>+${win} min</b><span>for tomorrow · ${picks.length ? TO.pointValue.fmt(TO.pointValue.fromDecimal(dec)) : '—'}</span></div><div class="l"><span>Miss one</span><b>−${pledgeMinutes} min</b><span>from tomorrow</span></div></div>
      ${todo.error ? `<div class="form-error">${esc(todo.error)}</div>` : ''}`;
  }

  TO.actions['todo-builder'] = () => {
    todo.error = '';
    ui.sheet('todo', { tall: true, render: () => ({ title: 'To-do Combo Goal', body: todoBody(), foot: `<button class="btn primary full" data-act="todo-place">Place to-do Combo Goal</button>` }) });
  };
  const refreshTodo = () => ui.refreshSheet('todo', ['body']);
  TO.actions['todo-add'] = () => { todo.tasks.push({ text: '', difficulty: 'easy' }); refreshTodo(); };
  TO.actions['todo-del'] = (el) => { todo.tasks.splice(Number(el.dataset.i), 1); refreshTodo(); };
  TO.actions['todo-diff'] = (el) => { todo.tasks[Number(el.dataset.i)].difficulty = el.dataset.d; refreshTodo(); };
  TO.actions['todo-preset'] = (el) => {
    const empty = todo.tasks.find((t) => !t.text.trim());
    if (empty) { empty.text = el.dataset.t; empty.difficulty = el.dataset.d; }
    else if (todo.tasks.length < TO.RULES.maxPicks) todo.tasks.push({ text: el.dataset.t, difficulty: el.dataset.d });
    else { ui.toast({ kind: 'warn', title: `Up to ${TO.RULES.maxPicks} tasks per Combo Goal` }); return; }
    refreshTodo();
  };
  TO.inputs['todo-pledge'] = (el) => { todo.pledgeMinutes = el.value; };
  for (let i = 0; i < 3; i++) TO.inputs[`todo-${i}`] = (el) => { todo.tasks[i].text = el.value; };
  TO.actions['todo-place'] = () => {
    if (!TO.net.guard()) return;
    try {
      TO.state.placeTodoCombo({ tasks: todo.tasks, pledgeMinutes: parseInt(todo.pledgeMinutes, 10) });
      ui.closeSheet('todo');
      ui.toast({ kind: 'win', title: 'To-do Combo Goal placed', msg: 'Check off each task in My Challenges before midnight.' });
      todo.tasks = [{ text: '', difficulty: 'easy' }]; todo.pledgeMinutes = '10'; todo.error = '';
      view.tab = 'open';
      TO.app.render();
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      todo.error = e.message;
      refreshTodo();
    }
  };
  TO.actions['todo-done'] = async (el) => {
    const pledge = TO.data.challenges.find((b) => b.id === el.dataset.pledge);
    const pick = pledge && pledge.picks[Number(el.dataset.i)];
    if (!pick) return;
    const ok = await ui.confirm({ title: 'Mark this task done?', body: `"${esc(pick.text)}"<br><br>TimeOut runs on the honor system for to-do combos. You can't undo this.`, confirm: 'It\'s done' });
    if (!ok) return;
    const resolved = TO.state.completeTodo(pledge.id, Number(el.dataset.i));
    if (resolved && resolved.status === 'won') ui.toast({ kind: 'win', title: `To-do Combo Goal won: +${resolved.reward - resolved.pledgeMinutes} min`, msg: 'Added to tomorrow\'s phone time.' });
    TO.app.render();
  };
})(window.TO);
