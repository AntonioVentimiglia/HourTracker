import jwt from 'jsonwebtoken';
import db from '../db/schema.js';

export const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me';

export function signToken(user) {
  return jwt.sign({ sub: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });
}

export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Missing bearer token' });
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    // A signature-valid token can still reference a user that no longer
    // exists (e.g. the dev seed script deletes and recreates the demo user
    // with a fresh id on every run) — writes would otherwise fail deep in a
    // foreign-key constraint instead of a clear auth error.
    const user = db.prepare('SELECT id FROM users WHERE id = ?').get(payload.sub);
    if (!user) return res.status(401).json({ error: 'User no longer exists. Please log in again.' });
    req.userId = payload.sub;
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}
