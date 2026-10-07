-- Sample data. Run after schema.sql (`npm run db:reset` does both).
-- Every seeded account uses the test password  timeout123  (bcrypt hash below).
-- Times are relative to now() so the data always looks recent.

INSERT INTO users (username, email, password_hash, is_demo, created_at, last_login_at, login_count) VALUES
  ('demo',       'demo@timeout.app', '$2b$10$3L0YBvaFJWj19Op0aXdVdO7lPYblABj.wnbKxlcMI3SPWwJR0TLAW', TRUE,  now() - interval '30 days', now() - interval '1 day',  12),
  ('mike_t',     'mike@example.com', '$2b$10$3L0YBvaFJWj19Op0aXdVdO7lPYblABj.wnbKxlcMI3SPWwJR0TLAW', FALSE, now() - interval '25 days', now() - interval '3 hours', 40),
  ('jess.plays', 'jess@example.com', '$2b$10$3L0YBvaFJWj19Op0aXdVdO7lPYblABj.wnbKxlcMI3SPWwJR0TLAW', FALSE, now() - interval '20 days', now() - interval '2 days',  18),
  ('lily_k',     'lily@example.com', '$2b$10$3L0YBvaFJWj19Op0aXdVdO7lPYblABj.wnbKxlcMI3SPWwJR0TLAW', FALSE, now() - interval '12 days', NULL,                       0);

-- Hashes of made-up tokens; nobody can log in with these. Real sessions come from POST /api/auth/login.
INSERT INTO sessions (user_id, token_hash, device_label, created_at, expires_at) VALUES
  (1, repeat('a', 64), 'Safari on iPhone (sample)',   now() - interval '1 day',   now() + interval '29 days'),
  (2, repeat('b', 64), 'Chrome on Mac (sample)',      now() - interval '3 hours', now() + interval '30 days'),
  (3, repeat('c', 64), 'Firefox on Windows (sample)', now() - interval '40 days', now() - interval '10 days');

-- ---------- Sample rows for the team's ERD tables go here ----------
