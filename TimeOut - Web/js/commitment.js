/* TimeOut web demo — pledges commitment (Screen 3). */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  const commitment = (TO.comboGoalBuilder = {
    selectedPicks: [],
    comboGoalMode: false, // picks stack up only in Combo Goal mode; otherwise a new pick replaces the old one
    stake: null,
    boost: false,
    insure: false,
    error: null,
    capped: false,
    notifiedChange: '',
    has(id) { return this.selectedPicks.some((l) => l.selId === id); },
    clear() {
      Object.assign(this, { selectedPicks: [], comboGoalMode: false, stake: null, boost: false, insure: false, error: null, capped: false, notifiedChange: '' });
    },
  });

  const refOf = (sel) => sel.gameId || sel.predId || sel.raceId;

  /** Tap on an challenge targets button. Outside Combo Goal mode the pick replaces whatever is on the commitment and opens it;
   *  in Combo Goal mode (Build Combo Goal on Home, or Add another pick) it's added, or swapped for a second pick on the same game. */
  commitment.toggle = (selId) => {
    if (commitment.has(selId)) {
      commitment.selectedPicks = commitment.selectedPicks.filter((l) => l.selId !== selId);
      afterChange();
      return;
    }
    const cur = S.currentSelection(selId);
    if (!cur || !cur.sel || !cur.open) { ui.toast({ kind: 'warn', title: 'Betting is closed on this pick' }); return; }
    const sel = cur.sel;
    const hasRace = commitment.selectedPicks.some((l) => String(l.ref).startsWith('race-'));
    if (commitment.comboGoalMode && (sel.kind === 'race' || hasRace)) {
      ui.toast({ kind: 'warn', title: 'Virtual races are single picks', msg: 'Use a virtual race pledge on its own, outside a Combo Goal.' });
      return;
    }
    const sameGame = commitment.selectedPicks.findIndex((l) => l.ref === refOf(sel));
    const leg = { selId: sel.id, price: sel.price, multiplier: TO.convertOddsToMultiplier(sel.price), line: sel.line, ref: refOf(sel) };
    if (!commitment.comboGoalMode) {
      commitment.selectedPicks = [leg];
      commitment.error = null;
      open();
      afterChange();
      return;
    }
    if (sameGame >= 0) {
      ui.toast({ kind: 'warn', title: 'One choice per matchup', msg: 'Remove the current choice before selecting another for this game.' });
      return;
    } else {
      if (commitment.selectedPicks.length >= TO.RULES.maxMatchupPicks) {
        ui.toast({ kind: 'warn', title: `Combo Goals allow up to ${TO.RULES.maxMatchupPicks} choices`, msg: 'Remove a choice to add another.' });
        return;
      }
      commitment.selectedPicks.push(leg);
    }
    commitment.error = null;
    if (ui.sheetOpen('commitment')) open();
    afterChange();
  };

  TO.actions['toggle-combo-goal'] = () => {
    const entering = !commitment.comboGoalMode;
    commitment.comboGoalMode = entering;
    commitment.selectedPicks = [];
    commitment.error = null;
    ui.closeSheet('commitment', true); // not discard(): that would also switch Combo Goal mode back off
    ui.closePage('combo-goal', true);
    TO.app.render();
  };

  function afterChange() {
    if (!commitment.selectedPicks.length) { ui.closeSheet('commitment'); ui.closePage('combo-goal', true); }
    else if (ui.sheetOpen('commitment')) ui.refreshSheet('commitment');
    TO.app.renderChrome();
    TO.app.refreshOddsButtons();
  }

  /** Closing the commitment (X, tapping outside, Escape) throws the picks away, so nothing lingers on Home. */
  function discard() {
    commitment.clear();
    ui.closePage('combo-goal', true);
    TO.app.renderChrome();
    TO.app.refreshOddsButtons();
  }

  function legState(leg) {
    const cur = S.currentSelection(leg.selId);
    const closed = !cur || !cur.sel || !cur.open;
    const changed = !closed && (cur.sel.price !== leg.price || cur.sel.line !== leg.line);
    return { cur, closed, changed };
  }

  commitment.status = () => {
    const states = commitment.selectedPicks.map(legState);
    return { states, closed: states.some((s) => s.closed), changed: states.some((s) => s.changed) };
  };

  function numbers() {
    const wl = TO.state.wallet();
    const stake = parseInt(commitment.stake, 10);
    const dec = commitment.selectedPicks.reduce((acc, pick) => acc * pick.multiplier, 1);
    let mult = wl.multiplier;
    if (commitment.boost && wl.boostsLeft > 0) mult *= 1 + TO.RULES.boostPercent;
    const s = Number.isFinite(stake) ? stake : 0;
    const rawTarget = s + Math.round((Math.round(s * dec) - s) * mult);
    const targetMinutes = Math.min(rawTarget, TO.MAX_ALLOWED_MINUTES);
    const winnings = Math.max(0, targetMinutes - s);
    return { wl, stake, dec, targetMultiplier: +dec.toFixed(2), rawTarget, targetMinutes, capApplied: rawTarget > TO.MAX_ALLOWED_MINUTES, mult, winnings, valid: Number.isInteger(stake) && stake >= 1 && stake <= wl.balance && TO.net.online() };
  }

  // ---------- Rendering ----------
  function legsHtml() {
    const st = commitment.status();
    const legs = commitment.selectedPicks.map((leg, i) => {
      const { cur, closed, changed } = st.states[i];
      const sel = cur && cur.sel;
      let title, sub, liveLine = '';
      if (String(leg.ref).startsWith('race-')) {
        const race = TO.races.get(leg.ref);
        const runner = sel && TO.races.horse(sel.horseId || sel.side);
        title = runner ? runner.name : 'Virtual race pick';
        sub = `Virtual Racing · Race #${esc(String(leg.ref).replace('race-', ''))}`;
        if (race && race.status === 'running') liveLine = `<div class="row-s tiny" style="margin-top:4px"><span class="live">LIVE</span><span class="muted bold">Race in progress</span></div>`;
        if (race && race.status === 'final') liveLine = `<div class="tiny muted bold" style="margin-top:4px">Race finished</div>`;
      } else if (leg.ref.startsWith('pm-')) {
        const p = S.prediction(leg.ref);
        title = sel ? S.selectionLabel(sel) : '';
        sub = `Prediction · ${esc(p.q)}`;
      } else {
        const g = S.game(leg.ref);
        title = sel ? S.selectionLabel(Object.assign({}, sel, { line: changed ? sel.line : leg.line }), g) : '';
        sub = `${S.marketLabel(sel || { market: 'ml' }, g)} · ${esc(g.away.name)} @ ${esc(g.home.name)}`;
        if (g.state === 'live') liveLine = `<div class="row-s tiny" style="margin-top:4px"><span class="live">LIVE</span><span class="muted bold">${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore} · ${esc(g.clock)}</span></div>`;
        if (g.state === 'postponed') liveLine = `<div class="tiny yellow bold" style="margin-top:4px">Postponed</div>`;
        if (g.state === 'final') liveLine = `<div class="tiny muted bold" style="margin-top:4px">Game over · ${esc(g.statusText)}</div>`;
      }
      const priceHtml = closed
        ? `<span class="tag red">Closed</span>`
        : changed
          ? `<div style="text-align:right"><span class="old">${TO.multiplierText(leg.price)}</span><span class="price" style="color:var(--warn)">${TO.multiplierText(sel.price)}</span>${sel.line !== leg.line ? `<div class="tiny yellow bold">Challenge target changed</div>` : ''}</div>`
          : `<span class="price">${TO.multiplierText(leg.price)}</span>`;
      return `<div class="commitment-leg ${closed ? 'closed' : changed ? 'changed' : ''}">
        <div class="grow"><div class="bold" style="font-size:15.5px">${esc(title)}</div><div class="small muted">${sub}</div>${liveLine}</div>
        ${priceHtml}
        <button class="icon-btn" style="width:30px;height:30px;margin:-4px -6px 0 0" data-act="commitment-remove" data-sel="${esc(leg.selId)}" aria-label="Remove pick">${icon('x', 16)}</button>
      </div>`;
    }).join('');
    let banner = '';
    if (st.closed) banner = `<div class="note red">${icon('alert', 16)}<span>A choice is no longer available (the game ended, was postponed, or challenges closed). Remove it to continue.</span></div>`;
    else if (st.changed) banner = `<div class="note warn">${icon('alert', 16)}<span>A challenge target changed while your commitment was open. Review it, then accept the update to continue.</span></div>`;
    const comboTarget = commitment.selectedPicks.reduce((acc, pick) => acc * pick.multiplier, 1);
    const combo = commitment.selectedPicks.length > 1 && !st.closed ? `<div class="row-layout small"><span class="muted bold">${commitment.selectedPicks.length}-pick Combo Goal · all choices count</span><span class="display" style="font-size:19px;color:var(--accent)">${comboTarget.toFixed(2)}x</span></div>` : '';
    return banner + legs + combo;
  }

  function summaryHtml() {
    const n = numbers();
    const { wl } = n;
    if (wl.lockedOut || wl.balance <= 0) return '';
    const stake = Number.isFinite(n.stake) ? n.stake : 0;
    let err = '';
    if (commitment.capped) err = `<div class="note red">${icon('alert', 16)}<span><b>Not enough screen time.</b> You have ${wl.balance} min available today.</span></div>`;
    else if (Number.isFinite(n.stake) && n.stake > wl.balance) err = `<div class="note red">${icon('alert', 16)}<span><b>Not enough screen time.</b> You have ${wl.balance} min available today.</span></div>`;
    else if (commitment.stake !== null && commitment.stake !== '' && (!Number.isFinite(n.stake) || n.stake < 1)) err = `<div class="note red">${icon('alert', 16)}<span>Enter a pledge of at least 1 minute.</span></div>`;
    const after = Math.max(wl.balance - stake, 0);
    return `${err}
      <div class="commitment-summary">
        <div class="row-layout small"><span>Committed Today</span><b>${n.valid ? stake : 0} min</b></div>
        <div class="row-layout small"><span>Combined Target</span><b class="green">${n.targetMultiplier.toFixed(2)}x</b></div>
        <div class="row-layout small"><span>Tomorrow's Projected Allowance</span><b class="green">${n.valid ? n.targetMinutes : 0} min</b></div>
        ${n.capApplied ? '<span class="tag yellow">Max Daily Cap Applied (120m max)</span>' : ''}
      </div>
      <div class="outcomes">
        <div class="w"><span>Earned Minutes</span><b>+${n.valid ? n.winnings : 0} min</b><span>added to tomorrow's phone time</span></div>
        <div class="l"><span>If a challenge is missed</span><b>−${n.valid ? stake : 0} min</b><span>from tomorrow's phone time</span></div>
      </div>
      <div class="row-layout small"><span class="muted">Available today after pledge</span><b class="num">${n.valid ? after : wl.balance} of ${wl.balance} min</b></div>
      ${commitment.error ? `<div class="form-error">${esc(commitment.error)}</div>` : ''}`;
  }

  function footHtml() {
    const st = commitment.status();
    const more = commitment.selectedPicks.length < TO.RULES.maxMatchupPicks && !st.closed ? `<button class="btn quiet sm" data-act="commitment-more">${icon('plus', 16)} Add another matchup choice</button>` : '';
    if (!TO.net.online()) return `<div class="note red">${icon('wifiOff', 16)}<span><b>No internet connection.</b> New pledges pause until you're back online.</span></div><button class="btn full" disabled>${icon('wifiOff', 18)} Waiting for connection</button>`;
    if (st.closed) return `<button class="btn primary full" disabled>Remove unavailable picks to continue</button>`;
    if (st.changed) return `<button class="btn warn full" data-act="commitment-accept">Accept updated target</button>`;
    const n = numbers();
    if (n.wl.lockedOut || n.wl.balance <= 0) return `<button class="btn full" disabled>${icon('lock', 18)} Betting locked until midnight</button>`;
    return `<button class="btn primary full" data-act="commitment-place" ${n.valid ? '' : 'disabled'}>${commitment.selectedPicks.length > 1 ? `Lock In ${commitment.selectedPicks.length}-Pick Combo Goal (${n.stake}m)` : `Confirm ${n.stake}m Pledge`}</button>${more}`;
  }

  function bodyHtml() {
    const wl = TO.state.wallet();
    if (commitment.stake === null) commitment.stake = String(Math.max(1, Math.min(TO.data.lastStake || 5, wl.balance || 1)));
    let controls;
    if (wl.lockedOut || wl.balance <= 0) {
      controls = `<div class="card" style="border-color:rgba(255,90,95,.4)"><div class="row-s red tiny bold" style="letter-spacing:.06em">${icon('lock', 14)} OUT OF PLEDGE MINUTES</div>
        <div class="bold" style="margin-top:6px">New bets are blocked until midnight.</div>
        <div class="display" style="font-size:36px;margin-top:4px">${ui.countdownEl(TO.nextMidnight())}</div>
        <div class="small muted">Your available pledge minutes reset at midnight.</div></div>`;
    } else {
      const quick = [15, 30, 45].map((v) => `<button data-act="commitment-quick" data-v="${v}" class="${String(v) === String(commitment.stake) ? 'on' : ''}" ${v > wl.balance ? 'disabled style="opacity:.35"' : ''}>${v}m</button>`).join('');
      const perks = [];
      if (wl.boostsLeft > 0) perks.push(`<label class="perk-row" for="commitment-boost"><span class="lr-icon" style="background:var(--blue-soft);color:var(--blue)">${icon('bolt', 17)}</span><span class="grow"><b>Allowance boost</b><div class="tiny muted">+10% earned minutes · ${wl.boostsLeft} left today (${esc(wl.tier.title)} perk)</div></span>${ui.switchEl('commitment-boost', commitment.boost, 'data-change="commitment-boost"')}</label>`);
      if (commitment.selectedPicks.length > 1 && wl.insuranceLeft > 0) perks.push(`<label class="perk-row" for="commitment-insure"><span class="lr-icon" style="background:rgba(197,140,255,.14);color:var(--purple)">${icon('shield', 17)}</span><span class="grow"><b>Miss-one protection</b><div class="tiny muted">Miss one choice and recover your committed minutes · 1 per week</div></span>${ui.switchEl('commitment-insure', commitment.insure, 'data-change="commitment-insure"')}</label>`);
      controls = `
        <div class="field">
          <label for="commitment-stake">Minutes to commit</label>
          <div class="stake-box">
            <button class="step" data-act="commitment-step" data-d="-1" aria-label="One minute less">${icon('minus', 20)}</button>
            <div class="stake-input"><input id="commitment-stake" type="number" inputmode="numeric" min="1" max="${wl.balance}" value="${esc(commitment.stake)}"><span>min</span></div>
            <button class="step" data-act="commitment-step" data-d="1" aria-label="One minute more">${icon('plus', 20)}</button>
          </div>
          <div class="quick">${quick}<button data-act="commitment-quick" data-v="${wl.balance}">Max Available</button></div>
        </div>
        <div class="note blue">${icon('info', 16)}<span>You're committing <b>tomorrow's phone time</b>. Minutes come from today's ${wl.balance} available minutes; successful challenges add to tomorrow's allowance.</span></div>
        ${perks.join('')}`;
    }
    return `<div class="stack-s" id="commitment-legs">${legsHtml()}</div>
      ${controls}
      <div class="stack-s" id="commitment-summary">${summaryHtml()}</div>`;
  }

  function open() {
    if (ui.sheetOpen('commitment')) { ui.refreshSheet('commitment'); return; }
    ui.sheet('commitment', {
      render: () => ({
        title: commitment.selectedPicks.length > 1 ? `${commitment.selectedPicks.length}-Pick Combo Goal` : 'Single Matchup Pledge',
        body: bodyHtml(),
        foot: footHtml(),
      }),
      onClose: discard,
    });
    TO.app.renderChrome();
  }
  commitment.open = open;

  /** Live refresh without touching the inputs the user may be typing in. */
  commitment.update = () => {
    const wrap = ui.layer().querySelector('[data-sheet="commitment"]');
    if (!wrap) return;
    const legs = wrap.querySelector('#commitment-legs');
    if (legs) legs.innerHTML = legsHtml();
    const sum = wrap.querySelector('#commitment-summary');
    if (sum) sum.innerHTML = summaryHtml();
    const foot = wrap.querySelector('.sheet-foot');
    if (foot) foot.innerHTML = footHtml();
    wrap.querySelector('.sheet-head h2').textContent = commitment.selectedPicks.length > 1 ? `${commitment.selectedPicks.length}-Pick Combo Goal` : 'Single Matchup Pledge';
  };

  // ---------- Combo Goal builder: a page of games to add picks from ----------
  function parlayPage() {
    const games = TO.views.home.boardGames().filter((g) => g.state === 'live' || g.state === 'scheduled');
    const inSlip = new Set(commitment.selectedPicks.map((l) => l.ref));
    const groups = S.LEAGUE_ORDER.filter((l) => games.some((g) => g.league === l)).map((l) => {
      const lg = games.filter((g) => g.league === l);
      return `<div class="league-head"><h3>${esc(S.LEAGUES[l].title)}</h3><span class="cnt">${lg.length} games</span></div>${lg.map((g) => TO.views.home.gameCard(g)).join('')}`;
    }).join('');
    const n = commitment.selectedPicks.length;
    const dec = commitment.selectedPicks.reduce((p, l) => p * TO.odds.decimal(l.price), 1);
    const full = n >= TO.RULES.maxMatchupPicks;
    return {
      title: 'Build a Combo Goal',
      body: `<div class="note blue">${icon('info', 16)}<span>Pick up to ${TO.RULES.maxMatchupPicks} sides from <b>different games</b>. Every pick has to win for the Combo Goal to pay. ${inSlip.size ? `Games already on your commitment are highlighted.` : ''}</span></div>
        <div class="combo-goal-days">${TO.views.home.dayBar()}</div>
        ${full ? `<div class="note warn">${icon('alert', 16)}<span>Your Combo Goal is full. Remove a pick on the commitment to add a different one.</span></div>` : ''}
        <div class="stack combo-goal-list">${groups || `<div class="empty">${icon('target', 36)}<h3>No games open for betting</h3><p>Check back when the next games start.</p></div>`}</div>
        <div class="page-fab combo-goal-fab"><button class="btn primary full" data-act="combo-goal-review" ${n ? '' : 'disabled'}><span class="count-pill" style="background:var(--accent-ink);color:var(--accent)">${n}</span>${n > 1 ? `Review ${n}-pick Combo Goal` : 'Review bet commitment'}${n > 1 ? `<span class="display" style="margin-left:auto;font-size:19px">${TO.odds.fmt(TO.odds.fromDecimal(dec))}</span>` : ''}</button></div>`,
    };
  }
  function openParlayPage() {
    ui.openPage('combo-goal', {
      render: parlayPage,
      // Going back returns to the commitment with the picks so far.
      onClose: () => { if (commitment.selectedPicks.length && !ui.sheetOpen('commitment')) open(); },
    });
  }
  /** True when the commitment sits beside the content instead of over it (the browser version overrides this). */
  commitment.docked = () => false;

  // ---------- Actions ----------
  const A = TO.actions;
  A['combo-goal-review'] = () => { ui.closePage('combo-goal'); TO.app.render(); };
  A.pick = (el) => commitment.toggle(el.dataset.sel);
  A['commitment-remove'] = (el) => { commitment.selectedPicks = commitment.selectedPicks.filter((l) => l.selId !== el.dataset.sel); afterChange(); };
  A['commitment-more'] = () => {
    commitment.comboGoalMode = true;
    if (!commitment.docked()) ui.closeSheet('commitment', true); // hide it without discarding the picks
    openParlayPage();
    TO.app.renderChrome();
  };
  A['open-commitment'] = () => open();
  A['commitment-quick'] = (el) => { commitment.stake = el.dataset.v; commitment.error = null; commitment.capped = false; ui.refreshSheet('commitment', ['body', 'foot']); };
  A['commitment-step'] = (el) => {
    const v = (parseInt(commitment.stake, 10) || 0) + Number(el.dataset.d);
    const max = TO.state.wallet().balance;
    commitment.capped = v > max;
    commitment.stake = String(Math.max(1, Math.min(v, max)));
    const input = document.getElementById('commitment-stake');
    if (input) input.value = commitment.stake;
    commitment.error = null;
    commitment.update();
  };
  A['commitment-accept'] = () => {
    for (const leg of commitment.selectedPicks) {
      const cur = S.currentSelection(leg.selId);
      if (cur && cur.sel) { leg.price = cur.sel.price; leg.multiplier = TO.convertOddsToMultiplier(cur.sel.price); leg.line = cur.sel.line; }
    }
    commitment.error = null;
    ui.refreshSheet('commitment');
  };
  A['commitment-place'] = () => {
    if (!TO.net.online()) { ui.refreshSheet('commitment'); return; }
    const n = numbers();
    try {
      const bet = TO.state.submitPledge({ picks: commitment.selectedPicks, stake: n.stake, boost: commitment.boost, insure: commitment.insure });
      const label = bet.legs.length > 1 ? `${bet.legs.length}-pick Combo Goal` : bet.legs[0].label;
      ui.toast({ kind: 'win', title: 'Pledge locked in', msg: `${label} · ${bet.stake} min committed. Track it in My Challenges.` });
      commitment.clear();
      ui.closeSheet('commitment');
      ui.closePage('combo-goal', true);
      TO.app.render();
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      commitment.error = e.code === 'odds_changed' ? null : e.message;
      if (e.code === 'odds_changed') ui.toast({ kind: 'warn', title: 'Challenge target changed', msg: 'Review the new odds and confirm again.' });
      ui.refreshSheet('commitment');
    }
  };

  // The stake can't go above today's betting balance: a bigger number snaps back to it.
  TO.inputs['commitment-stake'] = (el) => {
    const max = TO.state.wallet().balance;
    const n = parseInt(el.value, 10);
    commitment.capped = Number.isFinite(n) && n > max;
    if (commitment.capped) el.value = String(max);
    commitment.stake = el.value;
    commitment.error = null;
    el.classList.remove('bad');
    document.querySelectorAll('.quick button').forEach((b) => b.classList.toggle('on', b.dataset.v === el.value && b.textContent !== 'Max'));
    commitment.update();
  };
  TO.changes['commitment-boost'] = (el) => { commitment.boost = el.checked; commitment.update(); };
  TO.changes['commitment-insure'] = (el) => { commitment.insure = el.checked; commitment.update(); };
})(window.TO);
