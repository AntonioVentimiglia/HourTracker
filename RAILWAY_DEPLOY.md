# Deploying the backend to Railway (always-on, reachable from anywhere)

This puts the backend on Railway so it no longer depends on your Mac being on.
Once done, the app works on any network (WiFi or cellular), anywhere.

The repo is already prepared for this (Node 24 pinned, `railway.json`,
volume-ready DB path). You just do the dashboard steps below.

---

## 1. Create the project (Railway dashboard)

1. Go to **https://railway.app** and sign up (GitHub login is easiest).
2. **New Project → Deploy from GitHub repo →** pick `AntonioVentimiglia/HourTracker`.
   - Authorize Railway to access the repo if prompted.
3. When the service is created, open its **Settings** and set:
   - **Root Directory:** `backend`
     (the server lives in `backend/`, not the repo root — this is required)

## 2. Add a persistent volume (CRITICAL — or data is wiped on every deploy)

The backend stores everything in a SQLite file. Without a volume, Railway's
filesystem resets on each redeploy and all of Mom's history disappears.

1. In the service, go to **Variables/Settings → Volumes → New Volume**.
2. **Mount path:** `/data`
3. Any size (1 GB is plenty).

## 3. Set environment variables

In the service's **Variables** tab, add:

| Variable      | Value                                                              |
|---------------|-------------------------------------------------------------------|
| `DB_PATH`     | `/data/data.sqlite`                                               |
| `JWT_SECRET`  | `62ac8e1277d5ebd632b02db18b069decf346bd16fb1c64abe39ab3344e70e1a6` |

- `DB_PATH` points the database at the persistent volume from step 2.
- `JWT_SECRET` secures login tokens. **Must** be set — otherwise the server
  falls back to a public dev default that anyone could forge tokens against.
  (The value above was generated for you. If you'd rather make your own:
  `openssl rand -hex 32`. If you ever change it, everyone gets logged out once.)
- You do **not** need to set `PORT` — Railway injects it and the server reads it.

## 4. Deploy & get the URL

1. Railway builds and deploys automatically. Watch the **Deploy Logs** — you want
   to see `Work Hours Tracker API listening on ...` and the healthcheck on
   `/health` passing.
2. Go to **Settings → Networking → Generate Domain**. You'll get a public URL
   like `https://hourtracker-production-xxxx.up.railway.app`.
3. Test it in a browser: visiting `<that-url>/health` should return
   `{"ok":true,...}`.

**Send me that URL** and I'll point the app at it (Debug builds keep hitting your
Mac for local testing; the Release build Mom gets will hit Railway), drop the
local-HTTP exception, and rebuild the sideload `.ipa`.

## 5. Future updates

Because Railway is connected to GitHub, every push to `main` auto-redeploys.
Mom's data persists across deploys thanks to the volume.

---

## Notes / gotchas

- **Free trial limits:** Railway's free trial has a monthly usage credit and may
  require a card for volumes. If you hit a wall at the volume step, that's the
  trial's limit — the alternative is their cheapest paid tier (~a few $/mo) or
  Fly.io as a fallback.
- **Existing local data doesn't transfer.** The Railway database starts empty;
  Mom just registers once. Your local test accounts stay on your Mac only.
- **The demo seed script does NOT run in the cloud** (by design — it deletes and
  recreates the demo user). Real accounts are created via the app's signup.
