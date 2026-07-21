# FieldForce — How to Make It Work + What’s Done / Not Done

## A. Flow to make the application work

### Production only
The mobile app talks **only** to: `https://sales.digitalleadpro.com`.

The local `backend/` folder in this repo is **not** used by the app. See [PRODUCTION_API.md](PRODUCTION_API.md) for wired endpoints and the friend backlog for missing APIs.

### 1) Production API must be healthy
Confirm: `GET https://sales.digitalleadpro.com/health` returns ok (not 502).

Use real org users (examples from E2E):
- Executive: `farhan@addphonebook.com`
- Admin: `rajesh.kumar@addphonebook.com` / `lakshmiraj@addphonebook.com`

---

### 2) Backend must be running with the new APIs
~~The mobile app talks to local FieldForce backend~~ — **deprecated**. Use production only.

---

### 3) Master data the field flow needs
| Data | Why |
|------|-----|
| **Territory routes + outlets** (with lat/lng) | Executive must select a route and check in at shops |
| **Products** (optional but useful) | Order entry during visit |
| Outlets without GPS | Check-in will fail or ask for location fix |

---

### 4) Build / install the mobile app

```bash
cd mobile
flutter build apk --release
```

Install: `mobile/build/app/outputs/flutter-apk/app-release.apk`

Local backend testing only (phone cannot use localhost):

```bash
flutter run --dart-define=API_BASE_URL=http://YOUR_PC_LAN_IP:5000
```

---

### 5) Phone permissions
On first use allow:
- **Location** (check-in, map, GPS, prospects)
- **Camera** (selfie check-in)
- Photos/files (optional, for incident media)

---

### 6) End-to-end working flow (happy path)

```
Admin creates Executive + routes/outlets
        ↓
Executive logs in  →  attendance session starts
        ↓
Home → SELECT TODAY'S ROUTE AREA
        ↓
Tap outlet → CHECK-IN → GPS + Selfie
        ↓
Remarks / Order → SAVE
        ↓
Check-out from outlet
        ↓
(optional) Take Break / End Break
        ↓
Sync (if anything was offline)
        ↓
Admin → Logs → Visits & Orders  (see who / where / selfie)
        ↓
Executive → END DAY / CHECK OUT  (end whole day)
```

If this path works, the core product is working.

---

## B. What’s DONE vs NOT YET

Status relative to your full Sales Executive Tracking spec + current mobile app.

### Legend
- **Done** — usable in app (and API exists where needed)
- **Partial** — UI and/or API exist but incomplete, fragile, or not fully wired to production
- **Not yet** — missing or only stubbed

---

### Module 1 — Auth & Attendance
| Item | Status |
|------|--------|
| Email/mobile + password login | **Done** |
| JWT session | **Done** |
| Login starts attendance | **Done** (on successful login) |
| Logout / end day working hours | **Partial** (works locally + logout API; edge cases if API/old server mismatch) |
| Live working hours on Home | **Done** |
| Block multi-device login | **Done** (backend) |
| Incomplete session auto-close overnight | **Not yet** |
| Full attendance history UI for executive | **Partial** |

---

### Module 2 — Breaks
| Item | Status |
|------|--------|
| Take Break / End Break FAB | **Done** (fixed above bottom nav) |
| Categories Coffee / Lunch / Personal | **Done** |
| Sync breaks to API | **Partial** (wired; needs matching backend deployed) |
| Break history on dashboard | **Partial** |
| Auto-close break at midnight | **Not yet** |

---

### Module 3 — GPS & Odometer
| Item | Status |
|------|--------|
| GPS pings while on duty | **Partial** (periodic while app open / on duty — not true background when killed) |
| Distance on Route tab | **Partial** (accumulates; accuracy depends on phone GPS) |
| Odometer start Home / First Outlet | **Partial** (UI + ping field; needs server) |
| Admin map of full day polyline | **Partial** (pings list; not a polished live map trail) |
| Signal-lost segments > 5 min | **Done** (backend route logic) |
| True background tracking when app killed | **Not yet** |

