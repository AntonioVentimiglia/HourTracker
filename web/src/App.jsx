import React, { useEffect, useState, useCallback } from 'react';
import { api, getToken, setToken } from './api/client.js';
import Login from './pages/Login.jsx';
import Calendar from './pages/Calendar.jsx';
import Summary from './pages/Summary.jsx';
import RawData from './pages/RawData.jsx';
import ClockStrip from './components/ClockStrip.jsx';

const TABS = [
  ['calendar', 'Calendar'],
  ['summary', 'Summary'],
  ['raw', 'Raw Data'],
];

export default function App() {
  const [user, setUser] = useState(null);
  const [ready, setReady] = useState(false);
  const [tab, setTab] = useState('calendar');
  const [openSession, setOpenSession] = useState(null);
  const [refreshKey, setRefreshKey] = useState(0);

  // Resolve any stored token into a live session on first load.
  useEffect(() => {
    (async () => {
      if (!getToken()) { setReady(true); return; }
      try {
        const { user } = await api.me();
        setUser(user);
      } catch {
        setToken(null);
      } finally {
        setReady(true);
      }
    })();
  }, []);

  const refreshClock = useCallback(async () => {
    try {
      const { session } = await api.clockState();
      setOpenSession(session || null);
    } catch {
      setOpenSession(null);
    }
  }, []);

  useEffect(() => {
    if (user) refreshClock();
  }, [user, refreshClock]);

  // A single knob children call after any data change, so the clock strip
  // and whichever page is mounted both re-pull from the server.
  const onDataChanged = useCallback(() => {
    refreshClock();
    setRefreshKey((k) => k + 1);
  }, [refreshClock]);

  function logout() {
    setToken(null);
    setUser(null);
    setOpenSession(null);
  }

  if (!ready) return null;

  if (!user) {
    return (
      <div className="auth-wrap">
        <div className="wordmark">WORK<span className="tick">·</span>HOURS</div>
        <div className="auth-card">
          <Login onAuthed={(u) => { setUser(u); }} />
        </div>
        <p className="hint">Demo login is pre-filled — sign in to explore seeded data.</p>
      </div>
    );
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="wordmark">WORK<span className="tick">·</span>HOURS</div>
        <nav>
          {TABS.map(([id, label]) => (
            <button key={id} className={tab === id ? 'active' : ''} onClick={() => setTab(id)}>
              {label}
            </button>
          ))}
        </nav>
        <div className="user">
          {user.displayName || user.email}
          <button className="btn ghost" onClick={logout}>Log out</button>
        </div>
      </header>

      <ClockStrip openSession={openSession} onChange={onDataChanged} />

      <main className="content">
        {tab === 'calendar' && <Calendar user={user} refreshKey={refreshKey} onDataChanged={onDataChanged} />}
        {tab === 'summary' && <Summary user={user} refreshKey={refreshKey} onDataChanged={onDataChanged} />}
        {tab === 'raw' && <RawData user={user} refreshKey={refreshKey} onDataChanged={onDataChanged} />}
      </main>
    </div>
  );
}
