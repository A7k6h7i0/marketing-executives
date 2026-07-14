class ApiEndpoints {
  // Local backend — change for production deployment
  static const String baseUrl = 'http://localhost:5000';

  // Auth endpoints
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String register = '/auth/register';

  // Attendance & Breaks
  static const String attendanceHistory = '/attendance';
  static const String startBreak = '/breaks/start';
  static const String endBreak = '/breaks';
  static const String todayBreaks = '/breaks';

  // GPS & Odometer Tracking
  static const String gpsPing = '/gps/ping';
  static const String gpsHistory = '/gps/route';

  // Plans & Routes
  static const String routes = '/routes';
  static const String dailyPlans = '/plans';

  // Visits & Catalog
  static const String productCatalog = '/products';
  static const String checkin = '/visits/checkin';
  static const String placeOrder = '/visits';
  static const String checkout = '/visits';

  // Incidents
  static const String incidents = '/incidents';

  // Field-force Leads
  static const String nearbyLeads = '/leads/nearby';
  static const String saveLead = '/leads';
  static const String getLeads = '/leads';

  // Route Optimization
  static const String optimizeRoute = '/routes/optimize';

  // Admin Oversight endpoints
  static const String adminKpis = '/admin/kpis';
  static const String adminUsers = '/admin/users';

  // Telecaller CRM
  static const String telecallerLeads = '/telecaller/leads';
  static const String telecallerCalls = '/telecaller/calls';
  static const String telecallerUsers = '/telecaller/users';
  static const String telecallerBulkDistribute = '/telecaller/leads/bulk-distribute';
  static const String telecallerBulkDistributeFile = '/telecaller/leads/bulk-distribute-file';
  static const String telecallerDailyReport = '/telecaller/calls/daily-report.xlsx';
  static const String telecallerFollowups = '/telecaller/followups/today';
}
