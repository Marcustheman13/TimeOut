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
