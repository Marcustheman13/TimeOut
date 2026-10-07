-- TimeOut database schema (PostgreSQL).
-- Running this file drops and recreates everything, so `npm run db:reset` always gives a clean copy.
--
-- Right now it only has the two tables the login vertical slice needs. Add the rest of the tables
-- from the team's ERD (docs/erd.png) below, and add their names to the DROP line so resets stay clean.

DROP TABLE IF EXISTS sessions, users CASCADE;

-- One row per person who signs up. Login checks password_hash; every successful login
-- updates last_login_at and login_count (this is the team's vertical slice).
CREATE TABLE users (
  user_id         SERIAL PRIMARY KEY,
  username        VARCHAR(20)  NOT NULL UNIQUE,
  email           VARCHAR(254) NOT NULL UNIQUE,
  password_hash   TEXT         NOT NULL,              -- bcrypt hash, never the real password
  photo_url       TEXT,                               -- profile photo (URL or data: URL)
  is_demo         BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  last_login_at   TIMESTAMPTZ,
  login_count     INTEGER      NOT NULL DEFAULT 0
);

-- A logged-in device (browser tab now, the iOS app later). The client keeps the raw token;
-- we only store its SHA-256 hash, so a leaked database can't be used to log in.
CREATE TABLE sessions (
  session_id      SERIAL PRIMARY KEY,
  user_id         INTEGER      NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token_hash      CHAR(64)     NOT NULL UNIQUE,
  device_label    VARCHAR(200),                       -- from the User-Agent header
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ  NOT NULL
);

-- ---------- Team ERD tables go here ----------
