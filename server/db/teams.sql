-- Additive team tables for a database that already has users.
-- Safe to run more than once. schema.sql creates the same tables on a fresh database.

CREATE TABLE IF NOT EXISTS teams (
  team_id         TEXT PRIMARY KEY,
  name            VARCHAR(30)  NOT NULL,
  start_date      DATE         NOT NULL,
  end_date        DATE         NOT NULL,
  owner_username  VARCHAR(20)  NOT NULL,
  key_hash        CHAR(64)     NOT NULL,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT teams_dates CHECK (end_date >= start_date)
);

CREATE TABLE IF NOT EXISTS team_members (
  team_id    TEXT         NOT NULL REFERENCES teams(team_id) ON DELETE CASCADE,
  username   VARCHAR(20)  NOT NULL,
  joined_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (team_id, username)
);

CREATE UNIQUE INDEX IF NOT EXISTS team_members_lower ON team_members (team_id, lower(username));
