import { v4 as uuid } from 'uuid';
import db, { nextSeq } from '../db/schema.js';
import {
  durationSeconds, localDate, allocateAcrossDays,
  spokenDuration, spokenTime, DateTime,
} from './time.js';

const LONG_SESSION_HOURS = 12; // forgotten clock-out threshold

function nowIso() { return DateTime.utc().toISO(); }

function recordEvent({ userId, sessionId, type, timestampUtc, timezoneId, note,
                       source, deviceId, appVersion, metadata }) {
  const id = uuid();
  db.prepare(`
    INSERT INTO clock_events
      (id, user_id, session_id, type, timestamp_utc, timezone_id, local_date,
       note, source, device_id, app_version, metadata_json, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, userId, sessionId || null, type, timestampUtc, timezoneId,
         localDate(timestampUtc, timezoneId), note || null, source,
         deviceId || null, appVersion || null,
         metadata ? JSON.stringify(metadata) : null, nowIso());
  return id;
}

function logEdit({ userId, entityType, entityId, field, oldValue, newValue, source, reason }) {
  db.prepare(`
    INSERT INTO edit_history
      (id, user_id, entity_type, entity_id, field_name, old_value, new_value,
       edited_at, edited_by, source, reason)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(uuid(), userId, entityType, entityId, field,
         oldValue == null ? null : String(oldValue),
         newValue == null ? null : String(newValue),
         nowIso(), userId, source, reason || null);
}

export function getOpenSession(userId) {
  return db.prepare(
    `SELECT * FROM work_sessions WHERE user_id = ? AND status = 'open' AND deleted_at IS NULL
     ORDER BY start_utc DESC LIMIT 1`
  ).get(userId);
}

function computeWarnings(session) {
  const warnings = [];
  const start = DateTime.fromISO(session.start_utc, { zone: 'utc' });
  const end = session.end_utc ? DateTime.fromISO(session.end_utc, { zone: 'utc' }) : DateTime.utc();
  const hours = end.diff(start, 'hours').hours;
  if (!session.end_utc && hours >= LONG_SESSION_HOURS) warnings.push('open_too_long');
  if (session.end_utc && hours >= 16) warnings.push('very_long_session');
  if (session.end_utc && localDate(session.start_utc, session.start_timezone_id) !==
      localDate(session.end_utc, session.end_timezone_id || session.start_timezone_id)) {
    warnings.push('crosses_midnight');
  }
  return warnings;
}

// Takes ids and re-reads the raw DB row, because computeWarnings and the
// needs_review flag are keyed on snake_case columns — passing a serialized
// (camelCase) session here leaves those undefined and breaks the UPDATE bind.
function persistWarnings(userId, sessionId) {
  const row = getSessionRow(userId, sessionId);
  const warnings = computeWarnings(row);
  const needsReview = warnings.includes('open_too_long') ? 1 : row.needs_review;
  db.prepare(`UPDATE work_sessions SET validation_warnings = ?, needs_review = ? WHERE id = ?`)
    .run(JSON.stringify(warnings), needsReview, sessionId);
  return getSession(userId, sessionId);
}

// Duplicate clock-in is prevented by default: if already clocked in we do not
// create a second open session (brief §9.5).
export function clockIn({ userId, timestampUtc, timezoneId, note, source, deviceId, appVersion }) {
  timestampUtc = timestampUtc || nowIso();
  const open = getOpenSession(userId);
  if (open) {
    // Optionally append the note to the existing session.
    if (note) {
      const merged = open.note ? `${open.note}; ${note}` : note;
      logEdit({ userId, entityType: 'work_session', entityId: open.id, field: 'note',
                oldValue: open.note, newValue: merged, source, reason: 'note appended on duplicate clock-in' });
      db.prepare(`UPDATE work_sessions SET note = ?, updated_at = ?, updated_seq = ? WHERE id = ?`)
        .run(merged, nowIso(), nextSeq(), open.id);
      recordEvent({ userId, sessionId: open.id, type: 'note_added', timestampUtc, timezoneId, note, source, deviceId, appVersion });
    }
    return {
      status: 'already_clocked_in',
      session: getSession(userId, open.id),
      message: `You are already clocked in since ${spokenTime(open.start_utc, timezoneId)}.`,
    };
  }

  const id = uuid();
  const seq = nextSeq();
  db.prepare(`
    INSERT INTO work_sessions
      (id, user_id, start_utc, end_utc, start_timezone_id, note, status, source,
       created_at, updated_at, updated_seq)
    VALUES (?, ?, ?, NULL, ?, ?, 'open', ?, ?, ?, ?)
  `).run(id, userId, timestampUtc, timezoneId, note || null, source, nowIso(), nowIso(), seq);

  recordEvent({ userId, sessionId: id, type: 'clock_in', timestampUtc, timezoneId, note, source, deviceId, appVersion });

  return {
    status: 'clocked_in',
    session: getSession(userId, id),
    message: `Clocked in at ${spokenTime(timestampUtc, timezoneId)}${note ? ` for ${note}` : ''}.`,
  };
}

// Clock-out with no open session records an anomalous event and returns a clear
// message rather than creating a session (brief §9.6).
export function clockOut({ userId, timestampUtc, timezoneId, note, source, deviceId, appVersion }) {
  timestampUtc = timestampUtc || nowIso();
  const open = getOpenSession(userId);
  if (!open) {
    recordEvent({ userId, type: 'clock_out_no_session', timestampUtc, timezoneId, note, source, deviceId, appVersion });
    return { status: 'not_clocked_in', session: null, message: 'You are not currently clocked in.' };
  }

  const dur = durationSeconds(open.start_utc, timestampUtc);
  const mergedNote = note ? (open.note ? `${open.note}; ${note}` : note) : open.note;
  const seq = nextSeq();
  db.prepare(`
    UPDATE work_sessions
    SET end_utc = ?, end_timezone_id = ?, duration_seconds = ?, note = ?,
        status = 'closed', updated_at = ?, updated_seq = ?
    WHERE id = ?
  `).run(timestampUtc, timezoneId, dur, mergedNote, nowIso(), seq, open.id);

  recordEvent({ userId, sessionId: open.id, type: 'clock_out', timestampUtc, timezoneId, note, source, deviceId, appVersion });
  const session = persistWarnings(userId, open.id);

  return {
    status: 'clocked_out',
    session,
    message: `Clocked out. You worked ${spokenDuration(dur)}.`,
  };
}

export function addNote({ userId, note, timestampUtc, timezoneId, source, deviceId, appVersion }) {
  timestampUtc = timestampUtc || nowIso();
  const open = getOpenSession(userId);
  if (!open) {
    recordEvent({ userId, type: 'note_added', timestampUtc, timezoneId, note, source, deviceId, appVersion });
    return { status: 'no_open_session', message: "You're not clocked in, so I saved that as a standalone note." };
  }
  const merged = open.note ? `${open.note}; ${note}` : note;
  logEdit({ userId, entityType: 'work_session', entityId: open.id, field: 'note',
            oldValue: open.note, newValue: merged, source, reason: 'note added' });
  db.prepare(`UPDATE work_sessions SET note = ?, updated_at = ?, updated_seq = ? WHERE id = ?`)
    .run(merged, nowIso(), nextSeq(), open.id);
  recordEvent({ userId, sessionId: open.id, type: 'note_added', timestampUtc, timezoneId, note, source, deviceId, appVersion });
  return { status: 'note_added', session: getSession(userId, open.id), message: 'Note added.' };
}

export function createManualSession({ userId, startUtc, endUtc, timezoneId, note, color, source }) {
  const id = uuid();
  const dur = durationSeconds(startUtc, endUtc);
  const status = endUtc ? 'closed' : 'open';
  const seq = nextSeq();
  db.prepare(`
    INSERT INTO work_sessions
      (id, user_id, start_utc, end_utc, start_timezone_id, end_timezone_id,
       duration_seconds, note, color, status, source, created_at, updated_at, updated_seq)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(id, userId, startUtc, endUtc || null, timezoneId, endUtc ? timezoneId : null,
         dur, note || null, color || null, status, source || 'app', nowIso(), nowIso(), seq);
  recordEvent({ userId, sessionId: id, type: 'session_created', timestampUtc: startUtc, timezoneId, note, source: source || 'app' });
  return persistWarnings(userId, id);
}

const EDITABLE_FIELDS = { startUtc: 'start_utc', endUtc: 'end_utc', note: 'note', color: 'color', status: 'status' };

export function updateSession({ userId, sessionId, changes, source, reason }) {
  const existing = getSessionRow(userId, sessionId);
  if (!existing) return null;

  for (const [key, col] of Object.entries(EDITABLE_FIELDS)) {
    if (!(key in changes)) continue;
    const oldVal = existing[col];
    const newVal = changes[key];
    if (String(oldVal) === String(newVal)) continue;
    logEdit({ userId, entityType: 'work_session', entityId: sessionId, field: col,
              oldValue: oldVal, newValue: newVal, source: source || 'web', reason });
    db.prepare(`UPDATE work_sessions SET ${col} = ? WHERE id = ?`).run(newVal, sessionId);
  }

  const updated = getSessionRow(userId, sessionId);
  const dur = durationSeconds(updated.start_utc, updated.end_utc);
  const status = updated.end_utc ? (updated.status === 'open' ? 'closed' : updated.status) : 'open';
  db.prepare(`UPDATE work_sessions SET duration_seconds = ?, status = ?, updated_at = ?, updated_seq = ? WHERE id = ?`)
    .run(dur, status, nowIso(), nextSeq(), sessionId);
  recordEvent({ userId, sessionId, type: 'session_edited', timestampUtc: nowIso(),
                timezoneId: updated.start_timezone_id, source: source || 'web' });
  return persistWarnings(userId, sessionId);
}

export function deleteSession({ userId, sessionId, source }) {
  const existing = getSessionRow(userId, sessionId);
  if (!existing) return null;
  logEdit({ userId, entityType: 'work_session', entityId: sessionId, field: 'status',
            oldValue: existing.status, newValue: 'deleted', source: source || 'web', reason: 'deleted' });
  db.prepare(`UPDATE work_sessions SET status = 'deleted', deleted_at = ?, updated_at = ?, updated_seq = ? WHERE id = ?`)
    .run(nowIso(), nowIso(), nextSeq(), sessionId);
  recordEvent({ userId, sessionId, type: 'session_deleted', timestampUtc: nowIso(),
                timezoneId: existing.start_timezone_id, source: source || 'web' });
  return true;
}

export function restoreSession({ userId, sessionId, source }) {
  const existing = getSessionRow(userId, sessionId);
  if (!existing) return null;
  const status = existing.end_utc ? 'closed' : 'open';
  logEdit({ userId, entityType: 'work_session', entityId: sessionId, field: 'status',
            oldValue: 'deleted', newValue: status, source: source || 'web', reason: 'restored' });
  db.prepare(`UPDATE work_sessions SET status = ?, deleted_at = NULL, updated_at = ?, updated_seq = ? WHERE id = ?`)
    .run(status, nowIso(), nextSeq(), sessionId);
  recordEvent({ userId, sessionId, type: 'session_restored', timestampUtc: nowIso(),
                timezoneId: existing.start_timezone_id, source: source || 'web' });
  return getSession(userId, sessionId);
}

function getSessionRow(userId, sessionId) {
  return db.prepare(`SELECT * FROM work_sessions WHERE user_id = ? AND id = ?`).get(userId, sessionId);
}

export function getSession(userId, sessionId) {
  const row = getSessionRow(userId, sessionId);
  return row ? serializeSession(row) : null;
}

export function listSessions({ userId, startUtc, endUtc, includeDeleted }) {
  let sql = `SELECT * FROM work_sessions WHERE user_id = ?`;
  const args = [userId];
  if (startUtc) { sql += ` AND (end_utc IS NULL OR end_utc >= ?)`; args.push(startUtc); }
  if (endUtc)   { sql += ` AND start_utc < ?`; args.push(endUtc); }
  if (!includeDeleted) sql += ` AND status != 'deleted'`;
  sql += ` ORDER BY start_utc DESC`;
  return db.prepare(sql).all(...args).map(serializeSession);
}

export function listEvents({ userId, startUtc, endUtc }) {
  let sql = `SELECT * FROM clock_events WHERE user_id = ?`;
  const args = [userId];
  if (startUtc) { sql += ` AND timestamp_utc >= ?`; args.push(startUtc); }
  if (endUtc)   { sql += ` AND timestamp_utc < ?`; args.push(endUtc); }
  sql += ` ORDER BY timestamp_utc DESC`;
  return db.prepare(sql).all(...args).map(serializeEvent);
}

export function getHistory({ userId, entityType, entityId }) {
  return db.prepare(
    `SELECT * FROM edit_history WHERE user_id = ? AND entity_type = ? AND entity_id = ? ORDER BY edited_at ASC`
  ).all(userId, entityType, entityId);
}

function serializeSession(row) {
  return {
    id: row.id,
    userId: row.user_id,
    startUtc: row.start_utc,
    endUtc: row.end_utc,
    startTimezoneId: row.start_timezone_id,
    endTimezoneId: row.end_timezone_id,
    durationSeconds: row.duration_seconds ??
      (row.status === 'open' ? durationSeconds(row.start_utc, nowIso()) : null),
    note: row.note,
    color: row.color,
    status: row.status,
    source: row.source,
    needsReview: !!row.needs_review,
    validationWarnings: row.validation_warnings ? JSON.parse(row.validation_warnings) : [],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    updatedSeq: row.updated_seq,
  };
}

function serializeEvent(row) {
  return {
    id: row.id,
    userId: row.user_id,
    sessionId: row.session_id,
    type: row.type,
    timestampUtc: row.timestamp_utc,
    timezoneId: row.timezone_id,
    localDate: row.local_date,
    note: row.note,
    source: row.source,
    deviceId: row.device_id,
    appVersion: row.app_version,
    metadata: row.metadata_json ? JSON.parse(row.metadata_json) : null,
    createdAt: row.created_at,
  };
}

export { allocateAcrossDays, serializeSession };
