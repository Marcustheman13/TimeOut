-- Website admin access and account management for the four named TimeOut accounts.
-- Run in the Supabase SQL Editor after the main schema and account-delete migration.
-- Safe to rerun. Only users that already have a matching profile are provisioned below.

create table if not exists public.timeout_admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
-- No client-facing policies are needed. Security-definer RPCs owned by the database
-- owner can read this table, while anon/authenticated clients cannot access it directly.
alter table public.timeout_admin_users enable row level security;
revoke all on table public.timeout_admin_users from public, anon, authenticated;

insert into public.timeout_admin_users (user_id)
select p.id
from public.profiles p
where lower(p.username) in ('easton.putnam', 'time_out_account', 'wrfairholm', 'obr0')
on conflict (user_id) do nothing;

create or replace function public.timeout_admin_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.timeout_admin_users a where a.user_id = auth.uid()
  );
$$;
revoke all on function public.timeout_admin_is_admin() from public, anon, authenticated;
grant execute on function public.timeout_admin_is_admin() to authenticated;

create or replace function public.timeout_admin_list_users()
returns table (
  id uuid,
  email text,
  username text,
  display_name text,
  avatar_url text,
  created_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.timeout_admin_is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  return query
    select u.id, u.email::text, p.username::text, p.display_name::text, p.avatar_url::text,
           u.created_at, u.last_sign_in_at
    from auth.users u
    left join public.profiles p on p.id = u.id
    order by u.created_at desc;
end;
$$;
revoke all on function public.timeout_admin_list_users() from public, anon;
grant execute on function public.timeout_admin_list_users() to authenticated;

create or replace function public.timeout_admin_update_user(
  p_user uuid,
  p_username text,
  p_display_name text,
  p_avatar_url text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text := btrim(coalesce(p_username, ''));
begin
  if not public.timeout_admin_is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;
  if p_user is null or not exists (select 1 from auth.users u where u.id = p_user) then
    raise exception 'User not found.' using errcode = '22023';
  end if;
  if v_username !~ '^[A-Za-z0-9_.]{3,20}$' then
    raise exception 'Username must be 3–20 letters, numbers, dots or underscores.' using errcode = '22023';
  end if;
  if exists (select 1 from public.profiles p where lower(p.username) = lower(v_username) and p.id <> p_user) then
    raise exception 'That username is already in use.' using errcode = '23505';
  end if;
  update public.profiles
     set username = v_username,
         display_name = nullif(btrim(coalesce(p_display_name, '')), ''),
         avatar_url = nullif(btrim(coalesce(p_avatar_url, '')), '')
   where id = p_user;
  if not found then raise exception 'User profile not found.' using errcode = '22023'; end if;
end;
$$;
revoke all on function public.timeout_admin_update_user(uuid, text, text, text) from public, anon;
grant execute on function public.timeout_admin_update_user(uuid, text, text, text) to authenticated;

create or replace function public.timeout_admin_delete_user(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  r record;
begin
  if not public.timeout_admin_is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;
  if p_user is null or not exists (select 1 from auth.users u where u.id = p_user) then
    raise exception 'User not found.' using errcode = '22023';
  end if;
  if p_user = auth.uid() or exists (select 1 from public.timeout_admin_users a where a.user_id = p_user) then
    raise exception 'Admin accounts cannot be deleted from this page.' using errcode = '42501';
  end if;

  select p.username into v_name from public.profiles p where p.id = p_user;

  -- Delete child rows before their parent rows. The table scan covers user-owned tables
  -- added later as long as they use the app's user_id column convention.
  if to_regclass('public.challenge_picks') is not null and to_regclass('public.challenges') is not null
     and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenge_picks' and column_name = 'challenge_id') then
    execute 'delete from public.challenge_picks where challenge_id in (select id from public.challenges where user_id = $1)' using p_user;
  end if;
  if to_regclass('public.wallet_transactions') is not null and to_regclass('public.wallets') is not null
     and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'wallet_transactions' and column_name = 'wallet_id') then
    execute 'delete from public.wallet_transactions where wallet_id in (select id from public.wallets where user_id = $1)' using p_user;
  end if;
  if v_name is not null and to_regclass('public.team_members') is not null then
    execute 'delete from public.team_members where lower(username) = lower($1)' using v_name;
  end if;

  for r in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
     where c.table_schema = 'public' and c.column_name = 'user_id' and t.table_type = 'BASE TABLE'
     order by case when c.table_name in ('challenge_picks', 'wallet_transactions') then 0
                   when c.table_name in ('challenges', 'wallets') then 2 else 1 end, c.table_name
  loop
    execute format('delete from public.%I where user_id = $1', r.table_name) using p_user;
  end loop;

  if to_regclass('public.profiles') is not null then delete from public.profiles where id = p_user; end if;
  delete from auth.users where id = p_user;
end;
$$;
revoke all on function public.timeout_admin_delete_user(uuid) from public, anon;
grant execute on function public.timeout_admin_delete_user(uuid) to authenticated;

-- OKR 1: percentage of mature signup cohorts with at least three challenges in their first week.
-- This is an admin-only read RPC; running the migration does not execute the aggregate as a mutation.
create or replace function public.timeout_admin_okr_first_week_bets()
returns table (
  total_eligible_users bigint,
  users_with_3_plus_bets bigint,
  pct_users_3_plus_bets numeric,
  target_pct numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.timeout_admin_is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  return query
    with user_first_week_bets as (
      select p.id as user_id, count(c.id) as first_week_bet_count
      from public.profiles p
      left join public.challenges c
        on p.id = c.user_id
       and c.placed_at >= p.created_at
       and c.placed_at < p.created_at + interval '7 days'
      where p.created_at <= now() - interval '7 days'
      group by p.id
    )
    select count(*)::bigint,
           count(*) filter (where first_week_bet_count >= 3)::bigint,
           round(100.0 * count(*) filter (where first_week_bet_count >= 3) / nullif(count(*), 0), 2),
           70.00::numeric
    from user_first_week_bets;
end;
$$;
revoke all on function public.timeout_admin_okr_first_week_bets() from public, anon;
grant execute on function public.timeout_admin_okr_first_week_bets() to authenticated;

-- OKR 1: distinct users who logged in or placed a challenge in the last seven days.
create or replace function public.timeout_admin_okr_active_users_7d()
returns table (
  weekly_active_users bigint,
  total_registered_users bigint,
  pct_of_total_users_active numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.timeout_admin_is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  return query
    with active_users_7d as (
      select u.id as user_id
      from auth.users u
      where u.last_sign_in_at >= now() - interval '7 days'
      union
      select distinct c.user_id
      from public.challenges c
      where c.placed_at >= now() - interval '7 days'
    )
    select count(au.user_id)::bigint,
           (select count(*)::bigint from public.profiles),
           round(100.0 * count(au.user_id) / nullif((select count(*) from public.profiles), 0), 2)
    from active_users_7d au;
end;
$$;
revoke all on function public.timeout_admin_okr_active_users_7d() from public, anon;
grant execute on function public.timeout_admin_okr_active_users_7d() to authenticated;

-- OKR 2: registered users with at least one team membership.
create or replace function public.timeout_admin_okr_users_in_team()
returns table (
  total_users bigint,
  users_in_a_team bigint,
  pct_users_in_team numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.timeout_admin_is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  return query
    select count(distinct p.id)::bigint,
           count(distinct tm.username)::bigint,
           round(100.0 * count(distinct tm.username) / nullif(count(distinct p.id), 0), 2)
    from public.profiles p
    left join public.team_members tm on p.username = tm.username;
end;
$$;
revoke all on function public.timeout_admin_okr_users_in_team() from public, anon;
grant execute on function public.timeout_admin_okr_users_in_team() to authenticated;

-- OKR 2: average number of unique reciprocal friendship edges per registered user.
create or replace function public.timeout_admin_okr_avg_friends()
returns table (
  total_users bigint,
  total_friend_connections numeric,
  avg_friends_per_user numeric,
  avg_friends_among_users_with_friends numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.timeout_admin_is_admin() then
    raise exception 'Admin access required.' using errcode = '42501';
  end if;

  return query
    with all_friend_edges as (
      select f.user_a as user_id, f.user_b as friend_id from public.friendships f
      union all
      select f.user_b as user_id, f.user_a as friend_id from public.friendships f
    ),
    user_friend_counts as (
      select p.id as user_id, count(distinct afe.friend_id)::bigint as friend_count
      from public.profiles p
      left join all_friend_edges afe on p.id = afe.user_id
      group by p.id
    )
    select count(*)::bigint,
           coalesce(sum(friend_count), 0),
           round(avg(friend_count), 2),
           round(avg(friend_count) filter (where friend_count > 0), 2)
    from user_friend_counts;
end;
$$;
revoke all on function public.timeout_admin_okr_avg_friends() from public, anon;
grant execute on function public.timeout_admin_okr_avg_friends() to authenticated;
