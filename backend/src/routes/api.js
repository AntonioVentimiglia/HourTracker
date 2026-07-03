import { Router } from 'express';
import db from '../db/schema.js';
import { requireAuth } from '../middleware/auth.js';
import * as S from '../services/sessions.js';
import * as Sum from '../services/summaries.js';
import { billSessions } from '../services/billing.js';
import { humanDuration } from '../services/time.js';
import { DateTime } from 'luxon';

const router = Router();
router.use(requireAuth);

function userZone(userId) {
  const row = db.prepare('SELECT timezone_preference, week_starts_on FROM users WHERE id = ?').get(userId);
  return { zone: row?.timezone_preference || 'America/Los_Angeles', weekStartsOn: row?.week_starts_on ?? 0 };
}

// Idempotency guard so a Siri action retried offline doesn't double-write.
function withIdempotency(userId, key, produce) {
  if (!key) return produce();
  const existing = db.prepare('SELECT response_json FROM idempotency_keys WHERE key = ? AND user_id = ?').get(key, userId);
  if (existing) return JSON.parse(existing.response_json);
  const result = produce();
  db.prepare('INSERT INTO idempotency_keys (key, user_id, response_json, created_at) VALUES (?, ?, ?, ?)')
    .run(key, userId, JSON.stringify(result), DateTime.utc().toISO());
  return result;
}

// ---- Clock actions ----
router.post('/clock/in', (req, res) => {
  const { timestampUtc, timezoneId, note, source, deviceId, appVersion, idempotencyKey } = req.body || {};
  const { zone } = userZone(req.userId);
  const result = withIdempotency(req.userId, idempotencyKey, () =>
    S.clockIn({ userId: req.userId, timestampUtc, timezoneId: timezoneId || zone, note, source: source || 'app', deviceId, appVersion }));
  res.json(result);
});

router.post('/clock/out', (req, res) => {
  const { timestampUtc, timezoneId, note, source, deviceId, appVersion, idempotencyKey } = req.body || {};
  const { zone } = userZone(req.userId);
  const result = withIdempotency(req.userId, idempotencyKey, () =>
    S.clockOut({ userId: req.userId, timestampUtc, timezoneId: timezoneId || zone, note, source: source || 'app', deviceId, appVersion }));
  res.json(result);
});

router.post('/clock/note', (req, res) => {
  const { note, timestampUtc, timezoneId, source, deviceId, appVersion } = req.body || {};
  const { zone } = userZone(req.userId);
  if (!note) return res.status(400).json({ error: 'note required' });
  res.json(S.addNote({ userId: req.userId, note, timestampUtc, timezoneId: timezoneId || zone, source: source || 'app', deviceId, appVersion }));
});

router.get('/clock/state', (req, res) => {
  const open = S.getOpenSession(req.userId);
  res.json({ clockedIn: !!open, session: open ? S.getSession(req.userId, open.id) : null });
});

// ---- Sessions ----
router.get('/sessions', (req, res) => {
  const { start, end } = req.query;
  res.json({ sessions: S.listSessions({ userId: req.userId, startUtc: start, endUtc: end }) });
});

router.post('/sessions', (req, res) => {
  const { startUtc, endUtc, timezoneId, note, source } = req.body || {};
  const { zone } = userZone(req.userId);
  if (!startUtc) return res.status(400).json({ error: 'startUtc required' });
  res.json({ session: S.createManualSession({ userId: req.userId, startUtc, endUtc, timezoneId: timezoneId || zone, note, source: source || 'app' }) });
});

router.get('/sessions/:id', (req, res) => {
  const session = S.getSession(req.userId, req.params.id);
  if (!session) return res.status(404).json({ error: 'not found' });
  res.json({ session });
});

router.patch('/sessions/:id', (req, res) => {
  const { changes, source, reason } = req.body || {};
  const session = S.updateSession({ userId: req.userId, sessionId: req.params.id, changes: changes || req.body, source, reason });
  if (!session) return res.status(404).json({ error: 'not found' });
  res.json({ session });
});

router.delete('/sessions/:id', (req, res) => {
  const ok = S.deleteSession({ userId: req.userId, sessionId: req.params.id, source: req.query.source });
  if (!ok) return res.status(404).json({ error: 'not found' });
  res.json({ status: 'deleted' });
});

