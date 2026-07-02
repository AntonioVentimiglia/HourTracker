import React, { useState } from 'react';
import { api } from '../api/client.js';

// Converts a UTC ISO string to a value usable by <input type="datetime-local">.
function toLocalInput(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
function toUtc(localValue) {
  return localValue ? new Date(localValue).toISOString() : null;
}

export default function SessionModal({ session, onClose, onSaved }) {
  const isNew = !session;
  const [start, setStart] = useState(toLocalInput(session?.startUtc) || toLocalInput(new Date(Date.now() - 3600e3).toISOString()));
  const [end, setEnd] = useState(toLocalInput(session?.endUtc) || toLocalInput(new Date().toISOString()));
  const [hasEnd, setHasEnd] = useState(session ? !!session.endUtc : true);
  const [note, setNote] = useState(session?.note || '');
  const [busy, setBusy] = useState(false);

  const invalid = hasEnd && end && start && new Date(end) <= new Date(start);

  async function save() {
    if (invalid) return;
    setBusy(true);
    try {
      if (isNew) {
        await api.createSession({ startUtc: toUtc(start), endUtc: hasEnd ? toUtc(end) : null, note });
      } else {
        const changes = { startUtc: toUtc(start), note };
        if (hasEnd) changes.endUtc = toUtc(end);
        await api.updateSession(session.id, changes);
      }
      onSaved();
    } finally { setBusy(false); }
  }

  async function remove() {
    setBusy(true);
    try { await api.deleteSession(session.id); onSaved(); }
    finally { setBusy(false); }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{isNew ? 'New session' : 'Edit session'}</h3>
        <label>Start</label>
        <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
        <label style={{ display: 'flex', gap: 8, alignItems: 'center', textTransform: 'none' }}>
          <input type="checkbox" style={{ width: 'auto', margin: 0 }} checked={hasEnd} onChange={(e) => setHasEnd(e.target.checked)} />
          Has end time
        </label>
        {hasEnd && (
          <>
            <label>End</label>
            <input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} />
          </>
        )}
        <label>Note</label>
        <textarea rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="What were you working on?" />
        {invalid && <div className="err" style={{ marginBottom: 12 }}>End must be after start.</div>}
        <div className="actions">
          {!isNew && <button className="btn danger" onClick={remove} disabled={busy}>Delete</button>}
          <button className="btn" onClick={onClose}>Cancel</button>
          <button className="btn primary" onClick={save} disabled={busy || invalid}>Save</button>
        </div>
      </div>
    </div>
  );
}
