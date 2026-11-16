-- Stops a challenge from being placed twice. Run after tier-system-migration.sql. Safe to rerun.
--
-- The apps save in the background, and two saves running close together could both send the same
-- new challenge (November 2026: pairs of identical challenges 0.1 to 2 seconds apart).
--   * Apps now send their own ID for each challenge (p_client_ref). The same ID always returns the
--     challenge that was already saved, without charging the pledge again.
--   * Older apps send no ID. For them, the same picks and pledge placed again within 30 seconds
--     returns the earlier challenge instead of saving a second one.
-- The wallet row lock taken below makes both checks safe when two requests arrive at once.
--
-- Also caps the streak friends see at the account's age: a streak counts whole days since the account
-- was made (one spare day covers time zones). Earlier apps counted days with no screen-time data.

begin;

alter table public.challenges add column if not exists client_ref text;
create unique index if not exists challenges_user_client_ref_key
  on public.challenges (user_id, client_ref) where client_ref is not null;

-- The picks of a challenge as one comparable string: event, market, side and line.
create or replace function public.timeout_picks_signature(p_picks jsonb)
returns text
language sql
immutable
set search_path to ''
as $$
  select coalesce(string_agg(k, ',' order by k), '')
  from (
    select concat_ws('|', x->>'espn_event_id', x->>'market', coalesce(x->>'side', ''),
             coalesce(nullif(x->>'line', '')::numeric::text, '')) k
    from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) x
  ) s;
$$;

create or replace function public.timeout_challenge_signature(p_challenge_id uuid)
returns text
language sql
stable
set search_path to ''
as $$
  select coalesce(string_agg(k, ',' order by k), '')
  from (
    select concat_ws('|', p.espn_event_id, p.market, coalesce(p.side, ''), coalesce(p.line::text, '')) k
    from public.challenge_picks p where p.challenge_id = p_challenge_id
  ) s;
$$;

-- Replaces the 8-argument version. Old apps that leave out p_client_ref still reach this one.
drop function if exists public.timeout_place_challenge_with_perks(integer, numeric, integer, date, jsonb, boolean, boolean, numeric);

create or replace function public.timeout_place_challenge_with_perks(
  p_pledge_minutes integer,
  p_combined_value numeric,
  p_potential_reward integer,
  p_current_day date,
  p_picks jsonb,
  p_use_boost boolean,
  p_use_insurance boolean,
  p_multiplier numeric,
  p_client_ref text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
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
  v_signature text;
  v_ref text := nullif(trim(coalesce(p_client_ref, '')), '');
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

  -- One placement at a time per person: a second request for the same challenge waits here,
  -- then finds the first one below.
  select id, coalesce(tier_boosts_by_day, '{}'::jsonb), coalesce(tier_insurance_by_week, '{}'::jsonb)
  into v_wallet_id, v_boosts, v_insurance
  from public.wallets where user_id = v_user_id for update;
  if not found then raise exception 'Wallet is not set up'; end if;

  if v_ref is not null then
    select id into v_challenge_id from public.challenges where user_id = v_user_id and client_ref = v_ref;
    if found then return v_challenge_id; end if;
  else
    v_signature := public.timeout_picks_signature(p_picks);
    select c.id into v_challenge_id
    from public.challenges c
    where c.user_id = v_user_id
      and c.placed_at > now() - interval '30 seconds'
      and c.pledge_minutes = p_pledge_minutes
      and c.client_ref is null
      and public.timeout_challenge_signature(c.id) = v_signature
    order by c.placed_at desc
    limit 1;
    if found then return v_challenge_id; end if;
  end if;

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
  set boosted = p_use_boost, insured = p_use_insurance, multiplier = p_multiplier, client_ref = v_ref
  where id = v_challenge_id and user_id = v_user_id;
  return v_challenge_id;
end;
$function$;

revoke all on function public.timeout_place_challenge_with_perks(integer, numeric, integer, date, jsonb, boolean, boolean, numeric, text) from public;
grant execute on function public.timeout_place_challenge_with_perks(integer, numeric, integer, date, jsonb, boolean, boolean, numeric, text) to authenticated;
revoke all on function public.timeout_picks_signature(jsonb) from public;
revoke all on function public.timeout_challenge_signature(uuid) from public;

create or replace function public.timeout_set_streak(p_streak integer)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_age integer;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select current_date - p.created_at::date + 1 into v_age from public.profiles p where p.id = auth.uid();
  update public.wallets w
  set streak = greatest(0, least(coalesce(p_streak, 0), 3650, coalesce(v_age, 3650)))
  where w.user_id = auth.uid();
end;
$function$;

-- Existing streaks longer than the account is old.
update public.wallets w
set streak = greatest(0, current_date - p.created_at::date + 1)
from public.profiles p
where p.id = w.user_id and w.streak > current_date - p.created_at::date + 1;

notify pgrst, 'reload schema';

commit;
