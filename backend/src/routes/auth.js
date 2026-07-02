import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { DateTime } from 'luxon';
import db from '../db/schema.js';
import { signToken, requireAuth } from '../middleware/auth.js';

const router = Router();

router.post('/register', (req, res) => {
  const { email, password, displayName, timezonePreference, weekStartsOn } = req.body || {};
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });
  const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email.toLowerCase());
  if (existing) return res.status(409).json({ error: 'email already registered' });

  const user = {
    id: uuid(),
    email: email.toLowerCase(),
    display_name: displayName || '',
    password_hash: bcrypt.hashSync(password, 10),
    timezone_preference: timezonePreference || 'America/Los_Angeles',
    week_starts_on: weekStartsOn ?? 0,
    created_at: DateTime.utc().toISO(),
  };
  db.prepare(`INSERT INTO users
    (id, email, display_name, password_hash, timezone_preference, week_starts_on, created_at)
    VALUES (@id, @email, @display_name, @password_hash, @timezone_preference, @week_starts_on, @created_at)`
  ).run(user);
  res.json({ token: signToken(user), user: publicUser(user) });
});

router.post('/login', (req, res) => {
  const { email, password } = req.body || {};
  const row = db.prepare('SELECT * FROM users WHERE email = ?').get((email || '').toLowerCase());
  if (!row || !bcrypt.compareSync(password || '', row.password_hash)) {
    return res.status(401).json({ error: 'invalid credentials' });
  }
  res.json({ token: signToken(row), user: publicUser(row) });
});

router.get('/me', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM users WHERE id = ?').get(req.userId);
  if (!row) return res.status(404).json({ error: 'user not found' });
  res.json({ user: publicUser(row) });
});

function publicUser(row) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    timezonePreference: row.timezone_preference,
    weekStartsOn: row.week_starts_on,
    createdAt: row.created_at,
  };
}

export default router;
