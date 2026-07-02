# Work Hours Tracker

A work-hours tracking system with three clients sharing one backend:

- **iOS app** (SwiftUI + App Intents) — clock in/out, notes, calendar/summary/raw views, and **Siri voice commands**.
- **Web app** (React + Vite) — the same features in a browser.
- **Backend** (Node.js + Express + SQLite) — event-sourced API shared by both.

Timestamps are stored in UTC with timezone identifiers. The model separates append-only **ClockEvents** from editable **WorkSessions** (with an audit log), and handles DST, cross-midnight sessions, duplicate clock-ins, forgotten clock-outs, and offline sync.

---

## 1. Backend (start here — both clients need it)

Requires Node.js **22.5+** (uses the built-in `node:sqlite` module — no native compiler/Xcode toolchain needed).

```bash
cd backend
npm install
npm run seed      # creates a local SQLite DB with a demo user + sample data
npm start         # serves http://localhost:4000
```

You may see `ExperimentalWarning: SQLite is an experimental feature` on startup — that's expected and harmless; it's Node's built-in driver, not a sign anything is broken.

**Demo login:** `demo@example.com` / `password123`

`npm run seed` is safe to re-run; it resets the demo data. The database is a single file (`backend/data.sqlite`) created on first run.

---

## 2. Web app

Requires the backend running on port 4000.

```bash
cd web
npm install
npm run dev       # opens http://localhost:5173
```

Vite proxies API calls to `localhost:4000`, so no extra config is needed. Sign in with the demo account above.

---

## 3. iOS app (requires a Mac + Xcode)

The Swift sources are here but there is **no `.xcodeproj`** — you create the project in Xcode once and add the files. This takes ~5 minutes:

1. **Open Xcode → File → New → Project → iOS → App.**
   - Product Name: `WorkHoursTracker`
   - Interface: **SwiftUI**, Language: **Swift**
   - Save it somewhere temporary (you'll replace its files).

2. **Add the source files.** Delete the default `ContentView.swift` and the generated `App.swift`, then drag the contents of `ios/WorkHoursTracker/` (all folders: `Models`, `Views`, `Intents`, `Services`, `Utilities`, plus `WorkHoursTrackerApp.swift`) into the project navigator. Check **"Copy items if needed"** and add them to the app target.

3. **Replace Info.plist** (or merge its keys): use the provided `Info.plist`. It contains:
   - `NSSiriUsageDescription` (required for Siri).
   - An App Transport Security exception allowing `http://localhost` (so the Simulator can reach the backend during development).

4. **Enable the App Group** (needed so Siri intents and the app share the open-session state):
   - Select the app target → **Signing & Capabilities → + Capability → App Groups.**
   - Add the group `group.com.example.workhourstracker`.
   - The provided `WorkHoursTracker.entitlements` already declares this group — point the target's *Code Signing Entitlements* build setting at it, or just add the capability via the UI which regenerates it.

5. **Add the Siri capability:** same screen → **+ Capability → Siri.**

6. **Set your signing team** (Signing & Capabilities → Team) so it can run on the Simulator or a device.

7. **Run.** The **iOS Simulator reaches `localhost:4000` directly**, so with the backend running it works out of the box.
   - To run on a **physical iPhone**, the phone can't see your Mac's `localhost`. Edit `ios/WorkHoursTracker/Services/APIClient.swift` and change `baseURL` from `http://localhost:4000` to `http://<your-mac-LAN-IP>:4000` (e.g. `http://192.168.1.42:4000`). Find the IP with `ipconfig getifaddr en0` in Terminal. Both devices must be on the same Wi-Fi.

### Using Siri

The app registers App Shortcuts, so after building once you can say phrases that **include the app name**, e.g.:

- "Clock me in with Work Hours"
- "Clock me out with Work Hours"
- "Add a work note with Work Hours" → Siri asks *"What are you working on?"*
- "Show today's hours with Work Hours"

iOS does not allow third-party apps to claim bare phrases like "clock me in" — those require the app name, or you can create a personal Shortcut in the Shortcuts app that wraps the intent with your own phrase. The intents run in the background and work while the phone is locked.

---

## Architecture notes

- **Event sourcing:** every clock in/out writes an immutable row to `clock_events`. `work_sessions` are derived and editable; edits are recorded in `edit_history`. Deletes are soft (restorable).
- **Idempotency:** Siri/offline actions carry an `idempotencyKey` so retries don't create duplicate events.
- **Offline-first iOS:** actions queue locally (`LocalStore`) and push when connectivity returns (`/sync/push`).
- **Time handling:** `luxon` on the backend allocates cross-midnight durations to the correct local day and computes DST-safe week/month boundaries.

## API surface (backend)

`/auth/register`, `/auth/login`, `/auth/me` · `/clock/in`, `/clock/out`, `/clock/note`, `/clock/state` · `/sessions` (CRUD + `/restore`, `/history`) · `/events` · `/summaries/daily|weekly|monthly` · `/export/csv` · `/sync/push`, `/sync/pull`