router.post('/sessions/:id/restore', (req, res) => {
  const session = S.restoreSession({ userId: req.userId, sessionId: req.params.id, source: req.body?.source });
  if (!session) return res.status(404).json({ error: 'not found' });
  res.json({ session });
});

// ---- Raw events ----
router.get('/events', (req, res) => {
  const { start, end } = req.query;
  res.json({ events: S.listEvents({ userId: req.userId, startUtc: start, endUtc: end }) });
});

router.get('/sessions/:id/history', (req, res) => {
  res.json({ history: S.getHistory({ userId: req.userId, entityType: 'work_session', entityId: req.params.id }) });
});

// ---- Summaries ----
router.get('/summaries/daily', (req, res) => {
  const { zone } = userZone(req.userId);
  const date = req.query.date || DateTime.now().setZone(zone).toISODate();
  res.json(Sum.dailySummary(req.userId, date, zone));
});

router.get('/summaries/weekly', (req, res) => {
  const { zone, weekStartsOn } = userZone(req.userId);
  const weekStart = req.query.weekStart || DateTime.now().setZone(zone).toISODate();
  res.json(Sum.weeklySummary(req.userId, weekStart, zone, weekStartsOn));
});

router.get('/summaries/monthly', (req, res) => {
  const { zone } = userZone(req.userId);
  const month = req.query.month || DateTime.now().setZone(zone).toFormat('yyyy-LL');
  res.json(Sum.monthlySummary(req.userId, month, zone));
});

// ---- Billing blocks (for the calendar) ----
router.get('/billing/blocks', (req, res) => {
  const { zone } = userZone(req.userId);
  const { start, end } = req.query;
  const sessions = S.listSessions({ userId: req.userId, startUtc: start, endUtc: end });
  const bill = billSessions(sessions, zone);
  res.json({
    blocks: bill.blocks,
    billedSeconds: bill.billedSeconds,
    billedHuman: humanDuration(bill.billedSeconds),
    rawSeconds: bill.rawSeconds,
    rawHuman: humanDuration(bill.rawSeconds),
    billedByDay: bill.billedByDay,
  });
});

// ---- Export ----
router.get('/export/csv', (req, res) => {
  const { zone } = userZone(req.userId);
  const { start, end } = req.query;
  const sessions = S.listSessions({ userId: req.userId, startUtc: start, endUtc: end });
  res.setHeader('Content-Type', 'text/csv');
  res.setHeader('Content-Disposition', 'attachment; filename="work-hours.csv"');
  res.send(Sum.csvExport(sessions, zone));
});

// ---- Sync ----
// Pull everything changed since a cursor (updated_seq). Offline clients send
// their queued clock actions to the clock endpoints with idempotency keys.
router.get('/sync/pull', (req, res) => {
  const since = parseInt(req.query.since || '0', 10);
  const rows = db.prepare(
    `SELECT * FROM work_sessions WHERE user_id = ? AND updated_seq > ? ORDER BY updated_seq ASC`
  ).all(req.userId, since);
  const sessions = rows.map((r) => S.getSession(req.userId, r.id));
  const cursor = rows.length ? rows[rows.length - 1].updated_seq : since;
  res.json({ sessions, cursor });
});

router.post('/sync/push', (req, res) => {
  // Accepts a batch of queued clock actions from an offline client.
  const { actions } = req.body || {};
  const { zone } = userZone(req.userId);
  const results = [];
  for (const a of actions || []) {
    const common = { userId: req.userId, timezoneId: a.timezoneId || zone, note: a.note,
                     source: a.source || 'siri', deviceId: a.deviceId, appVersion: a.appVersion, timestampUtc: a.timestampUtc };
    const run = () => {
      if (a.type === 'clock_in') return S.clockIn(common);
      if (a.type === 'clock_out') return S.clockOut(common);
      if (a.type === 'note') return S.addNote(common);
      return { status: 'unknown_action' };
    };
    results.push(withIdempotency(req.userId, a.idempotencyKey, run));
  }
  res.json({ results });
});

export default router;
