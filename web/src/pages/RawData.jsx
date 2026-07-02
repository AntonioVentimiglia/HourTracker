import React, { useEffect, useMemo, useState } from 'react';
import { api, getToken } from '../api/client.js';
import { fmtDuration, fmtDate, fmtTime, startOfWeek, addDays, isoDate, liveDuration } from '../utils/format.js';

export default function RawData({ user, refreshKey, onDataChanged }) {
  const [view, setView] = useState('sessions'); // 'sessions' | 'events'
  const [anchor, setAnchor] = useState(new Date());
  const [sessions, setSessions] = useState([]);
  const [events, setEvents] = useState([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');

  const weekStart = useMemo(() => startOfWeek(anchor, user.weekStartsOn ?? 0), [anchor, user]);
  const start = weekStart.toISOString();
  const end = addDays(weekStart, 7).toISOString();

  async function load() {
    setErr('');
    try {
      const [{ sessions }, { events }] = await Promise.all([
        api.sessions(start, end),
        api.events(start, end),
      ]);
      setSessions(sessions);
      setEvents(events);
    } catch (e) {
      setErr(e.message);
    }
  }

  useEffect(() => { load(); }, [weekStart, refreshKey]);

  async function onDelete(s) {
    if (!confirm('Delete this session? It can be restored from the audit log.')) return;
    setBusy(true);
    try { await api.deleteSession(s.id); await load(); onDataChanged(); }
    catch (e) { setErr(e.message); }
    finally { setBusy(false); }
  }

  async function onRestore(s) {
    setBusy(true);
    try { await api.restoreSession(s.id); await load(); onDataChanged(); }
    catch (e) { setErr(e.message); }
    finally { setBusy(false); }
  }

  function downloadCsv() {
    // Fetch with auth then trigger a blob download (endpoint requires Bearer token).
    fetch(api.csvUrl(start, end), { headers: { Authorization: `Bearer ${getToken()}` } })
      .then((r) => r.ok ? r.blob() : r.text().then((t) => Promise.reject(new Error(t))))
      .then((blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `work-hours_${isoDate(weekStart)}.csv`;
        a.click();
        URL.revokeObjectURL(url);
      })
      .catch((e) => setErr(e.message));
  }

  return (
    <div>
      <div className="periodnav">
        <button className="arrow" onClick={() => setAnchor(addDays(anchor, -7))}>‹</button>
        <h2>{weekStart.toLocaleDateString([], { month: 'short', day: 'numeric' })} – {addDays(weekStart, 6).toLocaleDateString([], { month: 'short', day: 'numeric' })}</h2>
        <button className="arrow" onClick={() => setAnchor(addDays(anchor, 7))}>›</button>
        <div className="seg" style={{ marginLeft: 'auto' }}>
          <button className={view === 'sessions' ? 'active' : ''} onClick={() => setView('sessions')}>Sessions</button>
          <button className={view === 'events' ? 'active' : ''} onClick={() => setView('events')}>Events</button>
        </div>
        <button className="btn ghost" onClick={downloadCsv}>Export CSV</button>
      </div>

      {err && <div className="warn" style={{ marginBottom: 12 }}>⚠ {err}</div>}

      {view === 'sessions' ? (
        <table className="data">
          <thead>
            <tr>
              <th>Date</th><th>Start</th><th>End</th><th>Duration</th>
              <th>Status</th><th>Source</th><th>Note</th><th></th>
            </tr>
          </thead>
          <tbody>
            {sessions.length === 0 && (
              <tr><td colSpan={8} className="hint">No sessions this week.</td></tr>
            )}
            {sessions.map((s) => {
              const status = s.deletedAt ? 'deleted'
                : !s.endUtc ? (s.needsReview ? 'needs_review' : 'open')
                : (s.needsReview ? 'needs_review' : 'closed');
              return (
                <tr key={s.id} style={s.deletedAt ? { opacity: 0.55 } : undefined}>
                  <td className="mono">{fmtDate(s.startUtc)}</td>
                  <td className="mono">{fmtTime(s.startUtc)}</td>
                  <td className="mono">{s.endUtc ? fmtTime(s.endUtc) : '—'}</td>
                  <td className="mono">{fmtDuration(liveDuration(s))}</td>
                  <td><span className={`pill ${status}`}>{status.replace('_', ' ')}</span></td>
                  <td className="mono">{s.source}</td>
                  <td>{s.note || <span className="hint">—</span>}</td>
                  <td>
                    {s.deletedAt
                      ? <button className="link" disabled={busy} onClick={() => onRestore(s)}>Restore</button>
                      : <button className="link danger" disabled={busy} onClick={() => onDelete(s)}>Delete</button>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      ) : (
        <table className="data">
          <thead>
            <tr><th>Time</th><th>Type</th><th>Source</th><th>Note</th><th>Idempotency Key</th></tr>
          </thead>
          <tbody>
            {events.length === 0 && (
              <tr><td colSpan={5} className="hint">No clock events this week.</td></tr>
            )}
            {events.map((e) => (
              <tr key={e.id}>
                <td className="mono">{fmtDate(e.occurredUtc)} {fmtTime(e.occurredUtc)}</td>
                <td><span className={`pill ${e.type === 'clock_in' ? 'open' : 'closed'}`}>{e.type.replace('_', ' ')}</span></td>
                <td className="mono">{e.source}</td>
                <td>{e.note || <span className="hint">—</span>}</td>
                <td className="mono hint" style={{ fontSize: 11 }}>{e.idempotencyKey || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
