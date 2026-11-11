-- TimeOut friends: real friend requests, friendships and shared stats across accounts.
-- Run after the challenge rename, the challenge RPCs, the tier migration and the teams file. Safe to rerun.
--
-- The tables have row-level security with no policies, so clients can only reach them through
-- the functions below. Every function works from auth.uid(), so nobody can act for someone else.

-- Usernames are looked up case-insensitively (timeout_user_by_name), so they must be unique that way too.
-- If this fails, two profiles differ only by capitalisation: rename one, then rerun.
create unique index if not exists profiles_username_lower_key on public.profiles (lower(username));

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (from_user <> to_user),
  unique (from_user, to_user)
);
create index if not exists friend_requests_to_user on public.friend_requests (to_user);

create table if not exists public.friendships (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index if not exists friendships_user_b on public.friendships (user_b);

-- The secret in someone's invite link. Opening a link with the right code connects two people right away.
-- A link without it only sends a request, so nobody can force a friendship by typing a username into a URL.
create table if not exists public.friend_invites (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now()
);

alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.friend_invites enable row level security;

create or replace function public.timeout_user_by_name(p_username text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id from public.profiles p where lower(p.username) = lower(btrim(p_username)) limit 1
$$;

create or replace function public.timeout_are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.friendships f where f.user_a = least(p_a, p_b) and f.user_b = greatest(p_a, p_b))
$$;

create or replace function public.timeout_connect_friends(p_a uuid, p_b uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.friendships (user_a, user_b) values (least(p_a, p_b), greatest(p_a, p_b)) on conflict do nothing;
  delete from public.friend_requests r
  where (r.from_user = p_a and r.to_user = p_b) or (r.from_user = p_b and r.to_user = p_a);
end;
$$;

-- Same tier rule as both apps.
create or replace function public.timeout_tier_id(p_prefs jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when public.timeout_lock_points(p_prefs) >= 12 then 'hof'
    when public.timeout_lock_points(p_prefs) >= 8 then 'mvp'
    when public.timeout_lock_points(p_prefs) >= 4 then 'allstar'
    when public.timeout_lock_points(p_prefs) >= 1 then 'starter'
    else 'rookie'
  end
$$;

-- What one friend may see about another. Anything switched off in Privacy comes back as zero and share = false.
create or replace function public.timeout_friend_card(p_uid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_prefs jsonb;
  v_share_record boolean;
  v_share_minutes boolean;
  v_share_challenges boolean;
  v_w integer := 0;
  v_l integer := 0;
  v_net integer := 0;
  v_picks jsonb := '[]'::jsonb;
  v_profile record;
begin
  select p.username, p.display_name, p.avatar_url into v_profile from public.profiles p where p.id = p_uid;
  select coalesce(s.app_preferences, '{}'::jsonb) into v_prefs from public.user_settings s where s.user_id = p_uid;
  v_prefs := coalesce(v_prefs, '{}'::jsonb);
  v_share_record := coalesce((v_prefs #>> '{privacy,record}')::boolean, true);
  v_share_minutes := coalesce((v_prefs #>> '{privacy,minutes}')::boolean, true);
  v_share_challenges := coalesce((v_prefs #>> '{privacy,challenges}')::boolean, true);

  select count(*) filter (where c.status = 'won'), count(*) filter (where c.status = 'lost'),
         coalesce(sum(coalesce(c.actual_reward_minutes, 0) - c.pledge_minutes) filter (where c.status <> 'pending'), 0)
  into v_w, v_l, v_net
  from public.challenges c where c.user_id = p_uid;

  if v_share_challenges then
    select coalesce(jsonb_agg(item order by placed_at desc), '[]'::jsonb) into v_picks
    from (
      select c.placed_at,
             jsonb_build_object(
               'pledgeMinutes', c.pledge_minutes,
               'combinedValue', c.combined_value,
               'picks', coalesce((
                 select jsonb_agg(jsonb_build_object('market', k.market, 'side', k.side, 'line', k.line, 'matchup', k.matchup, 'price', k.accepted_value))
                 from public.challenge_picks k where k.challenge_id = c.id
               ), '[]'::jsonb)
             ) as item
      from public.challenges c
      where c.user_id = p_uid and c.status = 'pending'
      order by c.placed_at desc
      limit 3
    ) open_challenges;
  end if;

  return jsonb_build_object(
    'username', v_profile.username,
    'name', coalesce(nullif(v_profile.display_name, ''), v_profile.username),
    'photo', v_profile.avatar_url,
    'w', case when v_share_record then v_w else 0 end,
    'l', case when v_share_record then v_l else 0 end,
    'net', case when v_share_minutes then v_net else 0 end,
    'tier', public.timeout_tier_id(v_prefs),
    'streak', coalesce((select w.streak from public.wallets w where w.user_id = p_uid), 0),
    'share', jsonb_build_object('record', v_share_record, 'minutes', v_share_minutes, 'challenges', v_share_challenges),
    'picks', v_picks
  );
end;
$$;

-- Everything the Social tab shows: friends with their shared stats, and requests both ways.
create or replace function public.timeout_social_state()
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  return json_build_object(
    'friends', coalesce((
      select json_agg(public.timeout_friend_card(case when f.user_a = v_me then f.user_b else f.user_a end))
      from public.friendships f where f.user_a = v_me or f.user_b = v_me
    ), '[]'::json),
    'requestsIn', coalesce((
      select json_agg(json_build_object('id', r.id, 'username', p.username,
        'name', coalesce(nullif(p.display_name, ''), p.username), 'photo', p.avatar_url, 'at', r.created_at) order by r.created_at desc)
      from public.friend_requests r join public.profiles p on p.id = r.from_user where r.to_user = v_me
    ), '[]'::json),
    'requestsOut', coalesce((
      select json_agg(json_build_object('id', r.id, 'username', p.username,
        'name', coalesce(nullif(p.display_name, ''), p.username), 'photo', p.avatar_url, 'at', r.created_at) order by r.created_at desc)
      from public.friend_requests r join public.profiles p on p.id = r.to_user where r.from_user = v_me
    ), '[]'::json)
  );
end;
$$;

-- Returns 'requested', or 'friends' when they already asked you or you were already connected.
create or replace function public.timeout_send_friend_request(p_username text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_other uuid;
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  v_other := public.timeout_user_by_name(p_username);
  if v_other is null then raise exception 'No TimeOut account has that username.'; end if;
  if v_other = v_me then raise exception 'That is your own username.'; end if;
  if public.timeout_are_friends(v_me, v_other) then return 'friends'; end if;
  if exists (select 1 from public.friend_requests r where r.from_user = v_other and r.to_user = v_me) then
    perform public.timeout_connect_friends(v_me, v_other);
    return 'friends';
  end if;
  insert into public.friend_requests (from_user, to_user) values (v_me, v_other)
  on conflict (from_user, to_user) do update set created_at = now();
  return 'requested';
end;
$$;

create or replace function public.timeout_answer_friend_request(p_username text, p_accept boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_other uuid;
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  v_other := public.timeout_user_by_name(p_username);
  if v_other is null or not exists (select 1 from public.friend_requests r where r.from_user = v_other and r.to_user = v_me) then
    return false;
  end if;
  if p_accept then
    perform public.timeout_connect_friends(v_me, v_other);
  else
    delete from public.friend_requests r where r.from_user = v_other and r.to_user = v_me;
  end if;
  return true;
end;
$$;

create or replace function public.timeout_cancel_friend_request(p_username text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  delete from public.friend_requests r where r.from_user = v_me and r.to_user = public.timeout_user_by_name(p_username);
end;
$$;

create or replace function public.timeout_remove_friend(p_username text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_other uuid;
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  v_other := public.timeout_user_by_name(p_username);
  if v_other is null then return; end if;
  delete from public.friendships f where f.user_a = least(v_me, v_other) and f.user_b = greatest(v_me, v_other);
end;
$$;

-- The code that goes in your invite link. It stays the same so links you already shared keep working.
create or replace function public.timeout_my_invite_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_code text;
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  select i.code into v_code from public.friend_invites i where i.user_id = v_me;
  if v_code is null then
    v_code := replace(gen_random_uuid()::text, '-', '');
    insert into public.friend_invites (user_id, code) values (v_me, v_code);
  end if;
  return v_code;
end;
$$;

-- Opening someone's link. The right code connects you both. Otherwise it is an ordinary friend request.
create or replace function public.timeout_accept_friend_invite(p_username text, p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_other uuid;
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  v_other := public.timeout_user_by_name(p_username);
  if v_other is null then raise exception 'No TimeOut account has that username.'; end if;
  if v_other = v_me then return 'self'; end if;
  if exists (select 1 from public.friend_invites i where i.user_id = v_other and i.code = p_code) then
    perform public.timeout_connect_friends(v_me, v_other);
    return 'friends';
  end if;
  return public.timeout_send_friend_request(p_username);
end;
$$;

-- Username search that works whatever the profile table's read policy is. Only public profile fields come back.
create or replace function public.timeout_search_users(p_query text)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_clean text := lower(regexp_replace(left(coalesce(p_query, ''), 20), '[^A-Za-z0-9_.]', '', 'g'));
  v_like text;
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  if v_clean = '' then return '[]'::json; end if;
  v_like := '%' || replace(v_clean, '_', '\_') || '%';
  return coalesce((
    select json_agg(json_build_object('username', x.username, 'name', x.name, 'photo', x.avatar_url))
    from (
      select p.username, coalesce(nullif(p.display_name, ''), p.username) as name, p.avatar_url
      from public.profiles p
      where p.id <> v_me and p.username ilike v_like escape '\'
      order by (lower(p.username) = v_clean) desc, (lower(p.username) like v_clean || '%') desc, p.username
      limit 8
    ) x
  ), '[]'::json);
end;
$$;

-- Keeps the streak friends see in step with the app. The app works the streak out on the device.
create or replace function public.timeout_set_streak(p_streak integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  update public.wallets w set streak = greatest(0, least(coalesce(p_streak, 0), 3650)) where w.user_id = auth.uid();
end;
$$;

-- Team standings for the team's dates. Only people on the roster can read them, and Privacy still applies.
create or replace function public.timeout_team_standings(p_id text, p_key text)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_me text := public.timeout_me();
  v_team record;
begin
  select t.team_id, t.start_date, t.end_date, t.key_hash into v_team from public.teams t where t.team_id = p_id;
  if v_team.team_id is null or v_team.key_hash is distinct from public.timeout_team_key(p_key) then return '[]'::json; end if;
  if not exists (select 1 from public.team_members m where m.team_id = p_id and lower(m.username) = lower(v_me)) then return '[]'::json; end if;
  return coalesce((
    select json_agg(json_build_object(
      'username', m.username,
      'photo', p.avatar_url,
      'tier', public.timeout_tier_id(coalesce(s.app_preferences, '{}'::jsonb)),
      'hidden', p.id is null or not coalesce((s.app_preferences #>> '{privacy,minutes}')::boolean, true),
      'w', case when p.id is null or not coalesce((s.app_preferences #>> '{privacy,record}')::boolean, true) then 0 else coalesce(r.w, 0) end,
      'l', case when p.id is null or not coalesce((s.app_preferences #>> '{privacy,record}')::boolean, true) then 0 else coalesce(r.l, 0) end,
      'net', case when p.id is null or not coalesce((s.app_preferences #>> '{privacy,minutes}')::boolean, true) then 0 else coalesce(r.net, 0) end
    ))
    from public.team_members m
    left join public.profiles p on lower(p.username) = lower(m.username)
    left join public.user_settings s on s.user_id = p.id
    left join lateral (
      select count(*) filter (where c.status = 'won') as w, count(*) filter (where c.status = 'lost') as l,
             coalesce(sum(coalesce(c.actual_reward_minutes, 0) - c.pledge_minutes) filter (where c.status <> 'pending'), 0) as net
      from public.challenges c
      where c.user_id = p.id and c.placed_at >= v_team.start_date::timestamptz and c.placed_at < (v_team.end_date + 1)::timestamptz
    ) r on true
    where m.team_id = p_id
  ), '[]'::json);
end;
$$;

revoke all on function public.timeout_user_by_name(text) from public, anon, authenticated;
revoke all on function public.timeout_are_friends(uuid, uuid) from public, anon, authenticated;
revoke all on function public.timeout_connect_friends(uuid, uuid) from public, anon, authenticated;
revoke all on function public.timeout_friend_card(uuid) from public, anon, authenticated;

revoke all on function public.timeout_social_state() from public, anon;
revoke all on function public.timeout_send_friend_request(text) from public, anon;
revoke all on function public.timeout_answer_friend_request(text, boolean) from public, anon;
revoke all on function public.timeout_cancel_friend_request(text) from public, anon;
revoke all on function public.timeout_remove_friend(text) from public, anon;
revoke all on function public.timeout_my_invite_code() from public, anon;
revoke all on function public.timeout_accept_friend_invite(text, text) from public, anon;
revoke all on function public.timeout_search_users(text) from public, anon;
revoke all on function public.timeout_set_streak(integer) from public, anon;
revoke all on function public.timeout_team_standings(text, text) from public, anon;

grant execute on function public.timeout_social_state() to authenticated;
grant execute on function public.timeout_send_friend_request(text) to authenticated;
grant execute on function public.timeout_answer_friend_request(text, boolean) to authenticated;
grant execute on function public.timeout_cancel_friend_request(text) to authenticated;
grant execute on function public.timeout_remove_friend(text) to authenticated;
grant execute on function public.timeout_my_invite_code() to authenticated;
grant execute on function public.timeout_accept_friend_invite(text, text) to authenticated;
grant execute on function public.timeout_search_users(text) to authenticated;
grant execute on function public.timeout_set_streak(integer) to authenticated;
grant execute on function public.timeout_team_standings(text, text) to authenticated;

notify pgrst, 'reload schema';
