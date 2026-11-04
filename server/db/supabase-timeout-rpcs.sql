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
