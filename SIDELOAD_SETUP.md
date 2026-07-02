# Getting Work Hours onto Mom's iPhone (free, no Apple Developer account)

This uses **AltStore + AltServer** — a free community tool that installs the app
with a free Apple ID and re-signs it automatically over WiFi so it doesn't
expire after 7 days. It keeps Siri voice clock-in working (unlike a web app).

The app file to install is already built:

    /Users/ventimaj/Desktop/HourTracker/WorkHoursTracker.ipa

Whenever the app code changes, rebuild that file (see "Rebuilding the .ipa" at
the bottom) and re-import it in AltStore.

---

## What's needed to keep this running

**Mom's computer** — runs **AltServer**, which refreshes the app's signature
over WiFi about once a week so it never expires. Your Mac does **not** need to
stay on: the backend is hosted on Railway now (see `RAILWAY_DEPLOY.md`), so the
app works over WiFi or cellular, from anywhere — home or not.

---

## One-time setup

### A. On Mom's computer
1. Install AltServer from **https://altstore.io** (follow their current install
   steps — they differ slightly between Mac and Windows and change per version).
2. Plug Mom's iPhone into her computer once with a cable, trust the computer.
3. From AltServer's menu-bar/tray icon: **Install AltStore** onto her iPhone.
4. On the iPhone, sign in with an **Apple ID**. Recommended: make a **dedicated
   free Apple ID** just for this rather than using Mom's main one — AltServer
   stores the login, and a throwaway account keeps her real account out of it.
   (A free Apple ID allows 3 sideloaded apps; AltStore uses 1, this app uses 1.)
5. On the iPhone: **Settings → General → VPN & Device Management** → trust the
   developer profile for that Apple ID.

### B. Install the app through AltStore (on the iPhone)
1. AirDrop / email `WorkHoursTracker.ipa` to Mom's computer or phone.
2. Open **AltStore** on the iPhone → **My Apps** tab → **＋** (top-left) →
   pick `WorkHoursTracker.ipa`.
3. It installs and appears on the home screen. First launch will ask for
   Microphone / Speech / Siri permission — allow them for dictation + Siri.
4. Log her in once (the app remembers it permanently after that). Either create
   her account on the signup screen, or you make it for her ahead of time.

### C. Enable automatic WiFi refresh
- In AltServer on Mom's computer, enable **WiFi sync / background refresh** for
  her phone. As long as her computer is on and on the same WiFi, AltServer
  re-signs the app before the 7 days run out — no cable needed after the initial
  setup. Leaving her computer on (or waking it) roughly weekly is enough.

---

## Backend (resolved — hosted on Railway)

The Release build (this `.ipa`) points at the hosted backend:

    https://hourtracker-production.up.railway.app

This is set only for Release builds in `APIClient.swift` (Debug builds still
use the Mac's LAN IP for local dev/testing) — no always-on Mac required for
Mom's app, and it works over WiFi or cellular, anywhere. See
`RAILWAY_DEPLOY.md` for how that's hosted and how to redeploy backend changes.

---

## When it breaks (occasional, expected with this approach)

- **App shows a login screen again / "session expired"**: the backend user was
  reset. Just log in again.
- **App won't open / "unable to verify"**: the 7-day signature lapsed because
  AltServer wasn't running when it needed to refresh. Open AltStore on the phone
  → My Apps → refresh, or make sure her computer + AltServer are on and on WiFi.
- **After an iOS update**, sideloading tools sometimes need updating — grab the
  latest AltServer/AltStore from altstore.io. This is the tradeoff for avoiding
  the $99 Apple fee; it usually just works but occasionally needs your attention.

---

## Rebuilding the .ipa (after any app change)

    cd /Users/ventimaj/Desktop/HourTracker/ios
    xcodebuild -project WorkHoursTracker.xcodeproj -scheme WorkHoursTracker \
      -configuration Release -destination 'generic/platform=iOS' \
      -derivedDataPath /tmp/whtracker_release \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

    cd /tmp/whtracker_release/Build/Products/Release-iphoneos
    rm -rf Payload WorkHoursTracker.ipa && mkdir Payload
    cp -R WorkHoursTracker.app Payload/ && xattr -cr Payload
    zip -qr WorkHoursTracker.ipa Payload
    cp WorkHoursTracker.ipa /Users/ventimaj/Desktop/HourTracker/WorkHoursTracker.ipa

Then re-import the new `WorkHoursTracker.ipa` in AltStore on her phone.
