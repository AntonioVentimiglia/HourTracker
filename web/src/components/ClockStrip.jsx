import React, { useEffect, useState } from 'react';
import { api } from '../api/client.js';
import { fmtTime, fmtDuration, liveDuration } from '../utils/format.js';

export default function ClockStrip({ openSession, onChange }) {
  const [note, setNote] = useState('');
  const [, forceTick] = useState(0);

  // Live-update the running duration each second while clocked in.
  useEffect(() => {
    if (!openSession) return;
    const t = setInterval(() => forceTick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, [openSession]);

  async function clockIn() {
    await api.clockIn(note || null);
    setNote('');
    onChange();
  }
  async function clockOut() {
    await api.clockOut(null);
    onChange();
  }

  const live = !!openSession;
  return (
    <div className="clockstrip">
      <div>
        <div className="state-label">{live ? 'Clocked in' : 'Not clocked in'}</div>
        <div className={`big-time ${live ? 'live' : ''}`}>
          {live ? fmtDuration(liveDuration(openSession)) : '0h 0m'}
        </div>
        {live && (
          <div className="note-line">
            since {fmtTime(openSession.startUtc)}{openSession.note ? ` · ${openSession.note}` : ''}
          </div>
        )}
      </div>
      <div />
      {live ? (
        <button className="btn on-dark" onClick={clockOut}>Clock out</button>
      ) : (
        <form onSubmit={(e) => { e.preventDefault(); clockIn(); }}>
          <input placeholder="Working on…" value={note} onChange={(e) => setNote(e.target.value)} />
          <button className="btn primary" type="submit">Clock in</button>
        </form>
      )}
    </div>
  );
}
