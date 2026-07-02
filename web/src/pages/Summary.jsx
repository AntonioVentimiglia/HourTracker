import React, { useEffect, useState } from 'react';
import { api } from '../api/client.js';
import { fmtTime, isoDate, startOfWeek } from '../utils/format.js';

export default function Summary({ user, refreshKey }) {
  const [scope, setScope] = useState('week');
  const [daily, setDaily] = useState(null);
  const [weekly, setWeekly] = useState(null);

  async function load() {
    const now = new Date();
    if (scope === 'day') setDaily(await api.daily(isoDate(now)));
    else setWeekly(await api.weekly(isoDate(startOfWeek(now, user.weekStartsOn ?? 0))));
  }
  useEffect(() => { load(); }, [scope, refreshKey]);

  return (
    <div>
      <div className="periodnav">
        <h2>Summary</h2>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 4 }}>
          {['day', 'week'].map((s) => (
            <button key={s} className={`btn ${scope === s ? 'primary' : ''}`} onClick={() => setScope(s)}>{s}</button>
          ))}
        </div>
      </div>

      {scope === 'day' && daily && (
        <>
          <div className="statgrid">
            <Stat label="Total today" value={daily.allocatedHuman} accent />
            <Stat label="Sessions" value={daily.sessionCount} />
            <Stat label="First clock-in" value={daily.firstClockIn ? fmtTime(daily.firstClockIn) : '—'} />
            <Stat label="Last clock-out" value={daily.lastClockOut ? fmtTime(daily.lastClockOut) : '—'} />
          </div>
          {daily.openSessions > 0 && <p className="warn" style={{ color: 'var(--amber)' }}>⚠ An open session is still running.</p>}
          <Notes notes={daily.notes} />
        </>
      )}

      {scope === 'week' && weekly && (
        <>
          <div className="statgrid">
            <Stat label="Total this week" value={weekly.totalHuman} accent />
            <Stat label="Sessions" value={weekly.sessionCount} />
            <Stat label="Avg / active day" value={weekly.averagePerDayHuman} />
            <Stat label="Longest day" value={weekly.longestDay ? weekly.longestDay.human : '—'} />
          </div>
          <h3 style={{ fontFamily: 'var(--mono)', fontSize: 12, letterSpacing: '.08em', textTransform: 'uppercase', color: 'var(--muted)' }}>Daily breakdown</h3>
          {weekly.dailyBreakdown.map((d) => {
            const max = Math.max(1, ...weekly.dailyBreakdown.map((x) => x.seconds));
            return (
              <div className="bar-row" key={d.date}>
                <div className="bar-label"><span>{d.date}</span><span>{d.human}</span></div>
                <div className="bar-track"><div className="bar-fill" style={{ width: `${(d.seconds / max) * 100}%` }} /></div>
              </div>
            );
          })}
          <Notes notes={weekly.notes} />
        </>
      )}
    </div>
  );
}

function Stat({ label, value, accent }) {
  return (
    <div className="stat">
      <div className="label">{label}</div>
      <div className={`value ${accent ? 'accent' : ''}`}>{value}</div>
    </div>
  );
}

function Notes({ notes }) {
  if (!notes?.length) return null;
  return (
    <div className="stat" style={{ marginTop: 20 }}>
      <div className="label">Notes / tasks</div>
      <ul style={{ margin: '10px 0 0', paddingLeft: 18 }}>
        {notes.map((n, i) => <li key={i} style={{ marginBottom: 4 }}>{n}</li>)}
      </ul>
    </div>
  );
}
