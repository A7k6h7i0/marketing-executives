# FieldForce Marketing — App User Guide (for Testers)

**Who this is for:** Someone testing the app who has never used it before.  
**What this app is:** A field sales / marketing executive app. Executives visit outlets (shops), check in with GPS + selfie, record orders/remarks, track travel, take breaks, and report problems. Managers/admins monitor the team.

Use the login account your team gave you (email or mobile + password). After login, the app opens a different home screen depending on your role:
- **Sales Executive** → field work tabs (Home, Route, Prospects, Reports)
- **Admin / Manager** → management tabs (Oversight, Team, Logs, Incidents, Telecaller)
- **Telecaller** → calling / leads screen (separate role)

---

## 1. Login screen

| Element | What it does |
|--------|----------------|
| **Email or Mobile** | Enter your account email or phone number. |
| **Password** | Enter your password. |
| **Sign in** | Logs you in and opens the correct home for your role. |
| “Forgot your credentials?” text | Reminder only — there is no forgot-password button. Contact your admin. |

---

## 2. Sales Executive app

### Top bar (all executive tabs)

| Button / icon | What it does |
|---------------|----------------|
| **Sync** (circular arrows) | Uploads offline data (visits, GPS, leads, incidents) to the server when you have internet. |
| **Logout** | Ends your session and returns to the login screen. |

### Floating button (when you are on duty)

| Button | What it does |
|--------|----------------|
| **Take Break** | Starts a break. You must pick a type: Coffee / Lunch / Personal. |
| **End Break** | Ends the current break and returns you to working status. |

---

### Tab 1 — Home

**Purpose:** Start your day, see working hours, choose today’s route, visit outlets, check in / out.

#### Session card (blue/purple gradient)

| Element | Meaning |
|---------|---------|
| **ACTIVE SESSION / OFF DUTY / DAY COMPLETED** | Whether you are currently on duty. |
| **Hours** | How long you have been working today (updates while logged in). |
| **Break Taken** | Total break time today. |
| **Status** | WORKING, ON BREAK, CHECKED OUT, or ABSENT. |
| **Check-in / Check-out times** | When your duty day started and whether you ended it. |
| **END DAY / CHECK OUT** | Ends your whole work day (attendance), not a single outlet visit. Confirm with **END DAY** or cancel with **CANCEL**. |

#### Today’s Route Progress

Shows how many planned outlet visits you finished vs planned (example: `Visits: 2 / 10` and a progress bar).

#### Configure Your Day (only if no route selected yet)

| Button | What it does |
|--------|----------------|
| **SELECT TODAY’S ROUTE AREA** | Opens the list of routes/areas so you can load today’s outlet checklist. |

#### Active Outlet Visit card (appears after you check in)

| Button | What it does |
|--------|----------------|
| **Remarks / Order** | Opens products + visit notes for the outlet you are currently visiting. |
| **Check-out** | Finishes the current outlet visit. |

#### Today’s Target Outlets list

| Element | What it does |
|---------|----------------|
| Outlet row | Tap to open that outlet’s visit actions. |
| **ADD OUTLET** | Manually add another shop to today’s list. |

#### Selecting a route

1. Tap **SELECT TODAY’S ROUTE AREA**.
2. Tap a route from the list **or** tap **ADD CUSTOM ROUTE / AREA**.
3. For a custom route, fill **Route / Area Name**, **Region / City**, optional first outlet, then **SAVE CUSTOM ROUTE**.

#### Adding an outlet to today’s plan

1. Tap **ADD OUTLET**.
2. Fill **Outlet Name**, **Outlet Address**.
3. Optional: **Latitude** / **Longitude** (manual override).
4. Tap **ADD OUTLET** to save.

#### Outlet visit (most important flow)

1. Tap an outlet in **TODAY’S TARGET OUTLETS**.
2. Tap **CHECK-IN (100M GEOFENCE)**.
3. Allow location, then take a **front-camera selfie** (required).
4. If you are more than ~100m away, you may see **Geofence Violation**:
   - **CANCEL** — cancel check-in
   - **REQUEST OVERRIDE** — continue with a manager-override flag
5. After success you can:
   - **ORDER / SALES** or **ORDER / REMARKS** — add products and notes
   - **CHECK-OUT** — leave the outlet
   - **LATER** — close the popup; use the orange **Active Visit** card on Home

If another visit is still open, you may see **FORCE CHECK-OUT** to clear the stuck visit.

#### Order / Remarks sheet

| Element | What it does |
|---------|----------------|
| Product list **+** | Adds that product to the order. |
| − / + on selected items | Change quantity. |
| Quick chips (`Next Visit`, `Payment received`, etc.) | Inserts common remark text. |
| **Visit Notes / Customer Remarks** | Free text notes (keep under ~500 characters). |
| **SAVE PRODUCTS / REMARKS** | Saves order + remarks for this visit. |

---

### Tab 2 — Route

**Purpose:** See travel distance, map of outlets, and get an optimized visit order.

| Element | What it does |
|---------|----------------|
| **Total Distance** | Kilometres tracked today from GPS pings. |
| **Odometer Start** dropdown | Choose whether distance counting starts from **Home Location** or **First Outlet**. |
| Map | Shows your planned outlets (and your position when available). |
| Small location FAB | Recenters the map on you. |
| **INTELLIGENT ROUTE OPTIMIZATION** | Opens a dialog to compute a suggested visit order. |
| **COMPUTE OPTIMAL** | Builds the optimized stop list. |
| **CANCEL** / **DISMISS** | Close without / after viewing the plan. |
| Navigation icon on a stop | Opens Google/Apple Maps for that address. |
| Marker tap → **OPEN THIS ADDRESS IN MAPS** | Same — open maps for that outlet. |

