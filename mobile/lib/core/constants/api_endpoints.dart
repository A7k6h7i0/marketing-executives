/// Central API path definitions for the field-force backend (spec v1.0).
///
/// Override the host at build/run time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
class ApiEndpoints {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sales.digitalleadpro.com',
  );

  static const String apiPrefix = '/api/v1';

  // Auth
  static const String login = '$apiPrefix/auth/login';
  static const String logout = '$apiPrefix/auth/logout';
  static const String authMe = '$apiPrefix/auth/me';

  // Attendance
  static String attendanceHistory(String userId) => '$apiPrefix/attendance/$userId';
  static String attendanceToday(String userId) => '$apiPrefix/attendance/today/$userId';

  // Breaks
  static const String breaksStart = '$apiPrefix/breaks/start';
  static String breaksEnd(String breakId) => '$apiPrefix/breaks/$breakId/end';
  static String breaksToday(String userId) => '$apiPrefix/breaks/$userId/today';

  // GPS
  static const String gpsPing = '$apiPrefix/gps/ping';
  static String gpsRoute(String userId, String date) => '$apiPrefix/gps/route/$userId/$date';
  static String gpsSummary(String userId, String date) => '$apiPrefix/gps/summary/$userId/$date';

  // Plans & routes
  static const String routes = '$apiPrefix/routes';
  static String routeOutlets(String routeId) => '$apiPrefix/routes/$routeId/outlets';
  static const String plans = '$apiPrefix/plans';
  static String plansToday(String userId) => '$apiPrefix/plans/$userId/today';

  // Visits & products
  static const String products = '$apiPrefix/products';
  static const String visitsCheckIn = '$apiPrefix/visits/checkin';
  static String visitOrder(String visitId) => '$apiPrefix/visits/$visitId/order';
  static String visitCheckout(String visitId) => '$apiPrefix/visits/$visitId/checkout';
  static String visitsByDate(String userId, String date) => '$apiPrefix/visits/$userId/$date';

  // Outlets
  static const String outlets = '$apiPrefix/outlets';
  static String outletRatings(String outletId) => '$apiPrefix/outlets/$outletId/ratings';
  static String outletGrade(String outletId) => '$apiPrefix/outlets/$outletId/grade';

  // Incidents
  static const String incidents = '$apiPrefix/incidents';
  static String incidentsByUser(String userId) => '$apiPrefix/incidents/$userId';
  static String incidentResolve(String incidentId) => '$apiPrefix/incidents/$incidentId/resolve';

  // Leads
  static const String leads = '$apiPrefix/leads';
  static const String leadsNearby = '$apiPrefix/leads/nearby';
  static String leadById(String leadId) => '$apiPrefix/leads/$leadId';
  static String leadConvert(String leadId) => '$apiPrefix/leads/$leadId/convert';

  // Route optimization
  static const String routesOptimize = '$apiPrefix/routes/optimize';
  static String routesOptimizeById(String routeId) => '$apiPrefix/routes/optimize/$routeId';
  static String routesOptimizeSkip(String routeId, String stopId) =>
      '$apiPrefix/routes/optimize/$routeId/skip/$stopId';

  // Uploads
  static const String uploadSelfie = '$apiPrefix/uploads/selfie';

  // Admin
  static const String adminKpis = '$apiPrefix/admin/kpis';
  static String adminReports(String reportType) => '$apiPrefix/admin/reports/$reportType';
  static const String adminUsers = '$apiPrefix/admin/users';
  static String adminUser(String userId) => '$apiPrefix/admin/users/$userId';
  static const String adminLiveVisits = '$apiPrefix/admin/visits/live';

  // Telecaller
  static const String telecallerLeads = '$apiPrefix/telecaller/leads';
  static const String telecallerCalls = '$apiPrefix/telecaller/calls';
  static const String telecallerUsers = '$apiPrefix/telecaller/users';
  static const String telecallerBulkDistribute = '$apiPrefix/telecaller/leads/bulk-distribute';
  static const String telecallerBulkDistributeFile = '$apiPrefix/telecaller/leads/bulk-distribute-file';
  static const String telecallerDailyReport = '$apiPrefix/telecaller/calls/daily-report.xlsx';
  static const String telecallerFollowups = '$apiPrefix/telecaller/followups/today';

  // Legacy aliases (kept so older call sites compile during migration)
  static const String productCatalog = products;
  static const String saveLead = leads;
  static const String getLeads = leads;
  static const String nearbyLeads = leadsNearby;
  static const String visits = '$apiPrefix/visits';
  static const String users = adminUsers;
  static const String adminStats = adminKpis;
  static const String searchOutlets = leadsNearby;
}
