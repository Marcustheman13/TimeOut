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
