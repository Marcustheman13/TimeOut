-- TimeOut: in-app account deletion (App Store Review Guideline 5.1.1(v)).
-- Run once in Supabase SQL Editor. Safe to rerun.
--
-- The iOS app's Account > Delete account calls this RPC. It deletes the signed-in user's
-- rows in every public table with a user_id column, their bet legs and wallet transactions,
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

  -- Child rows first: bet legs and wallet transactions point at the user's bets and wallets.
  if to_regclass('public.bet_legs') is not null and to_regclass('public.bets') is not null
     and exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'bet_legs' and column_name = 'bet_id') then
    execute 'delete from public.bet_legs where bet_id in (select id from public.bets where user_id = $1)' using v_uid;
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

  -- Every other table that stores a user_id (bets, wallets, user_settings, ...), children first.
  for r in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'user_id' and t.table_type = 'BASE TABLE'
    order by case when c.table_name in ('bet_legs', 'wallet_transactions') then 0
                  when c.table_name in ('bets', 'wallets') then 2 else 1 end, c.table_name
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
