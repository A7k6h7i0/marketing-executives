# Production feature parity & friend backlog

The Flutter app talks **only** to `https://sales.digitalleadpro.com`.
The local `backend/` folder in this repo is unused by the mobile app.

## Wired to production (E2E-proven)

| Feature | Endpoint |
|---------|----------|
| Login | `POST /api/v1/auth/login` (`login_selfie_url` data URI for executives) |
| Attendance | `POST /api/v1/attendance/check-in`, `GET /api/v1/attendance/my` |
| Field routes | `GET /api/v1/field-routes` |
| Outlets | `GET/POST /api/v1/outlets` |
| Visits list (admin logs) | `GET /api/v1/visits` |
| Visit start / end | `POST /api/v1/visits/start`, `POST /api/v1/visits/:id/end` |
| Orders | `POST /api/v1/orders` |
| GPS | `POST /api/v1/gps/log` |
| Incidents | `GET/POST /api/v1/incidents` |
| Products | `GET/POST /api/v1/products`, `PATCH/DELETE /api/v1/products/:id` |
| Product brands | `GET/POST /api/v1/products/brands`, `PATCH/DELETE .../brands/:id` |
| Product categories | `GET/POST /api/v1/products/categories`, `PATCH/DELETE .../categories/:id` |
| Admin stats | `GET /api/v1/admin/stats` (role: **admin** only today) |
| Team directory | `GET /api/v1/users` (role: **admin/manager** only today) |
| Create user | `POST /api/v1/users` (role: **admin** only today) |
| Leaves | `POST /api/v1/leaves` |
| Leads | `GET/POST /api/v1/leads`, `PATCH /api/v1/leads/:id` |
| Lead convert (client) | `POST /api/v1/outlets` + `PATCH` lead `status=converted` (no `/convert` route) |
| Register organisation | `POST /api/v1/orgs/register` |
| Pending orgs (super_admin) | `GET /api/v1/admin/orgs/pending` |
| Approve / reject org | `PATCH .../approve` or `.../reject` with body `{}` |

## Multi-tenant flow

1. Prospect taps **Register organisation** → submits org + owner details.
2. Org stays **pending** until platform **super_admin** approves (or rejects).
3. Until approval, owners see a professional review message.
4. After approval, org **admin** / **executives** get current features.
5. Server enforces org isolation.

## Critical backend ask (super_admin parity)

Today production returns **403** for `super_admin` on:

- `GET /api/v1/users`
- `GET /api/v1/visits`
- `GET /api/v1/admin/stats`
- `POST /api/v1/users`

Message: `Requires role: admin` / `admin or manager`.

**Please allow `super_admin` on those routes** (same org scope is fine). Until then:

- Org **admin** Team / Logs / create-executive / KPIs work.
- Platform **super_admin** keeps pending-org approve/reject, but Team/Logs stay empty by server policy.

Also: pending-org payload currently returns `email/phone/address` as `null` even when registration sent them — please return full org + owner details on `GET /admin/orgs/pending`.

## Kept client-side

- Shop search → `https://data.mytaskking.com`
- Dwell / auto-complete visit timing
- Offline lead cache + convert fallback
- CSV export on device
- Breaks UI (offline until server adds breaks)
- Selfie / min-stay policy prefs (until admin settings API exists)

## Friend backlog (full parity)

1. Breaks endpoints
2. `GET/PATCH /api/v1/admin/settings`
3. Dedicated `POST /api/v1/leads/:id/convert` (optional; app already converts via outlets)
4. Telecaller routes if needed
5. Super_admin role on admin org routes (above)
