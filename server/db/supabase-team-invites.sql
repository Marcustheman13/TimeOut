-- Team invites need consent: adding someone to a team now sends them an invite they can accept or decline.
-- Run once in the Supabase SQL editor, after supabase-teams.sql. Safe to run again.
--
-- Before: a team member could put any username straight onto the roster.
-- After:  only you can put yourself on a roster (by accepting an invite or opening a team link).
--         Adding someone else creates a pending invite, which they see in the app with Join and Decline.

create table if not exists public.team_invites (
  team_id text not null references public.teams(team_id) on delete cascade,
  username text not null,
  invited_by text not null,
  -- The team link key, so the person who accepts gets the same access as someone opening the link.
  -- Only returned to the invited person.
  share_key text not null,
  created_at timestamptz not null default now(),
  primary key (team_id, username)
);

create unique index if not exists team_invites_lower on public.team_invites (team_id, lower(username));
create index if not exists team_invites_user on public.team_invites (lower(username));

alter table public.team_invites enable row level security;
-- No policies: only the security definer functions below read or write invites.

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
    ), '[]'::json),
    'invited', coalesce((
      select json_agg(i.username order by i.created_at, i.username)
      from public.team_invites i where i.team_id = t.team_id
    ), '[]'::json)
  )
  from public.teams t where t.team_id = p_id
$$;

-- Invite one person. Skips people already on the team or already invited.
create or replace function public.timeout_invite_to_team(p_id text, p_key text, p_username text, p_from text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_username !~ '^[A-Za-z0-9_.]{1,20}$' then return; end if;
  if exists (select 1 from public.team_members where team_id = p_id and lower(username) = lower(p_username)) then return; end if;
  if exists (select 1 from public.team_invites where team_id = p_id and lower(username) = lower(p_username)) then return; end if;
  insert into public.team_invites (team_id, username, invited_by, share_key) values (p_id, p_username, p_from, p_key);
end;
$$;

revoke all on function public.timeout_invite_to_team(text, text, text, text) from public, anon, authenticated;

-- Create a team, or return it when the same link is saved again. The creator joins; everyone else listed is invited.
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
  v_member text;
begin
  if p_id !~ '^[A-Za-z0-9_-]{1,40}$' or p_key !~ '^[a-f0-9]{32}$' then raise exception 'Invalid team link'; end if;
  if p_name is null or char_length(btrim(p_name)) < 1 or char_length(btrim(p_name)) > 30 then raise exception 'Give your team a name.'; end if;
  if p_end < p_start then raise exception 'End date must be on or after the start date.'; end if;
  if exists (select 1 from public.teams where team_id = p_id) then
    if (select key_hash from public.teams where team_id = p_id) <> v_hash then raise exception 'That team already exists'; end if;
    return public.timeout_team_json(p_id);
  end if;
  insert into public.teams (team_id, name, start_date, end_date, owner_username, key_hash)
  values (p_id, btrim(p_name), p_start, p_end, v_me, v_hash);
  insert into public.team_members (team_id, username) values (p_id, v_me);
  if jsonb_typeof(p_members) = 'array' then
    for v_member in select jsonb_array_elements_text(p_members) loop
      perform public.timeout_invite_to_team(p_id, p_key, v_member, v_me);
    end loop;
  end if;
  return public.timeout_team_json(p_id);
end;
$$;

-- Yourself: join (from a team link or an invite you accepted). Anyone else: send them an invite.
-- Only people already on the team can invite.
create or replace function public.timeout_add_team_member(p_id text, p_key text, p_username text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me text := public.timeout_me();
begin
  if (select key_hash from public.teams where team_id = p_id) is distinct from public.timeout_team_key(p_key) then
    raise exception 'That team link does not match a team';
  end if;
  if p_username !~ '^[A-Za-z0-9_.]{1,20}$' then raise exception 'That username is not valid.'; end if;
  if lower(p_username) = lower(v_me) then
    if not exists (select 1 from public.team_members where team_id = p_id and lower(username) = lower(v_me)) then
      insert into public.team_members (team_id, username) values (p_id, v_me);
    end if;
    delete from public.team_invites where team_id = p_id and lower(username) = lower(v_me);
  else
    if not exists (select 1 from public.team_members where team_id = p_id and lower(username) = lower(v_me)) then
      raise exception 'Only people on this team can invite others.';
    end if;
    perform public.timeout_invite_to_team(p_id, p_key, p_username, v_me);
  end if;
  return public.timeout_team_json(p_id);
end;
$$;

-- Invites waiting for the signed-in person. The key lets them join the same way a team link would.
create or replace function public.timeout_my_team_invites()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me text := public.timeout_me();
begin
  return coalesce((
    select json_agg(json_build_object(
      'id', t.team_id, 'name', t.name, 'start', t.start_date, 'end', t.end_date,
      'owner', t.owner_username, 'from', i.invited_by, 'key', i.share_key, 'at', i.created_at
    ) order by i.created_at desc)
    from public.team_invites i
    join public.teams t on t.team_id = i.team_id
    where lower(i.username) = lower(v_me)
  ), '[]'::json);
end;
$$;

-- Say no to an invite. The team is told nothing beyond the invite disappearing.
create or replace function public.timeout_decline_team_invite(p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me text := public.timeout_me();
begin
  delete from public.team_invites where team_id = p_id and lower(username) = lower(v_me);
end;
$$;

grant execute on function public.timeout_save_team(text, text, date, date, text, jsonb) to authenticated;
grant execute on function public.timeout_add_team_member(text, text, text) to authenticated;
grant execute on function public.timeout_my_team_invites() to authenticated;
grant execute on function public.timeout_decline_team_invite(text) to authenticated;
