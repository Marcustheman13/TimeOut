/* TimeOut web demo — shared UI: rendering helpers, sheets, dialogs, toasts and small components. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const S = TO.sim;

  const ui = (TO.ui = {});
  TO.actions = {};   // click handlers, keyed by data-act
  TO.inputs = {};    // input handlers, keyed by element id
  TO.changes = {};   // change handlers, keyed by data-change
  TO.views = {};
  ui.root = () => document.getElementById('screen');
  ui.layer = () => document.getElementById('layer');

  // ---------- Components ----------
  ui.teamBadge = (team, size) =>
    `<span class="team-badge" style="background:${team.color || 'var(--raised)'}${size ? `;width:${size}px;height:${size}px;font-size:${Math.round(size * 0.3)}px` : ''}">${team.logo ? `<img src="${esc(team.logo)}" alt="" onerror="this.style.display='none';this.nextElementSibling.style.display='grid'">` : ''}<span style="${team.logo ? 'display:none' : ''}">${esc(team.abbr)}</span></span>`;

  ui.tierBadge = (tierId, sm) => {
    const t = TO.state.tierById(tierId);
    return `<span class="tier-badge ${t.id === 'rookie' ? 'rookie' : ''} ${sm ? 'sm' : ''}" style="${t.id === 'rookie' ? '' : `background:${t.color}`}">${icon(t.icon, sm ? 11 : 13)}${esc(t.title)}</span>`;
  };

  ui.avatar = (src, cls = '') => `<img class="avatar ${cls}" src="${esc(src)}" alt="">`;

  ui.statusPill = (status) => {
    const label = { won: 'Won', lost: 'Lost', void: 'Void', push: 'Push', open: 'Open' }[status] || status;
    return `<span class="status-pill ${status}">${label.toUpperCase()}</span>`;
  };

  ui.oddsText = (price) => TO.odds.fmt(price);

  ui.leagueTitle = (id) => (id === 'pred' ? 'Predictions' : id === 'todo' ? 'To-Do' : id === 'parlay' ? 'Parlays' : (S.LEAGUES[id] || {}).title || id);
  ui.leagueShort = (id) => (id === 'pred' ? 'PRED' : id === 'todo' ? 'TO-DO' : id === 'parlay' ? 'PARLAY' : (S.LEAGUES[id] || {}).short || id);

  ui.gameStatus = (g) => {
    if (g.state === 'live') return `<span class="live">LIVE</span><span style="color:var(--text)">${esc(g.clock)}</span>`;
    if (g.state === 'scheduled') {
      const mins = Math.round((g.start - TO.now()) / TO.MIN);
      return `<span>${TO.fmtDay(g.start)} · ${TO.fmtTime(g.start)}</span>${mins <= 60 ? `<span class="faint">· starts in ${mins < 1 ? '<1' : mins} min</span>` : ''}`;
    }
    if (g.state === 'final') return `<span>${esc(g.statusText)}</span>`;
    if (g.state === 'canceled') return `<span class="yellow row-s">${icon('alert', 13)} Canceled · all bets voided, stakes returned</span>`;
    return `<span class="yellow row-s">${icon('alert', 13)} Postponed · all bets voided, stakes returned</span>`;
  };

  /** One odds button. Tapping adds or removes the pick on the bet slip. */
  ui.oddsBtn = (sel, { suspended, move, big, label } = {}) => {
    const on = TO.slip.has(sel.id);
    const locked = suspended;
    let ln = '';
    if (sel.market === 'spread') ln = TO.odds.fmtLine(sel.line);
    if (sel.market === 'total') ln = `${sel.side === 'over' ? 'O' : 'U'} ${TO.odds.fmtLine(sel.line, false)}`;
    const mv = move ? `<span class="mv ${move > 0 ? 'up' : 'down'}">${move > 0 ? '▲' : '▼'}</span>` : '';
    const inner = locked
      ? `${icon('lock', 14)}`
      : `${big && label ? `<span class="lbl">${esc(label)}</span>` : ''}${ln ? `<span class="ln">${ln}</span>` : ''}<span class="pr ${ln || (big && label) ? '' : 'solo'}">${mv}${ui.oddsText(sel.price)}</span>`;
    return `<button class="odds-btn ${on ? 'on' : ''} ${locked ? 'locked' : ''} ${big ? 'big' : ''}" data-act="pick" data-sel="${esc(sel.id)}" ${locked ? 'disabled' : ''} aria-pressed="${on}" aria-label="${esc(label || '')} ${ln} ${ui.oddsText(sel.price)}${locked ? ' suspended' : ''}">${inner}</button>`;
  };

  ui.countdownEl = (target, cls = '') => `<span class="${cls}" data-countdown="${target}">${TO.countdown(target - TO.now())}</span>`;

  ui.field = ({ id, label, type = 'text', value = '', placeholder = '', err, hint, attrs = '' }) => `
    <div class="field">
      <label for="${id}">${esc(label)}</label>
      ${type === 'password'
        ? `<div class="input-wrap"><input class="input ${err ? 'bad' : ''}" id="${id}" name="${id}" type="password" value="${esc(value)}" placeholder="${esc(placeholder)}" ${attrs}><button type="button" class="icon-btn" data-act="toggle-pw" data-for="${id}" aria-label="Show password">${icon('eye', 18)}</button></div>`
        : `<input class="input ${err ? 'bad' : ''}" id="${id}" name="${id}" type="${type}" value="${esc(value)}" placeholder="${esc(placeholder)}" ${attrs}>`}
      ${err ? `<div class="err">${esc(err)}</div>` : hint ? `<div class="hint">${esc(hint)}</div>` : ''}
    </div>`;

  ui.switchEl = (id, checked, attrs = '') => `<span class="switch"><input type="checkbox" id="${id}" ${checked ? 'checked' : ''} ${attrs}><span></span></span>`;

  // ---------- Sheets ----------
  let sheetSeq = 0;
  /** Opens a bottom sheet. Returns its id. `render` returns {title, body, foot}. */
  ui.sheet = (name, opts = {}) => {
    ui.closeSheet(name, true);
    const id = `sheet-${++sheetSeq}`;
    const wrap = document.createElement('div');
    wrap.className = 'sheet-wrap';
    wrap.dataset.sheet = name;
    wrap.id = id;
    wrap.style.cssText = 'position:absolute;inset:0;';
    wrap.innerHTML = `<div class="scrim" data-act="close-sheet" data-name="${name}"></div><div class="sheet ${opts.tall ? 'tall' : ''}" role="dialog" aria-modal="true"><div class="grab"></div><div class="sheet-head"><h2></h2><button class="icon-btn" data-act="close-sheet" data-name="${name}" aria-label="Close">${icon('x', 20)}</button></div><div class="sheet-body"></div><div class="sheet-foot" hidden></div></div>`;
    ui.layer().appendChild(wrap);
    wrap._opts = opts;
    ui.refreshSheet(name);
    return id;
  };

  ui.refreshSheet = (name, parts) => {
    const wrap = ui.layer().querySelector(`[data-sheet="${name}"]`);
    if (!wrap) return false;
    const r = wrap._opts.render ? wrap._opts.render() : {};
    const sheet = wrap.querySelector('.sheet');
    const which = parts || ['title', 'body', 'foot'];
    if (which.includes('title')) sheet.querySelector('.sheet-head h2').innerHTML = r.title || '';
    if (which.includes('body')) {
      const body = sheet.querySelector('.sheet-body');
      const st = body.scrollTop;
      body.innerHTML = r.body || '';
      body.scrollTop = st;
    }
    if (which.includes('foot')) {
      const foot = sheet.querySelector('.sheet-foot');
      foot.hidden = !r.foot;
      foot.innerHTML = r.foot || '';
    }
    if (wrap._opts.after) wrap._opts.after(sheet);
    return true;
  };

  ui.sheetOpen = (name) => !!ui.layer().querySelector(`[data-sheet="${name}"]`);
  ui.closeSheet = (name, silent) => {
    const wrap = ui.layer().querySelector(`[data-sheet="${name}"]`);
    if (!wrap) return;
    wrap.remove();
    if (!silent && wrap._opts.onClose) wrap._opts.onClose();
  };
  ui.closeAllSheets = () => ui.layer().querySelectorAll('[data-sheet]').forEach((w) => ui.closeSheet(w.dataset.sheet));

  // ---------- Pages (full-screen overlays: game detail, settings) ----------
  ui.openPage = (name, opts) => {
    ui.closePage(name, true);
    const el = document.createElement('div');
    el.className = 'page';
    el.dataset.page = name;
    el._opts = opts;
    el.innerHTML = `<div class="page-top"><button class="icon-btn" data-act="close-page" data-name="${name}" aria-label="Back">${icon('chevL', 22)}</button><div class="t"></div><div class="pt-right"></div></div><div class="page-scroll"></div>`;
    ui.layer().insertBefore(el, ui.layer().firstChild);
    ui.refreshPage(name);
    return el;
  };
  ui.refreshPage = (name) => {
    const el = ui.layer().querySelector(`[data-page="${name}"]`);
    if (!el) return false;
    const r = el._opts.render();
    el.querySelector('.page-top .t').innerHTML = r.title || '';
    el.querySelector('.pt-right').innerHTML = r.right || '';
    const sc = el.querySelector('.page-scroll');
    const st = sc.scrollTop;
    sc.innerHTML = r.body || '';
    sc.scrollTop = st;
    if (el._opts.after) el._opts.after(el);
    return true;
  };
  ui.pageOpen = (name) => !!ui.layer().querySelector(`[data-page="${name}"]`);
  ui.closePage = (name, silent) => {
    const el = ui.layer().querySelector(`[data-page="${name}"]`);
    if (el) { el.remove(); if (!silent && el._opts.onClose) el._opts.onClose(); }
  };
  ui.closeAllPages = () => ui.layer().querySelectorAll('[data-page]').forEach((p) => p.remove());

  // ---------- Dialogs (the artifact viewer blocks window.confirm, so this is in-page) ----------
  ui.confirm = ({ title, body, confirm = 'Confirm', cancel = 'Cancel', danger = false, tone }) =>
    new Promise((resolve) => {
      const wrap = document.createElement('div');
      wrap.style.cssText = 'position:absolute;inset:0;z-index:40';
      wrap.innerHTML = `<div class="scrim"></div><div class="dialog-wrap"><div class="dialog" role="alertdialog" aria-modal="true" aria-labelledby="dlg-t"><h3 id="dlg-t">${title}</h3><div class="body">${body || ''}</div><div class="acts">${cancel ? `<button class="btn ghost" data-r="0">${esc(cancel)}</button>` : ''}<button class="btn ${danger ? 'danger' : tone || 'primary'}" data-r="1">${esc(confirm)}</button></div></div></div>`;
      ui.layer().appendChild(wrap);
      const done = (v) => { wrap.remove(); resolve(v); };
      wrap.addEventListener('click', (e) => {
        const b = e.target.closest('[data-r]');
        if (b) done(b.dataset.r === '1');
        else if (e.target.classList.contains('scrim') || e.target.classList.contains('dialog-wrap')) done(false);
      });
      setTimeout(() => { const b = wrap.querySelector('[data-r="1"]'); if (b) b.focus(); }, 30);
    });

  // ---------- Toasts ----------
  ui.toast = ({ title, msg = '', kind = 'info', ms = 4200 }) => {
    const host = document.getElementById('toasts');
    if (!host) return;
    const ic = { win: 'check', loss: 'x', warn: 'alert', info: 'info' }[kind] || 'info';
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.setAttribute('role', 'status');
    el.innerHTML = `${icon(ic, 20)}<div class="grow"><div class="tt">${esc(title)}</div>${msg ? `<div class="tm">${esc(msg)}</div>` : ''}</div>`;
    const kill = () => { el.classList.add('out'); setTimeout(() => el.remove(), 260); };
    el.addEventListener('click', kill);
    host.appendChild(el);
    while (host.children.length > 3) host.firstChild.remove();
    setTimeout(kill, ms);
  };
  TO.on('toast', (t) => ui.toast(t));

  // ---------- Images ----------
  /** Reads an uploaded photo and returns a square 256px JPEG data URL. */
  ui.readPhoto = (file) =>
    new Promise((resolve, reject) => {
      if (!file || !/^image\//.test(file.type)) return reject(new Error('Choose an image file.'));
      const reader = new FileReader();
      reader.onload = () => {
        const img = new Image();
        img.onload = () => {
          const size = 256;
          const c = document.createElement('canvas');
          c.width = c.height = size;
          const ctx = c.getContext('2d');
          const s = Math.min(img.width, img.height);
          ctx.drawImage(img, (img.width - s) / 2, (img.height - s) / 2, s, s, 0, 0, size, size);
          resolve(c.toDataURL('image/jpeg', 0.85));
        };
        img.onerror = () => reject(new Error('That image could not be read.'));
        img.src = reader.result;
      };
      reader.onerror = () => reject(new Error('That image could not be read.'));
      reader.readAsDataURL(file);
    });

  ui.copy = async (text, input) => {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (e) {
      if (input) { input.focus(); input.select(); }
      return false;
    }
  };

  /** True when running inside the claude.ai artifact viewer (downloads are blocked there). */
  ui.embedded = (() => { try { return window.self !== window.top; } catch (e) { return true; } })();
})(window.TO);
