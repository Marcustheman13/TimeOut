-- Run after the main schema. These RPCs let the signed-in app place and settle
-- screen-time bets while keeping wallet changes atomic and behind RLS.

create or replace function public.timeout_place_bet(
  p_stake_minutes integer,
  p_combined_odds numeric,
  p_potential_payout integer,
  p_current_day date,
  p_legs jsonb
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
  v_bet_id uuid;
  v_leg jsonb;
begin
  if v_user_id is null then raise exception 'Sign in required'; end if;
  if p_stake_minutes < 1 or p_combined_odds <= 1 or p_potential_payout < 0 then raise exception 'Invalid bet values'; end if;
  if jsonb_typeof(p_legs) <> 'array' or jsonb_array_length(p_legs) < 1 then raise exception 'At least one bet leg is required'; end if;

  select id, balance_minutes into v_wallet_id, v_balance
  from public.wallets where user_id = v_user_id for update;
  if not found then raise exception 'Wallet is not set up'; end if;

  -- Reset the base daily wallet at the start of a new database day.
  if exists (select 1 from public.wallets where id = v_wallet_id and current_day <> p_current_day) then
    update public.wallets set balance_minutes = 60, current_day = p_current_day, is_locked = false
    where id = v_wallet_id returning balance_minutes into v_balance;
  end if;
  if v_balance < p_stake_minutes then raise exception 'Not enough betting minutes'; end if;

  insert into public.bets (user_id, stake_minutes, combined_odds, status, potential_payout_minutes)
  values (v_user_id, p_stake_minutes, p_combined_odds, 'pending'::public.bet_status, p_potential_payout)
  returning id into v_bet_id;

  for v_leg in select value from jsonb_array_elements(p_legs) loop
    if coalesce(v_leg->>'espn_event_id', '') = '' or coalesce(v_leg->>'league', '') = '' or coalesce(v_leg->>'market', '') = '' then
      raise exception 'A bet leg is missing its event, league, or market';
    end if;
    insert into public.bet_legs (bet_id, espn_event_id, league, matchup, market, side, line, accepted_odds)
    values (v_bet_id, v_leg->>'espn_event_id', v_leg->>'league', coalesce(v_leg->>'matchup', ''), v_leg->>'market', coalesce(v_leg->>'side', ''),
      nullif(v_leg->>'line', '')::numeric, (v_leg->>'accepted_odds')::numeric);
  end loop;

  update public.wallets set balance_minutes = balance_minutes - p_stake_minutes,
    is_locked = (balance_minutes - p_stake_minutes) <= 0, updated_at = now()
  where id = v_wallet_id;
  insert into public.wallet_transactions (wallet_id, bet_id, amount_minutes, type, description)
  values (v_wallet_id, v_bet_id, -p_stake_minutes, 'stake'::public.transaction_type, 'Sports bet placed');
  return v_bet_id;
end;
$$;

create or replace function public.timeout_settle_bet(
  p_bet_id uuid,
  p_status text,
  p_actual_payout integer,
  p_leg_results jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_wallet_id uuid;
  v_stake integer;
  v_result jsonb;
  v_leg_result public.leg_result;
  v_bet_status public.bet_status;
  v_tx_type public.transaction_type;
begin
  if v_user_id is null then raise exception 'Sign in required'; end if;
  if p_status not in ('won', 'lost', 'pushed', 'voided', 'cancelled') or p_actual_payout < 0 then raise exception 'Invalid settlement'; end if;
  v_bet_status := p_status::public.bet_status;
  update public.bets set status = v_bet_status, actual_payout_minutes = p_actual_payout, settled_at = now()
  where id = p_bet_id and user_id = v_user_id and status = 'pending'::public.bet_status
  returning stake_minutes into v_stake;
  if not found then return false; end if;

  for v_result in select value from jsonb_array_elements(coalesce(p_leg_results, '[]'::jsonb)) loop
    v_leg_result := case v_result->>'result'
      when 'won' then 'win'::public.leg_result
      when 'lost' then 'loss'::public.leg_result
      when 'push' then 'push'::public.leg_result
      when 'void' then 'void'::public.leg_result
      else 'pending'::public.leg_result end;
    update public.bet_legs set result = v_leg_result
    where bet_id = p_bet_id and espn_event_id = v_result->>'espn_event_id'
      and market = v_result->>'market' and side = v_result->>'side'
      and line is not distinct from nullif(v_result->>'line', '')::numeric;
  end loop;

  if p_actual_payout > 0 then
    select id into v_wallet_id from public.wallets where user_id = v_user_id for update;
    update public.wallets set balance_minutes = balance_minutes + p_actual_payout, is_locked = false, updated_at = now()
    where id = v_wallet_id;
    v_tx_type := case when p_status in ('pushed', 'voided', 'cancelled') then 'void'::public.transaction_type else 'payout'::public.transaction_type end;
    insert into public.wallet_transactions (wallet_id, bet_id, amount_minutes, type, description)
    values (v_wallet_id, p_bet_id, p_actual_payout, v_tx_type, 'Sports bet settled');
  end if;
  return true;
end;
$$;

revoke all on function public.timeout_place_bet(integer, numeric, integer, date, jsonb) from public;
revoke all on function public.timeout_settle_bet(uuid, text, integer, jsonb) from public;
grant execute on function public.timeout_place_bet(integer, numeric, integer, date, jsonb) to authenticated;
grant execute on function public.timeout_settle_bet(uuid, text, integer, jsonb) to authenticated;
