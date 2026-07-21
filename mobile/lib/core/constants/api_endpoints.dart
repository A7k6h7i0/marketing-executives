/// Production SFA API paths (`https://sales.digitalleadpro.com`).
///
/// Override host only for debugging:
///   flutter run --dart-define=API_BASE_URL=https://sales.digitalleadpro.com
class ApiEndpoints {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sales.digitalleadpro.com',
  );

  static const String apiPrefix = '/api/v1';

  // ── Auth ──────────────────────────────────────────────────────────
  static const String login = '$apiPrefix/auth/login';
  static const String logout = '$apiPrefix/auth/logout';
  static const String authMe = '$apiPrefix/auth/me';

  // ── Attendance ────────────────────────────────────────────────────
  static const String attendanceCheckIn = '$apiPrefix/attendance/check-in';
  static const String attendanceCheckOut = '$apiPrefix/attendance/check-out';
  static const String attendanceMy = '$apiPrefix/attendance/my';

  // ── Breaks (friend backlog — keep paths ready) ────────────────────
  static const String breaksStart = '$apiPrefix/breaks/start';
  static String breaksEnd(String breakId) => '$apiPrefix/breaks/$breakId/end';
  static const String breaksMy = '$apiPrefix/breaks/my';

  // ── GPS ───────────────────────────────────────────────────────────
  static const String gpsLog = '$apiPrefix/gps/log';

  // ── Field routes & outlets ────────────────────────────────────────
  static const String fieldRoutes = '$apiPrefix/field-routes';
  static String fieldRoute(String id) => '$apiPrefix/field-routes/$id';
  static const String outlets = '$apiPrefix/outlets';
  static String outlet(String id) => '$apiPrefix/outlets/$id';

  // ── Visits & orders ───────────────────────────────────────────────
  static const String visitsStart = '$apiPrefix/visits/start';
  static String visitsEnd(String visitId) => '$apiPrefix/visits/$visitId/end';
  static const String visits = '$apiPrefix/visits';
  static const String orders = '$apiPrefix/orders';

  // ── Products ──────────────────────────────────────────────────────
  static const String products = '$apiPrefix/products';
  static String product(String id) => '$apiPrefix/products/$id';
  static const String productCategories = '$apiPrefix/products/categories';
  static String productCategory(String id) => '$apiPrefix/products/categories/$id';
  static const String productBrands = '$apiPrefix/products/brands';
  static String productBrand(String id) => '$apiPrefix/products/brands/$id';

  // ── Territories ───────────────────────────────────────────────────
  static const String territories = '$apiPrefix/territories';
  static const String territoryRegions = '$apiPrefix/territories/regions';

  // ── Distributors ──────────────────────────────────────────────────
  static const String distributors = '$apiPrefix/distributors';

  // ── Incidents / leaves / expenses ─────────────────────────────────
  static const String incidents = '$apiPrefix/incidents';
  static const String leaves = '$apiPrefix/leaves';
  static const String expenses = '$apiPrefix/expenses';

  // ── Leads (friend backlog) ────────────────────────────────────────
  static const String leads = '$apiPrefix/leads';
  static String leadConvert(String leadId) => '$apiPrefix/leads/$leadId/convert';

  // ── Users (team directory) ────────────────────────────────────────
  static const String users = '$apiPrefix/users';
  static String user(String userId) => '$apiPrefix/users/$userId';

  // ── Organisations (multi-tenant) ──────────────────────────────────
  static const String orgsRegister = '$apiPrefix/orgs/register';
  static const String adminOrgsPending = '$apiPrefix/admin/orgs/pending';
  static String adminOrgApprove(String orgId) => '$apiPrefix/admin/orgs/$orgId/approve';
  static String adminOrgReject(String orgId) => '$apiPrefix/admin/orgs/$orgId/reject';
  /// Current tenant org (admin) — includes subscription trial/grace fields.
  static const String adminOrg = '$apiPrefix/admin/org';
  /// Super-admin: set/extend subscription dates for any org.
  static String adminOrgSubscription(String orgId) =>
      '$apiPrefix/admin/orgs/$orgId/subscription';

  // ── Uploads ───────────────────────────────────────────────────────
  static const String uploadSelfie = '$apiPrefix/uploads/selfie';
  static const String mediaUpload = '$apiPrefix/media/upload';

  // ── Admin ─────────────────────────────────────────────────────────
  static const String adminStats = '$apiPrefix/admin/stats';
  static const String adminUsers = users; // production uses /users, not /admin/users
  static String adminUser(String userId) => user(userId);
  static const String adminLiveVisits = '$apiPrefix/admin/visits/live';
  static const String adminSettings = '$apiPrefix/admin/settings';
  static const String approvalsPending = '$apiPrefix/approvals/pending';

  // ── Telecaller (friend backlog) ───────────────────────────────────
  static const String telecallerLeads = '$apiPrefix/telecaller/leads';
  static const String telecallerCalls = '$apiPrefix/telecaller/calls';
  static const String telecallerUsers = '$apiPrefix/telecaller/users';
  static const String telecallerBulkDistribute = '$apiPrefix/telecaller/leads/bulk-distribute';
  static const String telecallerBulkDistributeFile = '$apiPrefix/telecaller/leads/bulk-distribute-file';
  static const String telecallerDailyReport = '$apiPrefix/telecaller/calls/daily-report.xlsx';
  static const String telecallerFollowups = '$apiPrefix/telecaller/followups/today';

  // ── Compatibility aliases (old call sites → production paths) ─────
  static const String routes = fieldRoutes;
  static String routeOutlets(String routeId) => fieldRoute(routeId);
  static const String plans = fieldRoutes;
  static String plansToday(String userId) => fieldRoutes;
  static const String gpsPing = gpsLog;
  static String gpsRoute(String userId, String date) => gpsLog;
  static String gpsSummary(String userId, String date) => gpsLog;
  static String attendanceToday(String userId) => attendanceMy;
  static String attendanceHistory(String userId) => attendanceMy;
  static String breaksToday(String userId) => breaksMy;
  static const String visitsCheckIn = visitsStart;
  static String visitOrder(String visitId) => orders;
  static String visitCheckout(String visitId) => visitsEnd(visitId);
  static String visitsByDate(String userId, String date) => visits;
  static String incidentsByUser(String userId) => incidents;
  static String incidentResolve(String incidentId) => '$incidents/$incidentId/resolve';
  static const String leadsNearby = leads;
  static String leadById(String leadId) => '$leads/$leadId';
  static const String productCatalog = products;
  static const String saveLead = leads;
  static const String getLeads = leads;
  static const String nearbyLeads = leads;
  static const String adminKpis = adminStats;
  static const String searchOutlets = outlets;
  static String outletRatings(String outletId) => '$outlets/$outletId/ratings';
  static String outletGrade(String outletId) => '$outlets/$outletId/grade';
  static const String routesOptimize = '$apiPrefix/routes/optimize';
  static String routesOptimizeById(String routeId) => '$apiPrefix/routes/optimize/$routeId';
  static String routesOptimizeSkip(String routeId, String stopId) =>
      '$apiPrefix/routes/optimize/$routeId/skip/$stopId';
}
