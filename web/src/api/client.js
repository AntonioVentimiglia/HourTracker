const tokenKey = 'wh_token';

export function getToken() { return localStorage.getItem(tokenKey); }
export function setToken(t) { t ? localStorage.setItem(tokenKey, t) : localStorage.removeItem(tokenKey); }

async function req(path, { method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `Request failed (${res.status})`);
  }
  const ct = res.headers.get('content-type') || '';
  return ct.includes('application/json') ? res.json() : res.text();
}

export const api = {
  login: (email, password) => req('/auth/login', { method: 'POST', body: { email, password } }),
  register: (email, password, displayName) =>
    req('/auth/register', { method: 'POST', body: { email, password, displayName, timezonePreference: Intl.DateTimeFormat().resolvedOptions().timeZone } }),
  me: () => req('/auth/me'),

  clockState: () => req('/clock/state'),
  clockIn: (note) => req('/clock/in', { method: 'POST', body: { note, source: 'web', timezoneId: tz(), idempotencyKey: uuid() } }),
  clockOut: (note) => req('/clock/out', { method: 'POST', body: { note, source: 'web', timezoneId: tz(), idempotencyKey: uuid() } }),

  sessions: (start, end) => req(`/sessions?start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`),
  createSession: (b) => req('/sessions', { method: 'POST', body: { ...b, source: 'web', timezoneId: tz() } }),
  updateSession: (id, changes) => req(`/sessions/${id}`, { method: 'PATCH', body: { changes, source: 'web' } }),
  deleteSession: (id) => req(`/sessions/${id}`, { method: 'DELETE' }),
  restoreSession: (id) => req(`/sessions/${id}/restore`, { method: 'POST', body: { source: 'web' } }),
  history: (id) => req(`/sessions/${id}/history`),

  events: (start, end) => req(`/events?start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`),

  weekly: (weekStart) => req(`/summaries/weekly?weekStart=${weekStart}`),
  daily: (date) => req(`/summaries/daily?date=${date}`),
  monthly: (month) => req(`/summaries/monthly?month=${month}`),

  csvUrl: (start, end) => `/export/csv?start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`,
};

function tz() { return Intl.DateTimeFormat().resolvedOptions().timeZone; }
function uuid() {
  return crypto.randomUUID ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0; return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
      });
}
