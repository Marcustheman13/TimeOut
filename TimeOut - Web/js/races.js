/* TimeOut virtual horse racing: track animation and screen-time race selections. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;

  const horses = [
    { id: 1, number: 1, name: 'Midnight Surge', americanOdds: 180, form: '2-1-2', jockey: 'R. Vance', color: '#4fb3ff', speed: 1.025, variance: 0.18 },
    { id: 2, number: 2, name: 'Silicon Sprint', americanOdds: 220, form: '1-3-1', jockey: 'K. Chen', color: '#22d66e', speed: 1.018, variance: 0.19 },
    { id: 3, number: 3, name: 'Digital Blitz', americanOdds: 260, form: '3-2-1', jockey: 'T. Hayes', color: '#ffc940', speed: 1.010, variance: 0.20 },
    { id: 4, number: 4, name: 'Golden Hour', americanOdds: 310, form: '2-1-4', jockey: 'L. Moreno', color: '#ff718d', speed: 1.002, variance: 0.21 },
    { id: 5, number: 5, name: 'Circuit Breaker', americanOdds: 380, form: '1-4-2', jockey: 'D. Sterling', color: '#c58cff', speed: 0.995, variance: 0.22 },
  ];
  const KEY = 'timeout.virtualRaces';
  const saved = TO.store.get(KEY, null) || { next: 48, current: null, history: [] };
  let data = saved;
  let mounted = null;
  let frame = 0;
  let lastComment = 0;

  function persist() { TO.store.set(KEY, data); }
  function current() {
    if (!data.current) data.current = { number: data.next || 48, status: 'open' };
    return data.current;
  }
  function get(raceId) {
    const number = Number(String(raceId).replace(/^race-/, ''));
    const active = current();
    if (active.number === number) return active;
    return data.history.find((race) => race.number === number) || null;
  }
  const horse = (id) => horses.find((item) => item.id === Number(id)) || horses[0];
  const selectionId = (race, runner) => `race-${race.number}|race|${runner.id}`;
  function selection(race, runner) {
    return { id: selectionId(race, runner), raceId: `race-${race.number}`, horseId: runner.id, kind: 'race', market: 'race', side: String(runner.id), line: null, price: runner.americanOdds };
  }
  function currentSelection(selId) {
    const [ref, market, side] = String(selId).split('|');
    if (market !== 'race') return null;
    const race = get(ref);
    const runner = horse(side);
    return { sel: selection(race || { number: Number(ref.replace(/^race-/, '')) }, runner), open: !!race && race.status === 'open' };
  }
  function selectionLabel(sel) { return horse(sel.horseId || sel.side).name; }
  function implied(american) { return american > 0 ? 100 / (american + 100) : Math.abs(american) / (Math.abs(american) + 100); }
  function weightedWinner(seed) {
    const rng = TO.rng(seed);
    const total = horses.reduce((sum, h) => sum + implied(h.americanOdds), 0);
    let roll = rng() * total;
    for (const h of horses) { roll -= implied(h.americanOdds); if (roll <= 0) return h.id; }
    return horses[0].id;
  }
  function beginRace(race, seed, now = TO.now(), pledgeId = null) {
    const winnerId = weightedWinner(`${race.number}-${seed}-${now}`);
    const rest = horses.filter((h) => h.id !== winnerId).sort((a, b) => {
      const ra = TO.u01(`${seed}-${a.id}`) * a.speed;
      const rb = TO.u01(`${seed}-${b.id}`) * b.speed;
      return rb - ra;
    });
    race.status = 'running';
    race.startedAt = now;
    race.finishAt = now + 12000;
    race.winnerId = winnerId;
    race.order = [winnerId, ...rest.map((h) => h.id)];
    race.pledgeId = pledgeId;
    persist();
  }
  function startForBet(pledge, now = TO.now()) {
    const race = current();
    const leg = pledge.legs[0];
      if (race.status !== 'open' || leg.raceId !== `race-${race.number}`) throw new TO.AppError('closed', 'That race challenge is closed.');
    beginRace(race, pledge.id, now, pledge.id);
  }
  function startForViewing() {
    const race = current();
    if (race.status !== 'open') return;
    beginRace(race, `watch-${TO.uid('race')}`);
  }
  function finalize(race, now) {
    if (!race || race.status !== 'running' || now < race.finishAt) return;
    race.status = 'final';
    race.finishedAt = race.finishAt;
    data.history.unshift({ ...race });
    data.history = data.history.slice(0, 20);
    data.next = race.number + 1;
    data.current = { number: data.next, status: 'open' };
    persist();
  }
  function grade(sel, now = TO.now()) {
    const race = get(sel.raceId || sel.id.split('|')[0]);
    if (!race) return 'void';
    finalize(race, now);
    if (race.status !== 'final') return 'pending';
    return race.winnerId === Number(sel.horseId || sel.side) ? 'won' : 'lost';
  }

  function statusText(race) {
    if (race.status === 'running') return 'Race in progress';
    return race.status === 'final' ? `Race #${race.number} finished` : 'Challenge open';
  }
  function latestResultHtml(race) {
    return race ? `<div class="card race-card race-result"><span class="eyebrow">Last result · Race #${race.number}</span><b>${esc(horse(race.winnerId).name)} won</b><span class="small muted">${race.order.map((id, i) => `${i + 1}. ${esc(horse(id).name)}`).join(' · ')}</span></div>` : '';
  }
  function rosterHtml(race) {
    return horses.map((runner) => {
      const sel = selection(race, runner);
      const isWinner = race.status === 'final' && race.winnerId === runner.id;
      return `<div class="race-entry ${isWinner ? 'race-winner' : ''}">
        <div class="race-horse-info"><span class="race-silk" style="--silk:${runner.color}">#${runner.number}</span><span class="race-horse-copy"><b>${esc(runner.name)}</b><small>Form ${runner.form} · ${esc(runner.jockey)}</small></span></div>
        <div class="race-target">${TO.ui.challengeChoiceButton(sel, { suspended: race.status !== 'open', big: true, label: runner.name })}</div>
      </div>`;
    }).join('');
  }
  function render() {
    const race = current();
    const latest = data.history[0];
    return `<div class="stack race-page" data-race-id="${race.number}" data-race-status="${race.status}">
      <div class="page-head"><h1>Virtual Racing</h1><p>Pick a winner and stake screen-time minutes using your regular Daily Commitment.</p></div>
      <div class="card race-card">
        <div class="race-card-head"><div><span id="race-status" class="tag ${race.status === 'running' ? 'red' : 'green'}">${esc(statusText(race))}</span><span class="race-caption">· 1,200m Cyber Turf Classic #${race.number}</span></div><span class="race-clock" id="race-clock">12 sec</span></div>
        <div class="race-track-wrap"><canvas class="race-track" id="race-track" aria-label="Animated virtual horse race"></canvas><div class="race-finish-line" aria-hidden="true"></div></div>
        <div class="race-caller"><span>${icon('radio', 14)} Caller</span><span id="race-commentary">${race.status === 'running' ? 'The field is underway!' : 'Welcome to Silicon Downs. Select a horse to add it to your Daily Commitment.'}</span></div>
        <button class="btn primary full" id="race-start" data-act="race-start" ${race.status === 'open' ? '' : 'disabled'}>${race.status === 'open' ? 'Start race now' : race.status === 'running' ? 'Race in progress' : 'Race finished'}</button>
      </div>
      <div class="card race-card stack-s">
        <div class="row-layout"><div><h2 class="race-heading">Race targets</h2><div class="small muted">Choose a target to open your standard screen-time Daily Commitment.</div></div><span class="tag">5 runners</span></div>
        <div id="race-roster" class="race-roster">${rosterHtml(race)}</div>
        <div class="note blue">${icon('info', 16)}<span>Lock in pledge to start the race with your pick, or start it now to watch without a pledge. Pledges use your available screen-time minutes.</span></div>
      </div>
      ${latestResultHtml(latest)}
    </div>`;
  }

  function drawHorse(ctx, x, y, runner, elapsed) {
    const phase = elapsed / 90 + runner.id;
    ctx.save();
    ctx.translate(x, y);
    ctx.strokeStyle = runner.color; ctx.lineWidth = 3; ctx.lineCap = 'round';
    ctx.fillStyle = runner.color;
    ctx.beginPath(); ctx.ellipse(0, 0, 13, 7, 0, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.moveTo(8, -2); ctx.lineTo(17, -13); ctx.lineTo(22, -10); ctx.lineTo(19, -1); ctx.fill();
    ctx.fillStyle = '#f2f5f9'; ctx.beginPath(); ctx.arc(0, -10, 3, 0, Math.PI * 2); ctx.fill();
    const swing = Math.sin(phase) * 7;
    for (const [ax, dir] of [[-8, -1], [-3, 1], [6, -1], [10, 1]]) {
      ctx.beginPath(); ctx.moveTo(ax, 4); ctx.lineTo(ax + swing * dir, 15); ctx.stroke();
    }
    ctx.fillStyle = '#080d14'; ctx.beginPath(); ctx.roundRect(-5, -4, 10, 8, 2); ctx.fill();
    ctx.fillStyle = '#fff'; ctx.font = '700 7px system-ui'; ctx.textAlign = 'center'; ctx.fillText(String(runner.number), 0, 2);
    ctx.restore();
  }
  function paint(canvas, race, now) {
    if (!canvas || !canvas.isConnected) return;
    const box = canvas.getBoundingClientRect();
    if (!box.width) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (canvas.width !== Math.round(box.width * dpr) || canvas.height !== Math.round(250 * dpr)) {
      canvas.width = Math.round(box.width * dpr);
      canvas.height = Math.round(250 * dpr);
    }
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const w = box.width, h = 250;
    ctx.fillStyle = '#0a0d12'; ctx.fillRect(0, 0, w, h);
    const top = 20, lane = 42, start = 40, finish = w - 36;
    for (let i = 0; i < horses.length; i++) {
      const y = top + i * lane;
      ctx.fillStyle = i % 2 ? '#111720' : '#151d27'; ctx.fillRect(0, y, w, lane);
      ctx.strokeStyle = '#283141'; ctx.setLineDash([5, 6]); ctx.beginPath(); ctx.moveTo(0, y + lane); ctx.lineTo(w, y + lane); ctx.stroke(); ctx.setLineDash([]);
      ctx.fillStyle = '#5e687a'; ctx.font = '11px system-ui'; ctx.fillText(String(i + 1), 12, y + 24);
    }
    ctx.strokeStyle = '#8c96a8'; ctx.globalAlpha = 0.6; ctx.beginPath(); ctx.moveTo(start, top); ctx.lineTo(start, top + lane * horses.length); ctx.stroke(); ctx.globalAlpha = 1;
    ctx.fillStyle = '#f2f5f9';
    for (let y = top; y < top + lane * horses.length; y += 9) ctx.fillRect(finish - 3, y, 5, 5);
    const elapsed = race.status === 'running' ? Math.max(0, now - race.startedAt) : race.status === 'final' ? 12000 : 0;
    const order = race.order || horses.map((h) => h.id);
    const ranks = new Map(order.map((id, i) => [id, i]));
    horses.forEach((runner, idx) => {
      let progress = 0;
      if (race.status === 'running' || race.status === 'final') {
        const rank = ranks.get(runner.id) || 0;
        const duration = 9400 + rank * 450;
        progress = Math.min(1, elapsed / duration);
      }
      const x = start + progress * (finish - start - 12);
      const y = top + idx * lane + lane / 2;
      drawHorse(ctx, x, y, runner, elapsed);
    });
  }
  function updateMounted() {
    if (!mounted || !mounted.isConnected) { mounted = null; return; }
    const race = current();
    const page = mounted.querySelector('.race-page');
    if (page && page.dataset.raceId !== String(race.number)) {
      page.dataset.raceId = race.number;
      page.dataset.raceStatus = race.status;
      const statusTag = mounted.querySelector('#race-status');
      if (statusTag) statusTag.outerHTML = `<span id="race-status" class="tag green">Challenge open</span>`;
      const caption = mounted.querySelector('.race-caption');
      if (caption) caption.textContent = `· 1,200m Cyber Turf Classic #${race.number}`;
      const roster = mounted.querySelector('#race-roster');
      if (roster) roster.innerHTML = rosterHtml(race);
      const result = mounted.querySelector('.race-result');
      if (result) result.outerHTML = latestResultHtml(data.history[0]);
      else if (data.history[0]) page.insertAdjacentHTML('beforeend', latestResultHtml(data.history[0]));
      const comment = mounted.querySelector('#race-commentary');
      if (comment) comment.textContent = 'The previous race is official. Choose your next screen-time challenge.';
    } else if (page && page.dataset.raceStatus !== race.status) {
      page.dataset.raceStatus = race.status;
      const roster = mounted.querySelector('#race-roster');
      if (roster) roster.innerHTML = rosterHtml(race);
    }
    const statusTag = mounted.querySelector('#race-status');
    if (statusTag && race.status === 'running') { statusTag.textContent = 'Race in progress'; statusTag.className = 'tag red'; }
    const startButton = mounted.querySelector('#race-start');
    if (startButton) {
      startButton.disabled = race.status !== 'open';
      startButton.textContent = race.status === 'open' ? 'Start race now' : race.status === 'running' ? 'Race in progress' : 'Race finished';
    }
    const clock = mounted.querySelector('#race-clock');
    if (clock) clock.textContent = race.status === 'running' ? `${Math.max(0, Math.ceil((race.finishAt - TO.now()) / 1000))} sec` : '12 sec';
    const canvas = mounted.querySelector('#race-track');
    paint(canvas, race, TO.now());
    if (race.status === 'running' && TO.now() >= race.finishAt) {
      finalize(race, TO.now());
      TO.app.tick(true);
    }
    if (race.status === 'running' && TO.now() - lastComment > 2200) {
      lastComment = TO.now();
      const leader = (race.order || []).find((id, index) => (TO.now() - race.startedAt) / (9400 + index * 450) < 1) || race.order[0];
      const comment = mounted.querySelector('#race-commentary');
      if (comment) comment.textContent = `#${horse(leader).number} ${horse(leader).name} is driving for the lead.`;
    }
    if (mounted) frame = requestAnimationFrame(updateMounted);
  }
  function mount(page) {
    mounted = page;
    cancelAnimationFrame(frame);
    updateMounted();
  }

  TO.races = { horses, current, get, horse, currentSelection, selectionLabel, startForBet, grade, mount };
  TO.actions['race-start'] = startForViewing;
  TO.views.races = { render };
})(window.TO);
