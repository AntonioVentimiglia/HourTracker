import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { DateTime } from 'luxon';
import db from './schema.js';
import { clockIn, clockOut, createManualSession } from '../services/sessions.js';

const email = 'demo@example.com';
const zone = 'America/Los_Angeles';

db.prepare('DELETE FROM users WHERE email = ?').run(email);
const userId = uuid();
db.prepare(`INSERT INTO users (id, email, display_name, password_hash, timezone_preference, week_starts_on, created_at)
  VALUES (?, ?, ?, ?, ?, ?, ?)`).run(
  userId, email, 'Demo User', bcrypt.hashSync('password123', 10), zone, 0, DateTime.utc().toISO());

// A few days of sample sessions, including one crossing midnight.
const base = DateTime.now().setZone(zone).startOf('week');
const samples = [
  { day: 1, start: 9, end: 12.25, note: 'emails and standup' },
  { day: 1, start: 13, end: 17, note: 'client project build' },
  { day: 2, start: 8.5, end: 11, note: 'phone call with Alex' },
  { day: 2, start: 22, end: 26, note: 'late release deploy (crosses midnight)' }, // 10pm -> 2am
  { day: 3, start: 9, end: 15.5, note: 'writing report' },
];

for (const s of samples) {
  const start = base.plus({ days: s.day, hours: s.start });
  const end = base.plus({ days: s.day, hours: s.end });
  createManualSession({ userId, startUtc: start.toUTC().toISO(), endUtc: end.toUTC().toISO(),
                        timezoneId: zone, note: s.note, source: 'app' });
}

// Leave one open session to show the "active" state.
clockIn({ userId, timezoneId: zone, note: 'current task', source: 'siri' });

console.log('Seeded demo user:');
console.log('  email:    demo@example.com');
console.log('  password: password123');