---

### Module 4 — Daily Route & Area Planning
| Item | Status |
|------|--------|
| Select route / area for the day | **Done** |
| Load outlets + progress bar | **Done** / **Partial** (works if routes/outlets exist on server) |
| Add/remove outlets during day | **Partial** (add manual outlet yes; remove limited) |
| Routes from DB (not hardcoded) | **Done** on new backend; **Partial** if old production API |

---

### Module 5 — Outlet Visit Workflow (core)
| Item | Status |
|------|--------|
| Check-in with GPS + geofence ~100m | **Done** |
| Manager override when far | **Done** |
| Mandatory selfie | **Done** |
| Selfie upload to server | **Partial** (works when `/uploads/selfie` is deployed) |
| Remarks / products during visit | **Done** |
| Outlet check-out | **Done** |
| Active visit banner + force checkout | **Done** |
| Sync visit to server for admin | **Partial** (needs new visit APIs live on production) |
| Offline queue for visits | **Partial** |

---

### Module 6 — Incidents
| Item | Status |
|------|--------|
| Report incident from Reports tab | **Done** |
| Photo/video attach | **Partial** |
| Manager sees + Mark Resolved | **Partial** / **Done** in admin UI |
| Real FCM push to manager phone | **Not yet** (server logs stub) |

---

### Module 7 — Smart Leads
| Item | Status |
|------|--------|
| Nearby search + filters | **Partial** (API/Google or mock; depends on key) |
| Save lead | **Done** / **Partial** |
| Convert lead → outlet | **Partial** |

---

### Module 8 — Route Optimization
| Item | Status |
|------|--------|
| Optimize visit order + open Maps | **Partial** (client nearest-neighbor; Google Directions if key set on backend) |
| Skip stop + recalculate | **Not yet** / stub |

---

### Module 9 — Outlet Grading
| Item | Status |
|------|--------|
| Grade display on outlet | **Partial** |
| Submit 5-score rating form in app | **Not yet** (API method exists; full UI not shipped) |
| Admin rating trends | **Partial** (API reports) |

---

### Module 10 — Admin Dashboard & Reports
| Item | Status |
|------|--------|
| Mobile admin KPIs | **Partial** |
| Live visits with selfie + GPS + who | **Done** in app design; **needs** `GET /admin/visits/live` on server |
| Team create executive | **Partial** |
| Full web admin dashboard | **Not yet** (API reports exist; dedicated web field dashboard incomplete) |
| All report types as polished exports | **Partial** (JSON/API; Excel-style limited) |

---

### Extra — Telecaller
| Item | Status |
|------|--------|
| Telecaller role, leads, dialer, bulk assign | **Done** (separate module, more mature) |

---

## C. Short summary for your friend / stakeholders

### Working today (if new backend is deployed)
Login → select route → check-in (GPS+selfie) → remarks/order → checkout → breaks → incidents → prospects → admin can review visits/selfies (when synced).

### Still weak / missing
1. Production server may still be on **old APIs** — deploy backend update.  
2. GPS is **not** true 24/7 background when app is killed.  
3. Push notifications (FCM) for incidents — not real yet.  
4. Outlet grading form UI — not finished.  
5. Full web admin portal — not finished.  
6. Route optimization is basic unless Google API key is configured.

### Minimum checklist before a real field test
- [ ] New backend deployed (visits, gps/ping, uploads/selfie, admin/visits/live)  
- [ ] Real executive + admin accounts created  
- [ ] Routes + outlets with correct lat/lng  
- [ ] Fresh release APK installed  
- [ ] Location + camera permissions allowed  
- [ ] One full check-in → remarks → checkout → admin Logs refresh  

---

*See also: `USER_TESTING_GUIDE.md` for button-by-button UI help.*
