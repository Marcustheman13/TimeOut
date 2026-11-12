/* TimeOut web — the weekly report (menu > Weekly report). The server writes each report once a week; this only draws it. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const ui = TO.ui;

  /** Reports newest first, as the server returned them. `loaded` stays false until the first answer. */
  const weekly = (TO.weekly = { list: [], loaded: false, sel: 0 });

  const BADGE = { crushed: 'green', steady: 'blue', slipped: 'yellow', risky: 'red' };
  const unread = () => weekly.list.filter((r) => !r.read).length;
  weekly.unread = unread;

  let lastAt = 0;
  const announcedKey = () => `timeout.weekly.announced.${(TO.account && TO.account.server && TO.account.server.id) || ''}`;

  /** A banner the first time a new report is seen, once per week, and only if the person hasn't turned the report off. */
  function announceNew() {
    const newest = weekly.list[0];
    if (!newest || newest.read || !TO.data || TO.data.settings.notify.weekly === false) return;
    if (TO.store.get(announcedKey(), '') === newest.week) return;
    TO.store.set(announcedKey(), newest.week);
    ui.toast({ kind: 'info', title: 'Your weekly report is ready', msg: newest.report.headline, ms: 9000, onClick: () => TO.actions.settings({ dataset: { section: 'weekly' } }) });
  }

  const shouldLoad = () => !!(TO.account && TO.account.server && TO.api && TO.api.weeklyReports);

  /** Fetches the latest reports and updates the menu dots. Quiet when the server has none or can't be reached. */
  weekly.refresh = async (force = true) => {
    if (!shouldLoad()) return;
    if (!force && Date.now() - lastAt < 4 * 60 * 1000) return;
    const rows = await TO.api.weeklyReports();
    if (!rows || !TO.data) return;
    // A week opened a moment ago may not be marked read on the server yet, so keep what this device already knows.
    const seen = new Set(weekly.list.filter((r) => r.read).map((r) => r.week));
    weekly.list = rows.filter((r) => r && r.report && r.report.headline).map((r) => ({ week: String(r.weekStart), read: !!r.read || seen.has(String(r.weekStart)), report: r.report }));
    weekly.loaded = true;
    lastAt = Date.now();
    weekly.sel = Math.min(weekly.sel, Math.max(0, weekly.list.length - 1));
    if (TO.app && TO.app.renderChrome) TO.app.renderChrome();
    if (TO.app && TO.app.tab === 'home' && document.getElementById('view')) TO.app.renderView();
    announceNew();
    if (document.querySelector('[data-page="settings"] .weekly-page')) {
      ui.refreshPage('settings');
      weekly.markShown();
    }
  };

  /** Opening a report counts as reading it. */
  weekly.markShown = () => {
    const shown = weekly.list[weekly.sel];
    if (!shown || shown.read) return;
    shown.read = true;
    TO.api.markWeeklyReportRead(shown.week);
    if (TO.app && TO.app.renderChrome) TO.app.renderChrome();
    if (TO.app && TO.app.tab === 'home' && document.getElementById('view')) TO.app.renderView();
  };

  /** The Home card for a report nobody has opened yet. Opening it (Menu > Weekly report) takes the card away; a new report brings it back. */
  weekly.strip = () => {
    const newest = weekly.list[0];
    if (!newest || newest.read) return '';
    const r = newest.report;
    return `<button class="weekly-strip" data-act="settings" data-section="weekly">
      <span class="lr-icon">${icon('chart', 17)}</span>
      <span class="ws-main"><span class="ws-top"><b>Weekly report</b><span class="faint">${esc(r.range || '')}</span><span class="tag green">New</span></span><span class="ws-head">${esc(r.headline)}</span></span>
      <span class="faint">${icon('chevR', 16)}</span></button>`;
  };

  const toneOf = (status) => (status === 'under' ? 'green' : status === 'over' ? 'red' : 'faint');

  function dayTable(days) {
    if (!days) return '';
    const rows = days.map((d) => `<div class="wr-day"><span>${esc(d.weekday)}</span><span class="num">${d.used === null ? '–' : `${Number(d.used)} min`}</span><span class="num faint">${Number(d.limit)} min</span><b class="${toneOf(d.status)}">${d.status === 'none' ? '–' : d.status === 'over' ? 'Over' : 'Under'}</b></div>`).join('');
    return `<div class="stack-s"><div class="eyebrow">Day by day</div><div class="wr-days">${rows}</div></div>`;
  }

  function reportCard(r) {
    const tiles = (r.tiles || []).map((t) => `<div class="wr-tile"><b class="num">${esc(t.value)}</b><span>${esc(t.label)}</span></div>`).join('');
    return `<div class="card stack weekly-report">
      <div class="row-layout"><span class="tag ${BADGE[r.weekType] || 'blue'}">${esc(r.label || '')}</span><span class="small faint">${esc(r.range || '')}</span></div>
      <h2 class="wr-headline">${esc(r.headline)}</h2>
      <p class="wr-text">${esc(r.summary)}</p>
      ${tiles ? `<div class="wr-tiles">${tiles}</div>` : ''}
      <div class="wr-note"><div class="eyebrow">Worth noticing</div><p>${esc(r.insight)}</p></div>
      <div class="wr-note alt"><div class="eyebrow">Try this next week</div><p>${esc(r.suggestion && r.suggestion.text)}</p></div>
      ${dayTable(r.days)}
      <div class="tiny faint">Written by an AI from your own numbers. TimeOut pledges phone minutes, never money.</div>
    </div>`;
  }

  /** The body of the Weekly report page. */
  weekly.render = () => {
    if (!shouldLoad()) {
      return `<div class="card stack-s"><h2 style="margin:0;font-size:17px">Weekly report</h2><div class="small muted">Weekly reports are written for accounts that are signed in and synced. Log in to see yours.</div></div>`;
    }
    if (!weekly.loaded) return `<div class="small muted">Loading your reports…</div>`;
    if (!weekly.list.length) {
      return `<div class="card stack-s"><div class="row-s">${icon('chart', 18)}<h2 style="margin:0;font-size:17px">No report yet</h2></div>
        <div class="small muted">Every Monday morning TimeOut looks back at your week and writes you a short review: your challenge record, your net minutes and, once your phone has synced screen time, how you did against your limits. Your first one shows up here after a week with some activity.</div></div>`;
    }
    const shown = weekly.list[Math.min(weekly.sel, weekly.list.length - 1)];
    const earlier = weekly.list.map((r, i) => ({ r, i })).filter((x) => x.i !== weekly.sel);
    return `${reportCard(shown.report)}
      ${earlier.length ? `<div class="eyebrow">Other weeks</div><div class="list">${earlier.map(({ r, i }) => `<button class="list-row" data-act="weekly-open" data-i="${i}"><span class="lr-main"><div class="lr-title">${esc(r.report.headline)}</div><div class="lr-sub">${esc(r.report.range || '')}</div></span>${r.read ? '' : '<span class="tag green">New</span>'}</button>`).join('')}</div>` : ''}`;
  };

  TO.actions['weekly-open'] = (el) => {
    weekly.sel = Math.max(0, Math.min(weekly.list.length - 1, Number(el.dataset.i) || 0));
    weekly.markShown();
    if (ui.pageOpen('settings')) ui.refreshPage('settings');
  };
})(window.TO);
