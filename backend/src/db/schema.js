import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DB_PATH = process.env.DB_PATH || join(__dirname, '..', '..', 'data.sqlite');

// Node's built-in SQLite driver (stable in Node 22.5+, no native build step —
// this avoids the node-gyp/Xcode toolchain that better-sqlite3 requires).
const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA foreign_keys = ON');

// The schema follows the brief's event-sourced / audit-friendly model.
// Canonical timestamps are stored in UTC (ISO-8601). Timezone identifiers
// are preserved so the client can render local wall-clock time correctly.
db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id                 TEXT PRIMARY KEY,
  email              TEXT UNIQUE NOT NULL,
  display_name       TEXT NOT NULL DEFAULT '',
  password_hash      TEXT NOT NULL,
  timezone_preference TEXT NOT NULL DEFAULT 'America/Los_Angeles',
  week_starts_on     INTEGER NOT NULL DEFAULT 0, -- 0 = Sunday, 1 = Monday
  created_at         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform     TEXT NOT NULL, -- ios | web | mac
  device_name  TEXT NOT NULL DEFAULT '',
  app_version  TEXT NOT NULL DEFAULT '',
  created_at   TEXT NOT NULL,
  last_seen_at TEXT
);

-- Append-only raw actions. History is preserved here even when sessions change.
CREATE TABLE IF NOT EXISTS clock_events (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id    TEXT,
  type          TEXT NOT NULL, -- clock_in | clock_out | note_added | session_created |
                               -- session_edited | session_deleted | session_restored |
                               -- clock_out_no_session
  timestamp_utc TEXT NOT NULL,
  timezone_id   TEXT NOT NULL,
  local_date    TEXT NOT NULL,
  note          TEXT,
  source        TEXT NOT NULL, -- siri | app | web | import | automation
  device_id     TEXT,
  app_version   TEXT,
  metadata_json TEXT,
  created_at    TEXT NOT NULL
);

-- Derived, editable intervals of tracked time.
CREATE TABLE IF NOT EXISTS work_sessions (
  id                  TEXT PRIMARY KEY,
  user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  start_utc           TEXT NOT NULL,
  end_utc             TEXT,               -- NULL = open session
  start_timezone_id   TEXT NOT NULL,
  end_timezone_id     TEXT,
  duration_seconds    INTEGER,            -- cached; NULL while open
  note                TEXT,
  color               TEXT,               -- optional hex like #34C759; null = default
  status              TEXT NOT NULL DEFAULT 'open', -- open | closed | needs_review | deleted
  source              TEXT NOT NULL DEFAULT 'app',
  needs_review        INTEGER NOT NULL DEFAULT 0,
  validation_warnings TEXT,               -- JSON array of warning strings
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL,
  deleted_at          TEXT,
  updated_seq         INTEGER NOT NULL DEFAULT 0 -- monotonically increasing for sync
);

-- Full change log; edits never destroy prior values.
CREATE TABLE IF NOT EXISTS edit_history (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL, -- work_session | clock_event
  entity_id   TEXT NOT NULL,
  field_name  TEXT NOT NULL,
  old_value   TEXT,
  new_value   TEXT,
  edited_at   TEXT NOT NULL,
  edited_by   TEXT,          -- user id / "system"
  source      TEXT NOT NULL, -- app | web | siri | system
  reason      TEXT
);

-- Idempotency records prevent duplicate Siri actions from creating duplicate data.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key          TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL,
  response_json TEXT NOT NULL,
  created_at   TEXT NOT NULL
);

-- Monotonic sequence source shared across sessions for the sync cursor.
CREATE TABLE IF NOT EXISTS sync_counter (
  id  INTEGER PRIMARY KEY CHECK (id = 1),
  seq INTEGER NOT NULL
);
INSERT OR IGNORE INTO sync_counter (id, seq) VALUES (1, 0);

CREATE INDEX IF NOT EXISTS idx_sessions_user_start ON work_sessions(user_id, start_utc);
CREATE INDEX IF NOT EXISTS idx_sessions_user_seq   ON work_sessions(user_id, updated_seq);
CREATE INDEX IF NOT EXISTS idx_events_user_ts       ON clock_events(user_id, timestamp_utc);
CREATE INDEX IF NOT EXISTS idx_history_entity       ON edit_history(entity_type, entity_id);
`);

// Lightweight migrations for columns added after a table already exists on a
// deployed volume (CREATE TABLE IF NOT EXISTS won't add new columns).
function ensureColumn(table, column, definition) {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all();
  if (!cols.some((c) => c.name === column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}
ensureColumn('work_sessions', 'color', 'TEXT');

export function nextSeq() {
  const row = db.prepare('UPDATE sync_counter SET seq = seq + 1 WHERE id = 1 RETURNING seq').get();
  return row.seq;
}

export default db;
