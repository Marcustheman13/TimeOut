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
