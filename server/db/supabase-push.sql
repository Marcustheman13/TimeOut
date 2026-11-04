-- TimeOut push notifications: device tokens, and what tells the send-push Edge Function to run.
-- Run after apply-all-november-2026.sql, which creates challenges and friend_requests. Safe to rerun.
-- Setup steps, including the Vault secret this file reads: TimeOut - iOS App/Setup/PUSH_SETUP.md
--
-- The tables have row-level security with no policies, so clients can only reach them through
-- the functions below. Every client function works from auth.uid().

create extension if not exists pg_net;
create extension if not exists pg_cron;

-- One row per phone. The token is the key, so signing in as someone else on a phone moves it to them.
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_id on public.device_tokens (user_id);

-- What has already gone out, so the sweep every minute never repeats itself.
create table if not exists public.push_log (
  key text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  sent_at timestamptz not null default now()
);

alter table public.device_tokens enable row level security;
alter table public.push_log enable row level security;

-- MARK: Called by the app

create or replace function public.timeout_register_device(p_token text, p_environment text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'Sign in required'; end if;
  if p_token !~ '^[0-9a-f]{64,200}$' then raise exception 'Invalid device token'; end if;
  if p_environment not in ('sandbox', 'production') then raise exception 'Invalid push environment'; end if;
  insert into public.device_tokens (token, user_id, environment)
  values (p_token, v_me, p_environment)
  on conflict (token) do update
    set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();
end;
$$;

-- Signing out stops this phone getting that account's notifications.
create or replace function public.timeout_unregister_device(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  delete from public.device_tokens d where d.token = p_token and d.user_id = auth.uid();
end;
$$;

-- MARK: Called by the send-push Edge Function

-- Everything that might need a notification, limited to people with a phone registered and that
-- notification switched on in Settings. A missing preference counts as on, like both apps.
-- Preferences are compared as text because users write them. A bad value must not stop the sweep for everyone.
create or replace function public.timeout_push_work(p_scope text default 'all')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with people as (
    select u.user_id,
           coalesce(s.app_preferences, '{}'::jsonb) #>> '{notify,friends}' is distinct from 'false' as friends,
           coalesce(coalesce(s.app_preferences, '{}'::jsonb) #>> '{notify,resolved}',
                    coalesce(s.app_preferences, '{}'::jsonb) #>> '{notify,settled}') is distinct from 'false' as resolved
    from (select distinct d.user_id from public.device_tokens d) u
    left join public.user_settings s on s.user_id = u.user_id
  )
  select jsonb_build_object(
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object('userId', d.user_id, 'token', d.token, 'environment', d.environment))
      from public.device_tokens d
    ), '[]'::jsonb),

    -- created_at also moves when someone asks again, and the log key allows one notification per pair per day.
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', 'request:' || r.from_user || ':' || r.to_user || ':' || to_char(now() at time zone 'utc', 'YYYY-MM-DD'),
        'userId', r.to_user,
        'username', p.username))
      from public.friend_requests r
      join public.profiles p on p.id = r.from_user
      join people w on w.user_id = r.to_user and w.friends
      where r.created_at > now() - interval '10 minutes'
        and not exists (
          select 1 from public.push_log l
          where l.key = 'request:' || r.from_user || ':' || r.to_user || ':' || to_char(now() at time zone 'utc', 'YYYY-MM-DD'))
    ), '[]'::jsonb),

    -- Open challenges the function grades against ESPN, plus any another device has just resolved.
    'challenges', case when p_scope = 'friends' then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'userId', c.user_id,
        'status', c.status::text,
        'pledgeMinutes', c.pledge_minutes,
        'rewardMinutes', c.actual_reward_minutes,
        'insured', c.insured,
        'multiplier', c.multiplier,
        'picks', coalesce((
          select jsonb_agg(jsonb_build_object(
            'eventId', k.espn_event_id, 'league', k.league, 'matchup', k.matchup, 'market', k.market,
            'side', k.side, 'line', k.line, 'price', k.accepted_value, 'result', k.result::text))
          from public.challenge_picks k where k.challenge_id = c.id
        ), '[]'::jsonb)))
      from public.challenges c
      join people w on w.user_id = c.user_id and w.resolved
      where ((c.status::text = 'pending' and c.placed_at > now() - interval '14 days')
          or (c.status::text <> 'pending' and c.resolved_at > now() - interval '15 minutes'))
        and not exists (select 1 from public.push_log l where l.key = 'challenge:' || c.id)
    ), '[]'::jsonb) end
  )
$$;

-- True for whichever sweep gets there first.
create or replace function public.timeout_push_claim(p_key text, p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.push_log (key, user_id) values (p_key, p_user) on conflict (key) do nothing;
  return found;
end;
$$;

-- Apple couldn't take it right now, so the next sweep tries again.
create or replace function public.timeout_push_release(p_key text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_log l where l.key = p_key;
$$;

-- Apple says the app is gone from that phone.
create or replace function public.timeout_push_forget_device(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.device_tokens d where d.token = p_token;
$$;

-- MARK: What wakes the Edge Function

-- Runs inside other people's transactions, so nothing here may ever fail a friend request.
create or replace function public.timeout_ping_push(p_scope text default 'all')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.name = 'push_webhook_secret' limit 1;
  if v_secret is null then return; end if;
  perform net.http_post(
    url := 'https://obegznrsxlbpmtbmqkll.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('scope', p_scope),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 30000
  );
exception when others then
  raise warning 'timeout_ping_push failed: %', sqlerrm;
end;
$$;

create or replace function public.timeout_friend_request_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.timeout_ping_push('friends');
  return new;
end;
$$;

drop trigger if exists friend_request_push on public.friend_requests;
create trigger friend_request_push
  after insert on public.friend_requests
  for each row execute function public.timeout_friend_request_push();

-- A closed app can't resolve a challenge, so nothing changes in the database when its game ends.
-- This sweep is what notices. cron.schedule replaces a job of the same name, so rerunning is fine.
select cron.schedule('timeout-send-push', '* * * * *', $$select public.timeout_ping_push('all')$$);
select cron.schedule('timeout-push-log-cleanup', '0 4 * * *', $$delete from public.push_log where sent_at < now() - interval '30 days'$$);

-- MARK: Permissions

revoke all on table public.device_tokens from public, anon, authenticated;
revoke all on table public.push_log from public, anon, authenticated;

revoke all on function public.timeout_register_device(text, text) from public, anon;
revoke all on function public.timeout_unregister_device(text) from public, anon;
grant execute on function public.timeout_register_device(text, text) to authenticated;
grant execute on function public.timeout_unregister_device(text) to authenticated;

revoke all on function public.timeout_push_work(text) from public, anon, authenticated;
revoke all on function public.timeout_push_claim(text, uuid) from public, anon, authenticated;
revoke all on function public.timeout_push_release(text) from public, anon, authenticated;
revoke all on function public.timeout_push_forget_device(text) from public, anon, authenticated;
grant execute on function public.timeout_push_work(text) to service_role;
grant execute on function public.timeout_push_claim(text, uuid) to service_role;
grant execute on function public.timeout_push_release(text) to service_role;
grant execute on function public.timeout_push_forget_device(text) to service_role;

revoke all on function public.timeout_ping_push(text) from public, anon, authenticated;
revoke all on function public.timeout_friend_request_push() from public, anon, authenticated;

notify pgrst, 'reload schema';
