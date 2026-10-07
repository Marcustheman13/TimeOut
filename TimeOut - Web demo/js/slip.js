/* TimeOut web demo — bet slip (Screen 3). */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;
  const ui = TO.ui;

  const slip = (TO.slip = {
    legs: [],
    mode: 'minutes',
    stake: null,
    friends: [],
    terms: '',
    boost: false,
    insure: false,
    error: null,
    notifiedChange: '',
    has(id) { return this.legs.some((l) => l.selId === id); },
    clear() {
      Object.assign(this, { legs: [], mode: 'minutes', stake: null, friends: [], terms: '', boost: false, insure: false, error: null, notifiedChange: '' });
    },
  });

  const refOf = (sel) => sel.gameId || sel.predId;

  /** Tap on an odds button: add (or remove) the pick. The first pick opens the slip right away. */
  slip.toggle = (selId) => {
    if (slip.has(selId)) {
      slip.legs = slip.legs.filter((l) => l.selId !== selId);
      afterChange();
      return;
    }
    const cur = S.currentSelection(selId);
    if (!cur || !cur.sel || !cur.open) { ui.toast({ kind: 'warn', title: 'Betting is closed on this pick' }); return; }
    const sel = cur.sel;
    const sameGame = slip.legs.findIndex((l) => l.ref === refOf(sel));
    const leg = { selId: sel.id, price: sel.price, line: sel.line, ref: refOf(sel) };
    if (sameGame >= 0) {
      slip.legs[sameGame] = leg;
      ui.toast({ kind: 'info', title: 'Pick swapped', msg: 'A parlay can only have one pick per game.', ms: 2600 });
    } else {
      if (slip.legs.length >= TO.RULES.maxLegs) {
        ui.toast({ kind: 'warn', title: `Parlays are limited to ${TO.RULES.maxLegs} picks`, msg: 'Remove a pick to add another.' });
        return;
      }
      slip.legs.push(leg);
    }
    slip.error = null;
    const wasEmpty = slip.legs.length === 1 && sameGame < 0;
    if (wasEmpty || ui.sheetOpen('slip')) open();
    afterChange();
  };

  function afterChange() {
    if (!slip.legs.length) { ui.closeSheet('slip'); }
    else if (ui.sheetOpen('slip')) ui.refreshSheet('slip');
    TO.app.renderChrome();
    TO.app.refreshOddsButtons();
  }

  function legState(leg) {
    const cur = S.currentSelection(leg.selId);
    const closed = !cur || !cur.sel || !cur.open;
    const changed = !closed && (cur.sel.price !== leg.price || cur.sel.line !== leg.line);
    return { cur, closed, changed };
  }

  slip.status = () => {
    const states = slip.legs.map(legState);
    return { states, closed: states.some((s) => s.closed), changed: states.some((s) => s.changed) };
  };

  function numbers() {
    const wl = TO.state.wallet();
    const stake = parseInt(slip.stake, 10);
    const dec = slip.legs.reduce((p, l) => p * TO.odds.decimal(l.price), 1);
    let mult = wl.multiplier;
    if (slip.boost && wl.boostsLeft > 0) mult *= 1 + TO.RULES.boostPercent;
    const s = Number.isFinite(stake) ? stake : 0;
    const winnings = Math.round((Math.round(s * dec) - s) * mult);
    return { wl, stake, dec, american: TO.odds.fromDecimal(dec), mult, winnings, valid: Number.isInteger(stake) && stake >= 1 && stake <= wl.balance };
  }

  // ---------- Rendering ----------
  function legsHtml() {
    const st = slip.status();
    const legs = slip.legs.map((leg, i) => {
      const { cur, closed, changed } = st.states[i];
      const sel = cur && cur.sel;
      let title, sub, liveLine = '';
      if (leg.ref.startsWith('pm-')) {
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
          ? `<div style="text-align:right"><span class="old">${TO.odds.fmt(leg.price)}</span><span class="price" style="color:var(--warn)">${TO.odds.fmt(sel.price)}</span>${sel.line !== leg.line ? `<div class="tiny yellow bold">Line moved</div>` : ''}</div>`
          : `<span class="price">${TO.odds.fmt(leg.price)}</span>`;
      return `<div class="slip-leg ${closed ? 'closed' : changed ? 'changed' : ''}">
        <div class="grow"><div class="bold" style="font-size:15.5px">${esc(title)}</div><div class="small muted">${sub}</div>${liveLine}</div>
        ${priceHtml}
        <button class="icon-btn" style="width:30px;height:30px;margin:-4px -6px 0 0" data-act="slip-remove" data-sel="${esc(leg.selId)}" aria-label="Remove pick">${icon('x', 16)}</button>
      </div>`;
    }).join('');
    let banner = '';
    if (st.closed) banner = `<div class="note red">${icon('alert', 16)}<span>A pick is no longer available (the game ended, was postponed, or betting closed). Remove it to continue.</span></div>`;
    else if (st.changed) banner = `<div class="note warn">${icon('alert', 16)}<span>The odds changed while your slip was open. Check the new odds, then tap <b>Accept new odds</b> to continue.</span></div>`;
    const parlay = slip.legs.length > 1 && !st.closed ? `<div class="spread small"><span class="muted bold">${slip.legs.length}-pick parlay · every pick must win</span><span class="display" style="font-size:19px;color:var(--accent)">${TO.odds.fmt(TO.odds.fromDecimal(slip.legs.reduce((p, l) => p * TO.odds.decimal(l.price), 1)))}</span></div>` : '';
    return banner + legs + parlay;
  }

  function summaryHtml() {
    if (slip.mode === 'friend') {
      const len = slip.terms.length;
      return `<div class="spread tiny"><span class="faint">No screen time at stake. Your friend has to accept.</span><span class="${len > TO.RULES.friendLimit ? 'red' : 'faint'} bold">${len}/${TO.RULES.friendLimit}</span></div>${slip.error ? `<div class="form-error">${esc(slip.error)}</div>` : ''}`;
    }
    const n = numbers();
    const { wl } = n;
    if (wl.lockedOut || wl.balance <= 0) return '';
    const stake = Number.isFinite(n.stake) ? n.stake : 0;
    let err = '';
    if (Number.isFinite(n.stake) && n.stake > wl.balance) err = `<div class="note red">${icon('alert', 16)}<span><b>Not enough screentime.</b> You have ${wl.balance} min left to bet today.</span></div>`;
    else if (slip.stake !== null && slip.stake !== '' && (!Number.isFinite(n.stake) || n.stake < 1)) err = `<div class="note red">${icon('alert', 16)}<span>Enter a stake of at least 1 minute.</span></div>`;
    const after = Math.max(wl.balance - stake, 0);
    return `${err}
      <div class="outcomes">
        <div class="w"><span>If you win</span><b>+${n.valid ? n.winnings : 0} min</b><span>added to tomorrow's phone time</span></div>
        <div class="l"><span>If you lose</span><b>−${n.valid ? stake : 0} min</b><span>taken from tomorrow's phone time</span></div>
      </div>
      <div class="spread small"><span class="muted">Betting balance after this bet</span><b class="num">${n.valid ? after : wl.balance} of ${wl.balance} min</b></div>
      ${n.mult > 1 ? `<div class="spread small"><span class="muted">Winnings multiplier${slip.boost ? ' (streak + boost)' : ' (clean streak)'}</span><b class="green">${TO.state.fmtMult(+n.mult.toFixed(3))}</b></div>` : ''}
      ${slip.error ? `<div class="form-error">${esc(slip.error)}</div>` : ''}`;
  }

  function footHtml() {
    const st = slip.status();
    const more = slip.legs.length < TO.RULES.maxLegs && !st.closed ? `<button class="btn quiet sm" data-act="slip-more">${icon('plus', 16)} Add another pick for a parlay</button>` : '';
    if (st.closed) return `<button class="btn primary full" disabled>Remove unavailable picks to continue</button>`;
    if (st.changed) return `<button class="btn warn full" data-act="slip-accept">Accept new odds</button>`;
    if (slip.mode === 'friend') {
      const ok = slip.friends.length && slip.terms.trim() && slip.terms.length <= TO.RULES.friendLimit;
      return `<button class="btn primary full" data-act="slip-place" ${ok ? '' : 'disabled'}>${icon('send', 18)} Send friend bet</button>${more}`;
    }
    const n = numbers();
    if (n.wl.lockedOut || n.wl.balance <= 0) return `<button class="btn full" disabled>${icon('lock', 18)} Betting locked until midnight</button>`;
    return `<button class="btn primary full" data-act="slip-place" ${n.valid ? '' : 'disabled'}>Place bet${n.valid ? ` · ${n.stake} min` : ''}</button>${more}`;
  }

  function bodyHtml() {
    const wl = TO.state.wallet();
    if (slip.stake === null) slip.stake = String(Math.max(1, Math.min(TO.data.lastStake || 5, wl.balance || 1)));
    let controls;
    if (slip.mode === 'friend') {
      const friends = TO.data.friends;
      const picker = friends.length
        ? `<div class="pick-friends">${friends.map((u) => { const p = TO.state.person(u); return p ? `<button class="pick-friend ${slip.friends.includes(u) ? 'on' : ''}" data-act="slip-friend" data-u="${esc(u)}"><img src="${esc(p.photo)}" alt="">${esc(u)}</button>` : ''; }).join('')}</div>`
        : `<div class="note">${icon('users', 16)}<span>You don't have friends on TimeOut yet. <button class="link-btn" data-act="goto-social">Find friends in Social</button></span></div>`;
      controls = `
        <div class="field"><span class="label">Send to</span>${picker}</div>
        <div class="field"><label for="slip-terms">What's on the line?</label>
          <textarea class="textarea" id="slip-terms" maxlength="${TO.RULES.friendLimit}" placeholder="Loser does the dishes">${esc(slip.terms)}</textarea>
          <div class="hscroll" style="padding:0">${TO.state.TERMS_EXAMPLES.map((t) => `<button class="chip sm" data-act="slip-term" data-t="${esc(t)}">${esc(t)}</button>`).join('')}</div>
        </div>`;
    } else if (wl.lockedOut || wl.balance <= 0) {
      controls = `<div class="card" style="border-color:rgba(255,90,95,.4)"><div class="row-s red tiny bold" style="letter-spacing:.06em">${icon('lock', 14)} OUT OF BETTING MINUTES</div>
        <div class="bold" style="margin-top:6px">New bets are blocked until midnight.</div>
        <div class="display" style="font-size:36px;margin-top:4px">${ui.countdownEl(TO.nextMidnight())}</div>
        <div class="small muted">You can still send this as a friend bet with a custom stake.</div></div>`;
    } else {
      const quick = [5, 10, 15, 30].map((v) => `<button data-act="slip-quick" data-v="${v}" class="${String(v) === String(slip.stake) ? 'on' : ''}" ${v > wl.balance ? 'disabled style="opacity:.35"' : ''}>${v}</button>`).join('');
      const perks = [];
      if (wl.boostsLeft > 0) perks.push(`<label class="perk-row" for="slip-boost"><span class="lr-icon" style="background:var(--blue-soft);color:var(--blue)">${icon('bolt', 17)}</span><span class="grow"><b>Use an odds boost</b><div class="tiny muted">+10% winnings · ${wl.boostsLeft} left today (${esc(wl.tier.title)} perk)</div></span>${ui.switchEl('slip-boost', slip.boost, 'data-change="slip-boost"')}</label>`);
      if (slip.legs.length > 1 && wl.insuranceLeft > 0) perks.push(`<label class="perk-row" for="slip-insure"><span class="lr-icon" style="background:rgba(197,140,255,.14);color:var(--purple)">${icon('shield', 17)}</span><span class="grow"><b>Parlay insurance</b><div class="tiny muted">Miss by one pick and get your stake back · 1 per week</div></span>${ui.switchEl('slip-insure', slip.insure, 'data-change="slip-insure"')}</label>`);
      controls = `
        <div class="field">
          <label for="slip-stake">Minutes to stake</label>
          <div class="stake-box">
            <button class="step" data-act="slip-step" data-d="-1" aria-label="One minute less">${icon('minus', 20)}</button>
            <div class="stake-input"><input id="slip-stake" type="number" inputmode="numeric" min="1" max="${wl.balance}" value="${esc(slip.stake)}"><span>min</span></div>
            <button class="step" data-act="slip-step" data-d="1" aria-label="One minute more">${icon('plus', 20)}</button>
          </div>
          <div class="quick">${quick}<button data-act="slip-quick" data-v="${wl.balance}">Max</button></div>
        </div>
        <div class="note blue">${icon('info', 16)}<span>You're betting with <b>tomorrow's phone time</b>. Stakes come out of today's ${wl.balance} betting minutes; wins add to tomorrow's limit and losses take away from it.</span></div>
        ${perks.join('')}`;
    }
    return `<div class="stack-s" id="slip-legs">${legsHtml()}</div>
      <div class="seg" role="tablist">
        <button class="${slip.mode === 'minutes' ? 'on' : ''}" data-act="slip-mode" data-m="minutes">${icon('hourglass', 15)} Screen time</button>
        <button class="${slip.mode === 'friend' ? 'on' : ''}" data-act="slip-mode" data-m="friend">${icon('users', 15)} Friend bet</button>
      </div>
      ${controls}
      <div class="stack-s" id="slip-summary">${summaryHtml()}</div>`;
  }

  function open() {
    if (TO.pendingChallenge) {
      slip.mode = 'friend';
      slip.friends = [TO.pendingChallenge];
      TO.pendingChallenge = null;
    }
    if (ui.sheetOpen('slip')) { ui.refreshSheet('slip'); return; }
    ui.sheet('slip', {
      render: () => ({
        title: slip.legs.length > 1 ? `Parlay · ${slip.legs.length} picks` : 'Bet Slip',
        body: bodyHtml(),
        foot: footHtml(),
      }),
      onClose: () => TO.app.renderChrome(),
    });
    TO.app.renderChrome();
  }
  slip.open = open;

  /** Live refresh without touching the inputs the user may be typing in. */
  slip.update = () => {
    const wrap = ui.layer().querySelector('[data-sheet="slip"]');
    if (!wrap) return;
    const legs = wrap.querySelector('#slip-legs');
    if (legs) legs.innerHTML = legsHtml();
    const sum = wrap.querySelector('#slip-summary');
    if (sum) sum.innerHTML = summaryHtml();
    const foot = wrap.querySelector('.sheet-foot');
    if (foot) foot.innerHTML = footHtml();
    wrap.querySelector('.sheet-head h2').textContent = slip.legs.length > 1 ? `Parlay · ${slip.legs.length} picks` : 'Bet Slip';
  };

  // ---------- Actions ----------
  const A = TO.actions;
  A.pick = (el) => slip.toggle(el.dataset.sel);
  A['slip-remove'] = (el) => { slip.legs = slip.legs.filter((l) => l.selId !== el.dataset.sel); afterChange(); };
  A['slip-more'] = () => { ui.closeSheet('slip'); TO.ui.toast({ kind: 'info', title: 'Pick another game', msg: 'Tap any odds to add it. Your slip is at the bottom of the screen.', ms: 3000 }); };
  A['open-slip'] = () => open();
  A['slip-mode'] = (el) => { slip.mode = el.dataset.m; slip.error = null; ui.refreshSheet('slip'); };
  A['slip-quick'] = (el) => { slip.stake = el.dataset.v; slip.error = null; ui.refreshSheet('slip', ['body', 'foot']); };
  A['slip-step'] = (el) => {
    const v = (parseInt(slip.stake, 10) || 0) + Number(el.dataset.d);
    slip.stake = String(Math.max(1, v));
    const input = document.getElementById('slip-stake');
    if (input) input.value = slip.stake;
    slip.error = null;
    slip.update();
  };
  A['slip-friend'] = (el) => {
    const u = el.dataset.u;
    slip.friends = slip.friends.includes(u) ? slip.friends.filter((x) => x !== u) : [...slip.friends, u];
    el.classList.toggle('on');
    slip.update();
  };
  A['slip-term'] = (el) => {
    slip.terms = el.dataset.t;
    const ta = document.getElementById('slip-terms');
    if (ta) ta.value = slip.terms;
    slip.update();
  };
  A['slip-accept'] = () => {
    for (const leg of slip.legs) {
      const cur = S.currentSelection(leg.selId);
      if (cur && cur.sel) { leg.price = cur.sel.price; leg.line = cur.sel.line; }
    }
    slip.error = null;
    ui.refreshSheet('slip');
    TO.tester.mark('odds');
  };
  A['slip-place'] = () => {
    const friend = slip.mode === 'friend' ? { with: slip.friends, terms: slip.terms } : null;
    const n = numbers();
    try {
      const bet = TO.state.placeBet({ picks: slip.legs, stake: n.stake, friend, boost: slip.boost, insure: slip.insure });
      const label = bet.legs.length > 1 ? `${bet.legs.length}-pick parlay` : bet.legs[0].label;
      if (friend) {
        ui.toast({ kind: 'win', title: `Friend bet sent to ${friend.with.join(', ')}`, msg: `"${bet.friend.terms}" · ${label}` });
        TO.tester.mark('friend');
      } else {
        ui.toast({ kind: 'win', title: 'Bet placed', msg: `${label} · ${bet.stake} min to win ${Math.round((Math.round(bet.stake * bet.decimal) - bet.stake) * bet.multiplier)} min. It's in My Bets.` });
        TO.tester.mark('place');
        if (bet.legs.some((l) => l.kind === 'pred')) TO.tester.mark('pred');
        if (TO.state.wallet().lockedOut) TO.tester.mark('zero');
      }
      slip.clear();
      ui.closeSheet('slip');
      TO.app.render();
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      if (e.code === 'not_enough') TO.tester.mark('overstake');
      slip.error = e.code === 'odds_changed' ? null : e.message;
      if (e.code === 'odds_changed') ui.toast({ kind: 'warn', title: 'Odds changed', msg: 'Review the new odds and confirm again.' });
      ui.refreshSheet('slip');
    }
  };

  TO.inputs['slip-stake'] = (el) => {
    slip.stake = el.value;
    slip.error = null;
    const n = parseInt(el.value, 10);
    el.classList.toggle('bad', Number.isFinite(n) && n > TO.state.wallet().balance);
    if (Number.isFinite(n) && n > TO.state.wallet().balance) TO.tester.mark('overstake');
    document.querySelectorAll('.quick button').forEach((b) => b.classList.toggle('on', b.dataset.v === el.value && b.textContent !== 'Max'));
    slip.update();
  };
  TO.inputs['slip-terms'] = (el) => { slip.terms = el.value; slip.error = null; slip.update(); };
  TO.changes['slip-boost'] = (el) => { slip.boost = el.checked; slip.update(); };
  TO.changes['slip-insure'] = (el) => { slip.insure = el.checked; slip.update(); };
})(window.TO);
