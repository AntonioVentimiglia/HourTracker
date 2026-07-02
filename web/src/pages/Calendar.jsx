import React, { useEffect, useMemo, useState } from 'react';
import { api } from '../api/client.js';
import { fmtDuration, fmtTime, isoDate, startOfWeek, addDays, liveDuration } from '../utils/format.js';
import SessionModal from '../components/SessionModal.jsx';

export default function Calendar({ user, refreshKey, onDataChanged }) {
  const [anchor, setAnchor] = useState(new Date());
  const [sessions, setSessions] = useState([]);
  const [weekly, setWeekly] = useState(null);
  const [editing, setEditing] = useState(undefined); // undefined = closed, null = new, obj = edit

  const weekStart = useMemo(() => startOfWeek(anchor, user.weekStartsOn ?? 0), [anchor, user]);
  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => addDays(weekStart, i)), [weekStart]);

  async function load() {
    const start = weekStart.toISOString();
    const end = addDays(weekStart, 7).toISOString();
    const [{ sessions }, wk] = await Promise.all([
      api.sessions(start, end),
      api.weekly(isoDate(weekStart)),
    ]);
    setSessions(sessions);
    setWeekly(wk);
  }

  useEffect(() => { load(); }, [weekStart, refreshKey]);

  function byDay(day) {
    return sessions.filter((s) => new Date(s.startUtc).toDateString() === day.toDateString());
  }
  function dayTotal(day) {
    return byDay(day).reduce((sum, s) => sum + liveDuration(s), 0);
  }

  const today = new Date().toDateString();

  return (
    <div>
      <div className="periodnav">
        <button className="arrow" onClick={() => setAnchor(addDays(anchor, -7))}>‹</button>
        <h2>{weekStart.toLocaleDateString([], { month: 'short', day: 'numeric' })} – {addDays(weekStart, 6).toLocaleDateString([], { month: 'short', day: 'numeric' })}</h2>
        <button className="arrow" onClick={() => setAnchor(addDays(anchor, 7))}>›</button>
        <span className="total">Week: {weekly?.totalHuman ?? '0m'}</span>
        <button className="btn" onClick={() => setEditing(null)}>+ Session</button>
      </div>

      <div className="ledger">
        {days.map((day) => {
          const list = byDay(day);
          return (
            <div className={`row ${day.toDateString() === today ? 'today' : ''}`} key={day.toISOString()}>
              <div className="daycell">
                <span className="dow">{day.toLocaleDateString([], { weekday: 'short' })}</span>
                <span className="dnum">{day.getDate()}</span>
              </div>
              <div className="blocks">
                {list.length === 0 && <span className="hint" style={{ padding: '4px 0' }}>—</span>}
                {list.map((s) => (
                  <div className={`block ${!s.endUtc ? 'live' : ''}`} key={s.id} onClick={() => setEditing(s)}>
                    <div className="bar" />
                    <div>
                      <div className="times">
                        {fmtTime(s.startUtc)} – {s.endUtc ? fmtTime(s.endUtc) : 'Now'}
                        {!s.endUtc && <span className="badge"> ● ACTIVE</span>}
                      </div>
                      {s.note && <div className="note">{s.note}</div>}
                      {s.validationWarnings?.length > 0 && (
                        <div className="warn">⚠ {s.validationWarnings.join(', ')}</div>
                      )}
                    </div>
                    <div className="dur">{fmtDuration(liveDuration(s))}</div>
                  </div>
                ))}
              </div>
              <div className="daytotal">{dayTotal(day) > 0 ? fmtDuration(dayTotal(day)) : ''}</div>
            </div>
          );
        })}
      </div>

      {editing !== undefined && (
        <SessionModal
          session={editing}
          onClose={() => setEditing(undefined)}
          onSaved={() => { setEditing(undefined); load(); onDataChanged(); }}
        />
      )}
    </div>
  );
}
