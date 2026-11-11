-- Holds what the challenge tables don't: the phone's screen-time records (phone time used, emergency
-- unlocks, penalties), so the website can display them, and each device's totals for to-do, race and
-- prediction challenges. Safe to rerun. The apps keep working without it, but this stays on each device.
alter table public.user_settings
  add column if not exists shared_ledger jsonb not null default '{}'::jsonb;

notify pgrst, 'reload schema';
