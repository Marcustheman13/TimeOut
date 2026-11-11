-- TimeOut weekly report: who is due an email this week, the raw numbers for it, and a log of what was sent.
-- Run after apply-all-november-2026.sql and supabase-push.sql (it reuses the Vault secret and pg_cron/pg_net from that file).
-- Safe to rerun. Setup steps: supabase/functions/weekly-report/README.md
--
-- How it fits together: pg_cron pings the weekly-report Edge Function every hour, but only when somebody is
-- actually due (Monday 08:00-19:59 in their own timezone, not opted out, not already sent). The function asks
-- timeout_weekly_report_work for each person's raw numbers, works out the stats, asks the AI to write the email,
-- and sends it. Every attempt is recorded in weekly_reports, which is also what stops a second email.
--
-- The tables have row-level security with no policies, so clients can't reach them. Only the Edge Function
-- (service role) calls the functions below.

-- MARK: Tables

-- One row per person per week. status: pending = being worked on, sent = email went out,
-- dry_run = written but not sent (for review), skipped = nothing worth saying, failed = gave up.
create table if not exists public.weekly_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  week_start date not null, -- the Monday of the week the report is about, in the person's own timezone
  status text not null default 'pending' check (status in ('pending', 'sent', 'dry_run', 'skipped', 'failed')),
  source text check (source in ('ai', 'fallback')), -- who wrote the words: the AI, or the built-in template
  stats jsonb,       -- the numbers the report was built from
  decision jsonb,    -- what the AI decided: week type, tone, headline, insight, suggestion
  subject text,
  body_text text,    -- plain-text copy of the email, so a dry run can be read in the table
  email_id text,     -- Resend's id for the message
  note text,         -- why it was skipped, or why the AI's answer was replaced
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (user_id, week_start)
);

-- People who clicked unsubscribe. Kept apart from app_preferences because the apps save that whole object
-- back from the keys they know about, which could quietly wipe an unknown flag.
create table if not exists public.weekly_report_optouts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.weekly_reports enable row level security;
alter table public.weekly_report_optouts enable row level security;

-- MARK: Helpers

-- A timezone name Postgres understands, or Denver. A bad value in user_settings must not stop the sweep for everyone.
create or replace function public.timeout_safe_timezone(p_tz text)
returns text
language plpgsql
stable
set search_path = ''
as $$
begin
  perform now() at time zone coalesce(p_tz, '');
  return p_tz;
exception when others then
  return 'America/Denver';
end;
$$;

-- Who should get a report right now, and for which week. Normally that is everybody whose local clock says
-- Monday between 8am and 8pm and who hasn't been handled for last week. Passing p_user skips the clock and
-- the "already done" check, for sending one person a test report on any day. Opt-outs always win.
create or replace function public.timeout_weekly_report_due(
  p_now timestamptz default now(),
  p_user uuid default null,
  p_week_start date default null
)
returns table (user_id uuid, timezone text, week_start date)
language sql
stable
security definer
set search_path = ''
as $$
  select s.user_id, z.tz, w.week_start
  from public.user_settings s
  cross join lateral (select public.timeout_safe_timezone(s.timezone) as tz) z
  cross join lateral (select p_now at time zone z.tz as local_now) n
  -- Monday of the previous week: today's date, back to this Monday, back another 7 days.
  cross join lateral (select coalesce(p_week_start, n.local_now::date - extract(isodow from n.local_now)::int - 6) as week_start) w
  where (
      (p_user is not null and s.user_id = p_user)
      or (p_user is null
          and extract(isodow from n.local_now) = 1
          and extract(hour from n.local_now) between 8 and 19)
    )
    and exists (
      select 1 from auth.users u
      where u.id = s.user_id and u.email is not null and u.email_confirmed_at is not null)
    and not exists (select 1 from public.weekly_report_optouts o where o.user_id = s.user_id)
    and coalesce(s.app_preferences, '{}'::jsonb) #>> '{notify,weekly}' is distinct from 'false'
    and (
      p_user is not null
      or not exists (
        select 1 from public.weekly_reports r
        where r.user_id = s.user_id
          and r.week_start = w.week_start
          -- a pending row that is over 30 minutes old means the last attempt died, so try again
          and (r.status <> 'pending' or r.created_at > p_now - interval '30 minutes'))
    );
$$;

-- MARK: Called by the Edge Function

