class ApiEndpoints {
  static const String baseUrl = 'https://sales.digitalleadpro.com';
  static const String apiPrefix = '/api/v1';

  // Auth
  static const String login = '$apiPrefix/auth/login';
  static const String logout = '$apiPrefix/auth/logout';
  static const String authMe = '$apiPrefix/auth/me';

  // Attendance
  static const String checkIn = '$apiPrefix/attendance/check-in';
  static const String attendanceMy = '$apiPrefix/attendance/my';
  static const String attendanceToday = '$apiPrefix/attendance/today';
  static const String attendance = '$apiPrefix/attendance';

  // GPS
  static const String gpsLog = '$apiPrefix/gps/log';
  static const String gpsBulk = '$apiPrefix/gps/bulk';
  static const String gpsHistory = '$apiPrefix/gps/my/history';
  static const String gpsLive = '$apiPrefix/gps/live';

  // Sync
  static const String syncStatus = '$apiPrefix/sync/status';
  static const String syncPull = '$apiPrefix/sync/pull';
  static const String syncPush = '$apiPrefix/sync/push';

  // Search
  static const String search = '$apiPrefix/search';
  static const String searchOutlets = '$apiPrefix/search/outlets';

  // Products & master data
  static const String products = '$apiPrefix/products';

  // Leads
  static const String leads = '$apiPrefix/leads';

  // Visits & orders
  static const String visits = '$apiPrefix/visits';
  static const String orders = '$apiPrefix/orders';

  // Admin & manager
  static const String users = '$apiPrefix/users';
  static const String adminStats = '$apiPrefix/admin/stats';
  static const String adminOrg = '$apiPrefix/admin/org';
  static const String adminSettings = '$apiPrefix/admin/settings';
  static const String analyticsDashboard = '$apiPrefix/analytics/dashboard';
  static const String reportsDailySummary = '$apiPrefix/reports/daily-summary';
  static const String approvalsPending = '$apiPrefix/approvals/pending';

  // Notifications
  static const String notificationsUnread = '$apiPrefix/notifications/unread-count';
  static const String notificationsMarkRead = '$apiPrefix/notifications/mark-all-read';

  // Telecaller (not on production API — kept for local/dev fallback)
  static const String telecallerLeads = '$apiPrefix/telecaller/leads';
  static const String telecallerCalls = '$apiPrefix/telecaller/calls';
  static const String telecallerUsers = '$apiPrefix/telecaller/users';
  static const String telecallerBulkDistribute = '$apiPrefix/telecaller/leads/bulk-distribute';
  static const String telecallerBulkDistributeFile = '$apiPrefix/telecaller/leads/bulk-distribute-file';
  static const String telecallerDailyReport = '$apiPrefix/telecaller/calls/daily-report.xlsx';
  static const String telecallerFollowups = '$apiPrefix/telecaller/followups/today';

  // Legacy aliases used by app_provider
  static const String attendanceHistory = attendanceMy;
  static const String gpsPing = gpsLog;
  static const String productCatalog = products;
  static const String saveLead = leads;
  static const String getLeads = leads;
  static const String nearbyLeads = searchOutlets;
  static const String routes = syncPull;
}
