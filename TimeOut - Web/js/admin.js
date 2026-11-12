/* Website-only admin dashboard. Database RPCs enforce authorization independently of this UI. */
(function (TO) {
  'use strict';

  const ADMIN_PAGE_KEY = 'timeout.web.admin.open';
  const ADMIN_PAGE_USER_KEY = 'timeout.web.admin.user';
  const ADMIN_USERNAMES = new Set(['easton.putnam', 'time_out_account', 'wrfairholm', 'obr0']);
  const wasOpen = (() => { try { return sessionStorage.getItem(ADMIN_PAGE_KEY) === '1'; } catch (e) { return false; } })();
  const state = { active: wasOpen, users: [], loading: false, error: '', metricErrors: {}, metrics: {}, query: '', editing: null, saving: false, refreshedAt: 0 };
  const { esc, icon } = TO;
  const ui = TO.ui;
  const app = TO.app;

  const apiReady = () => !!(TO.account?.server && TO.api.configured && TO.api.hasToken());
  const setActive = (active) => {
    state.active = active;
    try {
      if (active) {
        sessionStorage.setItem(ADMIN_PAGE_KEY, '1');
        const id = TO.account?.server?.id;
        if (id) sessionStorage.setItem(ADMIN_PAGE_USER_KEY, id);
      } else {
        sessionStorage.removeItem(ADMIN_PAGE_KEY);
        sessionStorage.removeItem(ADMIN_PAGE_USER_KEY);
      }
    } catch (e) { /* session storage may be unavailable */ }
  };
  const metric = (label, detail, result = null, error = false, valueKey, valueFormat = 'count', summary = '') => {
    const rawValue = result && valueKey ? result[valueKey] : null;
    const value = rawValue == null ? '—' : valueFormat === 'percent' ? `${Number(rawValue).toFixed(2)}%` : valueFormat === 'decimal' ? Number(rawValue).toFixed(2) : Number(rawValue).toLocaleString();
    const note = result ? (typeof summary === 'function' ? summary(result) : summary) : '';
    return `<article class="admin-metric card"><div class="eyebrow">${esc(label)}</div><div class="admin-metric-value">${value}</div><p>${esc(detail)}</p>${note ? `<div class="admin-metric-summary">${esc(note)}</div>` : ''}<span class="admin-pending">${error ? 'Unavailable' : result ? 'Live' : 'Query pending'}</span></article>`;
  };

  function view() {
    const term = state.query.trim().toLowerCase();
    const users = state.users.filter((u) => !term || [u.username, u.display_name, u.email].some((x) => String(x || '').toLowerCase().includes(term)));
    const rows = users.map((u) => {
      if (state.editing === u.id) return `<article class="admin-user admin-user-edit card">
        <div class="admin-user-main"><div class="admin-avatar">${icon('user', 18)}</div><div class="admin-user-fields">
          <label>Username<input class="input" id="admin-username" maxlength="20" value="${esc(u.username || '')}"></label>
          <label>Display name<input class="input" id="admin-display-name" maxlength="60" value="${esc(u.display_name || '')}"></label>
          <label>Avatar URL<input class="input" id="admin-avatar-url" value="${esc(u.avatar_url || '')}" placeholder="Optional"></label>
        </div></div>
        <div class="admin-user-actions"><button class="btn primary sm" data-act="admin-save" data-id="${esc(u.id)}" ${state.saving ? 'disabled' : ''}>Save</button><button class="btn quiet sm" data-act="admin-cancel">Cancel</button></div>
      </article>`;
      const created = u.created_at ? new Date(u.created_at).toLocaleDateString() : '—';
      const lastSeen = u.last_sign_in_at ? new Date(u.last_sign_in_at).toLocaleDateString() : 'Never';
      return `<article class="admin-user card"><div class="admin-user-main"><div class="admin-avatar">${icon('user', 18)}</div><div class="admin-user-info">
        <b>@${esc(u.username || 'unknown')}</b><span>${esc(u.email || 'No email')}</span><small>${esc(u.display_name || '')}</small>
      </div></div><div class="admin-user-meta"><span>Joined <b>${esc(created)}</b></span><span>Last login <b>${esc(lastSeen)}</b></span></div>
      <div class="admin-user-actions"><button class="btn ghost sm" data-act="admin-edit" data-id="${esc(u.id)}">Edit</button><button class="btn danger sm" data-act="admin-delete" data-id="${esc(u.id)}" data-name="${esc(u.username || u.email || 'this user')}">Delete</button></div></article>`;
    }).join('');

    return `<div class="admin-view" data-tab="admin">
      <header class="admin-head page-head"><div><div class="eyebrow admin-kicker">TimeOut · Website administration</div><h1>Admin</h1><p>Product outcomes and account management.</p></div><div class="admin-refresh-control">${state.refreshedAt ? `<span class="admin-last-refresh">Updated ${esc(new Date(state.refreshedAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }))}</span>` : ''}<button class="btn ghost sm" data-act="admin-refresh" ${state.loading ? 'disabled' : ''}>${icon('refresh', 16)} ${state.loading ? 'Refreshing…' : 'Refresh'}</button></div></header>
      ${state.error ? `<div class="admin-error">${icon('alert', 17)}<span>${esc(state.error)}</span></div>` : ''}
      <section class="admin-okr-section"><div class="section-title"><h2>Objectives & key results</h2><span class="admin-note">Metrics refresh when you open the page</span></div>
        <article class="admin-objective card"><div class="admin-objective-top"><span class="admin-objective-num">01</span><div><span class="eyebrow">Objective</span><h3>Help users stop using sports gambling apps</h3></div></div>
          <div class="admin-metrics-grid">${metric('Users placing 3+ bets in week one', 'Target: 70% of eligible users place 3 or more bets in their first week.', state.metrics.firstWeekBets, state.metricErrors.firstWeekBets, 'pct_users_3_plus_bets', 'percent', (r) => `${Number(r.users_with_3_plus_bets)} of ${Number(r.total_eligible_users)} eligible users · target ${Number(r.target_pct).toFixed(0)}%`)}${metric('Weekly active users', 'Users who logged in or placed a bet during a one-week period.', state.metrics.activeUsers, state.metricErrors.activeUsers, 'weekly_active_users', 'count', (r) => `${r.pct_of_total_users_active == null ? '—' : `${Number(r.pct_of_total_users_active).toFixed(2)}%`} of ${Number(r.total_registered_users)} registered users`)}</div>
        </article>
        <article class="admin-objective card"><div class="admin-objective-top"><span class="admin-objective-num">02</span><div><span class="eyebrow">Objective</span><h3>Users using the social features of the app</h3></div></div>
          <div class="admin-metrics-grid">${metric('Users in a team', 'Share of registered users who belong to at least one team.', state.metrics.usersInTeam, state.metricErrors.usersInTeam, 'pct_users_in_team', 'percent', (r) => `${Number(r.users_in_a_team)} of ${Number(r.total_users)} users`)}${metric('Average friends per user', 'Mean number of friends for all users, including users with no friends.', state.metrics.avgFriends, state.metricErrors.avgFriends, 'avg_friends_per_user', 'decimal', (r) => `${Number(r.total_friend_connections)} total friend connections · ${r.avg_friends_among_users_with_friends == null ? '—' : Number(r.avg_friends_among_users_with_friends).toFixed(2)} among users with friends`)}</div>
        </article>
      </section>
      <section class="admin-users-section"><div class="section-title admin-users-title"><div><h2>Users</h2><p>Search accounts, edit profile details, or permanently delete an account and its data.</p></div><span class="admin-user-count">${state.loading ? 'Loading…' : `${state.users.length} accounts`}</span></div>
        <div class="admin-search"><span>${icon('search', 17)}</span><input class="input" id="admin-user-search" type="search" placeholder="Search username, name or email" value="${esc(state.query)}"></div>
        <div class="admin-user-list">${state.loading && !state.users.length ? '<div class="admin-empty card">Loading users…</div>' : rows || `<div class="admin-empty card">${state.users.length ? 'No users match that search.' : 'No users found.'}</div>`}</div>
      </section>
    </div>`;
  }

  async function load() {
    if (state.loading) return;
    if (!apiReady()) { state.error = 'Sign in to a connected account with admin access to manage users.'; app.renderView(); return; }
    state.loading = true; state.error = ''; app.renderView();
    const metricCalls = {
      firstWeekBets: TO.api.adminFirstWeekBets,
      activeUsers: TO.api.adminActiveUsers7d,
      usersInTeam: TO.api.adminUsersInTeam,
      avgFriends: TO.api.adminAvgFriends,
    };
    try {
      const [usersResult, ...metricResults] = await Promise.allSettled([TO.api.adminUsers(), ...Object.values(metricCalls).map((call) => call())]);
      if (usersResult.status === 'fulfilled') state.users = usersResult.value;
      else state.error = TO.friendlyMessage(usersResult.reason);
      Object.keys(metricCalls).forEach((key, index) => {
        const result = metricResults[index];
        if (result.status === 'fulfilled') {
          state.metrics[key] = result.value?.[0] || null;
          state.metricErrors[key] = false;
        } else state.metricErrors[key] = true;
      });
    } catch (error) { state.error = TO.friendlyMessage(error); }
    finally {
      state.refreshedAt = Date.now();
      state.loading = false;
      app.renderView();
    }
  }

  TO.admin = {
    get active() { return state.active; },
    isAdmin: () => {
      const user = TO.account?.server;
      if (!user || TO.account?.demo) return false;
      // If this same signed-in user already opened Admin, keep the view mounted across
      // refreshes while the role RPC is unavailable. Each database action still checks admin ID.
      try {
        if (state.active && user.id && sessionStorage.getItem(ADMIN_PAGE_USER_KEY) === user.id) return true;
      } catch (e) { /* session storage may be unavailable */ }
      if (user.isAdmin === true) return true;
      // Keep the website navigation stable during a transient role-RPC failure. All data RPCs
      // still enforce the provisioned admin ID in Postgres before returning or changing data.
      return user.isAdmin == null && ADMIN_USERNAMES.has(String(user.username || '').toLowerCase());
    },
    open: () => {
      if (!TO.admin.isAdmin()) return;
      setActive(true); state.editing = null; app.render();
      if (!state.users.length) load();
    },
    close: () => { setActive(false); app.render(); },
    render: view,
    reload: load,
  };

  const renderView = app.renderView;
  app.renderView = () => {
    if (state.active && TO.admin.isAdmin()) {
      const root = document.getElementById('view');
      if (root) root.innerHTML = view();
      return;
    }
    setActive(false);
    renderView();
  };

  TO.actions['admin-open'] = () => TO.admin.open();
  const appBoot = app.boot;
  app.boot = () => {
    appBoot();
    if (TO.admin.isAdmin() && state.active) load();
    else if (!TO.admin.isAdmin()) setActive(false);
  };
  const tabAction = TO.actions.tab;
  TO.actions.tab = (el) => { setActive(false); tabAction(el); };
  const settingsAction = TO.actions.settings;
  TO.actions.settings = (el) => { setActive(false); settingsAction(el); };
  const logoutAction = TO.actions.logout;
  TO.actions.logout = (...args) => { setActive(false); return logoutAction(...args); };
  TO.actions['admin-refresh'] = () => load();
  TO.actions['admin-cancel'] = () => { state.editing = null; app.renderView(); };
  TO.actions['admin-edit'] = (el) => { state.editing = el.dataset.id; app.renderView(); };
  TO.actions['admin-save'] = async (el) => {
    const username = document.getElementById('admin-username')?.value.trim() || '';
    const displayName = document.getElementById('admin-display-name')?.value.trim() || '';
    const avatarUrl = document.getElementById('admin-avatar-url')?.value.trim() || '';
    state.saving = true; app.renderView();
    try {
      await TO.api.adminUpdateUser({ id: el.dataset.id, username, displayName, avatarUrl });
      state.editing = null;
      ui.toast({ kind: 'win', title: 'User updated' });
      await load();
    } catch (error) { state.error = TO.friendlyMessage(error); }
    finally { state.saving = false; app.renderView(); }
  };
  TO.actions['admin-delete'] = async (el) => {
    const name = el.dataset.name;
    const ok = await ui.confirm({ title: `Delete ${esc(name)}?`, body: 'This permanently deletes their account and associated TimeOut data. This can’t be undone.', confirm: 'Delete user', danger: true });
    if (!ok) return;
    try {
      await TO.api.adminDeleteUser(el.dataset.id);
      state.users = state.users.filter((u) => u.id !== el.dataset.id);
      ui.toast({ kind: 'win', title: 'User deleted', msg: `${name} and their account data were removed.` });
      app.renderView();
    } catch (error) { state.error = TO.friendlyMessage(error); app.renderView(); }
  };
  document.addEventListener('input', (event) => {
    if (event.target.id !== 'admin-user-search') return;
    state.query = event.target.value;
    const y = document.getElementById('view')?.scrollTop || 0;
    app.renderView();
    const search = document.getElementById('admin-user-search');
    search?.focus();
    if (search) { search.setSelectionRange(search.value.length, search.value.length); document.getElementById('view').scrollTop = y; }
  });
})(window.TO);
