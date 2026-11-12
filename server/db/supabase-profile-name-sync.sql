-- Keeps the name other people see (profiles.display_name) in step with the username.
-- Friends lists, requests and leaderboards show display_name, which sign-up filled in from the username. Changing the
-- username later only updated profiles.username, so people kept seeing the old name.
-- Safe to rerun. The apps now send both columns; this makes sure any client (including older iPhone builds) does too.

create or replace function public.timeout_sync_display_name()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Only follow the username when the name was the username (or empty), so a name set on purpose would be left alone.
  if new.username is distinct from old.username and coalesce(old.display_name, '') in ('', old.username) then
    new.display_name := new.username;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_sync_display_name on public.profiles;
create trigger profiles_sync_display_name
  before update of username on public.profiles
  for each row execute function public.timeout_sync_display_name();

-- One-time fix for accounts that already changed their username. display_name has only ever been filled from the
-- username, so making them match loses nothing.
update public.profiles set display_name = username where display_name is distinct from username;