-- The raw numbers for everyone due, up to p_limit people (the next hourly run picks up the rest).
-- Only plain facts leave the database here. The function turns them into stats, and only the stats go to the AI.
-- Challenge dates are in the person's own timezone, and cover this week and the one before, for the comparison.
create or replace function public.timeout_weekly_report_work(
  p_now timestamptz default now(),
  p_user uuid default null,
  p_week_start date default null,
  p_limit int default 20
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.user_id), '[]'::jsonb)
  from (
    select d.user_id,
      jsonb_build_object(
        'userId', d.user_id,
        'email', u.email,
        'name', coalesce(nullif(p.display_name, ''), p.username),
        'timezone', d.timezone,
        'weekStart', d.week_start,
        -- Preferences are text that users write, so a bad value must not break everyone's report.
        'enforce', coalesce(s.app_preferences, '{}'::jsonb) ->> 'enforce' is distinct from 'false',
        'minLimit', case when coalesce(s.app_preferences, '{}'::jsonb) ->> 'minLimit' ~ '^[0-9]{1,4}$'
                         then (s.app_preferences ->> 'minLimit')::int else 0 end,
        'streak', coalesce(wl.streak, 0),
        'usageByDay', coalesce(s.shared_ledger -> 'usageByDay', '{}'::jsonb),
        'overridesByDay', coalesce(s.shared_ledger -> 'overridesByDay', '{}'::jsonb),
        'penaltyByDay', coalesce(s.shared_ledger -> 'penaltyByDay', '{}'::jsonb),
        'challenges', coalesce((
          select jsonb_agg(jsonb_build_object(
            'day', to_char(c.resolved_at at time zone d.timezone, 'YYYY-MM-DD'),
            'status', c.status::text,
            'pledge', c.pledge_minutes,
            'reward', c.actual_reward_minutes,
            'insured', c.insured,
            'leagues', coalesce((select jsonb_agg(distinct k.league) from public.challenge_picks k where k.challenge_id = c.id), '[]'::jsonb)))
          from public.challenges c
          where c.user_id = d.user_id
            and c.status::text in ('won', 'lost', 'tied')
            and (c.resolved_at at time zone d.timezone)::date between d.week_start - 7 and d.week_start + 6
        ), '[]'::jsonb)
      ) as item
    from public.timeout_weekly_report_due(p_now, p_user, p_week_start) d
    join auth.users u on u.id = d.user_id
    join public.user_settings s on s.user_id = d.user_id
    left join public.profiles p on p.id = d.user_id
    left join public.wallets wl on wl.user_id = d.user_id
    order by d.user_id
    limit greatest(p_limit, 1)
  ) x;
$$;

-- True for whichever run gets there first. p_force takes the row over even if it was already sent (test runs only).
create or replace function public.timeout_weekly_report_claim(p_user uuid, p_week date, p_force boolean default false)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.weekly_reports (user_id, week_start) values (p_user, p_week)
  on conflict (user_id, week_start) do update
    set status = 'pending', created_at = now(), sent_at = null
    where p_force
       or (weekly_reports.status = 'pending' and weekly_reports.created_at < now() - interval '30 minutes');
  return found;
end;
$$;

-- Records how it ended.
create or replace function public.timeout_weekly_report_finish(
  p_user uuid, p_week date, p_status text, p_source text,
  p_stats jsonb, p_decision jsonb, p_subject text, p_body text, p_email_id text, p_note text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.weekly_reports r
  set status = p_status, source = p_source, stats = p_stats, decision = p_decision,
      subject = p_subject, body_text = p_body, email_id = p_email_id, note = p_note,
      sent_at = case when p_status = 'sent' then now() else null end
  where r.user_id = p_user and r.week_start = p_week;
$$;

-- The email provider couldn't take it right now, so a later run tries again.
create or replace function public.timeout_weekly_report_release(p_user uuid, p_week date)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.weekly_reports r where r.user_id = p_user and r.week_start = p_week and r.status = 'pending';
$$;

-- The unsubscribe link in the email.
create or replace function public.timeout_weekly_report_unsubscribe(p_user uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.weekly_report_optouts (user_id) values (p_user) on conflict (user_id) do nothing;
$$;

-- MARK: What wakes the Edge Function

-- Pings only when someone is due, so the other 160-odd hours a week cost nothing.
create or replace function public.timeout_ping_weekly_report()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
begin
  if not exists (select 1 from public.timeout_weekly_report_due()) then return; end if;
  select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.name = 'push_webhook_secret' limit 1;
  if v_secret is null then return; end if;
  perform net.http_post(
    url := 'https://obegznrsxlbpmtbmqkll.supabase.co/functions/v1/weekly-report',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 120000
  );
exception when others then
  raise warning 'timeout_ping_weekly_report failed: %', sqlerrm;
end;
$$;

-- cron.schedule replaces a job of the same name, so rerunning is fine.
select cron.schedule('timeout-weekly-report', '5 * * * *', $$select public.timeout_ping_weekly_report()$$);

-- MARK: Permissions

revoke all on table public.weekly_reports from public, anon, authenticated;
revoke all on table public.weekly_report_optouts from public, anon, authenticated;

revoke all on function public.timeout_safe_timezone(text) from public, anon, authenticated;
revoke all on function public.timeout_weekly_report_due(timestamptz, uuid, date) from public, anon, authenticated;
revoke all on function public.timeout_weekly_report_work(timestamptz, uuid, date, int) from public, anon, authenticated;
revoke all on function public.timeout_weekly_report_claim(uuid, date, boolean) from public, anon, authenticated;
revoke all on function public.timeout_weekly_report_finish(uuid, date, text, text, jsonb, jsonb, text, text, text, text) from public, anon, authenticated;
revoke all on function public.timeout_weekly_report_release(uuid, date) from public, anon, authenticated;
revoke all on function public.timeout_weekly_report_unsubscribe(uuid) from public, anon, authenticated;
revoke all on function public.timeout_ping_weekly_report() from public, anon, authenticated;

grant execute on function public.timeout_weekly_report_work(timestamptz, uuid, date, int) to service_role;
grant execute on function public.timeout_weekly_report_claim(uuid, date, boolean) to service_role;
grant execute on function public.timeout_weekly_report_finish(uuid, date, text, text, jsonb, jsonb, text, text, text, text) to service_role;
grant execute on function public.timeout_weekly_report_release(uuid, date) to service_role;
grant execute on function public.timeout_weekly_report_unsubscribe(uuid) to service_role;

notify pgrst, 'reload schema';
