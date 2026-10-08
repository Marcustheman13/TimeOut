-- Run once after the original schema to persist the app's full settings object,
-- including locked apps, enforcement, notifications, and privacy choices.
alter table public.user_settings
  add column if not exists app_preferences jsonb not null default '{}'::jsonb;
