import React, { useState } from 'react';
import { api, setToken } from '../api/client.js';

export default function Login({ onAuthed }) {
  const [registering, setRegistering] = useState(false);
  const [email, setEmail] = useState('demo@example.com');
  const [password, setPassword] = useState('password123');
  const [name, setName] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setErr('');
    try {
      const res = registering
        ? await api.register(email, password, name)
        : await api.login(email, password);
      setToken(res.token);
      onAuthed(res.user);
    } catch {
      setErr(registering ? 'Sign up failed. That email may already be registered.'
                         : 'Login failed. Check your details and that the server is running.');
    } finally { setBusy(false); }
  }

  return (
    <div className="auth-wrap">
      <div className="wordmark">WORK<span className="tick">·</span>HOURS</div>
      <p className="hint">The shared ledger for your iPhone and computer.</p>
      <form className="auth-card" onSubmit={submit}>
        {registering && (
          <input placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} />
        )}
        <input placeholder="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        <input placeholder="Password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
        <button className="btn primary" disabled={busy}>{registering ? 'Create account' : 'Log in'}</button>
        {err && <div className="err">{err}</div>}
        <p className="hint" style={{ marginTop: 16, cursor: 'pointer' }} onClick={() => setRegistering(!registering)}>
          {registering ? 'Have an account? Log in' : 'New here? Create an account'}
        </p>
      </form>
    </div>
  );
}