---

### Tab 3 — Prospects

**Purpose:** Find nearby shops that are **not** already on your route and save them as leads (future outlets).

| Element | What it does |
|---------|----------------|
| **What are Prospects?** | Short explanation of this tab. |
| **Filter** | Retail Stores / Supermarkets / Restaurants / Pharmacies. |
| GPS refresh icon | Uses your current location to search again. |
| **SEARCH NOW** | Looks for nearby businesses. |
| Bookmark / **Save as Lead** | Saves that shop to **My Saved Prospects**. |
| **CONVERT** (on a saved lead) | Tries to turn the lead into an outlet in the system. |

---

### Tab 4 — Reports

**Purpose:** Report field problems (vehicle, medical, closed outlet, blocked road, etc.) so managers can see them.

| Element | What it does |
|---------|----------------|
| **Problem Type** | Vehicle Breakdown / Medical Emergency / Outlet Closed / Route Blocked / Other. |
| **Detailed Description** | Required text (at least 20 characters). |
| **ATTACH CAPTURED MEDIA (MAX 3)** | Optional photos/videos as evidence. |
| **SUBMIT REPORT & ALERT MANAGER** | Sends the incident. |
| **MY REPORTED FIELD PROBLEMS** | Your past reports and status. |

---

## 3. Admin / Manager app

### Top bar

| Button | What it does |
|--------|----------------|
| **Refresh** | Reloads KPIs, visits, GPS, team data. |
| **Logout** | Signs out. |

### Tab 1 — Oversight

**Purpose:** Live overview of the field team.

| Element | What it does |
|---------|----------------|
| KPI cards | Active executives, total distance, visits done, sales value. |
| Incidents alert | Shows if open incidents need attention. |
| **Automatic Visit Policy** | Set minimum minutes to auto-register a visit (1–30). **SAVE** / **CANCEL**. |
| **Excel Export** | Downloads a CSV of visit activity. |

### Tab 2 — Team

**Purpose:** See executives and create new ones.

| Element | What it does |
|---------|----------------|
| Team cards | Name, email, online/offline style status. |
| **+** / Add Field Executive FAB | Opens create form. |
| Form fields | Full Name, Email, Initial Password. |
| **CREATE FIELD ACCOUNT** | Creates the executive account. |

### Tab 3 — Logs

**Purpose:** Audit who checked in where (with selfie and GPS).

**Sub-tabs:**
1. **Visits & Orders** — each card shows:
   - Executive name & email  
   - Outlet name & address  
   - **Check-in selfie**  
   - Check-in / check-out times  
   - Order value & remarks  
   - GPS coordinates / location  
   - Status: **IN VISIT** or **COMPLETED**
2. **GPS Location Pings** — trail of location updates from executives.

### Tab 4 — Incidents

**Purpose:** Review field problem reports.

| Element | What it does |
|---------|----------------|
| Incident list | Type, description, who reported, evidence. |
| **MARK RESOLVED** | Closes the incident after it is handled. |

### Tab 5 — Telecaller

**Purpose:** Manage call-center leads (add, bulk assign, call, update status). Used more by managers/telecallers than field executives.

| Element | What it does |
|---------|----------------|
| **Add lead** | Create one lead (name, phone, company, etc.). |
| **Bulk assign** | Upload Excel/CSV and distribute leads to telecallers. |
| Search / status filters | Find leads by name or status. |
| Call action | Opens the phone dialer. |
| Status / notes | Update lead progress after the call. |

---

## 4. Suggested test scripts (for your friend)

### A. Executive happy path (core test)
1. Sign in as an executive.  
2. On Home, tap **SELECT TODAY’S ROUTE AREA** and pick a route.  
3. Tap an outlet → **CHECK-IN** → allow GPS → take selfie.  
4. Tap **Remarks / Order** → add a note → **SAVE**.  
5. Tap **Check-out**.  
6. Confirm progress increases on **Today’s Route Progress**.  
7. Tap **Take Break** → Coffee → later **End Break**.  
8. Open **Reports** and submit a short test incident (20+ characters).  
9. Open **Prospects**, search nearby, save one lead.  
10. Tap Sync, then Logout.

### B. Admin verification
1. Sign in as admin/manager.  
2. Open **Logs → Visits & Orders** and confirm the executive’s check-in, location, and selfie appear (refresh if needed).  
3. Open **Incidents** and confirm the test report; optionally **MARK RESOLVED**.  
4. Open **Team** and confirm the executive is listed.

---

## 5. Important differences (easy to confuse)

| Action | Meaning |
|--------|---------|
| **Outlet Check-in / Check-out** | You arrived / left **one shop**. |
| **END DAY / CHECK OUT** | You finished the **whole work day**. |
| **Take Break** | Pause working time (not an outlet visit). |
| **Sync** | Push offline records to the server so admin can see them. |

---

## 6. Permissions the phone may ask for

- **Location** — required for check-in, map, prospects, GPS tracking  
- **Camera** — required for check-in selfie  
- **Photos / files** — optional for incident media  

If these are denied, those features will fail.

---

## 7. Quick glossary

| Term | Meaning |
|------|---------|
| **Outlet** | A shop/customer location on the day’s route. |
| **Visit** | One check-in session at an outlet. |
| **Geofence** | You should be within ~100 metres of the outlet to check in (override possible). |
| **Prospect / Lead** | A potential new shop found nearby, not yet a full outlet. |
| **Incident / Field Report** | A problem that stops normal work (breakdown, closed shop, etc.). |
| **Odometer / Distance** | How far the executive has travelled while tracked. |

---

*This guide matches the current FieldForce Marketing mobile app (executive + admin screens). If a button label differs slightly after an update, use the same section of the app — the purpose stays the same.*
