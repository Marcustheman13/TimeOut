/* TimeOut web demo — Social (Screen 5): friends, leaderboard, requests & challenges, teams. */
(function (TO) {
  'use strict';
  const { esc, icon } = TO;
  const ui = TO.ui;
  const St = TO.state;

  const view = { tab: 'board', query: '' };
  const inviteLink = () => `https://timeout.app/join/${TO.account.username}`;

  function meCard() {
    const st = St.myStats();
    const wl = St.wallet();
    return `<div class="card me-card">
      ${ui.avatar(TO.account.photo, 'lg')}
      <div class="grow">
        <div class="row-s"><b style="font-size:17px">@${esc(TO.account.username)}</b></div>
        <div class="row-s" style="margin-top:5px;flex-wrap:wrap">${ui.tierBadge(wl.tier.id, true)}<span class="tiny bold ${wl.streak ? 'yellow' : 'faint'} row-s">${icon('flame', 12)}${wl.streak}-day streak</span></div>
        <div class="row" style="margin-top:8px;gap:16px"><span class="small"><b>${st.w}-${st.l}</b> <span class="muted">record</span></span><span class="small"><b class="${st.net > 0 ? 'green' : st.net < 0 ? 'red' : ''}">${TO.signedMin(st.net)}</b> <span class="muted">all time</span></span></div>
      </div>
    </div>`;
  }

  function searchResults() {
    const q = view.query.trim();
    if (!q) return '';
    const results = St.searchPeople(q);
    if (!results.length) {
      return `<div class="note">${icon('search', 16)}<div><b style="color:var(--text)">No one found with the username "${esc(q)}".</b><div style="margin-top:3px">They might not be on TimeOut yet. Send them your invite link instead.</div><button class="btn xs primary" style="margin-top:8px" data-act="copy-invite">${icon('link', 14)} Copy invite link</button></div></div>`;
    }
    return `<div class="list">${results.map((p) => {
      const rel = St.relation(p.username);
      const btn = rel === 'friend' ? `<span class="tag green">Friends</span>`
        : rel === 'requested' ? `<button class="btn xs ghost" data-act="cancel-request" data-u="${esc(p.username)}">Requested</button>`
        : rel === 'incoming' ? `<button class="btn xs primary" data-act="add-friend" data-u="${esc(p.username)}">Accept</button>`
        : `<button class="btn xs primary" data-act="add-friend" data-u="${esc(p.username)}">${icon('userPlus', 14)} Add</button>`;
      return `<div class="person-row"><button class="row grow" style="text-align:left" data-act="profile" data-u="${esc(p.username)}">${ui.avatar(p.photo)}<span class="grow" style="min-width:0"><b class="ellipsis" style="display:block">@${esc(p.username)}</b><span class="small muted">${esc(p.name || '')}${p.local ? ' · on this device' : ''}</span></span></button>${btn}</div>`;
    }).join('')}</div>`;
  }

  function findCard() {
    return `<div class="card stack-s" style="margin:0 16px">
      <h2 style="margin:0;font-size:17px">Find friends</h2>
      <div class="input-wrap"><input class="input" id="social-search" placeholder="Search by username" value="${esc(view.query)}" autocomplete="off" autocapitalize="off" spellcheck="false"><span class="icon-btn" style="pointer-events:none">${icon('search', 18)}</span></div>
      <div id="search-results" class="stack-s">${searchResults()}</div>
      <div class="spread small" style="margin-top:2px"><span class="muted ellipsis">Or share your invite link</span><button class="btn xs ghost" data-act="copy-invite">${icon('link', 14)} Copy link</button></div>
    </div>`;
  }

  function leaderboard() {
    if (!TO.data.friends.length) {
      return `<div class="empty">${icon('users', 40)}<h3>Bet against your friends</h3><p>Social is where you compare records with friends, send each other bet challenges, and form teams that compete for a week or a season. Add your first friend to get started.</p><button class="btn primary" data-act="copy-invite">${icon('link', 16)} Invite a friend</button><button class="btn quiet sm" data-act="focus-search">Search usernames instead</button></div>`;
    }
    const rows = St.leaderboard();
    return `<div class="stack-s pad"><div class="spread"><span class="eyebrow">Leaderboard · minutes won or lost</span><button class="link-btn tiny" data-act="settings" data-section="privacy">What friends see</button></div>
      <div class="list">${rows.map((r, i) => `<button class="lb-row ${r.me ? 'me' : ''}" data-act="profile" data-u="${esc(r.username)}">
        <span class="rk">${r.share.minutes ? i + 1 : '–'}</span>${ui.avatar(r.photo)}
        <span style="min-width:0"><span class="nm ellipsis" style="display:block">${r.me ? 'You' : `@${esc(r.username)}`}</span><span class="sub">${ui.tierBadge(r.tier, true)}${r.share.record ? `<span>${r.w}-${r.l}</span>` : '<span>Record private</span>'}${r.streak ? `<span class="yellow row-s">${icon('flame', 11)}${r.streak}</span>` : ''}</span></span>
        <span class="val">${r.share.minutes ? `<span class="${r.net > 0 ? 'green' : r.net < 0 ? 'red' : ''}">${TO.signed(r.net)}</span><small>min</small>` : `<span class="faint" style="font-size:14px">Private</span>`}</span>
      </button>`).join('')}</div>
      <div class="tiny faint">Friends only show the stats they've chosen to share.</div></div>`;
  }

  function requests() {
    const d = TO.data;
    const pendingCh = d.challengesIn.filter((c) => c.status === 'pending');
    const expired = d.challengesIn.filter((c) => c.status === 'expired');
    const parts = [];
    if (pendingCh.length || expired.length) {
      parts.push(`<div class="eyebrow">Bet challenges</div>` + [...pendingCh, ...expired].map((c) => {
        const p = St.person(c.from);
        return `<div class="card challenge-card">
          <div class="row">${ui.avatar(p ? p.photo : TO.initialsAvatar(c.from))}<div class="grow"><b>@${esc(c.from)}</b> challenged you<div class="tiny faint">${TO.ago(c.at)}</div></div>${c.status === 'expired' ? '<span class="tag">Expired</span>' : ''}</div>
          <div class="livebox"><div class="small muted">${esc(c.matchup)}</div><div class="spread"><span class="small">They picked <b>${esc(c.theirPick)}</b></span></div><div class="small">You'd take <b class="green">the other side</b></div></div>
          <div class="friend-terms">${icon('users', 16)}<span>"${esc(c.terms)}"</span></div>
          ${c.status === 'pending' ? `<div class="bet-actions"><button class="btn sm ghost" data-act="decline-ch" data-id="${c.id}">Decline</button><button class="btn sm primary" data-act="accept-ch" data-id="${c.id}">Accept bet</button></div>` : `<div class="bet-actions"><button class="btn sm ghost" data-act="decline-ch" data-id="${c.id}">Dismiss</button></div>`}
        </div>`;
      }).join(''));
    }
    if (d.requestsIn.length) {
      parts.push(`<div class="eyebrow">Friend requests</div><div class="list">${d.requestsIn.map((r) => {
        const p = St.person(r.from);
        return `<div class="person-row">${ui.avatar(p ? p.photo : TO.initialsAvatar(r.from))}<div class="grow"><b>@${esc(r.from)}</b><div class="tiny faint">${p && p.name && p.name !== r.from ? `${esc(p.name)} · ` : ''}${TO.ago(r.at)}</div></div><button class="btn xs ghost" data-act="decline-fr" data-id="${r.id}">Decline</button><button class="btn xs primary" data-act="accept-fr" data-id="${r.id}">Accept</button></div>`;
      }).join('')}</div>`);
    }
    if (d.requestsOut.length) {
      parts.push(`<div class="eyebrow">Sent requests</div><div class="list">${d.requestsOut.map((r) => {
        const p = St.person(r.to);
        return `<div class="person-row">${ui.avatar(p ? p.photo : TO.initialsAvatar(r.to))}<div class="grow"><b>@${esc(r.to)}</b><div class="tiny faint">Waiting for them to accept</div></div><button class="btn xs ghost" data-act="cancel-request" data-u="${esc(r.to)}">Cancel</button></div>`;
      }).join('')}</div>`);
    }
    if (!parts.length) return `<div class="empty">${icon('bell', 36)}<h3>You're all caught up</h3><p>Friend requests and bet challenges from friends show up here.</p></div>`;
    return `<div class="stack-s pad">${parts.join('')}</div>`;
  }

  function teams() {
    const list = TO.data.teams;
    const cards = list.map((t) => {
      const status = St.teamStatus(t);
      const standings = St.teamStandings(t);
      const myRank = standings.findIndex((s) => s.me) + 1;
      const statusTag = status === 'active' ? `<span class="tag green">Ends in ${TO.fmtIn(TO.dayStart(t.end) + TO.DAY - TO.now())}</span>` : status === 'upcoming' ? `<span class="tag blue">Starts ${TO.fmtDate(TO.dayStart(t.start))}</span>` : '<span class="tag">Ended</span>';
      return `<button class="card team-card tappable" style="text-align:left" data-act="team" data-id="${t.id}">
        <div class="spread"><b style="font-size:16px">${esc(t.name)}</b>${statusTag}</div>
        <div class="spread small muted"><span>${TO.fmtDate(TO.dayStart(t.start))} – ${TO.fmtDate(TO.dayStart(t.end))} · ${t.members.length} members</span><span class="avatars">${standings.slice(0, 5).map((s) => `<img src="${esc(s.photo)}" alt="">`).join('')}</span></div>
        ${status !== 'upcoming' ? `<div class="small">You're <b>${TO.ordinal(myRank)}</b> of ${standings.length} · leader <b>${standings[0].me ? 'you' : `@${esc(standings[0].username)}`}</b></div>` : ''}
      </button>`;
    }).join('');
    return `<div class="stack-s pad">
      <div class="small muted">Teams compete over the dates you pick. Whoever wins the most minutes in that stretch tops the team.</div>
      <button class="btn primary sm" data-act="team-new">${icon('plus', 16)} Create a team</button>
      ${cards || `<div class="empty">${icon('trophy', 36)}<h3>No teams yet</h3><p>Start one with a few friends and pick a start and end date.</p></div>`}
    </div>`;
  }

  function render() {
    const d = TO.data;
    const reqCount = d.requestsIn.length + d.challengesIn.filter((c) => c.status === 'pending').length;
    const tab = (k, label, n) => `<button class="${view.tab === k ? 'on' : ''}" data-act="social-tab" data-t="${k}">${label}${n ? ` <span class="count-pill" style="background:var(--live);color:#fff">${n}</span>` : ''}</button>`;
    let body;
    if (view.tab === 'requests') body = requests();
    else if (view.tab === 'teams') body = teams();
    else body = leaderboard();
    return `<div class="page-head"><h1>Social</h1><p>Compete with friends: compare records, send bet challenges, and join teams.</p></div>
      <div class="stack">
        ${meCard()}
        ${findCard()}
        <div class="pad"><div class="seg">${tab('board', 'Friends')}${tab('requests', 'Requests', reqCount)}${tab('teams', 'Teams')}</div></div>
        ${body}
      </div>`;
  }

  TO.views.social = { render, view, badge: () => TO.data.requestsIn.length + TO.data.challengesIn.filter((c) => c.status === 'pending').length };

  // ---------- Profile sheet ----------
  function profile(username) {
    const isMe = username === TO.account.username;
    ui.sheet('profile', {
      render: () => {
        const p = isMe ? null : St.person(username);
        if (!isMe && !p) return { title: 'Profile', body: '<div class="muted">This person could not be found.</div>' };
        const rel = isMe ? 'me' : St.relation(username);
        const st = isMe ? St.myStats() : null;
        const share = isMe ? { record: true, minutes: true, bets: true } : p.share;
        const showAll = isMe || rel === 'friend';
        const rec = isMe ? `${st.w}-${st.l}` : `${p.w}-${p.l}`;
        const net = isMe ? st.net : p.net;
        const tierId = isMe ? St.wallet().tier.id : p.tier;
        const streak = isMe ? St.wallet().streak : p.streak;
        const picks = !isMe && showAll ? St.sharedPicks(p) : [];
        const stat = (label, val, ok) => `<div><b>${ok ? val : '<span class="faint" style="font-size:16px">Private</span>'}</b><span>${label}</span></div>`;
        let actions = '';
        if (rel === 'friend') actions = `<button class="btn primary full" data-act="challenge-friend" data-u="${esc(username)}">${icon('target', 18)} Challenge to a bet</button><button class="btn quiet sm" data-act="remove-friend" data-u="${esc(username)}">Remove friend</button>`;
        else if (rel === 'requested') actions = `<button class="btn ghost full" data-act="cancel-request" data-u="${esc(username)}">Friend request sent · Cancel</button>`;
        else if (rel === 'incoming' || rel === 'none') actions = `<button class="btn primary full" data-act="add-friend" data-u="${esc(username)}">${icon('userPlus', 18)} ${rel === 'incoming' ? 'Accept friend request' : 'Add friend'}</button>`;
        return {
          title: isMe ? 'Your profile' : `@${esc(username)}`,
          body: `<div class="row" style="gap:14px">${ui.avatar(isMe ? TO.account.photo : p.photo, 'xl')}<div><div style="font-size:20px;font-weight:800">${isMe ? `@${esc(username)}` : esc(p.name)}</div>${isMe ? '' : `<div class="muted small">@${esc(username)}</div>`}<div class="row-s" style="margin-top:8px">${ui.tierBadge(tierId, true)}${streak ? `<span class="tiny bold yellow row-s">${icon('flame', 12)}${streak}-day streak</span>` : ''}</div></div></div>
            ${showAll ? `<div class="record-big">${stat('Record', rec, share.record)}${stat('Minutes won/lost', `<span class="${net > 0 ? 'green' : net < 0 ? 'red' : ''}">${TO.signed(net)}</span>`, share.minutes)}${stat('Clean streak', `${streak}d`, true)}</div>` : `<div class="note">${icon('lock', 16)}<span>Add @${esc(username)} as a friend to see their stats.</span></div>`}
            ${!isMe && showAll ? (share.bets ? `<div class="stack-s"><div class="eyebrow">Open bets they're sharing</div>${picks.length ? picks.map((k) => `<div class="card tight spread"><div><b>${esc(k.label)}</b><div class="small muted">${esc(k.matchup)}</div></div><div style="text-align:right"><div class="display green" style="font-size:18px">${TO.odds.fmt(k.price)}</div><div class="tiny faint">${k.stake} min</div></div></div>`).join('') : '<div class="small muted">No open bets right now.</div>'}</div>` : `<div class="small muted">${esc(p.name)} keeps their open bets private.</div>`) : ''}
            ${isMe ? `<button class="btn ghost sm" data-act="settings" data-section="privacy">${icon('eye', 16)} Choose what friends can see</button>` : ''}`,
          foot: isMe ? '' : actions,
        };
      },
    });
  }

  // ---------- Team sheets ----------
  function teamSheet(id) {
    ui.sheet('team', {
      tall: true,
      render: () => {
        const t = TO.data.teams.find((x) => x.id === id);
        if (!t) return { title: 'Team', body: '' };
        const status = St.teamStatus(t);
        const rows = St.teamStandings(t);
        const invitable = TO.data.friends.filter((f) => !t.members.includes(f));
        return {
          title: esc(t.name),
          body: `<div class="spread small muted"><span class="row-s">${icon('calendar', 14)} ${TO.fmtDate(TO.dayStart(t.start))} – ${TO.fmtDate(TO.dayStart(t.end))}</span><span>${status === 'active' ? `Ends in ${TO.fmtIn(TO.dayStart(t.end) + TO.DAY - TO.now())}` : status === 'upcoming' ? `Starts in ${TO.fmtIn(TO.dayStart(t.start) - TO.now())}` : 'Ended'}</span></div>
            <div class="list">${rows.map((r, i) => `<div class="lb-row ${r.me ? 'me' : ''}"><span class="rk">${r.hidden ? '–' : i + 1}</span>${ui.avatar(r.photo)}<span><span class="nm">${r.me ? 'You' : `@${esc(r.username)}`}</span><span class="sub">${r.w}-${r.l} during this team</span></span><span class="val">${r.hidden ? '<span class="faint" style="font-size:14px">Private</span>' : `<span class="${r.net > 0 ? 'green' : r.net < 0 ? 'red' : ''}">${TO.signed(r.net)}</span><small>min</small>`}</span></div>`).join('')}</div>
            <div class="tiny faint">Standings count screen-time bets placed between the start and end dates. Friend bets don't count.</div>
            ${invitable.length ? `<div class="field"><span class="label">Invite more friends</span><div class="pick-friends">${invitable.map((u) => { const p = St.person(u); return `<button class="pick-friend" data-act="team-invite" data-id="${t.id}" data-u="${esc(u)}"><img src="${esc(p.photo)}" alt="">${icon('plus', 14)} ${esc(u)}</button>`; }).join('')}</div></div>` : ''}`,
          foot: `<button class="btn quiet sm" data-act="team-leave" data-id="${t.id}">Leave team</button>`,
        };
      },
    });
  }

  const draft = { name: '', start: '', end: '', members: [], errors: {} };
  function newTeamSheet() {
    Object.assign(draft, { name: '', start: TO.dayKey(), end: TO.addDays(TO.dayKey(), 7), members: [], errors: {} });
    ui.sheet('team-new', {
      tall: true,
      render: () => ({
        title: 'Create a team',
        body: `${ui.field({ id: 'team-name', label: 'Team name', value: draft.name, placeholder: 'Sunday Squad', err: draft.errors.name, attrs: 'maxlength="30"' })}
          <div class="row" style="align-items:flex-start">${`<div class="grow">${ui.field({ id: 'team-start', label: 'Start date', type: 'date', value: draft.start, err: draft.errors.start })}</div><div class="grow">${ui.field({ id: 'team-end', label: 'End date', type: 'date', value: draft.end, err: draft.errors.end })}</div>`}</div>
          <div class="field"><span class="label">Invite friends</span>${TO.data.friends.length ? `<div class="pick-friends">${TO.data.friends.map((u) => { const p = St.person(u); return p ? `<button class="pick-friend ${draft.members.includes(u) ? 'on' : ''}" data-act="team-pick" data-u="${esc(u)}"><img src="${esc(p.photo)}" alt="">${esc(u)}</button>` : ''; }).join('')}</div>` : '<div class="note">Add friends first, then build a team.</div>'}${draft.errors.members ? `<div class="err">${esc(draft.errors.members)}</div>` : ''}</div>`,
        foot: `<button class="btn primary full" data-act="team-create">Create team</button>`,
      }),
    });
  }

  // ---------- Actions ----------
  const A = TO.actions;
  A['social-tab'] = (el) => { view.tab = el.dataset.t; TO.app.render(); };
  A.profile = (el) => profile(el.dataset.u);
  A['copy-invite'] = async () => {
    const ok = await ui.copy(inviteLink());
    ui.toast({ kind: ok ? 'win' : 'info', title: ok ? 'Invite link copied' : 'Your invite link', msg: ok ? inviteLink() : `Copy this: ${inviteLink()}`, ms: 5000 });
    TO.tester.mark('search');
  };
  A['focus-search'] = () => { const i = document.getElementById('social-search'); if (i) i.focus(); };
  A['add-friend'] = (el) => {
    const u = el.dataset.u;
    const rel = St.relation(u);
    St.sendFriendRequest(u);
    ui.toast({ kind: 'win', title: rel === 'incoming' ? `You and @${u} are now friends` : `Friend request sent to @${u}` });
    rerender();
  };
  A['cancel-request'] = (el) => { St.cancelFriendRequest(el.dataset.u); rerender(); };
  A['accept-fr'] = (el) => { const r = TO.data.requestsIn.find((x) => x.id === el.dataset.id); St.acceptFriendRequest(el.dataset.id); if (r) ui.toast({ kind: 'win', title: `You and @${r.from} are now friends` }); TO.app.render(); };
  A['decline-fr'] = (el) => { St.declineFriendRequest(el.dataset.id); TO.app.render(); };
  A['remove-friend'] = async (el) => {
    const u = el.dataset.u;
    if (!(await ui.confirm({ title: `Remove @${esc(u)}?`, body: 'You can add them again later.', confirm: 'Remove', danger: true }))) return;
    St.removeFriend(u);
    ui.closeSheet('profile');
    TO.app.render();
  };
  A['accept-ch'] = (el) => {
    try {
      const bet = St.acceptChallenge(el.dataset.id);
      ui.toast({ kind: 'win', title: 'Challenge accepted', msg: `${bet.legs[0].label} · "${bet.friend.terms}". It's in My Bets.` });
      TO.tester.mark('friend');
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      ui.toast({ kind: 'warn', title: 'Challenge expired', msg: e.message });
    }
    TO.app.render();
  };
  A['decline-ch'] = (el) => { St.declineChallenge(el.dataset.id); TO.app.render(); };
  A['challenge-friend'] = (el) => {
    const u = el.dataset.u;
    TO.pendingChallenge = u;
    ui.closeAllSheets();
    TO.app.go('home');
    ui.toast({ kind: 'info', title: `Pick a game to challenge @${u}`, msg: 'Tap any odds. The slip opens as a friend bet with them already selected.', ms: 5000 });
  };
  A['goto-social'] = () => { ui.closeAllSheets(); ui.closeAllPages(); TO.app.go('social'); };
  A.team = (el) => teamSheet(el.dataset.id);
  A['team-new'] = () => newTeamSheet();
  A['team-pick'] = (el) => {
    const u = el.dataset.u;
    draft.members = draft.members.includes(u) ? draft.members.filter((x) => x !== u) : [...draft.members, u];
    el.classList.toggle('on');
  };
  A['team-create'] = () => {
    draft.name = document.getElementById('team-name').value;
    draft.start = document.getElementById('team-start').value;
    draft.end = document.getElementById('team-end').value;
    try {
      const t = St.createTeam(draft);
      ui.closeSheet('team-new');
      ui.toast({ kind: 'win', title: `${t.name} created`, msg: `${t.members.length - 1} friend${t.members.length === 2 ? '' : 's'} invited.` });
      TO.tester.mark('team');
      view.tab = 'teams';
      TO.app.render();
    } catch (e) {
      if (!(e instanceof TO.AppError)) throw e;
      draft.errors = e.fields || {};
      ui.refreshSheet('team-new', ['body']);
    }
  };
  A['team-invite'] = (el) => { St.inviteToTeam(el.dataset.id, [el.dataset.u]); ui.toast({ kind: 'win', title: `Invited @${el.dataset.u}` }); ui.refreshSheet('team'); TO.app.render(); };
  A['team-leave'] = async (el) => {
    if (!(await ui.confirm({ title: 'Leave this team?', body: 'Your results stop counting toward its standings.', confirm: 'Leave team', danger: true }))) return;
    St.leaveTeam(el.dataset.id);
    ui.closeSheet('team');
    TO.app.render();
  };

  function rerender() {
    TO.app.render();
    if (ui.sheetOpen('profile')) ui.refreshSheet('profile');
  }

  TO.inputs['social-search'] = (el) => {
    view.query = el.value;
    const box = document.getElementById('search-results');
    if (box) box.innerHTML = searchResults();
    if (el.value.trim() && !St.searchPeople(el.value).length) TO.tester.mark('search');
  };
})(window.TO);
