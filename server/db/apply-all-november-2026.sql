-- ============================================================================
-- TimeOut database update: paste this whole file into the Supabase SQL Editor and press Run.
--
-- It brings the live database up to the code on main:
--   1. renames bets to challenges (and the columns and labels with them)
--   2. installs the challenge functions and the tier system
--   3. adds team rosters and account deletion, which were never installed
--   4. adds real friends: requests, friendships, shared stats and invite links
--
-- Your data is kept: rows are renamed in place, nothing is deleted. Safe to run twice.
-- iOS builds made before the November 2026 rename stop syncing challenges after this runs.
-- ============================================================================


-- ---------- rename-challenge-vocabulary.sql ----------

-- Renames gambling vocabulary in an existing TimeOut database.
-- Run this once in the Supabase SQL editor, then re-run:
--   server/db/supabase-timeout-rpcs.sql
--   TimeOut - Web/db/tier-system-migration.sql
--   server/db/supabase-delete-account.sql
-- Safe to run again. Fresh projects that already use the new names are unchanged.
-- The old names below are the previous table, column, and type names.

begin;

do $$
begin
  if to_regclass('public.bets') is not null and to_regclass('public.challenges') is null then
    alter table public.bets rename to challenges;
  end if;
  if to_regclass('public.bet_legs') is not null and to_regclass('public.challenge_picks') is null then
    alter table public.bet_legs rename to challenge_picks;
  end if;
  if exists (select 1 from pg_type where typnamespace = 'public'::regnamespace and typname = 'bet_status')
     and not exists (select 1 from pg_type where typnamespace = 'public'::regnamespace and typname = 'challenge_status') then
    alter type public.bet_status rename to challenge_status;
  end if;
  if exists (select 1 from pg_type where typnamespace = 'public'::regnamespace and typname = 'leg_result')
     and not exists (select 1 from pg_type where typnamespace = 'public'::regnamespace and typname = 'pick_result') then
    alter type public.leg_result rename to pick_result;
  end if;
end $$;

do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenges' and column_name = 'stake_minutes') then
    alter table public.challenges rename column stake_minutes to pledge_minutes;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenges' and column_name = 'combined_odds') then
    alter table public.challenges rename column combined_odds to combined_value;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenges' and column_name = 'potential_payout_minutes') then
    alter table public.challenges rename column potential_payout_minutes to potential_reward_minutes;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenges' and column_name = 'actual_payout_minutes') then
    alter table public.challenges rename column actual_payout_minutes to actual_reward_minutes;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenges' and column_name = 'settled_at') then
    alter table public.challenges rename column settled_at to resolved_at;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenge_picks' and column_name = 'bet_id') then
    alter table public.challenge_picks rename column bet_id to challenge_id;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'challenge_picks' and column_name = 'accepted_odds') then
    alter table public.challenge_picks rename column accepted_odds to accepted_value;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'wallet_transactions' and column_name = 'bet_id') then
    alter table public.wallet_transactions rename column bet_id to challenge_id;
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'challenge_status' and e.enumlabel = 'pushed'
  ) then
    alter type public.challenge_status rename value 'pushed' to 'tied';
  end if;
  if exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'pick_result' and e.enumlabel = 'push'
  ) then
    alter type public.pick_result rename value 'push' to 'tie';
  end if;
  if exists (
    select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'transaction_type' and e.enumlabel = 'stake'
  ) then
    alter type public.transaction_type rename value 'stake' to 'pledge';
  end if;
end $$;

do $$
begin
  if to_regclass('public.challenge_picks') is not null then
    update public.challenge_picks set market = 'winner' where market in ('ml', 'moneyline');
    update public.challenge_picks set market = 'margin' where market = 'spread';
    update public.challenge_picks set side = 'higher' where side = 'over';
    update public.challenge_picks set side = 'lower' where side = 'under';
  end if;
end $$;

drop function if exists public.timeout_place_bet(integer, numeric, integer, date, jsonb);
drop function if exists public.timeout_place_bet_with_tiers(integer, numeric, integer, date, jsonb);
drop function if exists public.timeout_place_bet_with_perks(integer, numeric, integer, date, jsonb, boolean, boolean, numeric);
drop function if exists public.timeout_settle_bet(uuid, text, integer, jsonb);

commit;

-- ---------- supabase-settings-migration.sql ----------

-- Run once after the original schema to persist the app's full settings object,
-- including locked apps, enforcement, notifications, and privacy choices.
alter table public.user_settings
  add column if not exists app_preferences jsonb not null default '{}'::jsonb;

-- ---------- supabase-timeout-rpcs.sql ----------

-- Run after the main schema. These RPCs let the signed-in app place and resolve
-- screen-time challenges while keeping wallet changes atomic and behind RLS.

create or replace function public.timeout_place_challenge(
  p_pledge_minutes integer,
  p_combined_value numeric,
  p_potential_reward integer,
  p_current_day date,
  p_picks jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet_id uuid;
  v_balance integer;
  v_challenge_id uuid;
  v_pick jsonb;
begin
  if v_user_id is null then raise exception 'Sign in required'; end if;
  if p_pledge_minutes < 1 or p_combined_value <= 1 or p_potential_reward < 0 then raise exception 'Invalid challenge values'; end if;
  if jsonb_typeof(p_picks) <> 'array' or jsonb_array_length(p_picks) < 1 then raise exception 'At least one challenge pick is required'; end if;

  select id, balance_minutes into v_wallet_id, v_balance
  from public.wallets where user_id = v_user_id for update;
  if not found then raise exception 'Wallet is not set up'; end if;

  -- Reset the base daily wallet at the start of a new database day.
  if exists (select 1 from public.wallets where id = v_wallet_id and current_day <> p_current_day) then
    update public.wallets set balance_minutes = 60, current_day = p_current_day, is_locked = false
    where id = v_wallet_id returning balance_minutes into v_balance;
  end if;
  if v_balance < p_pledge_minutes then raise exception 'Not enough challenge minutes'; end if;

  insert into public.challenges (user_id, pledge_minutes, combined_value, status, potential_reward_minutes)
  values (v_user_id, p_pledge_minutes, p_combined_value, 'pending'::public.challenge_status, p_potential_reward)
  returning id into v_challenge_id;

  for v_pick in select value from jsonb_array_elements(p_picks) loop
    if coalesce(v_pick->>'espn_event_id', '') = '' or coalesce(v_pick->>'league', '') = '' or coalesce(v_pick->>'market', '') = '' then
      raise exception 'A challenge pick is missing its event, league, or market';
    end if;
    insert into public.challenge_picks (challenge_id, espn_event_id, league, matchup, market, side, line, accepted_value)
    values (v_challenge_id, v_pick->>'espn_event_id', v_pick->>'league', coalesce(v_pick->>'matchup', ''), v_pick->>'market', coalesce(v_pick->>'side', ''),
      nullif(v_pick->>'line', '')::numeric, (v_pick->>'accepted_value')::numeric);
  end loop;

  update public.wallets set balance_minutes = balance_minutes - p_pledge_minutes,
    is_locked = (balance_minutes - p_pledge_minutes) <= 0, updated_at = now()
  where id = v_wallet_id;
  insert into public.wallet_transactions (wallet_id, challenge_id, amount_minutes, type, description)
  values (v_wallet_id, v_challenge_id, -p_pledge_minutes, 'pledge'::public.transaction_type, 'Sports challenge placed');
  return v_challenge_id;
end;
$$;

create or replace function public.timeout_resolve_challenge(
  p_challenge_id uuid,
  p_status text,
  p_actual_reward integer,
  p_pick_results jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet_id uuid;
  v_pledge integer;
  v_result jsonb;
  v_pick_result public.pick_result;
  v_challenge_status public.challenge_status;
begin
  if v_user_id is null then raise exception 'Sign in required'; end if;
  if p_status not in ('won', 'lost', 'tied', 'voided', 'cancelled') or p_actual_reward < 0 then raise exception 'Invalid resolution'; end if;
  v_challenge_status := p_status::public.challenge_status;
  update public.challenges set status = v_challenge_status, actual_reward_minutes = p_actual_reward, resolved_at = now()
  where id = p_challenge_id and user_id = v_user_id and status = 'pending'::public.challenge_status
  returning pledge_minutes into v_pledge;
  if not found then return false; end if;

  for v_result in select value from jsonb_array_elements(coalesce(p_pick_results, '[]'::jsonb)) loop
    v_pick_result := case v_result->>'result'
      when 'won' then 'win'::public.pick_result
      when 'lost' then 'loss'::public.pick_result
      when 'tie' then 'tie'::public.pick_result
      when 'void' then 'void'::public.pick_result
      else 'pending'::public.pick_result end;
    update public.challenge_picks set result = v_pick_result
    where challenge_id = p_challenge_id and espn_event_id = v_result->>'espn_event_id'
      and market = v_result->>'market' and side = v_result->>'side'
      and line is not distinct from nullif(v_result->>'line', '')::numeric;
  end loop;

  -- Only voids and pushes return the pledge to today’s challenging balance. Wins affect the next phone-time limit through the resolved challenge result.
  if p_actual_reward > 0 and p_status in ('tied', 'voided', 'cancelled') then
    select id into v_wallet_id from public.wallets where user_id = v_user_id for update;
    update public.wallets set balance_minutes = balance_minutes + p_actual_reward, is_locked = false, updated_at = now()
    where id = v_wallet_id;
    insert into public.wallet_transactions (wallet_id, challenge_id, amount_minutes, type, description)
    values (v_wallet_id, p_challenge_id, p_actual_reward, 'void'::public.transaction_type, 'Sports challenge refunded');
  end if;
  return true;
end;
$$;

revoke all on function public.timeout_place_challenge(integer, numeric, integer, date, jsonb) from public;
revoke all on function public.timeout_resolve_challenge(uuid, text, integer, jsonb) from public;
grant execute on function public.timeout_place_challenge(integer, numeric, integer, date, jsonb) to authenticated;
grant execute on function public.timeout_resolve_challenge(uuid, text, integer, jsonb) to authenticated;

-- ---------- tier-system-migration.sql ----------

-- Run in Supabase SQL Editor. This is safe to rerun after the earlier
-- tier-bonus version: it only adds missing columns and creates/replaces helper
-- functions; it does not drop or rewrite existing rows or functions.
begin;

alter table public.user_settings
  add column if not exists app_preferences jsonb not null default '{}'::jsonb;

alter table public.wallets
  add column if not exists tier_bonus_day date,
  add column if not exists tier_bonus_minutes integer not null default 0,
  add column if not exists tier_boosts_by_day jsonb not null default '{}'::jsonb,
  add column if not exists tier_insurance_by_week jsonb not null default '{}'::jsonb;

alter table public.challenges
  add column if not exists boosted boolean not null default false,
  add column if not exists insured boolean not null default false,
  add column if not exists multiplier numeric not null default 1;

-- Lock points from a saved settings object: the app/site list, or the real Screen Time picks made on an iPhone,
-- whichever is higher. Limits have to be on for them to count.
create or replace function public.timeout_lock_points(p_prefs jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when coalesce((p_prefs->>'enforce')::boolean, false) then greatest(
    coalesce((
      select sum(case when locked_app in ('cat-social', 'cat-ent', 'cat-games') then 3 else 1 end)::integer
      from jsonb_array_elements_text(case when jsonb_typeof(p_prefs->'lockedApps') = 'array' then p_prefs->'lockedApps' else '[]'::jsonb end) as selected(locked_app)
    ), 0),
    least(greatest(coalesce((p_prefs->>'deviceLockPoints')::integer, 0), 0), 30)
  ) else 0 end
$$;

create or replace function public.timeout_place_challenge_with_tiers(
  p_pledge_minutes integer,
  p_combined_value numeric,
  p_potential_reward integer,
  p_current_day date,
  p_picks jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet_id uuid;
  v_balance integer;
  v_bonus_day date;
  v_bonus_minutes integer;
  v_bonus_delta integer;
  v_enforce boolean := false;
  v_lock_points integer := 0;
  v_tier_bonus integer := 0;
  v_challenge_id uuid;
  v_pick jsonb;
begin
  if v_user_id is null then raise exception 'Sign in required'; end if;
  if p_pledge_minutes < 1 or p_combined_value <= 1 or p_potential_reward < 0 then raise exception 'Invalid challenge values'; end if;
  if jsonb_typeof(p_picks) <> 'array' or jsonb_array_length(p_picks) < 1 then raise exception 'At least one challenge pick is required'; end if;

  select public.timeout_lock_points(app_preferences), coalesce((app_preferences->>'enforce')::boolean, false)
  into v_lock_points, v_enforce
  from public.user_settings where user_id = v_user_id;
  v_lock_points := coalesce(v_lock_points, 0);
  v_enforce := coalesce(v_enforce, false);
  v_tier_bonus := case
    when not v_enforce then 0
    when v_lock_points >= 8 then 10
    when v_lock_points >= 4 then 5
    when v_lock_points >= 1 then 5
    else 0
  end;

  select id, balance_minutes, tier_bonus_day, tier_bonus_minutes
  into v_wallet_id, v_balance, v_bonus_day, v_bonus_minutes
  from public.wallets where user_id = v_user_id for update;
  if not found then raise exception 'Wallet is not set up'; end if;

  -- Reset the daily base wallet and bonus ledger together on a new app day.
  if exists (select 1 from public.wallets where id = v_wallet_id and current_day <> p_current_day) then
    update public.wallets
    set balance_minutes = 60, current_day = p_current_day, is_locked = false,
        tier_bonus_day = null, tier_bonus_minutes = 0
    where id = v_wallet_id
    returning balance_minutes, tier_bonus_day, tier_bonus_minutes
    into v_balance, v_bonus_day, v_bonus_minutes;
  end if;

  -- Credit only the newly earned part of today's tier bonus. The row lock and
  -- bonus date make repeated challenge submissions safe from duplicate credits.
  if v_tier_bonus > coalesce(v_bonus_minutes, 0)
     or (v_tier_bonus > 0 and v_bonus_day is distinct from p_current_day) then
    v_bonus_delta := case
      when v_bonus_day = p_current_day then greatest(v_tier_bonus - coalesce(v_bonus_minutes, 0), 0)
      else v_tier_bonus
    end;
    update public.wallets
    set balance_minutes = balance_minutes + v_bonus_delta,
        tier_bonus_day = p_current_day,
        tier_bonus_minutes = case
          when v_bonus_day = p_current_day then greatest(v_tier_bonus, coalesce(tier_bonus_minutes, 0))
          else v_tier_bonus
        end,
        is_locked = false,
        updated_at = now()
    where id = v_wallet_id
    returning balance_minutes, tier_bonus_day, tier_bonus_minutes
    into v_balance, v_bonus_day, v_bonus_minutes;
  end if;

  if v_balance < p_pledge_minutes then raise exception 'Not enough challenge minutes'; end if;

  insert into public.challenges (user_id, pledge_minutes, combined_value, status, potential_reward_minutes)
  values (v_user_id, p_pledge_minutes, p_combined_value, 'pending'::public.challenge_status, p_potential_reward)
  returning id into v_challenge_id;

  for v_pick in select value from jsonb_array_elements(p_picks) loop
    if coalesce(v_pick->>'espn_event_id', '') = '' or coalesce(v_pick->>'league', '') = '' or coalesce(v_pick->>'market', '') = '' then
      raise exception 'A challenge pick is missing its event, league, or market';
    end if;
    insert into public.challenge_picks (challenge_id, espn_event_id, league, matchup, market, side, line, accepted_value)
    values (v_challenge_id, v_pick->>'espn_event_id', v_pick->>'league', coalesce(v_pick->>'matchup', ''), v_pick->>'market', coalesce(v_pick->>'side', ''),
      nullif(v_pick->>'line', '')::numeric, (v_pick->>'accepted_value')::numeric);
  end loop;

  update public.wallets set balance_minutes = balance_minutes - p_pledge_minutes,
    is_locked = (balance_minutes - p_pledge_minutes) <= 0, updated_at = now()
  where id = v_wallet_id;
  insert into public.wallet_transactions (wallet_id, challenge_id, amount_minutes, type, description)
  values (v_wallet_id, v_challenge_id, -p_pledge_minutes, 'pledge'::public.transaction_type, 'Sports challenge placed');
  return v_challenge_id;
end;
$$;

revoke all on function public.timeout_place_challenge_with_tiers(integer, numeric, integer, date, jsonb) from public;
grant execute on function public.timeout_place_challenge_with_tiers(integer, numeric, integer, date, jsonb) to authenticated;

create or replace function public.timeout_place_challenge_with_perks(
  p_pledge_minutes integer,
  p_combined_value numeric,
  p_potential_reward integer,
  p_current_day date,
  p_picks jsonb,
  p_use_boost boolean,
  p_use_insurance boolean,
  p_multiplier numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet_id uuid;
  v_enforce boolean := false;
  v_lock_points integer := 0;
  v_boost_limit integer := 0;
  v_insurance_limit integer := 0;
  v_boosts jsonb := '{}'::jsonb;
  v_insurance jsonb := '{}'::jsonb;
  v_boost_count integer := 0;
  v_insurance_count integer := 0;
  v_week_key text;
  v_challenge_id uuid;
begin
  if v_user_id is null then raise exception 'Sign in required'; end if;
  if p_multiplier < 1 or p_multiplier > 1.5 then raise exception 'Invalid reward multiplier'; end if;
  if p_use_insurance and jsonb_array_length(p_picks) < 2 then raise exception 'Insurance requires a combo'; end if;

  select public.timeout_lock_points(app_preferences), coalesce((app_preferences->>'enforce')::boolean, false)
  into v_lock_points, v_enforce
  from public.user_settings where user_id = v_user_id;
  v_lock_points := coalesce(v_lock_points, 0);
  v_enforce := coalesce(v_enforce, false);
  v_boost_limit := case when not v_enforce then 0 when v_lock_points >= 8 then 2 when v_lock_points >= 4 then 1 else 0 end;
  v_insurance_limit := case when v_enforce and v_lock_points >= 12 then 1 else 0 end;
  v_week_key := (p_current_day - (extract(isodow from p_current_day)::integer - 1))::text;

  select id, coalesce(tier_boosts_by_day, '{}'::jsonb), coalesce(tier_insurance_by_week, '{}'::jsonb)
  into v_wallet_id, v_boosts, v_insurance
  from public.wallets where user_id = v_user_id for update;
  if not found then raise exception 'Wallet is not set up'; end if;
  v_boost_count := coalesce((v_boosts ->> (p_current_day::text))::integer, 0);
  v_insurance_count := coalesce((v_insurance ->> v_week_key)::integer, 0);
  if p_use_boost and v_boost_count >= v_boost_limit then raise exception 'No point-value boosts left for this tier today'; end if;
  if p_use_insurance and v_insurance_count >= v_insurance_limit then raise exception 'No combo protection left for this tier this week'; end if;

  update public.wallets
  set tier_boosts_by_day = case when p_use_boost
        then jsonb_set(v_boosts, array[p_current_day::text], to_jsonb(v_boost_count + 1), true)
        else v_boosts end,
      tier_insurance_by_week = case when p_use_insurance
        then jsonb_set(v_insurance, array[v_week_key], to_jsonb(v_insurance_count + 1), true)
        else v_insurance end,
      updated_at = now()
  where id = v_wallet_id;

  v_challenge_id := public.timeout_place_challenge_with_tiers(
    p_pledge_minutes, p_combined_value, p_potential_reward, p_current_day, p_picks
  );
  update public.challenges
  set boosted = p_use_boost, insured = p_use_insurance, multiplier = p_multiplier
  where id = v_challenge_id and user_id = v_user_id;
  return v_challenge_id;
end;
$$;

revoke all on function public.timeout_place_challenge_with_perks(integer, numeric, integer, date, jsonb, boolean, boolean, numeric) from public;
grant execute on function public.timeout_place_challenge_with_perks(integer, numeric, integer, date, jsonb, boolean, boolean, numeric) to authenticated;

notify pgrst, 'reload schema';

commit;

-- ---------- supabase-teams.sql ----------

-- Optional Supabase home for teams. Run once in the SQL editor.
-- The web app uses these only when it is not talking to the Express API.
-- Membership is one row per person. A save never replaces the whole roster.
-- The share key from a team link is stored as a SHA-256 hash.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.teams (
  team_id text primary key,
  name text not null check (char_length(name) between 1 and 30),
  start_date date not null,
  end_date date not null check (end_date >= start_date),
  owner_username text not null,
  key_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id text not null references public.teams(team_id) on delete cascade,
  username text not null,
  joined_at timestamptz not null default now(),
  primary key (team_id, username)
);

create unique index if not exists team_members_lower on public.team_members (team_id, lower(username));

alter table public.teams enable row level security;
alter table public.team_members enable row level security;

create or replace function public.timeout_team_key(p_key text)
returns text
language sql
immutable
as $$
  select encode(extensions.digest(convert_to(p_key, 'UTF8'), 'sha256'), 'hex')
$$;

create or replace function public.timeout_me()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select username into v_name from public.profiles where id = auth.uid();
  if v_name is null or v_name = '' then raise exception 'Profile has no username'; end if;
  return v_name;
end;
$$;

create or replace function public.timeout_team_json(p_id text)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'id', t.team_id,
    'name', t.name,
    'start', t.start_date,
    'end', t.end_date,
    'owner', t.owner_username,
    'members', coalesce((
      select json_agg(m.username order by m.joined_at, m.username)
      from public.team_members m where m.team_id = t.team_id
    ), '[]'::json)
  )
  from public.teams t where t.team_id = p_id
$$;

-- Create a team, or return it when the same link is saved again. Does not add people on a retry.
create or replace function public.timeout_save_team(
  p_id text,
  p_name text,
  p_start date,
  p_end date,
  p_key text,
  p_members jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me text := public.timeout_me();
  v_hash text := public.timeout_team_key(p_key);
  v_owner text;
  v_member text;
begin
  if p_id !~ '^[A-Za-z0-9_-]{1,40}$' or p_key !~ '^[a-f0-9]{32}$' then raise exception 'Invalid team link'; end if;
  if p_name is null or char_length(btrim(p_name)) < 1 or char_length(btrim(p_name)) > 30 then raise exception 'Give your team a name.'; end if;
  if p_end < p_start then raise exception 'End date must be on or after the start date.'; end if;
  if exists (select 1 from public.teams where team_id = p_id) then
    if (select key_hash from public.teams where team_id = p_id) <> v_hash then raise exception 'That team already exists'; end if;
    return public.timeout_team_json(p_id);
  end if;
  v_owner := v_me;
  insert into public.teams (team_id, name, start_date, end_date, owner_username, key_hash)
  values (p_id, btrim(p_name), p_start, p_end, v_owner, v_hash);
  insert into public.team_members (team_id, username) values (p_id, v_owner);
  if jsonb_typeof(p_members) = 'array' then
    for v_member in select jsonb_array_elements_text(p_members) loop
      if v_member ~ '^[A-Za-z0-9_.]{1,20}$' and not exists (
        select 1 from public.team_members where team_id = p_id and lower(username) = lower(v_member)
      ) then
        insert into public.team_members (team_id, username) values (p_id, v_member);
      end if;
    end loop;
  end if;
  return public.timeout_team_json(p_id);
end;
$$;

create or replace function public.timeout_add_team_member(p_id text, p_key text, p_username text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select key_hash from public.teams where team_id = p_id) is distinct from public.timeout_team_key(p_key) then
    raise exception 'That team link does not match a team';
  end if;
  if p_username !~ '^[A-Za-z0-9_.]{1,20}$' then raise exception 'That username is not valid.'; end if;
  if not exists (select 1 from public.team_members where team_id = p_id and lower(username) = lower(p_username)) then
    insert into public.team_members (team_id, username) values (p_id, p_username);
  end if;
  return public.timeout_team_json(p_id);
end;
$$;

create or replace function public.timeout_leave_team(p_id text, p_key text, p_username text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner text;
  v_next text;
begin
  if (select key_hash from public.teams where team_id = p_id) is distinct from public.timeout_team_key(p_key) then
    raise exception 'That team link does not match a team';
  end if;
  delete from public.team_members where team_id = p_id and lower(username) = lower(p_username);
  if not exists (select 1 from public.team_members where team_id = p_id) then
    delete from public.teams where team_id = p_id;
    return null;
  end if;
  select owner_username into v_owner from public.teams where team_id = p_id;
  if lower(v_owner) = lower(p_username) then
    select username into v_next from public.team_members where team_id = p_id order by joined_at, username limit 1;
    update public.teams set owner_username = v_next where team_id = p_id;
  end if;
  return public.timeout_team_json(p_id);
end;
$$;

create or replace function public.timeout_get_team(p_id text, p_key text)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select key_hash from public.teams where team_id = p_id) is distinct from public.timeout_team_key(p_key) then
    return null;
  end if;
  return public.timeout_team_json(p_id);
end;
$$;

-- Teams the signed-in profile is on. A new device can read them without the link.
create or replace function public.timeout_my_teams()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me text := public.timeout_me();
begin
  return coalesce((
    select json_agg(public.timeout_team_json(t.team_id) order by t.created_at)
    from public.teams t
    join public.team_members m on m.team_id = t.team_id
    where lower(m.username) = lower(v_me)
  ), '[]'::json);
end;
$$;

grant execute on function public.timeout_save_team(text, text, date, date, text, jsonb) to authenticated;
grant execute on function public.timeout_add_team_member(text, text, text) to authenticated;
grant execute on function public.timeout_leave_team(text, text, text) to authenticated;
grant execute on function public.timeout_get_team(text, text) to authenticated;
grant execute on function public.timeout_my_teams() to authenticated;

-- ---------- supabase-social.sql ----------

-- TimeOut friends: real friend requests, friendships and shared stats across accounts.
-- Run after the challenge rename, the challenge RPCs, the tier migration and the teams file. Safe to rerun.
--
-- The tables have row-level security with no policies, so clients can only reach them through
-- the functions below. Every function works from auth.uid(), so nobody can act for someone else.

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

-- ---------- supabase-delete-account.sql ----------

-- TimeOut: in-app account deletion (App Store Review Guideline 5.1.1(v)).
-- Run once in Supabase SQL Editor. Safe to rerun.
--
-- The iOS app's Account > Delete account calls this RPC. It deletes the signed-in user's
-- rows in every public table with a user_id column, their challenge picks and wallet transactions,
-- their team memberships and profile, and finally their auth user.

create or replace function public.timeout_delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
  r record;
begin
  if v_uid is null then
    raise exception 'Not signed in.';
  end if;

  if to_regclass('public.profiles') is not null then
    select p.username into v_name from public.profiles p where p.id = v_uid;
  end if;

  -- Child rows first: challenge picks and wallet transactions point at the user's challenges and wallets.
  if to_regclass('public.challenge_picks') is not null and to_regclass('public.challenges') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'challenge_picks' and column_name = 'challenge_id') then
    execute 'delete from public.challenge_picks where challenge_id in (select id from public.challenges where user_id = $1)' using v_uid;
  end if;
  if to_regclass('public.wallet_transactions') is not null and to_regclass('public.wallets') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'wallet_transactions' and column_name = 'wallet_id') then
    execute 'delete from public.wallet_transactions where wallet_id in (select id from public.wallets where user_id = $1)' using v_uid;
  end if;

  -- Team rosters are keyed by username.
  if v_name is not null and to_regclass('public.team_members') is not null then
    execute 'delete from public.team_members where lower(username) = lower($1)' using v_name;
  end if;

  -- Every other table that stores a user_id (challenges, wallets, user_settings, ...), children first.
  for r in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'user_id' and t.table_type = 'BASE TABLE'
    order by case when c.table_name in ('challenge_picks', 'wallet_transactions') then 0
                  when c.table_name in ('challenges', 'wallets') then 2 else 1 end, c.table_name
  loop
    execute format('delete from public.%I where user_id = $1', r.table_name) using v_uid;
  end loop;

  if to_regclass('public.profiles') is not null then
    delete from public.profiles where id = v_uid;
  end if;

  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.timeout_delete_account() from public, anon;
grant execute on function public.timeout_delete_account() to authenticated;
