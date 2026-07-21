import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';
import '../constants/api_endpoints.dart';
import '../database/database_helper.dart';
import '../services/field_api_service.dart';
import '../services/business_data_service.dart';
import '../services/organisation_registry.dart';
import '../utils/device_id.dart';
import '../utils/device_location.dart';
import '../utils/geo.dart';
import '../../features/telecaller/data/telecaller_recording_setup.dart';

class AppProvider extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  late final FieldApiService _api = FieldApiService(_apiClient);
  final BusinessDataService _businessData = BusinessDataService();
  final _uuid = const Uuid();
  Timer? _gpsTrackingTimer;
  double? _lastPingLat;
  double? _lastPingLng;

  // Auth State
  bool _isAuthenticated = false;
  /// False until startup session restore / token check finishes. AuthGate waits on this.
  bool _sessionReady = false;
  String? _token;
  String? _refreshToken;
  String? _userId;
  String? _email;
  String? _phone;
  String? _role;
  /// Plain password from last successful login (shown on Management Desk). Cleared on logout.
  String? _loginPassword;
  String? _region;
  /// Tenant org slug from login (`user.org.slug`) — used for AddPhoneBook exemption.
  String? _orgSlug;
  bool _isLoading = false;
  String? _loginError;
  bool _telecallerSetupLoaded = false;
  bool _telecallerSetupComplete = false;

  // Attendance & Break State
  String? _activeAttendanceId;
  String? _attendanceStatus = 'ABSENT'; // LOGGED_IN, CHECKED_OUT, ABSENT
  DateTime? _attendanceStartAt;
  DateTime? _attendanceEndAt;
  double _todayWorkingHours = 0.0;
  Map<String, dynamic>? _activeBreak;
  List<dynamic> _todayBreaks = [];
  int _totalBreakSeconds = 0;
  String _totalBreakFormatted = '00:00';
  Timer? _workingHoursTimer;

  // Route & Plan State
  List<dynamic> _availableRoutes = [];
  List<dynamic> _routeOutlets = [];
  Map<String, dynamic>? _todayPlan;
  List<dynamic> _plannedOutlets = [];
  int _plannedVisitsCount = 0;
  int _completedVisitsCount = 0;
  double _planProgressPercentage = 0.0;

  // GPS & Odometer State
  String _odometerStartPoint = 'HOME'; // HOME, FIRST_OUTLET
  double _totalDistanceCoveredKm = 0.0;
  List<Map<String, dynamic>> _todayGpsRoute = [];

  // Visit Workflow State
  Map<String, dynamic>? _activeVisit;
  List<dynamic> _productCatalog = [];
  List<Map<String, dynamic>> _currentOrderItems = []; // { sku, name, qty, unitPrice }
  double _currentOrderTotal = 0.0;

  // Leads State
  List<dynamic> _nearbyLeads = [];
  List<dynamic> _savedLeads = [];

  // Optimized Route State
  Map<String, dynamic>? _optimizedRoute;

  // Incidents State
  List<dynamic> _userIncidents = [];

  // Admin / Manager Oversight State
  List<dynamic> _adminUsersList = [];
  Map<String, dynamic>? _adminStats;
  List<dynamic> _adminLiveVisitsList = [];
  List<dynamic> _adminLiveGpsList = [];
  int _minimumVisitDurationMinutes = 3;
  bool _selfieRequired = false; // Admin policy; default No
  Timer? _autoVisitTimer;
  String? _dwellOutletId;
  DateTime? _dwellStartedAt;
  Map<String, dynamic>? _lastAutoRegisteredOutlet;

  /// Once-per-day blink selfie for executives entering the field (not login screen).
  String? _dailyFieldSelfieDate;
  String? _dailyFieldSelfieUserId;
  String? _dailyFieldSelfieUrl;

  static const String _prefsDailySelfieDate = 'daily_field_selfie_date';
  static const String _prefsDailySelfieUser = 'daily_field_selfie_user';
  static const String _prefsDailySelfieUrl = 'daily_field_selfie_url';

  // Premium fallback demo routes (for when backend returns empty data)
  final List<Map<String, dynamic>> _demoRoutes = [
    {
      'id': 'route-cp-111',
      'name': 'Connaught Place Central Market Route',
      'region': 'New Delhi Central',
      'outlets': [
        {
          'id': 'outlet-cp-001',
          'name': 'Bikanervala CP Retail',
          'address': 'Radial Road 1, Connaught Place, New Delhi',
          'latitude': 28.6304,
          'longitude': 77.2177,
          'grade': 'A',
          'overallRating': '4.8',
          'visitStatus': 'PENDING',
        },
        {
          'id': 'outlet-cp-002',
          'name': 'Kwality Restaurant Store',
          'address': 'Radial Road 2, Connaught Place, New Delhi',
          'latitude': 28.6320,
          'longitude': 77.2195,
          'grade': 'B',
          'overallRating': '3.9',
          'visitStatus': 'PENDING',
        },
        {
          'id': 'outlet-cp-003',
          'name': 'Modern Pharmacy & Chemist',
          'address': 'Outer Circle, Connaught Place, New Delhi',
          'latitude': 28.6336,
          'longitude': 77.2211,
          'grade': 'A',
          'overallRating': '4.5',
          'visitStatus': 'PENDING',
        }
      ]
    },
    {
      'id': 'route-dw-222',
      'name': 'Dwarka Sector 12 Retail Route',
      'region': 'New Delhi West',
      'outlets': [
        {
          'id': 'outlet-dw-001',
          'name': 'Pinnacle Supermarket',
          'address': 'Sector 12 Market, Dwarka, New Delhi',
          'latitude': 28.5921,
          'longitude': 77.0460,
          'grade': 'A',
          'overallRating': '4.7',
          'visitStatus': 'PENDING',
        },
        {
          'id': 'outlet-dw-002',
          'name': 'Aggarwal Sweets & Provisions',
          'address': 'Sector 12 Main Market, Dwarka, New Delhi',
          'latitude': 28.5928,
          'longitude': 77.0476,
          'grade': 'C',
          'overallRating': '2.8',
          'visitStatus': 'PENDING',
        }
      ]
    },
    {
      'id': 'route-no-333',
      'name': 'Noida Sector 62 Distributors Route',
      'region': 'Delhi NCR East',
      'outlets': [
        {
          'id': 'outlet-no-001',
          'name': 'Krishna Super Store',
          'address': 'Sector 62 Commercial Hub, Noida',
          'latitude': 28.6279,
          'longitude': 77.3649,
          'grade': 'B',
          'overallRating': '3.6',
          'visitStatus': 'PENDING',
        }
      ]
    }
  ];

  // Premium fallback demo catalogs (Module 5 product catalog backup)
  // Getters
  bool get isAuthenticated => _isAuthenticated;
  bool get isSessionReady => _sessionReady;
  bool get isLoading => _isLoading;
  String? get loginError => _loginError;

  Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  String _messageFromApiError(dynamic data) {
    final body = _mapFrom(data);
    final error = _mapFrom(body['error']);
    return error['message']?.toString() ?? body['message']?.toString() ?? '';
  }

  /// True when the string looks like a usable login email (catches typos like `.com.com`).
  static bool isValidLoginEmail(String email) {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !e.contains('@')) return false;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) return false;
    // Common typo: gmail.com.com / example.in.in
    if (RegExp(r'\.(com|in|net|org|co|io)\.\1$').hasMatch(e)) return false;
    return true;
  }

  String _loginFailureMessage(DioException error) {
    final status = error.response?.statusCode;
    final apiMessage = _messageFromApiError(error.response?.data);
    final raw = '${error.message ?? ''} ${error.response?.data ?? ''}'.toLowerCase();
    final apiLower = apiMessage.toLowerCase();
    final code = () {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        return data['error']['code']?.toString();
      }
      return null;
    }();

    if (code == 'SELFIE_REQUIRED' || apiLower.contains('selfie')) {
      return 'SELFIE_REQUIRED';
    }

    if (code == 'DEVICE_LOCKED' || apiLower.contains('already active on another device')) {
      return 'This account is still locked to another device session. '
          'On that phone use Logout (not just close the app). '
          'If the phone is lost, ask platform super_admin to Unlock device / force-logout.';
    }

    if (status == 402 ||
        code == 'SUBSCRIPTION_EXPIRED' ||
        (apiLower.contains('subscription') && apiLower.contains('expired'))) {
      return ApiClient.subscriptionExpiredUserMessage;
    }

    final looksLikeAuthFailure = status == 400 ||
        status == 401 ||
        status == 403 ||
        apiLower.contains('invalid') ||
        apiLower.contains('credential') ||
        apiLower.contains('password') ||
        apiLower.contains('unauthorized') ||
        apiLower.contains('not found') ||
        apiLower.contains('no user') ||
        apiLower.contains('user not') ||
        raw.contains('invalid email') ||
        raw.contains('invalid credentials');

    if (looksLikeAuthFailure) {
      // Prefer a clear credentials message over raw server / network wording.
      if (apiMessage.isNotEmpty &&
          !apiLower.contains('cannot reach') &&
          !apiLower.contains('network') &&
          !apiLower.contains('timeout') &&
          apiLower != 'invalid request.' &&
          apiLower != 'invalid request') {
        return apiMessage;
      }
      return 'Invalid email or password.';
    }

    // Surface Zod field errors instead of the generic "Invalid request."
    if (apiLower == 'invalid request.' || apiLower == 'invalid request' || code == 'VALIDATION_ERROR') {
      final details = () {
        final data = error.response?.data;
        if (data is Map && data['error'] is Map) {
          final fieldErrors = data['error']['details']?['fieldErrors'];
          if (fieldErrors is Map && fieldErrors.isNotEmpty) {
            final first = fieldErrors.entries.first;
            final msgs = first.value;
            final detail = msgs is List && msgs.isNotEmpty ? msgs.first.toString() : msgs.toString();
            return '${first.key}: $detail';
          }
        }
        return null;
      }();
      if (details != null) return 'Login rejected ($details). Please try again.';
    }

    if (status == 502 ||
        status == 503 ||
        status == 504 ||
        raw.contains('bad gateway') ||
        raw.contains('status code of 502') ||
        raw.contains('status code of 503') ||
        raw.contains('status code of 504')) {
      return 'Server is temporarily down (${status ?? 502}). '
          'Cannot reach ${ApiEndpoints.baseUrl} — restart/redeploy the backend, then try again.';
    }
    if (status == 500) {
      return 'Production server error (500). The login API is down — check the backend service.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot reach ${ApiEndpoints.baseUrl}. Check your internet connection.';
    }
    if (apiMessage.isNotEmpty) return apiMessage;
    // Never show raw Dio stack text to the user.
    return 'Login failed (HTTP ${status ?? 'network'}). Please try again.';
  }
  String? get userId => _userId;
  String? get email => _email;
  String? get loginPassword => _loginPassword;
  String? get phone => _phone;
  String? get role => _role;
  String? get region => _region;
  bool get telecallerSetupLoaded => _telecallerSetupLoaded;
  bool get telecallerSetupComplete => _telecallerSetupComplete;

  Future<void> reloadTelecallerSetup() async {
    await TelecallerRecordingSetup.load();
    _telecallerSetupComplete = TelecallerRecordingSetup.isComplete;
    _telecallerSetupLoaded = true;
    notifyListeners();
  }
  String? get activeAttendanceId => _activeAttendanceId;
  String? get attendanceStatus => _attendanceStatus;
  DateTime? get attendanceCheckInAt => _attendanceStartAt;
  DateTime? get attendanceCheckOutAt => _attendanceEndAt;
  double get todayWorkingHours => _todayWorkingHours;
  Map<String, dynamic>? get activeBreak => _activeBreak;
  List<dynamic> get todayBreaks => _todayBreaks;
  String get totalBreakFormatted => _totalBreakFormatted;
  List<dynamic> get availableRoutes => _availableRoutes;
  List<dynamic> get routeOutlets => _routeOutlets;
  Map<String, dynamic>? get todayPlan => _todayPlan;
  List<dynamic> get plannedOutlets => _plannedOutlets;
  List<dynamic> get pendingPlanOutlets {
    final seenNames = <String>{};
    final out = <dynamic>[];
    for (final o in _plannedOutlets) {
      if (o is! Map || o['visitStatus'] == 'COMPLETED') continue;
      final name = (o['name'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final id = o['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        // Prefer id uniqueness among pending
      }
      if (name.isNotEmpty && !seenNames.add(name)) continue;
      out.add(o);
    }
    return out;
  }
  List<dynamic> get visitedPlanOutlets => _plannedOutlets
      .where((o) => o is Map && o['visitStatus'] == 'COMPLETED')
      .toList();

  /// Quick-remark chips used at checkout (keep in sync with Home UI).
  static const List<String> quickRemarkKeywords = [
    'Next Visit',
    'Payment received',
    'Payment pending',
    'Order placed last week',
    'Visit again next week',
  ];

  /// Visited tab: completed visits + next-visit scheduled + any quick remarks.
  List<dynamic> get visitedRemarkOutlets {
    final byId = <String, Map<String, dynamic>>{};
    for (final o in _plannedOutlets) {
      if (o is! Map) continue;
      final map = Map<String, dynamic>.from(o);
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final completed = map['visitStatus'] == 'COMPLETED';
      final hasNext = (map['nextVisitDate']?.toString() ?? '').isNotEmpty &&
          DateTime.tryParse(map['nextVisitDate'].toString()) != null;
      final remarks = (map['visitRemarks'] ?? map['remarks'] ?? '').toString().trim();
      final hasRemarkKeyword = quickRemarkKeywords.any(
        (k) => remarks.toLowerCase().contains(k.toLowerCase()),
      );
      if (completed || hasNext || hasRemarkKeyword || remarks.isNotEmpty) {
        byId[id] = map;
      }
    }
    final list = byId.values.toList();
    list.sort((a, b) {
      final ca = a['visitStatus'] == 'COMPLETED' ? 0 : 1;
      final cb = b['visitStatus'] == 'COMPLETED' ? 0 : 1;
      if (ca != cb) return ca.compareTo(cb);
      return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
    });
    return list;
  }

  /// Filter [visitedRemarkOutlets] by a quick-remark keyword (or next-visit date).
  List<dynamic> visitedOutletsForRemark(String? keyword) {
    final all = visitedRemarkOutlets;
    if (keyword == null || keyword.isEmpty || keyword.toLowerCase() == 'all') {
      return all;
    }
    final key = keyword.toLowerCase();
    return all.where((o) {
      if (o is! Map) return false;
      if (key == 'next visit') {
        final next = o['nextVisitDate']?.toString() ?? '';
        if (next.isNotEmpty && DateTime.tryParse(next) != null) return true;
      }
      final remarks = (o['visitRemarks'] ?? o['remarks'] ?? '').toString().toLowerCase();
      return remarks.contains(key);
    }).toList();
  }

  /// Matched quick-remark labels for an outlet (for blue chips in Visited).
  static List<String> remarkChipsForOutlet(Map<String, dynamic> outlet) {
    final remarks = (outlet['visitRemarks'] ?? outlet['remarks'] ?? '').toString();
    final chips = <String>[];
    for (final k in quickRemarkKeywords) {
      if (remarks.toLowerCase().contains(k.toLowerCase())) {
        chips.add(k);
      }
    }
    final next = outlet['nextVisitDate']?.toString() ?? '';
    if (next.isNotEmpty && DateTime.tryParse(next) != null && !chips.contains('Next Visit')) {
      chips.insert(0, 'Next Visit');
    }
    return chips;
  }
  int get plannedVisitsCount => _plannedVisitsCount;
  int get completedVisitsCount => _completedVisitsCount;
  double get planProgressPercentage => _planProgressPercentage;
  String get odometerStartPoint => _odometerStartPoint;
  double get totalDistanceCoveredKm => _totalDistanceCoveredKm;
  List<Map<String, dynamic>> get todayGpsRoute => _todayGpsRoute;
  Map<String, dynamic>? get activeVisit => _activeVisit;
  List<dynamic> get productCatalog => _productCatalog;
  List<Map<String, dynamic>> get currentOrderItems => _currentOrderItems;
  double get currentOrderTotal => _currentOrderTotal;
  List<dynamic> get nearbyLeads => _nearbyLeads;
  List<dynamic> get savedLeads => _savedLeads;
  Map<String, dynamic>? get optimizedRoute => _optimizedRoute;
  List<dynamic> get userIncidents => _userIncidents;
  List<dynamic> get adminUsersList => _adminUsersList;
  Map<String, dynamic>? get adminStats => _adminStats;

  /// Current org subscription from GET /admin/org or admin stats.
  Map<String, dynamic>? _orgSubscription;
  Map<String, dynamic>? get orgSubscription => _orgSubscription;

  String? get subscriptionStatus =>
      _orgSubscription?['subscription_status']?.toString() ??
      (_adminStats?['org'] is Map
          ? (_adminStats!['org'] as Map)['subscription_status']?.toString()
          : null);

  DateTime? get trialEndsAt {
    final raw = _orgSubscription?['trial_ends_at'] ??
        (_adminStats?['org'] is Map ? (_adminStats!['org'] as Map)['trial_ends_at'] : null);
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  DateTime? get gracePeriodEndsAt {
    final raw = _orgSubscription?['grace_period_ends_at'] ??
        (_adminStats?['org'] is Map ? (_adminStats!['org'] as Map)['grace_period_ends_at'] : null);
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  bool get _isPlatformSuperAdmin =>
      (_role ?? '').toLowerCase() == 'super_admin' ||
      (_role ?? '').toLowerCase() == 'superadmin';

  /// Public for admin UI (force-unlock stuck DEVICE_LOCKED accounts).
  bool get isPlatformSuperAdmin => _isPlatformSuperAdmin;

  /// Platform owner org — never show trial banner or apply client lock.
  bool get _isAddPhoneBookOrg {
    final slug = (_orgSlug ??
            _orgSubscription?['slug']?.toString() ??
            (_adminStats?['org'] is Map ? (_adminStats!['org'] as Map)['slug'] : null) ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (slug == 'addphonebook') return true;
    final email = (_email ?? '').toLowerCase();
    if (email.endsWith('@addphonebook.com')) return true;
    final orgName = (_orgSubscription?['name'] ??
            (_adminStats?['org'] is Map ? (_adminStats!['org'] as Map)['name'] : null) ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return orgName == 'addphonebook';
  }

  /// Super admin + AddPhoneBook members are never gated by trial/grace in the app.
  bool get _isExemptFromSubscriptionGate =>
      _isPlatformSuperAdmin || _isAddPhoneBookOrg;

  static String _fmtSubDate(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$dd/$mm/${local.year}';
  }

  /// True when server stamped grace has passed (client-side helper; server enforces 402).
  bool get isPastGracePeriod {
    if (_isExemptFromSubscriptionGate) return false;
    final end = gracePeriodEndsAt;
    if (end == null) return false;
    return DateTime.now().toUtc().isAfter(end.toUtc());
  }

  bool get isInGracePeriod {
    if (_isExemptFromSubscriptionGate) return false;
    final trial = trialEndsAt;
    final grace = gracePeriodEndsAt;
    if (trial == null || grace == null) return false;
    final now = DateTime.now().toUtc();
    return now.isAfter(trial.toUtc()) && !now.isAfter(grace.toUtc());
  }

  /// Tenant orgs only (not super admin, not AddPhoneBook).
  String? get subscriptionBannerText {
    if (_isExemptFromSubscriptionGate) return null;

    final status = (subscriptionStatus ?? '').toLowerCase();
    final trial = trialEndsAt;
    final grace = gracePeriodEndsAt;
    if (status.isEmpty && trial == null && grace == null) return null;

    if (isPastGracePeriod || status == 'expired' || status == 'suspended') {
      final graceLabel = grace != null ? ' (ended ${_fmtSubDate(grace)})' : '';
      return 'Subscription expired$graceLabel — payment required to restore access.';
    }
    if (isInGracePeriod && grace != null) {
      return 'Grace period — access locks on ${_fmtSubDate(grace)}. '
          'Trial ended ${trial != null ? _fmtSubDate(trial) : 'earlier'}. Pay to continue.';
    }
    if (trial != null && grace != null) {
      return 'Free trial until ${_fmtSubDate(trial)}. '
          'Grace until ${_fmtSubDate(grace)} (access locks after that). '
          'Status: ${subscriptionStatus ?? 'trialing'}';
    }
    if (trial != null) {
      return 'Free trial until ${_fmtSubDate(trial)} (then 3-day grace). '
          'Status: ${subscriptionStatus ?? 'trialing'}';
    }
    if (grace != null) {
      return 'Access until ${_fmtSubDate(grace)}. Status: ${subscriptionStatus ?? 'trialing'}';
    }
    if (status == 'trialing') {
      return 'Free trial active — expiry dates not returned by server yet. Pull to refresh, or ask platform to stamp trial/grace dates.';
    }
    if (status == 'active') return 'Subscription active.';
    return 'Subscription: ${subscriptionStatus ?? 'unknown'}';
  }

  String? _lastApproveSubscriptionSummary;
  String? get lastApproveSubscriptionSummary => _lastApproveSubscriptionSummary;

  /// Clears lock flag set by Dio when API returns 402 SUBSCRIPTION_EXPIRED.
  Future<String?> consumeSubscriptionLockMessage() async {
    // Platform super admin + AddPhoneBook never lock out.
    if (_isExemptFromSubscriptionGate) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('subscription_locked');
      await prefs.remove('subscription_lock_message');
      ApiClient.subscriptionLockedNotifier.value = false;
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('subscription_locked') != true &&
        !ApiClient.subscriptionLockedNotifier.value) {
      return null;
    }
    final msg = prefs.getString('subscription_lock_message') ??
        ApiClient.subscriptionExpiredUserMessage;
    await prefs.remove('subscription_locked');
    await prefs.remove('subscription_lock_message');
    ApiClient.subscriptionLockedNotifier.value = false;
    _token = null;
    _isAuthenticated = false;
    _loginError = msg;
    notifyListeners();
    return msg;
  }

  /// Called when mid-session API returns 402 — drop session and show login.
  Future<void> forceLogoutForExpiredSubscription() async {
    if (_isExemptFromSubscriptionGate) {
      ApiClient.subscriptionLockedNotifier.value = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('subscription_locked');
      await prefs.remove('subscription_lock_message');
      return;
    }
    await consumeSubscriptionLockMessage();
  }
  List<dynamic> get adminLiveVisitsList => _adminLiveVisitsList;
  List<dynamic> get adminLiveGpsList => _adminLiveGpsList;
  int get minimumVisitDurationMinutes => _minimumVisitDurationMinutes;
  bool get selfieRequired => _selfieRequired;
  Map<String, dynamic>? get lastAutoRegisteredOutlet => _lastAutoRegisteredOutlet;
  String? get authToken => _token;

  /// Backend login selfie for executives — once per calendar day (no second dashboard prompt).
  bool get hasCompletedLoginSelfieToday =>
      _isExecutiveRole() &&
      _dailyFieldSelfieDate == _todayDateKey() &&
      _dailyFieldSelfieUserId == _userId;

  /// Cached login selfie URL/data-URI for today (reuse if server asks again same day).
  String? get todaysLoginSelfieUrl {
    if (_dailyFieldSelfieDate != _todayDateKey() ||
        _dailyFieldSelfieUserId != _userId) {
      return null;
    }
    final url = (_dailyFieldSelfieUrl ?? '').trim();
    return url.isEmpty ? null : url;
  }

  @Deprecated('Use hasCompletedLoginSelfieToday')
  bool get hasCompletedDailyFieldSelfieToday => hasCompletedLoginSelfieToday;

  @Deprecated('Dashboard daily selfie removed — login selfie only')
  bool get needsDailyFieldSelfie => false;

  String? get dailyFieldSelfieUrl => _dailyFieldSelfieUrl;

  AppProvider() {
    _loadSavedSession();
  }

  // Load session from SharedPreferences on startup
  Future<void> _loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      _token = prefs.getString('jwt_token');
      _refreshToken = prefs.getString('refresh_token');
      _userId = prefs.getString('user_id');
      _email = prefs.getString('user_email');
      _phone = prefs.getString('user_phone');
      _role = prefs.getString('user_role');
      _loginPassword = prefs.getString('user_login_password');
      _region = prefs.getString('user_region');
      _orgSlug = prefs.getString('user_org_slug');
      _minimumVisitDurationMinutes = prefs.getInt('minimum_visit_duration_minutes') ?? 3;
      _selfieRequired = prefs.getBool('selfie_required') ?? false;
      _dailyFieldSelfieDate = prefs.getString(_prefsDailySelfieDate);
      _dailyFieldSelfieUserId = prefs.getString(_prefsDailySelfieUser);
      _dailyFieldSelfieUrl = prefs.getString(_prefsDailySelfieUrl);

      await TelecallerRecordingSetup.load();
      _telecallerSetupComplete = TelecallerRecordingSetup.isComplete;
      _telecallerSetupLoaded = true;

      // One-time security reset: older installs may still have a leftover JWT (e.g. super_admin).
      // After this build, require an explicit login once; later opens keep that account.
      const secureSessionFlag = 'secure_session_v1';
      if (prefs.getBool(secureSessionFlag) != true) {
        await _clearAuthPrefs(prefs);
        await prefs.setBool(secureSessionFlag, true);
        return;
      }

      // Drop stale demo / local-backend sessions — never auto-login as alpha.com users.
      final savedEmail = (_email ?? '').toLowerCase().trim();
      if (savedEmail.endsWith('@alpha.com') ||
          savedEmail == 'exec@alpha.com' ||
          savedEmail == 'admin@alpha.com' ||
          savedEmail.endsWith('@fieldforce.com')) {
        await _clearAuthPrefs(prefs);
        return;
      }

      // Incomplete / corrupt session → force login (never open a dashboard half-logged-in).
      if (_token == null ||
          _token!.isEmpty ||
          _userId == null ||
          _userId!.isEmpty ||
          _role == null ||
          _role!.isEmpty) {
        await _clearAuthPrefs(prefs);
        return;
      }

      // Verify JWT with the server before trusting a restored session (security).
      final valid = await _validateStoredSession();
      if (!valid) {
        await _clearAuthPrefs(prefs);
        return;
      }

      _isAuthenticated = true;
      notifyListeners();
      await fetchFieldSettings();

      if (_role?.toUpperCase() == 'TELECALLER') {
        // no-op
      } else if (_isAdminRole()) {
        fetchAdminDashboardData();
      } else {
        await _restoreTodayPlanFromLocal();
        await _restoreLocalAttendance();
        await _restoreTodayBreaksFromLocal();
        await _restoreTodayDistance();
        await _recomputeTodayDistanceFromLocalGps();
        // Re-ask / refresh GPS on app reopen so tracking continues for executives.
        final access = await DeviceLocation.ensureAccess();
        if (access == LocationAccessResult.granted) {
          final pos = await DeviceLocation.resolvePosition(
            timeLimit: const Duration(seconds: 10),
            requestIfNeeded: false,
          );
          if (pos != null) {
            await recordGpsPing(pos.latitude, pos.longitude, _odometerStartPoint, address: 'Session resume');
          }
        }
        fetchTodayLiveSummary();
        fetchAvailableRoutes();
        fetchTodayPlan();
        restoreActiveVisitFromLocalDb();
        fetchProductCatalog();
        fetchSavedLeads();
        fetchUserIncidents();
        startContinuousGpsTracking();
      }
    } finally {
      _sessionReady = true;
      notifyListeners();
    }
  }

  Future<void> _clearAuthPrefs(SharedPreferences prefs) async {
    await prefs.remove('jwt_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('user_email');
    await prefs.remove('user_phone');
    await prefs.remove('user_role');
    await prefs.remove('user_region');
    await prefs.remove('user_org_slug');
    await prefs.remove('user_login_password');
    _token = null;
    _refreshToken = null;
    _userId = null;
    _email = null;
    _phone = null;
    _role = null;
    _loginPassword = null;
    _region = null;
    _orgSlug = null;
    _isAuthenticated = false;
  }

  /// Confirms the stored JWT is still accepted by production before auto-entering the app.
  Future<bool> _validateStoredSession() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.authMe);
      final status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        return false;
      }
      if (status >= 200 && status < 300) {
        final data = _responseData(response);
        final user = _mapFrom(data['user']).isNotEmpty ? _mapFrom(data['user']) : data;
        if (user.isNotEmpty) {
          final id = user['id']?.toString();
          final email = user['email']?.toString();
          final role = user['role']?.toString();
          final phone = user['phone']?.toString();
          final prefs = await SharedPreferences.getInstance();
          if (id != null && id.isNotEmpty) {
            _userId = id;
            await prefs.setString('user_id', id);
          }
          if (email != null && email.isNotEmpty) {
            _email = email;
            await prefs.setString('user_email', email);
          }
          if (role != null && role.isNotEmpty) {
            _role = role;
            await prefs.setString('user_role', role);
          }
          if (phone != null) {
            _phone = phone;
            await prefs.setString('user_phone', phone);
          }
          final org = _mapFrom(user['org']);
          final slug = org['slug']?.toString();
          if (slug != null && slug.isNotEmpty) {
            _orgSlug = slug;
            await prefs.setString('user_org_slug', slug);
          }
        }
        return _userId != null && _role != null && _token != null;
      }
      // /auth/me not available (404) — allow resume only with a complete local session.
      return _token != null &&
          _token!.isNotEmpty &&
          _userId != null &&
          _role != null;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) return false;
      // Offline / timeouts: keep last good session for field use.
      return _token != null &&
          _token!.isNotEmpty &&
          _userId != null &&
          _role != null;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _responseData(Response response) {
    final body = _mapFrom(response.data);
    final nested = _mapFrom(body['data']);
    return nested.isNotEmpty ? nested : body;
  }

  List<dynamic> _responseList(Response response, [String? key]) {
    final body = _mapFrom(response.data);
    final nested = body['data'] is Map ? _mapFrom(body['data']) : <String, dynamic>{};

    List<dynamic>? asList(dynamic v) => v is List ? v : null;

    if (key != null) {
      final keyed = asList(body[key]) ?? asList(nested[key]);
      if (keyed != null) return keyed;
    }
    return asList(body['data']) ??
        asList(nested['users']) ??
        asList(body['users']) ??
        asList(body['routes']) ??
        asList(nested['routes']) ??
        asList(body['outlets']) ??
        asList(nested['outlets']) ??
        asList(body['products']) ??
        asList(nested['products']) ??
        asList(body['incidents']) ??
        asList(nested['incidents']) ??
        asList(body['leads']) ??
        asList(nested['leads']) ??
        const [];
  }

  bool _isAdminRole([String? role]) {
    final r = (role ?? _role ?? '').toLowerCase();
    return r == 'super_admin' ||
        r == 'admin' ||
        r == 'manager' ||
        r == 'super_admin' ||
        r == 'regional_manager' ||
        r == 'sales_manager' ||
        r == 'superadmin';
  }

  bool _isExecutiveRole([String? role]) {
    final r = (role ?? _role ?? '').toLowerCase();
    return r == 'executive' || r == 'sales_executive';
  }

  /// Platform super-admins (e.g. Lakshmiraj) must never appear in org Team/Logs.
  bool _isHiddenFromOrgActivity({
    String? role,
    String? name,
    String? email,
  }) {
    final r = (role ?? '').toLowerCase().trim();
    if (r == 'super_admin' || r == 'superadmin') return true;
    final blob = '${name ?? ''} ${email ?? ''}'.toLowerCase();
    if (blob.contains('lakshmiraj')) return true;
    return false;
  }

  static const String dailyLoginOutletName = 'Daily Field Login';
  static const String dailyLoginNotesPrefix = 'DAILY_FIELD_LOGIN';

  bool _isSystemDailyLoginOutlet(Map outlet) {
    final name = (outlet['name'] ?? '').toString().trim().toLowerCase();
    return name == dailyLoginOutletName.toLowerCase();
  }

  /// Product catalog mutations require org admin on the API (not manager).
  bool get canManageProductCatalog {
    final r = (_role ?? '').toLowerCase();
    return r == 'admin';
  }

  bool get isManagerRole {
    final r = (_role ?? '').toLowerCase();
    return r == 'manager' || r == 'sales_manager' || r == 'regional_manager';
  }

  // 1. Authentication Methods
  Future<bool> login(
    String emailOrPhone,
    String password,
    String deviceId, {
    String? loginSelfieUrl,
    String? orgSlug,
  }) async {
    _isLoading = true;
    _loginError = null;
    notifyListeners();

    try {
      final isEmail = emailOrPhone.contains('@');
      if (isEmail && !isValidLoginEmail(emailOrPhone)) {
        _loginError = 'Invalid email address. Check for typos (e.g. .com.com).';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final resolvedDeviceId = deviceId.isNotEmpty ? deviceId : await DeviceId.get();
      final response = await _api.login(
        password: password,
        email: isEmail ? emailOrPhone.trim() : null,
        phone: isEmail ? null : emailOrPhone.trim(),
        deviceId: resolvedDeviceId,
        orgSlug: (orgSlug != null && orgSlug.trim().isNotEmpty) ? orgSlug.trim() : null,
        loginSelfieUrl: loginSelfieUrl,
      );

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        final payload = _responseData(response);
        final user = _mapFrom(payload['user']);

        _token = payload['access_token']?.toString() ?? payload['token']?.toString();
        _refreshToken = payload['refresh_token']?.toString() ?? payload['refreshToken']?.toString();
        _userId = user['id']?.toString();
        _email = user['email']?.toString();
        _phone = user['phone']?.toString();
        _role = user['role']?.toString();
        _region = user['org_id']?.toString() ??
            _mapFrom(user['org'])['id']?.toString() ??
            user['region']?.toString();
        _orgSlug = _mapFrom(user['org'])['slug']?.toString() ??
            (orgSlug != null && orgSlug.trim().isNotEmpty ? orgSlug.trim().toLowerCase() : null);

        if (_token == null || _userId == null || _role == null) {
          throw Exception('Invalid login response from server');
        }

        await prefs.setString('jwt_token', _token!);
        if (_refreshToken != null && _refreshToken!.isNotEmpty) {
          await prefs.setString('refresh_token', _refreshToken!);
        } else {
          await prefs.remove('refresh_token');
        }
        await prefs.setString('user_id', _userId!);
        if (_email != null) await prefs.setString('user_email', _email!);
        if (_phone != null) await prefs.setString('user_phone', _phone!);
        await prefs.setString('user_role', _role!);
        _loginPassword = password;
        await prefs.setString('user_login_password', password);
        if (_region != null) await prefs.setString('user_region', _region!);
        if (_orgSlug != null && _orgSlug!.isNotEmpty) {
          await prefs.setString('user_org_slug', _orgSlug!);
        } else {
          await prefs.remove('user_org_slug');
        }
        await prefs.setString('device_fingerprint', resolvedDeviceId);

        await TelecallerRecordingSetup.load();
        _telecallerSetupComplete = TelecallerRecordingSetup.isComplete;
        _telecallerSetupLoaded = true;

        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();
        await fetchFieldSettings();

        if (_role?.toUpperCase() == 'TELECALLER') {
          // Telecaller loads its own data
        } else if (_isAdminRole()) {
          // Platform/org admins: no GPS / attendance check-in at login.
          fetchAdminDashboardData();
        } else {
          // Field executive: require real GPS, start attendance + continuous tracking.
          final access = await DeviceLocation.ensureAccess();
          if (access != LocationAccessResult.granted) {
            _loginError = 'Location permission is required for executive login. Allow Location and try again.';
            await _abortAuthenticatedSession(
              deviceId: resolvedDeviceId,
              reason: 'location_denied',
            );
            _isLoading = false;
            notifyListeners();
            return false;
          }

          final pos = await DeviceLocation.resolvePosition(
            timeLimit: const Duration(seconds: 12),
            requestIfNeeded: false,
          );
          if (pos == null) {
            _loginError = 'Could not read GPS. Turn on Location and try login again.';
            await _abortAuthenticatedSession(
              deviceId: resolvedDeviceId,
              reason: 'gps_unavailable',
            );
            _isLoading = false;
            notifyListeners();
            return false;
          }

          try {
            await _api.checkInAttendance(latitude: pos.latitude, longitude: pos.longitude);
          } catch (e) {
            print('Attendance check-in failed: $e');
          }

          String? address;
          try {
            // Lightweight reverse lookup for admin Logs display.
            final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
            if (places.isNotEmpty) {
              final p = places.first;
              address = [
                p.name,
                p.subLocality,
                p.locality,
                p.administrativeArea,
              ].where((s) => (s ?? '').toString().trim().isNotEmpty).join(', ');
            }
          } catch (_) {}

          await recordGpsPing(
            pos.latitude,
            pos.longitude,
            _odometerStartPoint,
            address: address?.isNotEmpty == true ? address : 'Login location',
          );

          _startAttendanceClock(DateTime.now().toUtc());
          await _restoreTodayPlanFromLocal();
          await _restoreTodayDistance();
          await _recomputeTodayDistanceFromLocalGps();
          fetchTodayLiveSummary();
          fetchAvailableRoutes();
          fetchTodayPlan();
          fetchProductCatalog();
          fetchSavedLeads();
          fetchUserIncidents();
          startContinuousGpsTracking();
        }

        return true;
      }

      _loginError = 'Unexpected server response (${response.statusCode}).';
    } on DioException catch (e) {
      _loginError = _loginFailureMessage(e);
      print('Login failed: $_loginError');
    } catch (e) {
      _loginError = e.toString().replaceFirst('Exception: ', '');
      print('Login failed: $_loginError');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout(String deviceId) async {
    _isLoading = true;
    notifyListeners();

    stopContinuousGpsTracking();

    final prefs = await SharedPreferences.getInstance();
    final resolvedDeviceId = deviceId.isNotEmpty
        ? deviceId
        : (prefs.getString('device_fingerprint') ?? await DeviceId.get());
    final refresh = _refreshToken ?? prefs.getString('refresh_token');

    // Close attendance + revoke device session BEFORE clearing local JWT.
    _lastActionError = null;
    await checkOutAttendance(endDayOnly: true);
    try {
      await _api.logout(resolvedDeviceId, refreshToken: refresh);
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ??
          'Production logout failed. The local session was cleared, but this device may still be locked on the server.';
      print('Production logout failed: $_lastActionError');
    } catch (e) {
      _lastActionError =
          'Production logout failed. The local session was cleared, but this device may still be locked on the server.';
      print('Production logout failed: $e');
    }

    // Clear local session regardless of API success (failsafe).
    // Keep telecaller OEM folder link so agents do not re-onboard every login.
    await TelecallerRecordingSetup.load();
    final keepComplete = TelecallerRecordingSetup.isComplete;
    final keepPath = TelecallerRecordingSetup.folderPath;
    final keepLabel = TelecallerRecordingSetup.folderLabel;
    final keepLastPath = TelecallerRecordingSetup.lastUploadedPath;
    final keepLastMs = TelecallerRecordingSetup.lastUploadedModifiedMs;

    // Preserve organisation registration vault across logout (super-admin needs history).
    final orgRegistry = prefs.getString(OrganisationRegistry.prefsKey);
    // Keep once-per-day field selfie so re-login same day does not re-ask.
    final keepSelfieDate = prefs.getString(_prefsDailySelfieDate);
    final keepSelfieUser = prefs.getString(_prefsDailySelfieUser);
    final keepSelfieUrl = prefs.getString(_prefsDailySelfieUrl);
    // Keep one-time security migration flag so logout does not force wipe on next cold start.
    const secureSessionFlag = 'secure_session_v1';
    final keepSecureFlag = prefs.getBool(secureSessionFlag) == true;
    await prefs.clear();
    if (orgRegistry != null && orgRegistry.isNotEmpty) {
      await prefs.setString(OrganisationRegistry.prefsKey, orgRegistry);
    }
    if (keepSelfieDate != null && keepSelfieDate.isNotEmpty) {
      await prefs.setString(_prefsDailySelfieDate, keepSelfieDate);
    }
    if (keepSelfieUser != null && keepSelfieUser.isNotEmpty) {
      await prefs.setString(_prefsDailySelfieUser, keepSelfieUser);
    }
    if (keepSelfieUrl != null && keepSelfieUrl.isNotEmpty) {
      await prefs.setString(_prefsDailySelfieUrl, keepSelfieUrl);
    }
    if (keepSecureFlag) {
      await prefs.setBool(secureSessionFlag, true);
    }
    _dailyFieldSelfieDate = keepSelfieDate;
    _dailyFieldSelfieUserId = keepSelfieUser;
    _dailyFieldSelfieUrl = keepSelfieUrl;
    await TelecallerRecordingSetup.reset();

    if (keepPath != null && keepPath.isNotEmpty) {
      await TelecallerRecordingSetup.setFolderPath(
        path: keepPath,
        displayName: keepLabel,
      );
    }
    if (keepLastPath != null && keepLastMs != null) {
      await TelecallerRecordingSetup.markLastUploaded(keepLastPath, keepLastMs);
    }
    if (keepComplete) {
      await TelecallerRecordingSetup.markComplete();
    }
    _telecallerSetupComplete = TelecallerRecordingSetup.isComplete;
    _telecallerSetupLoaded = true;

    _isAuthenticated = false;
    _token = null;
    _refreshToken = null;
    _userId = null;
    _email = null;
    _phone = null;
    _role = null;
    _loginPassword = null;
    _region = null;
    _activeAttendanceId = null;
    _attendanceStatus = 'ABSENT';
    _attendanceStartAt = null;
    _attendanceEndAt = null;
    _todayWorkingHours = 0.0;
    _activeBreak = null;
    _todayBreaks = [];
    _totalBreakSeconds = 0;
    _totalBreakFormatted = '00:00';
    _workingHoursTimer?.cancel();

    // Clear route and workflow states
    _availableRoutes = [];
    _routeOutlets = [];
    _todayPlan = null;
    _plannedOutlets = [];
    _plannedVisitsCount = 0;
    _completedVisitsCount = 0;
    _planProgressPercentage = 0.0;
    _totalDistanceCoveredKm = 0.0;
    _todayGpsRoute = [];
    _activeVisit = null;
    _productCatalog = [];
    _currentOrderItems = [];
    _currentOrderTotal = 0.0;
    _nearbyLeads = [];
    _savedLeads = [];
    _optimizedRoute = null;
    _userIncidents = [];
    stopAutoVisitMonitoring();
    _lastAutoRegisteredOutlet = null;
    await _clearTodayPlanFromLocal();

    _isLoading = false;
    notifyListeners();
  }

  // 2. Attendance & Break Management
  String _todayDateKey() => DateTime.now().toLocal().toIso8601String().substring(0, 10);

  void _recalculateBreakFormatted() {
    if (_totalBreakSeconds < 3600) {
      final mins = _totalBreakSeconds ~/ 60;
      final secs = _totalBreakSeconds % 60;
      _totalBreakFormatted = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      return;
    }
    final hrs = _totalBreakSeconds ~/ 3600;
    final mins = (_totalBreakSeconds % 3600) ~/ 60;
    _totalBreakFormatted = '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }

  Future<void> _persistLocalAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayDateKey();
    await prefs.setString('local_attendance_date', today);
    if (_attendanceStartAt != null) {
      await prefs.setString('local_attendance_check_in', _attendanceStartAt!.toIso8601String());
    }
    if (_attendanceEndAt != null) {
      await prefs.setString('local_attendance_check_out', _attendanceEndAt!.toIso8601String());
    } else {
      await prefs.remove('local_attendance_check_out');
    }
    await prefs.setString('local_attendance_status', _attendanceStatus ?? 'ABSENT');
  }

  Future<void> _restoreLocalAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('local_attendance_date');
    if (savedDate != _todayDateKey()) {
      await _clearLocalAttendance();
      return;
    }

    final checkInStr = prefs.getString('local_attendance_check_in');
    if (checkInStr == null) return;

    _attendanceStartAt = DateTime.parse(checkInStr).toUtc();
    final checkOutStr = prefs.getString('local_attendance_check_out');
    final savedStatus = prefs.getString('local_attendance_status');

    if (checkOutStr != null || savedStatus == 'CHECKED_OUT') {
      _attendanceEndAt = checkOutStr != null ? DateTime.parse(checkOutStr).toUtc() : null;
      _attendanceStatus = 'CHECKED_OUT';
      _workingHoursTimer?.cancel();
      if (_attendanceEndAt != null) {
        _todayWorkingHours = _attendanceEndAt!.difference(_attendanceStartAt!).inSeconds / 3600.0;
      }
      return;
    }

    _attendanceEndAt = null;
    _startAttendanceClock(_attendanceStartAt!, persist: false);
  }

  Future<void> _clearLocalAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_attendance_date');
    await prefs.remove('local_attendance_check_in');
    await prefs.remove('local_attendance_check_out');
    await prefs.remove('local_attendance_status');
  }

  Future<void> _restoreTodayBreaksFromLocal() async {
    final today = _todayDateKey();
    final rows = await DatabaseHelper.instance.queryAll(
      'offline_breaks',
      where: 'break_date = ?',
      whereArgs: [today],
    );

    _todayBreaks = [];
    _totalBreakSeconds = 0;
    _activeBreak = null;

    for (final row in rows) {
      final breakMap = {
        'id': row['id'],
        'breakType': row['break_type'],
        'startTime': row['start_time'],
        'endTime': row['end_time'],
      };
      _todayBreaks.add(breakMap);

      final duration = int.tryParse(row['duration_seconds']?.toString() ?? '') ?? 0;
      if (row['end_time'] == null) {
        _activeBreak = breakMap;
      } else {
        _totalBreakSeconds += duration;
      }
    }
    _recalculateBreakFormatted();
  }

  Future<void> fetchTodayLiveSummary() async {
    if (_userId == null) return;

    try {
      final response = await _api.attendanceToday(_userId!);
      if (response.statusCode == 200) {
        final data = _mapFrom(response.data);
        _activeAttendanceId = data['attendanceId']?.toString();
        final status = data['status']?.toString();

        if (data['loginTime'] != null) {
          _attendanceStartAt = DateTime.parse(data['loginTime'].toString()).toUtc();
        }

        if (status == 'LOGGED_OUT' || data['logoutTime'] != null) {
          if (data['logoutTime'] != null) {
            _attendanceEndAt = DateTime.parse(data['logoutTime'].toString()).toUtc();
          }
          _attendanceStatus = 'CHECKED_OUT';
          _workingHoursTimer?.cancel();
          _todayWorkingHours =
              double.tryParse(data['totalWorkingHours']?.toString() ?? '') ?? _todayWorkingHours;
        } else if (status == 'LOGGED_IN' || status == 'PRESENT' || data['loginTime'] != null) {
          _attendanceEndAt = null;
          _startAttendanceClock(_attendanceStartAt ?? DateTime.now().toUtc(), persist: false);
          startContinuousGpsTracking();
        } else {
          await _restoreLocalAttendance();
        }

        final activeBreak = data['activeBreak'];
        if (activeBreak is Map) {
          _activeBreak = {
            'id': activeBreak['id'],
            'breakType': activeBreak['breakType'],
            'startTime': activeBreak['breakStartTime']?.toString() ??
                activeBreak['startTime']?.toString(),
          };
        }

        await _persistLocalAttendance();
      } else {
        await _restoreLocalAttendance();
      }
    } catch (e) {
      print('Fetch today summary failed: $e');
      await _restoreLocalAttendance();
    }

    await _restoreTodayBreaksFromLocal();
    notifyListeners();
  }

  Future<bool> checkOutAttendance({bool endDayOnly = false}) async {
    if (_attendanceStatus != 'LOGGED_IN' && _attendanceStatus != 'PRESENT') {
      // Still try server check-out when ending day from logout (status may be stale).
      if (!endDayOnly) return false;
    }

    if (_activeBreak != null) {
      await endBreakSession();
    }

    try {
      double lat = 0;
      double lng = 0;
      final pos = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 4));
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
      }
      await _api.checkOutAttendance(latitude: lat, longitude: lng);
    } catch (e) {
      print('Production attendance check-out: $e');
    }

    final now = DateTime.now().toUtc();
    _attendanceEndAt = now;
    _attendanceStatus = 'CHECKED_OUT';
    _workingHoursTimer?.cancel();

    if (_attendanceStartAt != null) {
      _todayWorkingHours = now.difference(_attendanceStartAt!).inSeconds / 3600.0;
      if (_todayWorkingHours < 0) _todayWorkingHours = 0.0;
    }

    await _persistLocalAttendance();
    notifyListeners();
    return true;
  }

  /// Login succeeded on server but client cannot continue (no GPS, etc.).
  /// Must revoke the device session or the account stays DEVICE_LOCKED.
  Future<void> _abortAuthenticatedSession({
    required String deviceId,
    required String reason,
  }) async {
    print('Aborting authenticated session ($reason) — revoking server device lock');
    final prefs = await SharedPreferences.getInstance();
    final refresh = _refreshToken ?? prefs.getString('refresh_token');
    try {
      await _api.checkOutAttendance(latitude: 0, longitude: 0);
    } catch (_) {}
    try {
      await _api.logout(deviceId, refreshToken: refresh);
    } catch (e) {
      print('Abort logout failed: $e');
    }
    _isAuthenticated = false;
    _token = null;
    _refreshToken = null;
    await prefs.remove('jwt_token');
    await prefs.remove('refresh_token');
    notifyListeners();
  }

  /// Super-admin: unlock a stuck DEVICE_LOCKED account so they can sign in again.
  Future<bool> forceLogoutUser(String userId) async {
    _lastActionError = null;
    try {
      final ok = await _api.adminForceLogout(userId);
      if (ok) {
        await fetchAdminUsersList();
        await fetchAdminLiveVisitsList();
      } else {
        _lastActionError = 'Production force-logout failed. Check that this account has super_admin permission.';
      }
      return ok;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ??
          'Production force-logout failed. Check that this account has super_admin permission.';
      print('forceLogoutUser failed: $_lastActionError');
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      print('forceLogoutUser failed: $_lastActionError');
      return false;
    }
  }

  /// Login-screen emergency unlock for DEVICE_LOCKED users.
  /// Uses a temporary production super-admin token, then clears it so the app
  /// stays on the login screen.
  Future<bool> emergencyForceLogoutWithSuperAdmin({
    required String superAdminEmail,
    required String superAdminPassword,
    required String targetEmailOrUserId,
    String? orgSlug,
  }) async {
    _lastActionError = null;
    final target = targetEmailOrUserId.trim();
    if (target.isEmpty) {
      _lastActionError = 'Enter the locked user email or user id.';
      return false;
    }

    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final previousToken = prefs.getString('jwt_token');
    final previousRefresh = prefs.getString('refresh_token');
    final previousUserId = prefs.getString('user_id');
    final previousEmail = prefs.getString('user_email');
    final previousPhone = prefs.getString('user_phone');
    final previousRole = prefs.getString('user_role');
    final previousRegion = prefs.getString('user_region');
    final previousOrgSlug = prefs.getString('user_org_slug');
    final previousPassword = prefs.getString('user_login_password');
    String? tempDeviceId;
    String? tempRefresh;

    try {
      final deviceId = 'super-admin-unlock-${DateTime.now().millisecondsSinceEpoch}';
      tempDeviceId = deviceId;
      final loginResponse = await _api.login(
        password: superAdminPassword,
        email: superAdminEmail.trim(),
        deviceId: deviceId,
        orgSlug: (orgSlug != null && orgSlug.trim().isNotEmpty) ? orgSlug.trim() : null,
      );
      final payload = _responseData(loginResponse);
      final token = payload['access_token']?.toString() ?? payload['token']?.toString();
      final refresh = payload['refresh_token']?.toString() ?? payload['refreshToken']?.toString();
      if (token == null || token.isEmpty) {
        _lastActionError = 'Super-admin login did not return a token.';
        return false;
      }

      await prefs.setString('jwt_token', token);
      if (refresh != null && refresh.isNotEmpty) {
        tempRefresh = refresh;
        await prefs.setString('refresh_token', refresh);
      } else {
        await prefs.remove('refresh_token');
      }

      var targetUserId = target;
      final uuidLike = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(target);
      if (!uuidLike) {
        final knownAddPhoneBookIds = <String, String>{
          'lakshmiraj@addphonebook.com': '00000000-0000-4000-a000-000000000001',
          'rajesh.kumar@addphonebook.com': '00000000-0000-4000-a000-000000000011',
          'farhan@addphonebook.com': '00000000-0000-4000-a000-000000000014',
        };
        targetUserId = knownAddPhoneBookIds[target.toLowerCase()] ?? '';

        if (targetUserId.isEmpty) {
          try {
            final users = await _api.production.adminUsers();
            Map<String, dynamic>? match;
            for (final user in users) {
              final email = (user['email'] ?? '').toString().trim().toLowerCase();
              final phone = (user['phone'] ?? '').toString().trim();
              if (email == target.toLowerCase() || phone == target) {
                match = user;
                break;
              }
            }
            targetUserId = match?['id']?.toString() ?? '';
          } on DioException catch (e) {
            final msg = ApiClient.errorMessage(e) ?? '';
            if (e.response?.statusCode == 403 || msg.toLowerCase().contains('requires role')) {
              _lastActionError =
                  'Production blocked user lookup for super_admin. Paste the locked user id instead of email.';
              return false;
            }
            rethrow;
          }
        }

        if (targetUserId.isEmpty) {
          _lastActionError =
              'Could not find that user in production. Enter the exact user id instead of email.';
          return false;
        }
      }

      if (targetUserId.isEmpty) {
        _lastActionError = 'Could not resolve locked user id.';
        return false;
      }

      final ok = await _api.adminForceLogout(targetUserId);
      if (!ok) {
        _lastActionError = 'Production force-logout failed for this user.';
        return false;
      }
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ??
          'Unlock failed. Check super-admin credentials and production permissions.';
      return false;
    } catch (e) {
      _lastActionError = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      if (tempDeviceId != null) {
        try {
          await _api.logout(tempDeviceId!, refreshToken: tempRefresh);
        } catch (_) {}
      }
      if (previousToken != null && previousToken.isNotEmpty) {
        await prefs.setString('jwt_token', previousToken);
      } else {
        await prefs.remove('jwt_token');
      }
      if (previousRefresh != null && previousRefresh.isNotEmpty) {
        await prefs.setString('refresh_token', previousRefresh);
      } else {
        await prefs.remove('refresh_token');
      }
      if (previousUserId != null) await prefs.setString('user_id', previousUserId);
      if (previousEmail != null) await prefs.setString('user_email', previousEmail);
      if (previousPhone != null) await prefs.setString('user_phone', previousPhone);
      if (previousRole != null) await prefs.setString('user_role', previousRole);
      if (previousRegion != null) await prefs.setString('user_region', previousRegion);
      if (previousOrgSlug != null) await prefs.setString('user_org_slug', previousOrgSlug);
      if (previousPassword != null) await prefs.setString('user_login_password', previousPassword);

      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> checkInAttendance(double lat, double lng, {double accuracy = 8.5}) async {
    try {
      final result = await _api.checkInAttendance(latitude: lat, longitude: lng);
      if (result != null && result['id'] != null) {
        _activeAttendanceId = result['id'].toString();
      }
    } catch (e) {
      print('Production attendance check-in: $e');
    }
    if (_attendanceStatus != 'LOGGED_IN' && _attendanceStatus != 'PRESENT') {
      _startAttendanceClock(DateTime.now().toUtc());
    }
    await fetchTodayLiveSummary();
    startContinuousGpsTracking();
    return true;
  }

  /// Server already accepted login without asking for selfie (done for today on backend).
  Future<void> markLoginSelfieSatisfiedByServer() async {
    if (!_isExecutiveRole() || _userId == null) return;
    _dailyFieldSelfieDate = _todayDateKey();
    _dailyFieldSelfieUserId = _userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDailySelfieDate, _dailyFieldSelfieDate!);
    await prefs.setString(_prefsDailySelfieUser, _userId!);
    notifyListeners();
    // Still publish today's login activity when we have a selfie URL from earlier today.
    final existing = todaysLoginSelfieUrl ?? _dailyFieldSelfieUrl;
    if (existing != null && existing.isNotEmpty) {
      await finalizeLoginSelfieForToday(selfieDataUrl: existing);
    }
  }

  /// After backend accepts login selfie: mark once-per-day and publish to admin Logs.
  /// Does not open the camera again — uses [localSelfiePath] or [selfieDataUrl] from login.
  Future<void> finalizeLoginSelfieForToday({
    String? localSelfiePath,
    String? selfieDataUrl,
  }) async {
    if (!_isExecutiveRole() || _userId == null) return;

    String remoteSelfie = '';
    if (localSelfiePath != null && localSelfiePath.isNotEmpty) {
      remoteSelfie = await _resolveSelfieUrl(localSelfiePath);
    } else if (selfieDataUrl != null && selfieDataUrl.trim().isNotEmpty) {
      remoteSelfie = await _resolveSelfieUrl(selfieDataUrl.trim());
    } else if ((_dailyFieldSelfieUrl ?? '').isNotEmpty) {
      remoteSelfie = await _resolveSelfieUrl(_dailyFieldSelfieUrl!);
    }

    final todayKey = _todayDateKey();

    _dailyFieldSelfieDate = todayKey;
    _dailyFieldSelfieUserId = _userId;
    if (remoteSelfie.isNotEmpty) {
      _dailyFieldSelfieUrl = remoteSelfie;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsDailySelfieDate, _dailyFieldSelfieDate!);
    await prefs.setString(_prefsDailySelfieUser, _userId!);
    if (remoteSelfie.isNotEmpty) {
      await prefs.setString(_prefsDailySelfieUrl, remoteSelfie);
    }
    notifyListeners();

    // Avoid duplicate daily-login visits on re-login the same day.
    final publishedKey = 'daily_login_published_${todayKey}_$_userId';
    if (prefs.getBool(publishedKey) == true) {
      return;
    }

    final selfieForPublish = remoteSelfie.isNotEmpty ? remoteSelfie : 'auto-detected';

    // Publish once to visits so admin Logs can show today's login selfie / activity.
    try {
      double lat = 0;
      double lng = 0;
      String? address;
      final pos = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 8));
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
        try {
          final places = await placemarkFromCoordinates(lat, lng);
          if (places.isNotEmpty) {
            final p = places.first;
            address = [
              p.name,
              p.subLocality,
              p.locality,
              p.administrativeArea,
            ].where((s) => (s ?? '').toString().trim().isNotEmpty).join(', ');
          }
        } catch (_) {}
      }
      await _publishDailyLoginActivity(
        latitude: lat,
        longitude: lng,
        address: address,
        selfieUrl: selfieForPublish,
      );
      await prefs.setBool(publishedKey, true);
    } catch (e) {
      print('finalizeLoginSelfieForToday publish skipped: $e');
    }
  }

  /// @deprecated Use [finalizeLoginSelfieForToday] — local second selfie prompt removed.
  Future<bool> completeDailyFieldSelfie(String localSelfiePath) async {
    await finalizeLoginSelfieForToday(localSelfiePath: localSelfiePath);
    return true;
  }

  /// Creates/reuses a system outlet and records start+end visit with daily selfie.
  Future<void> _publishDailyLoginActivity({
    required double latitude,
    required double longitude,
    String? address,
    required String selfieUrl,
  }) async {
    try {
      String? outletId;
      try {
        final outlets = await _api.production.outlets();
        for (final o in outlets) {
          final name = (o['name'] ?? '').toString().trim().toLowerCase();
          if (name == dailyLoginOutletName.toLowerCase()) {
            outletId = o['id']?.toString();
            break;
          }
        }
      } catch (_) {}

      if (outletId == null || outletId.isEmpty) {
        final created = await _api.production.createOutlet({
          'name': dailyLoginOutletName,
          'address': 'System · daily executive login & selfie',
          'latitude': latitude,
          'longitude': longitude,
          'type': 'other',
        });
        outletId = created?['id']?.toString();
      }
      if (outletId == null || outletId.isEmpty) return;

      final notes =
          '$dailyLoginNotesPrefix|place=${address ?? 'Field start'}';
      final visit = await _api.production.visitStart(
        outletId: outletId,
        latitude: latitude,
        longitude: longitude,
        notes: notes,
        selfieUrl: selfieUrl,
      );
      final visitId = visit['id']?.toString();
      if (visitId != null && visitId.isNotEmpty) {
        await _api.production.visitEnd(
          visitId: visitId,
          latitude: latitude,
          longitude: longitude,
          outcome: 'completed',
          notes: notes,
        );
      }
    } catch (e) {
      print('Publish daily login activity failed (local selfie still saved): $e');
    }
  }

  void _startAttendanceClock(DateTime checkInAt, {bool persist = true}) {
    _attendanceStartAt = checkInAt.toUtc();
    _attendanceEndAt = null;
    _attendanceStatus = 'LOGGED_IN';
    _workingHoursTimer?.cancel();

    void updateHours() {
      final now = DateTime.now().toUtc();
      _todayWorkingHours = now.difference(_attendanceStartAt!).inSeconds / 3600.0;
      if (_todayWorkingHours < 0) _todayWorkingHours = 0.0;
      notifyListeners();
    }

    updateHours();
    _workingHoursTimer = Timer.periodic(const Duration(seconds: 30), (_) => updateHours());

    if (persist) {
      _persistLocalAttendance();
    }
  }

  Future<bool> startBreakSession(String breakType) async {
    if (_attendanceStatus != 'LOGGED_IN' && _attendanceStatus != 'PRESENT') {
      return false;
    }
    if (_activeBreak != null) return false;

    final normalizedType = breakType.trim().toUpperCase().replaceAll(' ', '_');
    final apiType = normalizedType.contains('LUNCH')
        ? 'LUNCH'
        : normalizedType.contains('PERSONAL')
            ? 'PERSONAL'
            : 'COFFEE';

    final now = DateTime.now().toUtc();
    final localId = _uuid.v4();
    String breakId = localId;
    var synced = 0;

    try {
      final response = await _api.startBreak(apiType);
      if (response.statusCode == 201) {
        final created = _mapFrom(response.data['break'] ?? response.data['data']);
        breakId = created['id']?.toString() ?? localId;
        synced = 1;
      }
    } catch (e) {
      print('Break start API failed, queuing offline: $e');
    }

    final startIso = now.toIso8601String();
    _activeBreak = {
      'id': breakId,
      'breakType': apiType,
      'startTime': startIso,
    };
    _todayBreaks.add(_activeBreak);

    await DatabaseHelper.instance.insert('offline_breaks', {
      'id': breakId,
      'break_type': apiType,
      'start_time': startIso,
      'end_time': null,
      'duration_seconds': 0,
      'break_date': _todayDateKey(),
      'synced': synced,
    });

    notifyListeners();
    return true;
  }

  Future<bool> endBreakSession() async {
    if (_activeBreak == null) return false;

    final now = DateTime.now().toUtc();
    final startTime = DateTime.parse(_activeBreak!['startTime'].toString()).toUtc();
    final durationSeconds = now.difference(startTime).inSeconds;
    if (durationSeconds < 0) return false;

    final breakId = _activeBreak!['id'].toString();
    try {
      await _api.endBreak(breakId);
    } catch (e) {
      print('Break end API failed, keeping local close: $e');
    }

    _totalBreakSeconds += durationSeconds;
    _recalculateBreakFormatted();

    _activeBreak!['endTime'] = now.toIso8601String();
    await DatabaseHelper.instance.update(
      'offline_breaks',
      {
        'end_time': now.toIso8601String(),
        'duration_seconds': durationSeconds,
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [breakId],
    );

    _activeBreak = null;
    notifyListeners();
    return true;
  }

  // 3. Route & Daily Plan Management
  Map<String, dynamic> _normalizeOutlet(Map<String, dynamic> outlet) {
    return {
      'id': outlet['id'],
      'name': outlet['name'] ?? outlet['outlet_name'] ?? 'Outlet',
      'address': outlet['address'] ?? outlet['outlet_address'] ?? '',
      'phone': outlet['phone'] ?? outlet['contactPhone'] ?? outlet['contact_phone'] ?? '',
      'ownerName': outlet['owner_name'] ?? outlet['ownerName'] ?? '',
      'ownerPhone': outlet['owner_phone'] ?? outlet['ownerPhone'] ?? '',
      'nextVisitDate': outlet['next_visit_date'] ??
          outlet['nextVisitDate'] ??
          outlet['next_visit_at'] ??
          outlet['scheduled_next_visit'],
      'nextVisitNotes': outlet['next_visit_notes'] ??
          outlet['nextVisitNotes'] ??
          outlet['notes'] ??
          '',
      'partyStatus': outlet['party_status'] ?? outlet['partyStatus'] ?? 'active',
      'latitude': outlet['latitude'] ?? outlet['gps_lat'] ?? outlet['lat'],
      'longitude': outlet['longitude'] ?? outlet['gps_lng'] ?? outlet['lng'],
      'grade': outlet['grade'],
      'overallRating': outlet['overall_rating'] ?? outlet['overallRating'],
      'visitStatus': outlet['visit_status'] ?? outlet['visitStatus'] ?? 'PENDING',
      'isManual': outlet['isManual'] == true,
    };
  }

  Future<Map<String, dynamic>?> _pullSyncData() async {
    if (_userId == null) return null;
    try {
      final response = await _api.todayPlan(_userId!);
      if (response.statusCode == 200) {
        return _responseData(response);
      }
    } catch (e) {
      print('Today plan pull failed: $e');
    }
    return null;
  }

  Future<void> fetchTodayPlan() async {
    // Keep the executive's selected day plan. Production todayPlan often returns
    // every outlet with PENDING status, which wiped "Visit completed".
    final hadLocalPlan = _todayPlan != null && _plannedOutlets.isNotEmpty;
    if (!hadLocalPlan) {
      await _restoreTodayPlanFromLocal();
    }

    try {
      final data = await _pullSyncData();
      if (data != null && !hadLocalPlan && _todayPlan == null) {
        final plan = data['plan'];
        final outlets = (data['outlets'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((o) => _normalizeOutlet(Map<String, dynamic>.from(o)))
            .toList();
        final progress = _mapFrom(data['progress']);

        if (plan is Map && outlets.isNotEmpty) {
          _todayPlan = Map<String, dynamic>.from(plan);
          _plannedOutlets = outlets;
          _dedupePlannedOutlets();
          _plannedVisitsCount = int.tryParse(progress['planned']?.toString() ?? '') ??
              int.tryParse(_todayPlan!['plannedVisits']?.toString() ?? '') ??
              _plannedOutlets.length;
        }
      }
    } catch (e) {
      print('fetchTodayPlan failed: $e');
    }

    await _applyVisitStatusesFromOfflineVisits();
    await _mergeOutletNextVisitsFromServer();
    _dedupePlannedOutlets();
    await _recomputeTodayDistanceFromLocalGps();
    await restoreActiveVisitFromLocalDb();
    if (_todayPlan != null) {
      startAutoVisitMonitoring();
      await _persistTodayPlanLocally();
    }
    notifyListeners();
  }

  /// Pull next_visit_date + contact fields from GET /outlets so Home keeps showing
  /// details the executive entered (server plan payloads often omit them).
  Future<void> _mergeOutletNextVisitsFromServer() async {
    if (_plannedOutlets.isEmpty) return;
    try {
      final remote = await _api.production.outlets();
      if (remote.isEmpty) return;
      final byId = <String, Map<String, dynamic>>{};
      for (final o in remote) {
        final id = o['id']?.toString();
        if (id != null && id.isNotEmpty) byId[id] = o;
      }
      var changed = false;
      for (var i = 0; i < _plannedOutlets.length; i++) {
        final o = _plannedOutlets[i];
        if (o is! Map) continue;
        final id = o['id']?.toString();
        if (id == null) continue;
        final remoteO = byId[id];
        if (remoteO == null) continue;
        final copy = Map<String, dynamic>.from(o);
        final next = remoteO['next_visit_date'] ??
            remoteO['nextVisitDate'] ??
            remoteO['next_visit_at'];
        final notes = remoteO['next_visit_notes'] ??
            remoteO['nextVisitNotes'] ??
            remoteO['notes'];
        final phone = remoteO['phone']?.toString();
        final ownerName = (remoteO['owner_name'] ?? remoteO['ownerName'])?.toString();
        final ownerPhone = (remoteO['owner_phone'] ?? remoteO['ownerPhone'])?.toString();
        final address = remoteO['address']?.toString();
        final name = remoteO['name']?.toString();

        if (next != null && next.toString().isNotEmpty) {
          if (copy['nextVisitDate']?.toString() != next.toString()) {
            copy['nextVisitDate'] = next.toString();
            changed = true;
          }
        }
        if (notes != null && notes.toString().isNotEmpty) {
          copy['nextVisitNotes'] = notes.toString();
          changed = true;
        }
        // Prefer server values when present; never wipe local non-empty with empty.
        if (name != null && name.isNotEmpty && copy['name']?.toString() != name) {
          copy['name'] = name;
          changed = true;
        }
        if (phone != null && phone.isNotEmpty) {
          copy['phone'] = phone;
          changed = true;
        }
        if (ownerName != null && ownerName.isNotEmpty) {
          copy['ownerName'] = ownerName;
          changed = true;
        }
        if (ownerPhone != null && ownerPhone.isNotEmpty) {
          copy['ownerPhone'] = ownerPhone;
          changed = true;
        }
        if (address != null && address.isNotEmpty) {
          copy['address'] = address;
          changed = true;
        }
        _plannedOutlets[i] = copy;
      }
      if (changed) await _persistTodayPlanLocally();
    } catch (e) {
      print('mergeOutletNextVisitsFromServer failed: $e');
    }
  }

  Future<void> _applyVisitStatusesFromOfflineVisits() async {
    if (_plannedOutlets.isEmpty) return;

    final visits = await DatabaseHelper.instance.queryAll('offline_visits');
    final completedIds = <String>{};
    final inProgressIds = <String>{};
    final remarksByOutlet = <String, String>{};

    for (final visit in visits) {
      final outletId = visit['outlet_id']?.toString();
      if (outletId == null || outletId.isEmpty) continue;
      final checkIn = visit['checkin_time']?.toString();
      final checkOut = visit['checkout_time']?.toString();
      final when = checkOut ?? checkIn;
      if (!_isSameLocalDay(when, DateTime.now())) continue;
      final remarks = (visit['remarks'] ?? '').toString().trim();
      if (remarks.isNotEmpty) {
        remarksByOutlet[outletId] = remarks;
      }
      if (checkOut != null && checkOut.isNotEmpty) {
        completedIds.add(outletId);
      } else {
        inProgressIds.add(outletId);
      }
    }

    for (var i = 0; i < _plannedOutlets.length; i++) {
      final outlet = _plannedOutlets[i];
      if (outlet is! Map) continue;
      final id = outlet['id']?.toString();
      if (id == null) continue;
      final copy = Map<String, dynamic>.from(outlet);
      if (completedIds.contains(id)) {
        copy['visitStatus'] = 'COMPLETED';
      } else if (inProgressIds.contains(id) || isVisitActiveForOutlet(id)) {
        copy['visitStatus'] = 'IN_PROGRESS';
      } else if ((copy['visitStatus']?.toString() ?? '') != 'COMPLETED') {
        final current = copy['visitStatus']?.toString() ?? 'PENDING';
        if (current != 'COMPLETED') copy['visitStatus'] = 'PENDING';
      }
      final savedRemarks = remarksByOutlet[id];
      if (savedRemarks != null && savedRemarks.isNotEmpty) {
        copy['visitRemarks'] = savedRemarks;
        copy['remarks'] = savedRemarks;
      }
      _plannedOutlets[i] = copy;
    }

    _recomputePlanProgressFromOutlets();
  }

  void _recomputePlanProgressFromOutlets() {
    _plannedVisitsCount = _plannedOutlets.length;
    _completedVisitsCount = _plannedOutlets.where((o) => o is Map && o['visitStatus'] == 'COMPLETED').length;
    _planProgressPercentage = _plannedVisitsCount > 0
        ? (_completedVisitsCount / _plannedVisitsCount) * 100.0
        : 0.0;
    if (_todayPlan != null) {
      _todayPlan!['planned_visits'] = _plannedVisitsCount;
      _todayPlan!['completed_visits'] = _completedVisitsCount;
      _todayPlan!['completedVisits'] = _completedVisitsCount;
    }
  }

  bool _isSameLocalDay(String? iso, DateTime day) {
    if (iso == null || iso.isEmpty) return false;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return false;
    final local = parsed.toLocal();
    return local.year == day.year && local.month == day.month && local.day == day.day;
  }

  Future<void> _recomputeTodayDistanceFromLocalGps() async {
    final pings = await DatabaseHelper.instance.queryAll('offline_gps_pings');
    final todayPings = pings.where((p) => _isSameLocalDay(p['timestamp']?.toString(), DateTime.now())).toList();
    double km = 0.0;
    for (var i = 1; i < todayPings.length; i++) {
      final prevLat = double.tryParse(todayPings[i - 1]['latitude']?.toString() ?? '');
      final prevLng = double.tryParse(todayPings[i - 1]['longitude']?.toString() ?? '');
      final currLat = double.tryParse(todayPings[i]['latitude']?.toString() ?? '');
      final currLng = double.tryParse(todayPings[i]['longitude']?.toString() ?? '');
      if (prevLat == null || prevLng == null || currLat == null || currLng == null) continue;
      if (prevLat.abs() < 0.01 && prevLng.abs() < 0.01) continue;
      if (currLat.abs() < 0.01 && currLng.abs() < 0.01) continue;
      final delta = _calculateHaversineDistance(prevLat, prevLng, currLat, currLng);
      if (delta >= 0.015) km += delta;
    }
    if (todayPings.isNotEmpty) {
      _lastPingLat = double.tryParse(todayPings.last['latitude']?.toString() ?? '');
      _lastPingLng = double.tryParse(todayPings.last['longitude']?.toString() ?? '');
    }
    // Never replace a higher live total with a lower recompute mid-session unless recompute is newer.
    if (km >= _totalDistanceCoveredKm || _totalDistanceCoveredKm == 0) {
      _totalDistanceCoveredKm = km;
    }
    await _persistTodayDistance();
  }

  Future<void> _persistTodayDistance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('today_distance_km_${_todayDateKey()}', _totalDistanceCoveredKm);
  }

  Future<void> _restoreTodayDistance() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble('today_distance_km_${_todayDateKey()}');
    if (saved != null && saved > _totalDistanceCoveredKm) {
      _totalDistanceCoveredKm = saved;
    }
  }

  Future<void> fetchAvailableRoutes() async {
    final localRoutes = await _loadCustomRoutesFromLocalDb();
    final serverRoutes = <dynamic>[];

    try {
      final response = await _api.getRoutes();
      if (response.statusCode == 200) {
        serverRoutes.addAll(_responseList(response, 'routes'));
      }
    } catch (e) {
      print('fetchAvailableRoutes failed: $e');
    }

    _availableRoutes = [
      ...localRoutes,
      ...serverRoutes.where((serverRoute) {
        final serverId = serverRoute is Map ? serverRoute['id']?.toString() : null;
        return serverId == null ||
            localRoutes.every((localRoute) => localRoute['id']?.toString() != serverId);
      }),
    ];
    notifyListeners();
  }

  Future<void> fetchRouteOutlets(String routeId) async {
    try {
      final response = await _api.getRouteOutlets(routeId);
      if (response.statusCode == 200) {
        final payload = _responseData(response);
        final raw = (payload['outlets'] as List<dynamic>?) ??
            _responseList(response, 'outlets');
        _routeOutlets = raw
            .whereType<Map>()
            .map((o) => _normalizeOutlet(Map<String, dynamic>.from(o)))
            .where((o) => !_isSystemDailyLoginOutlet(o))
            .toList();
        // Collapse duplicate shops returned by the route payload.
        final seenIds = <String>{};
        final seenNames = <String>{};
        _routeOutlets = _routeOutlets.where((o) {
          if (o is! Map) return false;
          final id = o['id']?.toString() ?? '';
          final name = (o['name'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          if (id.isNotEmpty && !seenIds.add(id)) return false;
          if (name.isNotEmpty && !seenNames.add(name)) return false;
          return true;
        }).toList();
        notifyListeners();
      }
    } catch (e) {
      print('fetchRouteOutlets failed: $e');
      _routeOutlets = [];
      notifyListeners();
    }
  }

  Future<bool> saveDailyPlan(String routeId, String areaName, int plannedVisits) async {
    final selectedRoute = _availableRoutes.cast<dynamic>().firstWhere(
      (r) => r is Map && r['id']?.toString() == routeId,
      orElse: () => null,
    );

    try {
      final response = await _api.savePlan(
        areaName: areaName,
        plannedVisits: plannedVisits,
        routeId: RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(routeId) ? routeId : null,
      );
      if (response.statusCode == 200) {
        await fetchTodayPlan();
        if (_plannedOutlets.isEmpty && selectedRoute is Map) {
          await fetchRouteOutlets(routeId);
          if (_routeOutlets.isNotEmpty) {
            _plannedOutlets = List.from(_routeOutlets);
            _dedupePlannedOutlets();
            _plannedVisitsCount = _plannedOutlets.length;
            _todayPlan ??= {
              'route_id': routeId,
              'area_name': areaName,
              'planned_visits': plannedVisits,
              'completed_visits': 0,
            };
            await _persistTodayPlanLocally();
            startAutoVisitMonitoring();
            notifyListeners();
          }
        } else {
          startAutoVisitMonitoring();
        }
        return true;
      }
    } catch (e) {
      print('saveDailyPlan API failed, using local plan: $e');
    }

    // Offline / local custom route fallback
    List<dynamic> outlets = [];
    if (selectedRoute is Map) {
      if (selectedRoute['isManual'] == true) {
        outlets = List<dynamic>.from(selectedRoute['outlets'] as List? ?? []);
      } else {
        await fetchRouteOutlets(routeId);
        outlets = List.from(_routeOutlets);
      }
    }

    _todayPlan = {
      'id': 'plan-local-${_uuid.v4()}',
      'route_id': routeId,
      'area_name': areaName,
      'planned_visits': plannedVisits > 0 ? plannedVisits : outlets.length,
      'completed_visits': 0,
    };
    _plannedOutlets = outlets.map((o) => o is Map ? _normalizeOutlet(Map<String, dynamic>.from(o)) : o).toList();
    _dedupePlannedOutlets();
    _routeOutlets = List.from(_plannedOutlets);
    _plannedVisitsCount = _plannedOutlets.length;
    _completedVisitsCount = 0;
    _planProgressPercentage = 0.0;
    await _persistTodayPlanLocally();
    startAutoVisitMonitoring();
    notifyListeners();
    return true;
  }

  Future<void> _persistTodayPlanLocally() async {
    final prefs = await SharedPreferences.getInstance();
    if (_todayPlan == null) {
      await _clearTodayPlanFromLocal();
      return;
    }

    await prefs.setString('local_today_plan', jsonEncode(_todayPlan));
    await prefs.setString('local_planned_outlets', jsonEncode(_plannedOutlets));
  }

  Future<void> _restoreTodayPlanFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final planJson = prefs.getString('local_today_plan');
    final outletsJson = prefs.getString('local_planned_outlets');
    if (planJson == null || outletsJson == null) return;

    try {
      final restoredPlan = jsonDecode(planJson);
      final restoredOutlets = List<dynamic>.from(jsonDecode(outletsJson) as List<dynamic>);
      if (restoredOutlets.isEmpty) return;

      _todayPlan = restoredPlan is Map<String, dynamic>
          ? restoredPlan
          : Map<String, dynamic>.from(restoredPlan as Map);
      _plannedOutlets = restoredOutlets;
      _dedupePlannedOutlets();
      _routeOutlets = List.from(_plannedOutlets);
      _plannedVisitsCount = _plannedOutlets.length;
      await _persistTodayPlanLocally();

      final localCompleted = await DatabaseHelper.instance.queryAll(
        'offline_visits',
        where: 'checkout_time IS NOT NULL',
      );
      // Prefer status flags stored on outlets; fall back to today's checkouts.
      await _applyVisitStatusesFromOfflineVisits();
      if (_completedVisitsCount == 0) {
        _completedVisitsCount = localCompleted
            .where((v) => _isSameLocalDay(v['checkout_time']?.toString(), DateTime.now()))
            .length;
        _planProgressPercentage = _plannedVisitsCount > 0
            ? (_completedVisitsCount / _plannedVisitsCount) * 100.0
            : 0.0;
      }

      await restoreActiveVisitFromLocalDb();
      startAutoVisitMonitoring();
      notifyListeners();
    } catch (e) {
      print('Restore local today plan failed: $e');
    }
  }

  Future<void> _clearTodayPlanFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('local_today_plan');
    await prefs.remove('local_planned_outlets');
  }

  Future<bool> createManualRoute(String name, String region, {List<Map<String, dynamic>> outlets = const []}) async {
    final route = {
      'id': 'route-${_uuid.v4()}',
      'name': name,
      'region': region,
      'outlets': outlets,
      'isManual': true,
    };

    await _saveCustomRouteToLocalDb(route);
    _availableRoutes = [
      route,
      ..._availableRoutes.where((existing) => existing is! Map || existing['id']?.toString() != route['id']),
    ];
    notifyListeners();
    return true;
  }

  Future<bool> addManualOutletToTodayPlan(
    String name,
    String address, {
    required double latitude,
    required double longitude,
    String? phone,
    String? ownerName,
    String? ownerPhone,
  }) async {
    if (_todayPlan == null) {
      _todayPlan = {
        'id': 'local-plan-${_uuid.v4()}',
        'route_id': 'manual',
        'planned_visits': 0,
      };
    }

    final outletPhone = (phone ?? '').trim();
    final concernName = (ownerName ?? '').trim();
    final concernPhone = (ownerPhone ?? '').trim();

    String outletId = _uuid.v4();
    try {
      final created = await _api.production.createOutlet({
        'name': name.trim(),
        'address': address.trim(),
        if (outletPhone.isNotEmpty) 'phone': outletPhone,
        if (concernName.isNotEmpty) 'owner_name': concernName,
        if (concernPhone.isNotEmpty) 'owner_phone': concernPhone,
        'latitude': latitude,
        'longitude': longitude,
        'type': 'retailer',
        'source': 'manual',
      });
      if (created != null && created['id'] != null) {
        outletId = created['id'].toString();
      }
    } catch (e) {
      print('Manual outlet create on server failed, keeping local id: $e');
    }

    final outlet = {
      'id': outletId,
      'name': name.trim(),
      'address': address.trim(),
      'phone': outletPhone,
      'ownerName': concernName,
      'ownerPhone': concernPhone,
      'latitude': latitude,
      'longitude': longitude,
      'grade': 'Unrated',
      'overallRating': null,
      'visitStatus': 'PENDING',
      'isManual': true,
      'partyStatus': 'active',
    };

    _routeOutlets.insert(0, outlet);
    // Newest manual outlet at the top of Planned.
    _plannedOutlets = [outlet, ..._plannedOutlets];
    _dedupePlannedOutlets();
    _plannedVisitsCount = _plannedOutlets.length;
    _todayPlan!['planned_visits'] = _plannedVisitsCount;
    final activeRouteId = _todayPlan!['route_id']?.toString();
    if (activeRouteId != null && activeRouteId != 'manual') {
      await _appendOutletToSavedRoute(activeRouteId, outlet);
    }
    if (_plannedVisitsCount > 0) {
      _planProgressPercentage = (_completedVisitsCount / _plannedVisitsCount) * 100.0;
    }
    await _persistTodayPlanLocally();
    notifyListeners();
    return true;
  }

  /// Soft-delete outlet on server and remove from today's planned list.
  Future<bool> deletePlannedOutlet(String outletId) async {
    _lastActionError = null;
    if (outletId.isEmpty) {
      _lastActionError = 'Outlet id missing.';
      return false;
    }
    try {
      final ok = await _api.production.deleteOutlet(outletId);
      if (!ok) {
        // Still remove from local plan if server soft-delete failed for local-only ids.
        print('DELETE outlet returned non-success; removing from local plan anyway.');
      }
    } catch (e) {
      print('DELETE outlet failed: $e');
      _lastActionError = 'Could not delete outlet on server.';
    }

    _plannedOutlets = _plannedOutlets
        .where((o) => o is! Map || o['id']?.toString() != outletId)
        .toList();
    _routeOutlets = _routeOutlets
        .where((o) => o is! Map || o['id']?.toString() != outletId)
        .toList();
    _plannedVisitsCount = _plannedOutlets.length;
    _completedVisitsCount =
        _plannedOutlets.where((o) => o is Map && o['visitStatus'] == 'COMPLETED').length;
    if (_todayPlan != null) {
      _todayPlan!['planned_visits'] = _plannedVisitsCount;
    }
    if (_plannedVisitsCount > 0) {
      _planProgressPercentage = (_completedVisitsCount / _plannedVisitsCount) * 100.0;
    } else {
      _planProgressPercentage = 0;
    }
    await _persistTodayPlanLocally();
    notifyListeners();
    return true;
  }

  /// Schedule next visit date/time (+ optional notes) via PATCH /outlets/:id.
  Future<bool> scheduleOutletNextVisit({
    required String outletId,
    required DateTime when,
    String? notes,
  }) async {
    _lastActionError = null;
    if (outletId.isEmpty) {
      _lastActionError = 'Outlet id missing.';
      return false;
    }
    final note = (notes ?? '').trim();
    final whenIso = when.toUtc().toIso8601String();
    try {
      final updated = await _api.production.updateOutlet(outletId, {
        'next_visit_date': whenIso,
        if (note.isNotEmpty) 'next_visit_notes': note,
        if (note.isNotEmpty) 'notes': note,
      });
      if (updated == null) {
        _lastActionError = 'Could not save next visit on server.';
        // Keep local schedule so executive still sees it.
      } else {
        final serverNext = updated['next_visit_date'] ?? updated['nextVisitDate'];
        if (serverNext != null && serverNext.toString().isNotEmpty) {
          // Prefer server-confirmed value when present.
        }
      }
    } catch (e) {
      print('scheduleOutletNextVisit failed: $e');
      _lastActionError = e.toString();
    }

    for (var i = 0; i < _plannedOutlets.length; i++) {
      final o = _plannedOutlets[i];
      if (o is Map && o['id']?.toString() == outletId) {
        final copy = Map<String, dynamic>.from(o);
        copy['nextVisitDate'] = whenIso;
        copy['nextVisitNotes'] = note;
        final existingRemarks = (copy['visitRemarks'] ?? copy['remarks'] ?? '').toString();
        final parts = existingRemarks
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (!parts.any((p) => p.toLowerCase() == 'next visit')) {
          parts.insert(0, 'Next Visit');
        }
        if (note.isNotEmpty && !parts.contains(note)) {
          parts.add(note);
        }
        copy['visitRemarks'] = parts.join('; ');
        copy['remarks'] = copy['visitRemarks'];
        _plannedOutlets[i] = copy;
        break;
      }
    }
    await _persistTodayPlanLocally();
    notifyListeners();
    return true;
  }

  Future<void> restoreActiveVisitFromLocalDb() async {
    if (_activeVisit != null) return;

    final openVisits = await DatabaseHelper.instance.queryAll(
      'offline_visits',
      where: 'checkout_time IS NULL',
    );
    if (openVisits.isEmpty) return;

    final latestVisit = openVisits.last;
    final outletId = latestVisit['outlet_id']?.toString();
    if (outletId == null || outletId.isEmpty) return;

    List<Map<String, dynamic>> orderedItems = [];
    final rawProducts = latestVisit['products_ordered']?.toString();
    if (rawProducts != null && rawProducts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProducts);
        if (decoded is List) {
          orderedItems = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        }
      } catch (_) {
        orderedItems = [];
      }
    }

    _activeVisit = {
      'id': latestVisit['id'],
      'outletId': outletId,
      'gpsLat': latestVisit['gps_lat'],
      'gpsLng': latestVisit['gps_lng'],
      'address': latestVisit['address'],
      'selfieUrl': latestVisit['selfie_url'],
      'productsOrdered': orderedItems,
      'salesValue': double.tryParse(latestVisit['sales_value']?.toString() ?? '') ?? 0.0,
      'remarks': latestVisit['remarks'],
      'isLocal': true,
      'outletName': _findOutletById(outletId)?['name'] ?? 'Checked-in outlet',
      'executiveEmail': _email,
      'executiveName': _email?.split('@').first,
    };
    _currentOrderItems = orderedItems;
    _currentOrderTotal = double.tryParse(latestVisit['sales_value']?.toString() ?? '') ?? 0.0;

    _markOutletVisitStatus(outletId, 'IN_PROGRESS');
    if (_attendanceStatus != 'LOGGED_IN') {
      final checkInAt = DateTime.tryParse(latestVisit['checkin_time']?.toString() ?? '') ?? DateTime.now().toUtc();
      _startAttendanceClock(checkInAt);
    }
    notifyListeners();
  }

  Future<bool> restoreActiveVisitForOutlet(String outletId) async {
    if (_activeVisit != null) {
      return _activeVisit!['outletId']?.toString() == outletId;
    }

    final openVisits = await DatabaseHelper.instance.queryAll(
      'offline_visits',
      where: 'outlet_id = ? AND checkout_time IS NULL',
      whereArgs: [outletId],
    );
    if (openVisits.isEmpty) return false;

    final visit = openVisits.last;
    List<Map<String, dynamic>> orderedItems = [];
    final rawProducts = visit['products_ordered']?.toString();
    if (rawProducts != null && rawProducts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProducts);
        if (decoded is List) {
          orderedItems = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
        }
      } catch (_) {
        orderedItems = [];
      }
    }

    _activeVisit = {
      'id': visit['id'],
      'outletId': outletId,
      'gpsLat': visit['gps_lat'],
      'gpsLng': visit['gps_lng'],
      'address': visit['address'],
      'selfieUrl': visit['selfie_url'],
      'productsOrdered': orderedItems,
      'salesValue': double.tryParse(visit['sales_value']?.toString() ?? '') ?? 0.0,
      'remarks': visit['remarks'],
      'isLocal': true,
    };
    _currentOrderItems = orderedItems;
    _currentOrderTotal = double.tryParse(visit['sales_value']?.toString() ?? '') ?? 0.0;
    _markOutletVisitStatus(outletId, 'IN_PROGRESS');
    if (_attendanceStatus != 'LOGGED_IN') {
      final checkInAt = DateTime.tryParse(visit['checkin_time']?.toString() ?? '') ?? DateTime.now().toUtc();
      _startAttendanceClock(checkInAt);
    }
    notifyListeners();
    return true;
  }

  Future<List<Map<String, dynamic>>> _loadCustomRoutesFromLocalDb() async {
    final rows = await DatabaseHelper.instance.queryAll('offline_custom_routes');
    return rows.map((row) {
      final outlets = jsonDecode(row['outlets_json']?.toString() ?? '[]');
      return {
        'id': row['id'],
        'name': row['name'],
        'region': row['region'],
        'outlets': outlets is List ? outlets : <dynamic>[],
        'isManual': true,
      };
    }).toList().reversed.toList();
  }

  Future<void> _saveCustomRouteToLocalDb(Map<String, dynamic> route) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await DatabaseHelper.instance.insert('offline_custom_routes', {
      'id': route['id'],
      'name': route['name'],
      'region': route['region'],
      'outlets_json': jsonEncode(route['outlets'] ?? <dynamic>[]),
      'created_at': route['created_at'] ?? now,
      'updated_at': now,
    });
  }

  Future<void> _appendOutletToSavedRoute(String routeId, Map<String, dynamic> outlet) async {
    final routeIndex = _availableRoutes.indexWhere((route) => route['id']?.toString() == routeId);
    if (routeIndex == -1) return;

    final route = Map<String, dynamic>.from(_availableRoutes[routeIndex] as Map);
    final outlets = List<dynamic>.from(route['outlets'] as List<dynamic>? ?? []);
    if (outlets.any((existing) => existing is Map && existing['id'] == outlet['id'])) return;

    outlets.add(outlet);
    route['outlets'] = outlets;
    _availableRoutes[routeIndex] = route;

    if (route['isManual'] == true) {
      await _saveCustomRouteToLocalDb(route);
    }
  }

  // 4. GPS & Odometer Tracking
  void setOdometerStartPoint(String value) {
    _odometerStartPoint = value;
    notifyListeners();
  }

  void clearLastAutoRegisteredOutlet() {
    _lastAutoRegisteredOutlet = null;
  }

  void startAutoVisitMonitoring() {
    _autoVisitTimer?.cancel();
    if (_todayPlan == null || _plannedOutlets.isEmpty) return;

    _autoVisitTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _tickAutoVisitMonitoring();
    });
  }

  void stopAutoVisitMonitoring() {
    _autoVisitTimer?.cancel();
    _autoVisitTimer = null;
    _dwellOutletId = null;
    _dwellStartedAt = null;
  }

  Future<void> _tickAutoVisitMonitoring() async {
    if (_todayPlan == null || _activeVisit != null) return;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 10));
      if (position == null) return;
      await processAutoVisitLocation(position.latitude, position.longitude);
    } catch (_) {
      // Keep monitoring alive even if one GPS read fails.
    }
  }

  Future<void> processAutoVisitLocation(double lat, double lng, {String? address}) async {
    if (_todayPlan == null || _activeVisit != null) {
      _dwellOutletId = null;
      _dwellStartedAt = null;
      return;
    }

    Map<String, dynamic>? matchedOutlet;
    for (final outlet in _plannedOutlets) {
      if (outlet is! Map) continue;
      final outletId = outlet['id']?.toString();
      if (outletId == null) continue;
      if (outlet['visitStatus'] == 'COMPLETED' || outlet['visitStatus'] == 'IN_PROGRESS') continue;
      if (await _hasOpenVisitForOutlet(outletId)) continue;

      final targetLat = double.tryParse(outlet['latitude']?.toString() ?? '');
      final targetLng = double.tryParse(outlet['longitude']?.toString() ?? '');
      if (targetLat == null || targetLng == null) continue;

      final distanceM = _calculateHaversineDistance(lat, lng, targetLat, targetLng) * 1000.0;
      if (distanceM <= 100.0) {
        matchedOutlet = Map<String, dynamic>.from(outlet);
        break;
      }
    }

    if (matchedOutlet == null) {
      _dwellOutletId = null;
      _dwellStartedAt = null;
      return;
    }

    final outletId = matchedOutlet['id'].toString();
    if (_dwellOutletId != outletId) {
      _dwellOutletId = outletId;
      _dwellStartedAt = DateTime.now();
      return;
    }

    final dwellSeconds = DateTime.now().difference(_dwellStartedAt!).inSeconds;
    if (dwellSeconds >= _minimumVisitDurationMinutes * 60) {
      // When selfie is required, auto-dwell only starts a visit if policy allows;
      // default policy (selfie OFF) auto-completes the outlet visit.
      if (_selfieRequired) {
        await autoRegisterVisit(outletId, lat, lng, address, matchedOutlet);
      } else {
        await autoCompleteVisit(outletId, lat, lng, address, matchedOutlet);
      }
      _dwellOutletId = null;
      _dwellStartedAt = null;
    }
  }

  Future<bool> _hasOpenVisitForOutlet(String outletId) async {
    final openVisits = await DatabaseHelper.instance.queryAll(
      'offline_visits',
      where: 'outlet_id = ? AND checkout_time IS NULL',
      whereArgs: [outletId],
    );
    return openVisits.isNotEmpty;
  }

  Future<void> autoRegisterVisit(
    String outletId,
    double lat,
    double lng,
    String? address,
    Map<String, dynamic> outlet,
  ) async {
    if (_activeVisit != null) return;

    if (_attendanceStatus != 'LOGGED_IN') {
      _startAttendanceClock(DateTime.now().toUtc());
    }

    final localId = _uuid.v4();
    final resolvedAddress = address ?? '';
    await DatabaseHelper.instance.insert('offline_visits', {
      'id': localId,
      'outlet_id': outletId,
      'gps_lat': lat,
      'gps_lng': lng,
      'address': resolvedAddress,
      'selfie_url': 'auto-detected',
      'checkin_time': DateTime.now().toUtc().toIso8601String(),
      'manager_override': 0,
      'auto_detected': 1,
      'remarks': 'Auto-registered after $_minimumVisitDurationMinutes min stay at outlet.',
      'synced': 0,
    });
    await recordGpsPing(lat, lng, _odometerStartPoint, address: resolvedAddress);

    _activeVisit = {
      'id': localId,
      'outletId': outletId,
      'gpsLat': lat,
      'gpsLng': lng,
      'address': resolvedAddress,
      'selfieUrl': 'auto-detected',
      'isLocal': true,
      'autoDetected': true,
    };
    _currentOrderItems = [];
    _currentOrderTotal = 0.0;
    _markOutletVisitStatus(outletId, 'IN_PROGRESS');
    _lastAutoRegisteredOutlet = {
      'id': outletId,
      'name': outlet['name'] ?? 'Outlet',
    };
    notifyListeners();
  }

  /// Auto-complete outlet after dwell (selfie policy OFF): check-in + check-out = COMPLETED.
  Future<void> autoCompleteVisit(
    String outletId,
    double lat,
    double lng,
    String? address,
    Map<String, dynamic> outlet,
  ) async {
    if (_activeVisit != null) return;

    if (_attendanceStatus != 'LOGGED_IN') {
      _startAttendanceClock(DateTime.now().toUtc());
    }

    final localId = _uuid.v4();
    final resolvedAddress = address ?? '';
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final remarks = 'Auto-completed after $_minimumVisitDurationMinutes min stay (selfie not required).';

    String visitId = localId;
    var synced = 0;

    try {
      final response = await _apiClient.post(ApiEndpoints.visitsCheckIn, data: {
        if (RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(outletId)) 'outletId': outletId,
        'outlet': {
          'name': outlet['name'],
          'address': outlet['address'] ?? resolvedAddress,
          'gpsLat': double.tryParse(outlet['latitude']?.toString() ?? '') ?? lat,
          'gpsLng': double.tryParse(outlet['longitude']?.toString() ?? '') ?? lng,
        },
        'gpsLat': lat,
        'gpsLng': lng,
        'selfieUrl': 'auto-detected',
        'managerOverrideFlag': false,
        'autoComplete': true,
      });
      if (response.statusCode == 201) {
        final visit = _mapFrom(response.data['visit']);
        visitId = visit['id']?.toString() ?? visitId;
        synced = 1;
      }
    } catch (e) {
      print('Auto-complete visit API failed, storing locally: $e');
    }

    await DatabaseHelper.instance.insert('offline_visits', {
      'id': visitId,
      'outlet_id': outletId,
      'gps_lat': lat,
      'gps_lng': lng,
      'address': resolvedAddress,
      'selfie_url': 'auto-detected',
      'checkin_time': nowIso,
      'checkout_time': nowIso,
      'manager_override': 0,
      'auto_detected': 1,
      'remarks': remarks,
      'synced': synced,
    });
    await recordGpsPing(lat, lng, _odometerStartPoint, address: resolvedAddress);

    _markOutletVisitStatus(outletId, 'COMPLETED');
    _completedVisitsCount = _plannedOutlets.where((o) => o is Map && o['visitStatus'] == 'COMPLETED').length;
    if (_plannedVisitsCount > 0) {
      _planProgressPercentage = (_completedVisitsCount / _plannedVisitsCount) * 100.0;
    }
    if (_todayPlan != null) {
      _todayPlan!['completed_visits'] = _completedVisitsCount;
      _todayPlan!['completedVisits'] = _completedVisitsCount;
    }

    _lastAutoRegisteredOutlet = {
      'id': outletId,
      'name': outlet['name'] ?? 'Outlet',
      'completed': true,
    };
    notifyListeners();
  }

  Map<String, dynamic>? _findOutletById(String outletId) {
    for (final outlet in _plannedOutlets) {
      if (outlet is Map && outlet['id']?.toString() == outletId) {
        return Map<String, dynamic>.from(outlet);
      }
    }
    for (final outlet in _routeOutlets) {
      if (outlet is Map && outlet['id']?.toString() == outletId) {
        return Map<String, dynamic>.from(outlet);
      }
    }
    return null;
  }

  void startContinuousGpsTracking() {
    if (_gpsTrackingTimer != null) return;
    _gpsTrackingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_attendanceStatus != 'LOGGED_IN' && _attendanceStatus != 'PRESENT') return;
      if (_activeBreak != null) return;
      try {
        final position = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 12));
        if (position == null) return;
        await recordGpsPing(position.latitude, position.longitude, _odometerStartPoint);
      } catch (e) {
        print('Continuous GPS ping failed: $e');
      }
    });
  }

  void stopContinuousGpsTracking() {
    _gpsTrackingTimer?.cancel();
    _gpsTrackingTimer = null;
  }

  DateTime? _lastGeocodeAt;
  double? _lastGeocodeLat;
  double? _lastGeocodeLng;
  String? _lastGeocodeAddress;

  Future<String?> resolveAddressFromCoordinates(double latitude, double longitude) async {
    try {
      final places = await placemarkFromCoordinates(latitude, longitude);
      if (places.isEmpty) return null;
      final p = places.first;
      final parts = <String>[
        if ((p.name ?? '').trim().isNotEmpty) p.name!.trim(),
        if ((p.street ?? '').trim().isNotEmpty && p.street != p.name) p.street!.trim(),
        if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
        if ((p.administrativeArea ?? '').trim().isNotEmpty) p.administrativeArea!.trim(),
        if ((p.postalCode ?? '').trim().isNotEmpty) p.postalCode!.trim(),
        if ((p.country ?? '').trim().isNotEmpty) p.country!.trim(),
      ];
      // Prefer plus-code / street line when name alone is a plus code with empty locality.
      final joined = parts.where((s) => s.isNotEmpty).toSet().join(', ');
      return joined.isNotEmpty ? joined : null;
    } catch (_) {
      return null;
    }
  }

  bool _isUnresolvedAddress(String? address) {
    if (address == null) return true;
    final a = address.trim().toLowerCase();
    if (a.isEmpty) return true;
    const placeholders = {
      'location name not resolved',
      'address not resolved',
      'tracked location',
      'gps ping',
      'location',
      'session resume',
      'visit check-in',
      'visit check-out',
      'login location',
    };
    return placeholders.contains(a);
  }

  Future<String?> _resolveAddressCached(double latitude, double longitude, {bool force = false}) async {
    if (!force &&
        _lastGeocodeAddress != null &&
        _lastGeocodeLat != null &&
        _lastGeocodeLng != null &&
        _lastGeocodeAt != null) {
      final age = DateTime.now().difference(_lastGeocodeAt!);
      final movedKm = Geo.distanceKm(_lastGeocodeLat!, _lastGeocodeLng!, latitude, longitude);
      if (age < const Duration(minutes: 2) && movedKm < 0.2) {
        return _lastGeocodeAddress;
      }
    }
    final resolved = await resolveAddressFromCoordinates(latitude, longitude);
    if (resolved != null) {
      _lastGeocodeAddress = resolved;
      _lastGeocodeLat = latitude;
      _lastGeocodeLng = longitude;
      _lastGeocodeAt = DateTime.now();
    }
    return resolved;
  }

  Future<void> recordGpsPing(double latitude, double longitude, String trackingStartPoint, {String? address}) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final localPingId = _uuid.v4();
    final startPoint = trackingStartPoint == 'FIRST_OUTLET' ? 'FIRST_OUTLET' : 'HOME';

    var resolvedAddress = address;
    if (_isUnresolvedAddress(resolvedAddress)) {
      resolvedAddress = await _resolveAddressCached(latitude, longitude);
    }

    if (_lastPingLat != null && _lastPingLng != null) {
      final deltaKm = Geo.distanceKm(_lastPingLat!, _lastPingLng!, latitude, longitude);
      // Ignore GPS jitter under ~15 metres
      if (deltaKm >= 0.015) {
        _totalDistanceCoveredKm += deltaKm;
        await _persistTodayDistance();
      }
    }
    _lastPingLat = latitude;
    _lastPingLng = longitude;

    await DatabaseHelper.instance.insert('offline_gps_pings', {
      'id': localPingId,
      'latitude': latitude,
      'longitude': longitude,
      'address': resolvedAddress,
      'timestamp': timestamp,
      'tracking_start_point': startPoint,
      'synced': 0,
    });

    _todayGpsRoute.add({
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
    });
    notifyListeners();

    try {
      final deviceId = await DeviceId.get();
      final response = await _api.gpsPing(
        latitude: latitude,
        longitude: longitude,
        trackingStartPoint: startPoint,
        timestamp: timestamp,
        address: resolvedAddress,
        deviceId: deviceId,
        offlineId: localPingId,
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        await DatabaseHelper.instance.update(
          'offline_gps_pings',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [localPingId],
        );
        final ping = _mapFrom(response.data['ping']);
        final serverDelta = double.tryParse(ping['distanceFromPrev']?.toString() ?? '');
        if (serverDelta != null && serverDelta > 0) {
          // Prefer server odometer accumulation when available
          await refreshGpsSummaryFromServer();
        }
      }
    } catch (e) {
      print('Production GPS ping failed. Queued locally for offline sync: $e');
    }
  }

  Future<void> refreshGpsSummaryFromServer() async {
    if (_userId == null) return;
    try {
      final response = await _api.gpsSummary(_userId!, _todayDateKey());
      if (response.statusCode == 200) {
        final payload = _responseData(response);
        final km = double.tryParse(
              (payload['totalDistanceKm'] ?? response.data['totalDistanceKm'])?.toString() ?? '',
            ) ??
            0.0;
        // Production stub returns 0 — never wipe a real local odometer with that.
        if (km > _totalDistanceCoveredKm) {
          _totalDistanceCoveredKm = km;
          await _persistTodayDistance();
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  // 5. Outlet Visit Workflow
  static const List<Map<String, dynamic>> _fallbackProductCatalog = [
    {
      'id': 'fallback-ply-18',
      'sku': 'PLY-18MM',
      'name': 'Premium Plywood 18mm',
      'size': '18mm',
      'unitPrice': 1500.0,
      'isCustom': false,
      'isFallback': true,
    },
    {
      'id': 'fallback-ply-12',
      'sku': 'PLY-12MM',
      'name': 'Premium Plywood 12mm',
      'size': '12mm',
      'unitPrice': 1200.0,
      'isCustom': false,
      'isFallback': true,
    },
  ];

  static const _hiddenProductsPrefsKey = 'hidden_product_ids';

  Future<Set<String>> _loadHiddenProductIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_hiddenProductsPrefsKey) ?? const <String>[];
      return raw.toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistHiddenProductIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenProductsPrefsKey, ids.toList());
  }

  Future<List<Map<String, dynamic>>> _loadExecutiveCustomProducts() async {
    try {
      final rows = await DatabaseHelper.instance.queryAll('offline_executive_products');
      return rows.map((row) {
        return {
          'id': row['id'],
          'sku': row['sku'] ?? 'CUSTOM',
          'name': row['name'] ?? 'Product',
          'size': row['size'] ?? '',
          'unitPrice': double.tryParse(row['unit_price']?.toString() ?? '') ?? 0.0,
          'isCustom': true,
          'isFallback': false,
        };
      }).toList();
    } catch (e) {
      print('Load executive products failed: $e');
      return [];
    }
  }

  Future<void> fetchProductCatalog() async {
    List<Map<String, dynamic>> apiProducts = [];
    try {
      final response = await _api.products();
      if (response.statusCode == 200) {
        final rawProducts = _responseList(response, 'products');
        apiProducts = rawProducts.map((p) {
          final map = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
          final unitPrice = double.tryParse(
                (map['unitPrice'] ?? map['unit_price'] ?? map['price'] ?? map['mrp'] ?? map['ptr'] ?? 0).toString(),
              ) ??
              0.0;
          return {
            'id': map['id'],
            'sku': map['sku'] ?? 'SKU-GEN',
            'name': map['name'] ?? 'Product',
            'size': map['size'] ?? map['pack_size'] ?? map['uom'] ?? '',
            'unitPrice': unitPrice,
            'mrp': map['mrp'],
            'ptr': map['ptr'],
            'category_id': map['category_id'],
            'brand_id': map['brand_id'],
            'isCustom': false,
            'isFallback': false,
            'raw': map,
          };
        }).toList();
      }
    } catch (e) {
      print('Fetch product catalog failed: $e');
    }

    final hidden = await _loadHiddenProductIds();
    final custom = await _loadExecutiveCustomProducts();
    final byId = <String, Map<String, dynamic>>{};
    for (final p in apiProducts) {
      final id = p['id']?.toString();
      if (id != null && id.isNotEmpty && !hidden.contains(id)) byId[id] = p;
    }
    for (final p in custom) {
      final id = p['id']?.toString() ?? p['sku']?.toString();
      if (id != null && id.isNotEmpty && !hidden.contains(id)) byId[id] = p;
    }

    for (final p in _fallbackProductCatalog) {
      final id = p['id'].toString();
      if (hidden.contains(id)) continue;
      // Local edit (custom row with same id) already in byId wins.
      byId.putIfAbsent(id, () => Map<String, dynamic>.from(p));
    }

    _productCatalog = byId.values.toList();
    notifyListeners();
  }

  Future<bool> upsertExecutiveProduct({
    String? id,
    String? existingSku,
    required String name,
    required String size,
    required double unitPrice,
  }) async {
    _lastActionError = null;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _lastActionError = 'Product name is required.';
      return false;
    }
    if (unitPrice < 0) {
      _lastActionError = 'Price cannot be negative.';
      return false;
    }

    final isEdit = id != null && id.isNotEmpty;
    final productId = isEdit ? id! : _uuid.v4();
    String sku = (existingSku != null && existingSku.trim().isNotEmpty)
        ? existingSku.trim()
        : 'EXE-${productId.replaceAll('-', '').substring(0, 8).toUpperCase()}';
    final now = DateTime.now().toUtc().toIso8601String();
    String createdAt = now;

    if (isEdit) {
      try {
        final rows = await DatabaseHelper.instance.queryAll(
          'offline_executive_products',
          where: 'id = ?',
          whereArgs: [productId],
        );
        if (rows.isNotEmpty) {
          sku = rows.first['sku']?.toString() ?? sku;
          createdAt = rows.first['created_at']?.toString() ?? now;
        }
      } catch (_) {}
    }

    // Editing a hardcoded/API product: keep it visible after save.
    if (isEdit) {
      final hidden = await _loadHiddenProductIds();
      if (hidden.remove(productId)) {
        await _persistHiddenProductIds(hidden);
      }
    }

    try {
      await DatabaseHelper.instance.insert('offline_executive_products', {
        'id': productId,
        'name': trimmedName,
        'size': size.trim(),
        'sku': sku,
        'unit_price': unitPrice,
        'created_at': createdAt,
        'updated_at': now,
      });
    } catch (e) {
      _lastActionError = 'Could not save product locally.';
      print('upsertExecutiveProduct failed: $e');
      return false;
    }

    if (!isEdit) {
      try {
        await _api.production.createProduct({
          'name': trimmedName,
          'sku': sku,
          'mrp': unitPrice,
          'ptr': unitPrice,
          if (size.trim().isNotEmpty) 'pack_size': size.trim(),
        });
      } catch (_) {}
    }

    await fetchProductCatalog();
    return true;
  }

  Future<bool> deleteExecutiveProduct(String productId) async {
    _lastActionError = null;
    try {
      // Hide from catalog (hardcoded + API + custom) so it does not reappear.
      final hidden = await _loadHiddenProductIds();
      hidden.add(productId);
      await _persistHiddenProductIds(hidden);

      try {
        await DatabaseHelper.instance.delete(
          'offline_executive_products',
          where: 'id = ?',
          whereArgs: [productId],
        );
      } catch (_) {}

      await fetchProductCatalog();
      return true;
    } catch (e) {
      _lastActionError = 'Could not delete product.';
      return false;
    }
  }

  List<Map<String, dynamic>> _productCategories = [];
  List<Map<String, dynamic>> _productBrands = [];
  List<Map<String, dynamic>> get productCategoriesAdmin => _productCategories;
  List<Map<String, dynamic>> get productBrandsAdmin => _productBrands;

  Future<void> fetchProductAdminLists() async {
    try {
      _productCategories = await _api.production.productCategories();
      _productBrands = await _api.production.productBrands();
      await fetchProductCatalog();
      notifyListeners();
    } catch (e) {
      print('Fetch product admin lists failed: $e');
      notifyListeners();
    }
  }

  Future<bool> createProductAdmin({
    required String name,
    required String sku,
    required double mrp,
    required double ptr,
    String? categoryId,
    String? brandId,
  }) async {
    _lastActionError = null;
    try {
      await _api.production.createProduct({
        'name': name.trim(),
        'sku': sku.trim(),
        'mrp': mrp,
        'ptr': ptr,
        if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
        if (brandId != null && brandId.isNotEmpty) 'brand_id': brandId,
      });
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not create product.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> updateProductAdmin(String id, Map<String, dynamic> fields) async {
    _lastActionError = null;
    try {
      await _api.production.updateProduct(id, fields);
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not update product.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> deleteProductAdmin(String id) async {
    _lastActionError = null;
    try {
      final ok = await _api.production.deleteProduct(id);
      if (!ok) {
        _lastActionError = 'Delete product failed.';
        return false;
      }
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not delete product.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> createProductCategoryAdmin(String name) async {
    _lastActionError = null;
    try {
      await _api.production.createProductCategory({'name': name.trim()});
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not create category.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> updateProductCategoryAdmin(String id, String name) async {
    _lastActionError = null;
    try {
      await _api.production.updateProductCategory(id, {'name': name.trim()});
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not update category.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> deleteProductCategoryAdmin(String id) async {
    _lastActionError = null;
    try {
      final ok = await _api.production.deleteProductCategory(id);
      if (!ok) {
        _lastActionError = 'Delete category failed.';
        return false;
      }
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not delete category.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> createProductBrandAdmin(String name) async {
    _lastActionError = null;
    try {
      await _api.production.createProductBrand({'name': name.trim()});
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not create brand.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> updateProductBrandAdmin(String id, String name) async {
    _lastActionError = null;
    try {
      await _api.production.updateProductBrand(id, {'name': name.trim()});
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not update brand.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> deleteProductBrandAdmin(String id) async {
    _lastActionError = null;
    try {
      final ok = await _api.production.deleteProductBrand(id);
      if (!ok) {
        _lastActionError = 'Delete brand failed.';
        return false;
      }
      await fetchProductAdminLists();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not delete brand.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  /// Upload blink/login selfie to production `/api/v1/media/upload-login-selfie`.
  /// Returns an absolute HTTPS URL when successful.
  Future<String?> uploadLoginSelfieFile(File file) async {
    try {
      final url = await _api.uploadLoginSelfie(file);
      if (url == null || url.trim().isEmpty) return null;
      final trimmed = url.trim();
      if (trimmed.startsWith('http')) return trimmed;
      if (trimmed.startsWith('/')) return '${ApiEndpoints.baseUrl}$trimmed';
      return '${ApiEndpoints.baseUrl}/$trimmed';
    } catch (e) {
      print('uploadLoginSelfieFile failed: $e');
      return null;
    }
  }

  Future<String> _resolveSelfieUrl(String localPathOrUrl) async {
    final raw = localPathOrUrl.trim();
    if (raw.isEmpty) return raw;

    // Prefer a short HTTP(S) URL — data URIs are too large for visit.selfie_url columns.
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    File? file;
    var deleteTemp = false;
    if (raw.startsWith('data:image')) {
      try {
        final b64 = raw.contains(',') ? raw.split(',').last : raw;
        final bytes = base64Decode(b64);
        final dir = await Directory.systemTemp.createTemp('me_selfie_');
        file = File('${dir.path}/selfie.jpg');
        await file.writeAsBytes(bytes, flush: true);
        deleteTemp = true;
      } catch (_) {
        return raw.length > 480 ? 'auto-detected' : raw;
      }
    } else {
      file = File(raw);
      if (!await file.exists()) {
        // Maybe a relative server path.
        if (raw.startsWith('/')) return '${ApiEndpoints.baseUrl}$raw';
        return raw;
      }
    }

    try {
      final uploaded = await _api.uploadSelfie(file!);
      if (uploaded.trim().isNotEmpty) {
        final url = uploaded.trim();
        if (url.startsWith('http')) return url;
        if (url.startsWith('/')) return '${ApiEndpoints.baseUrl}$url';
        return '${ApiEndpoints.baseUrl}/$url';
      }
    } catch (e) {
      print('Selfie upload failed, embedding data URI fallback: $e');
    }

    // Upload unavailable — keep a renderable data URI when we still have bytes.
    try {
      if (await file!.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final embedded = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          if (deleteTemp) {
            try {
              await file.parent.delete(recursive: true);
            } catch (_) {}
          }
          return embedded;
        }
      }
    } catch (_) {}

    if (deleteTemp) {
      try {
        await file!.parent.delete(recursive: true);
      } catch (_) {}
    }
    return raw.startsWith('data:image') ? raw : 'auto-detected';
  }

  /// Normalize any selfie field from API / notes into a renderable absolute URL.
  String? _absoluteSelfieUrl(String? raw) {
    if (raw == null) return null;
    var selfie = raw.trim();
    if (selfie.isEmpty || selfie == 'auto-detected' || selfie == 'null') return null;

    // Truncated data URIs cannot decode — treat as missing.
    if (selfie.startsWith('data:image')) {
      final payload = selfie.contains(',') ? selfie.split(',').last : '';
      if (payload.length < 64) return null;
      try {
        base64Decode(payload);
        return selfie;
      } catch (_) {
        return null;
      }
    }

    if (selfie.startsWith('http://') || selfie.startsWith('https://')) return selfie;
    if (selfie.startsWith('/')) return '${ApiEndpoints.baseUrl}$selfie';

    // Raw base64 without data: prefix
    if (selfie.length > 100 &&
        !selfie.contains(r'\') &&
        !selfie.contains('/') &&
        !selfie.contains('.')) {
      try {
        base64Decode(selfie);
        return 'data:image/jpeg;base64,$selfie';
      } catch (_) {}
    }

    if (File(selfie).existsSync()) return selfie;
    return '${ApiEndpoints.baseUrl}/$selfie';
  }

  Future<Map<String, dynamic>?> checkInOutlet(
    String outletId,
    double lat,
    double lng,
    String selfieUrl, {
    bool managerOverride = false,
    String? address,
  }) async {
    await restoreActiveVisitFromLocalDb();
    if (_activeVisit != null) {
      if (isVisitActiveForOutlet(outletId)) {
        if (_attendanceStatus != 'LOGGED_IN') {
          _startAttendanceClock(DateTime.now().toUtc());
        }
        return {
          'success': true,
          'visit': _activeVisit,
          'offline': _activeVisit!['isLocal'] == true,
          'alreadyActive': true,
          'requiresOverride': false,
          'distanceMeters': 0.0,
        };
      }
      return {
        'success': false,
        'activeVisitExists': true,
        'message': 'Another outlet visit is already active. Please check out before starting a new visit.',
        'activeOutletId': _activeVisit!['outletId']?.toString(),
      };
    }

    if (_selfieRequired && (selfieUrl.isEmpty || selfieUrl == 'auto-detected')) {
      return {
        'success': false,
        'requiresSelfie': true,
        'message': 'Selfie check-in is required by admin policy.',
      };
    }

    double distanceMeters = 0.0;
    final outlet = _findOutletById(outletId);

    if (outlet != null) {
      final targetLat = double.tryParse(outlet['latitude']?.toString() ?? '');
      final targetLng = double.tryParse(outlet['longitude']?.toString() ?? '');

      if (targetLat == null || targetLng == null) {
        return {
          'success': false,
          'requiresOutletLocation': true,
          'message': 'Outlet target location is missing. Add/resolve outlet latitude and longitude before check-in.',
        };
      }

      distanceMeters = Geo.distanceMeters(lat, lng, targetLat, targetLng);
      if (distanceMeters > 100.0 && !managerOverride) {
        return {
          'success': false,
          'requiresOverride': true,
          'distanceMeters': distanceMeters,
        };
      }
    }

    await checkInAttendance(lat, lng);

    final effectiveSelfie = (selfieUrl.isEmpty) ? 'auto-detected' : selfieUrl;
    final remoteSelfieUrl = effectiveSelfie == 'auto-detected'
        ? 'auto-detected'
        : await _resolveSelfieUrl(effectiveSelfie);
    final outletPayload = outlet == null
        ? null
        : {
            'name': outlet['name'],
            'address': outlet['address'] ?? address ?? outlet['name'],
            'gpsLat': double.tryParse(outlet['latitude']?.toString() ?? '') ?? lat,
            'gpsLng': double.tryParse(outlet['longitude']?.toString() ?? '') ?? lng,
          };

    String visitId = _uuid.v4();
    var synced = 0;
    var isLocal = true;
    var resolvedOutletId = outletId;

    try {
      final response = await _api.checkInVisit(
        outletId: RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(outletId) ? outletId : null,
        outlet: outletPayload,
        gpsLat: lat,
        gpsLng: lng,
        selfieUrl: remoteSelfieUrl,
        managerOverrideFlag: managerOverride,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final payload = _responseData(response);
        final visit = _mapFrom(payload['visit']);
        visitId = visit['id']?.toString() ?? visitId;
        if (visit['outlet_id'] != null) {
          resolvedOutletId = visit['outlet_id'].toString();
        } else if (visit['outletId'] != null) {
          resolvedOutletId = visit['outletId'].toString();
        }
        synced = 1;
        isLocal = false;
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['requiresOverride'] == true) {
        return {
          'success': false,
          'requiresOverride': true,
          'distanceMeters': double.tryParse(data['distanceMeters']?.toString() ?? '') ?? distanceMeters,
        };
      }
      if (e.response?.statusCode == 409) {
        return {
          'success': false,
          'activeVisitExists': true,
          'message': data is Map ? (data['error']?.toString() ?? 'Active visit exists') : 'Active visit exists',
          'activeOutletId': data is Map ? data['activeOutletId']?.toString() : null,
        };
      }
      print('Check-in API failed, storing offline: ${e.response?.data ?? e.message}');
    } catch (e) {
      print('Check-in API failed, storing offline: $e');
    }

    final localVisit = {
      'id': visitId,
      // Keep the planned/checklist outlet id so Home UI keeps matching after check-in.
      'outlet_id': outletId,
      'gps_lat': lat,
      'gps_lng': lng,
      'address': address,
      'selfie_url': remoteSelfieUrl,
      'checkin_time': DateTime.now().toUtc().toIso8601String(),
      'manager_override': managerOverride ? 1 : 0,
      'synced': synced,
    };
    await DatabaseHelper.instance.insert('offline_visits', localVisit);
    await recordGpsPing(lat, lng, _odometerStartPoint, address: address);

    final outletName = outlet?['name']?.toString() ?? 'Outlet';
    _activeVisit = {
      'id': visitId,
      'outletId': outletId,
      'serverOutletId': resolvedOutletId,
      'outletName': outletName,
      'gpsLat': lat,
      'gpsLng': lng,
      'address': address,
      'selfieUrl': remoteSelfieUrl,
      'isLocal': isLocal,
      'checkInTime': localVisit['checkin_time'],
      'executiveEmail': _email,
      'executiveName': _email?.split('@').first,
    };
    _markOutletVisitStatus(outletId, 'IN_PROGRESS');
    if (resolvedOutletId != outletId) {
      _markOutletVisitStatus(resolvedOutletId, 'IN_PROGRESS');
    }
    _currentOrderItems = [];
    _currentOrderTotal = 0.0;
    notifyListeners();

    return {
      'success': true,
      'visit': _activeVisit,
      'offline': isLocal,
      'requiresOverride': false,
      'distanceMeters': distanceMeters,
    };
  }

  bool isVisitActiveForOutlet(String? outletId) {
    if (_activeVisit == null || outletId == null || outletId.isEmpty) return false;
    final activeId = _activeVisit!['outletId']?.toString();
    final serverId = _activeVisit!['serverOutletId']?.toString();
    return activeId == outletId || serverId == outletId;
  }

  double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geo.distanceKm(lat1, lon1, lat2, lon2);
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = v?.toString().trim() ?? '';
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return '';
  }

  void addProductToOrder(String sku, String name, int qty, double unitPrice, {String? productId, String? size}) {
    final existingIdx = _currentOrderItems.indexWhere((item) => item['sku'] == sku);
    final displayName = (size != null && size.trim().isNotEmpty) ? '$name ($size)' : name;

    if (existingIdx != -1) {
      _currentOrderItems[existingIdx]['qty'] += qty;
    } else {
      _currentOrderItems.add({
        'id': productId ?? sku,
        'sku': sku,
        'name': displayName,
        'size': size ?? '',
        'qty': qty,
        'unitPrice': unitPrice,
      });
    }

    _recalculateOrderTotal();
  }

  void updateProductQty(String sku, int qty) {
    final idx = _currentOrderItems.indexWhere((item) => item['sku'] == sku);
    if (idx != -1) {
      if (qty <= 0) {
        _currentOrderItems.removeAt(idx);
      } else {
        _currentOrderItems[idx]['qty'] = qty;
      }
      _recalculateOrderTotal();
    }
  }

  void _recalculateOrderTotal() {
    _currentOrderTotal = _currentOrderItems.fold(0.0, (sum, item) => sum + (item['qty'] * item['unitPrice']));
    notifyListeners();
  }

  Future<bool> submitOrder(String remarks) async {
    if (_activeVisit == null) return false;
    final visitId = _activeVisit!['id'].toString();
    final trimmedRemarks = remarks.trim();

    if (_currentOrderItems.isEmpty && trimmedRemarks.isEmpty) {
      return false;
    }

    // Stamp ORDER_TOTAL into remarks so admin Logs can show the amount from visit notes.
    final orderTag = 'ORDER_TOTAL=${_currentOrderTotal.toStringAsFixed(2)}';
    final notesWithTotal = _currentOrderItems.isEmpty
        ? trimmedRemarks
        : (trimmedRemarks.isEmpty
            ? orderTag
            : (trimmedRemarks.contains('ORDER_TOTAL=')
                ? trimmedRemarks
                : '$trimmedRemarks|$orderTag'));

    await DatabaseHelper.instance.update(
      'offline_visits',
      {
        'products_ordered': jsonEncode(_currentOrderItems),
        'sales_value': _currentOrderTotal,
        'remarks': notesWithTotal,
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [visitId],
    );

    try {
      final serverOutletId = _activeVisit!['serverOutletId']?.toString();
      final outletId = (serverOutletId != null && serverOutletId.isNotEmpty)
          ? serverOutletId
          : _activeVisit!['outletId']?.toString();
      await _api.submitVisitOrder(
        visitId: visitId,
        outletId: outletId,
        productsOrdered: _currentOrderItems
            .map((item) => {
                  'id': item['id'],
                  'productId': item['id'],
                  'sku': item['sku'],
                  'qty': item['qty'],
                  'quantity': item['qty'],
                  'unitPrice': item['unitPrice'],
                  'price': item['unitPrice'],
                  'name': item['name'],
                })
            .toList(),
        remarks: notesWithTotal.isEmpty ? null : notesWithTotal,
      );
      await DatabaseHelper.instance.update(
        'offline_visits',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [visitId],
      );
    } catch (e) {
      print('submitOrder API failed, kept offline: $e');
    }

    _activeVisit!['productsOrdered'] = _currentOrderItems;
    _activeVisit!['salesValue'] = _currentOrderTotal;
    _activeVisit!['remarks'] = notesWithTotal;
    _applyRemarksToPlannedOutlet(_activeVisit!['outletId']?.toString(), trimmedRemarks);
    notifyListeners();
    return true;
  }

  void _applyRemarksToPlannedOutlet(String? outletId, String remarks) {
    if (outletId == null || outletId.isEmpty) return;
    for (var i = 0; i < _plannedOutlets.length; i++) {
      final o = _plannedOutlets[i];
      if (o is! Map || o['id']?.toString() != outletId) continue;
      final copy = Map<String, dynamic>.from(o);
      copy['visitRemarks'] = remarks;
      copy['remarks'] = remarks;
      // If quick remark includes Next Visit and no date yet, leave date to schedule dialog.
      _plannedOutlets[i] = copy;
      break;
    }
    _persistTodayPlanLocally();
  }

  Future<bool> checkoutOutlet() async {
    if (_activeVisit == null) return false;
    final visitId = _activeVisit!['id'].toString();
    final outletId = _activeVisit!['outletId'];

    final checkoutTime = DateTime.now().toUtc().toIso8601String();
    await DatabaseHelper.instance.update(
      'offline_visits',
      {
        'checkout_time': checkoutTime,
        'synced': 0,
      },
      where: 'id = ?',
      whereArgs: [visitId],
    );

    try {
      double lat = 0;
      double lng = 0;
      try {
        final pos = await DeviceLocation.resolvePosition(timeLimit: const Duration(seconds: 8));
        if (pos != null) {
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}

      // Pass remarks (includes ORDER_TOTAL=…) so admin Logs can read sales from visit notes.
      var checkoutNotes = _activeVisit?['remarks']?.toString() ?? '';
      final sales = double.tryParse(_activeVisit?['salesValue']?.toString() ?? '') ?? _currentOrderTotal;
      if (sales > 0 && !checkoutNotes.contains('ORDER_TOTAL=')) {
        checkoutNotes = checkoutNotes.isEmpty
            ? 'ORDER_TOTAL=${sales.toStringAsFixed(2)}'
            : '$checkoutNotes|ORDER_TOTAL=${sales.toStringAsFixed(2)}';
      }

      await _api.checkoutVisit(
        visitId,
        latitude: lat,
        longitude: lng,
        outcome: 'completed',
        notes: checkoutNotes.isEmpty ? null : checkoutNotes,
      );
      await DatabaseHelper.instance.update(
        'offline_visits',
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [visitId],
      );
    } catch (e) {
      print('checkout API failed, kept offline: $e');
    }

    _markOutletVisitStatus(outletId, 'COMPLETED');
    final remarks = (_activeVisit?['remarks'] ?? '').toString();
    if (remarks.isNotEmpty) {
      _applyRemarksToPlannedOutlet(outletId?.toString(), remarks);
    }

    _activeVisit = null;
    _currentOrderItems = [];
    _currentOrderTotal = 0.0;

    _recomputePlanProgressFromOutlets();
    await _persistTodayPlanLocally();
    // Do NOT call fetchTodayPlan() here — production plan endpoint resets all outlets to PENDING.
    notifyListeners();
    return true;
  }

  /// Clears a stuck open visit (force checkout) so the executive can continue.
  Future<bool> forceCheckoutActiveVisit() async {
    if (_activeVisit == null) {
      await restoreActiveVisitFromLocalDb();
    }
    if (_activeVisit == null) return false;
    return checkoutOutlet();
  }

  Future<List<Map<String, dynamic>>> getOutletVisitHistory(String outletId) async {
    final rows = await DatabaseHelper.instance.queryAll(
      'offline_visits',
      where: 'outlet_id = ?',
      whereArgs: [outletId],
    );

    return rows.reversed.map((visit) {
      final orderedProducts = <Map<String, dynamic>>[];
      final rawProducts = visit['products_ordered']?.toString();
      if (rawProducts != null && rawProducts.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawProducts);
          if (decoded is List) {
            orderedProducts.addAll(decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)));
          }
        } catch (_) {
          // Ignore corrupted local product JSON and keep the rest of the visit history visible.
        }
      }

      return {
        'id': visit['id'],
        'checkInTime': visit['checkin_time'],
        'checkOutTime': visit['checkout_time'],
        'address': visit['address'],
        'remarks': visit['remarks'],
        'products': orderedProducts,
        'salesValue': double.tryParse(visit['sales_value']?.toString() ?? '') ?? 0.0,
      };
    }).toList();
  }

  Future<void> fetchFieldSettings() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.adminSettings);
      if (response.statusCode == 200) {
        final data = _mapFrom(response.data);
        _selfieRequired = data['selfieRequired'] == true;
        final minutes = int.tryParse(data['minVisitDurationMinutes']?.toString() ?? '');
        if (minutes != null) _minimumVisitDurationMinutes = minutes.clamp(1, 120);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('selfie_required', _selfieRequired);
        await prefs.setInt('minimum_visit_duration_minutes', _minimumVisitDurationMinutes);
        notifyListeners();
      }
    } catch (e) {
      print('fetchFieldSettings failed (using local defaults): $e');
    }
  }

  Future<void> setMinimumVisitDurationMinutes(int minutes) async {
    final safeMinutes = minutes.clamp(1, 480);
    _minimumVisitDurationMinutes = safeMinutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('minimum_visit_duration_minutes', safeMinutes);
    notifyListeners();
    await _persistFieldSettings();
  }

  Future<void> setSelfieRequired(bool required) async {
    _selfieRequired = required;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('selfie_required', required);
    notifyListeners();
    await _persistFieldSettings();
  }

  Future<void> _persistFieldSettings() async {
    try {
      await _apiClient.patch(ApiEndpoints.adminSettings, data: {
        'selfieRequired': _selfieRequired,
        'minVisitDurationMinutes': _minimumVisitDurationMinutes,
      });
    } catch (e) {
      print('Persist field settings failed: $e');
    }
  }

  Future<String> exportVisitsCsv({bool share = false}) async {
    // Prefer org-wide visits from API so manager/admin exports are not empty
    // (local offline_visits only has visits from this device).
    final rows = <List<dynamic>>[];
    try {
      final visits = await _api.production.listVisits();
      Map<String, Map<String, dynamic>> usersById = {};
      Map<String, Map<String, dynamic>> outletsById = {};
      try {
        final users = await _api.production.adminUsers();
        for (final u in users) {
          final id = u['id']?.toString();
          if (id != null) usersById[id] = u;
        }
      } catch (_) {}
      try {
        final outlets = await _api.production.outlets();
        for (final o in outlets) {
          final id = o['id']?.toString();
          if (id != null) outletsById[id] = o;
        }
      } catch (_) {}

      for (final visit in visits) {
        final userId = visit['user_id']?.toString() ?? '';
        final outletId = visit['outlet_id']?.toString() ?? '';
        final user = usersById[userId] ?? {};
        final outlet = outletsById[outletId] ?? {};
        final role = (user['role'] ?? '').toString().toLowerCase();
        // Export field executive work only.
        if (role.isNotEmpty && role != 'executive' && role != 'sales_executive') {
          // Keep unknown-role visits (older payloads) if user missing role.
          if (user.isNotEmpty) continue;
        }

        final checkIn = visit['check_in_at']?.toString() ?? visit['checkInTime']?.toString() ?? '';
        final checkOut = visit['check_out_at']?.toString() ?? visit['checkOutTime']?.toString() ?? '';
        final stay = _formatStayDuration(checkIn, checkOut);
        final lat = visit['check_in_lat'] ?? visit['start_latitude'] ?? visit['gpsLat'] ?? '';
        final lng = visit['check_in_lng'] ?? visit['start_longitude'] ?? visit['gpsLng'] ?? '';
        final location = outlet['address'] ??
            visit['check_in_address'] ??
            visit['address'] ??
            ((lat.toString().isNotEmpty && lng.toString().isNotEmpty) ? 'GPS: $lat, $lng' : '');

        rows.add([
          user['name'] ?? user['email'] ?? 'Executive',
          user['email'] ?? '',
          outlet['name'] ?? 'Outlet',
          location,
          checkIn,
          checkOut,
          stay,
          lat,
          lng,
          visit['notes'] ?? visit['remarks'] ?? '',
          visit['status'] ?? '',
        ]);
      }
    } catch (e) {
      print('Org visits export failed, falling back to local: $e');
    }

    if (rows.isEmpty) {
      final localVisits = await DatabaseHelper.instance.queryAll('offline_visits');
      for (final visit in localVisits) {
        final checkIn = visit['checkin_time']?.toString() ?? '';
        final checkOut = visit['checkout_time']?.toString() ?? '';
        final planned = _findOutletById(visit['outlet_id']?.toString() ?? '');
        rows.add([
          _email?.split('@').first ?? 'Executive',
          _email ?? '',
          planned?['name'] ?? 'Outlet',
          visit['address'] ?? planned?['address'] ?? '',
          checkIn,
          checkOut,
          _formatStayDuration(checkIn, checkOut),
          visit['gps_lat'] ?? '',
          visit['gps_lng'] ?? '',
          visit['remarks'] ?? '',
          visit['checkout_time'] != null ? 'completed' : 'open',
        ]);
      }
    }

    final buffer = StringBuffer();
    buffer.writeln(
      'Executive Name,Executive Email,Outlet,Location,Check-in,Check-out,Time Stayed,Latitude,Longitude,Remarks,Status',
    );
    for (final row in rows) {
      buffer.writeln(row.map(_csvCell).join(','));
    }

    final fileName = 'marketing_executive_visits_${DateTime.now().millisecondsSinceEpoch}.csv';
    // Prefer a location users can open in Files / Downloads.
    final file = await _writeExportFile(fileName, buffer.toString());

    // Always offer the system share sheet so the file can be saved to Downloads / Drive / Files.
    // (App-private paths are not visible in the phone Files app.)
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv', name: fileName)],
          subject: 'Executive visit report',
          text: 'Marketing Executives visit report — save to Downloads or Files',
        ),
      );
    } catch (e) {
      print('Share export failed: $e');
    }
    return file.path;
  }

  /// Writes CSV where Android users can find it (public Download when allowed).
  Future<File> _writeExportFile(String fileName, String contents) async {
    if (Platform.isAndroid) {
      final candidates = <Directory>[
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Downloads'),
      ];
      for (final dir in candidates) {
        try {
          if (await dir.exists()) {
            final file = File('${dir.path}/$fileName');
            await file.writeAsString(contents);
            return file;
          }
        } catch (_) {
          // Scoped storage may block — fall through.
        }
      }
    }

    Directory directory;
    try {
      directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      directory = await getApplicationDocumentsDirectory();
    }
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(contents);
    return file;
  }

  String _formatStayDuration(String? checkInIso, String? checkOutIso) {
    final start = DateTime.tryParse(checkInIso ?? '');
    final end = DateTime.tryParse(checkOutIso ?? '');
    if (start == null || end == null) return '';
    final mins = end.difference(start).inMinutes;
    if (mins < 0) return '';
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _productNamesForCsv(dynamic rawProducts) {
    if (rawProducts == null || rawProducts.toString().isEmpty) return '';
    try {
      final decoded = jsonDecode(rawProducts.toString());
      if (decoded is! List) return '';
      return decoded
          .whereType<Map>()
          .map((item) {
            final name = item['name'] ?? item['sku'] ?? 'Product';
            final qty = item['qty'] ?? 0;
            return '$name x$qty';
          })
          .join('; ');
    } catch (_) {
      return '';
    }
  }

  String _csvCell(dynamic value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  void _markOutletVisitStatus(String outletId, String status) {
    for (final outlet in _plannedOutlets) {
      if (outlet is Map && outlet['id']?.toString() == outletId) {
        outlet['visitStatus'] = status;
      }
    }
    for (final outlet in _routeOutlets) {
      if (outlet is Map && outlet['id']?.toString() == outletId) {
        outlet['visitStatus'] = status;
      }
    }
    _recomputePlanProgressFromOutlets();
    // Fire-and-forget persist so completed visits survive refresh.
    _persistTodayPlanLocally();
  }

  // 6. Exception & Incident Reporting
  Future<void> fetchUserIncidents() async {
    final orgId = _region;
    try {
      final response = await _api.userIncidents(_userId ?? '');
      if (response.statusCode == 200) {
        final raw = _responseList(response, 'incidents');
        _userIncidents = raw.map((row) {
          final item = row is Map ? Map<String, dynamic>.from(row) : <String, dynamic>{};
          final rawMap = item['raw'] is Map ? Map<String, dynamic>.from(item['raw'] as Map) : item;
          final status = (item['resolutionStatus'] ?? item['status'] ?? rawMap['status'] ?? 'OPEN')
              .toString()
              .toUpperCase();
          final normalizedStatus = (status == 'RESOLVED' || status == 'CLOSED') ? 'RESOLVED' : 'OPEN';
          return {
            'id': item['id'] ?? rawMap['id'],
            'incidentType': item['incidentType'] ?? item['type'] ?? rawMap['type'] ?? 'OTHER',
            'description': item['description'] ?? rawMap['description'] ?? '',
            'imageUrls': item['imageUrls'] ?? [],
            'videoUrls': item['videoUrls'] ?? [],
            'resolutionStatus': normalizedStatus,
            'createdAt': item['createdAt']?.toString() ?? rawMap['created_at']?.toString() ?? '',
            'userId': item['userId'] ?? rawMap['user_id'],
            'orgId': rawMap['org_id']?.toString() ?? item['orgId']?.toString(),
            'raw': rawMap,
          };
        }).where((inc) {
          // Hard isolation: never show another organisation's incidents.
          if (orgId == null || orgId.isEmpty) return true;
          final incidentOrg = inc['orgId']?.toString();
          if (incidentOrg == null || incidentOrg.isEmpty) return false;
          return incidentOrg == orgId;
        }).toList();
        notifyListeners();
        return;
      }
    } catch (e) {
      print('Fetch incidents API failed: $e');
    }

    try {
      // Avoid leaking previous-org offline incidents into another tenant session.
      if (_isAdminRole()) {
        _userIncidents = [];
        notifyListeners();
        return;
      }
      final localIncidents = await DatabaseHelper.instance.queryAll('offline_incidents');
      _userIncidents = localIncidents.map((row) {
        return {
          'id': row['id'],
          'incidentType': row['incident_type'] ?? 'OTHER',
          'description': row['description'] ?? '',
          'imageUrls': row['image_urls'] != null && row['image_urls'].toString().isNotEmpty
              ? row['image_urls'].toString().split(',')
              : [],
          'videoUrls': row['video_urls'] != null && row['video_urls'].toString().isNotEmpty
              ? row['video_urls'].toString().split(',')
              : [],
          'resolutionStatus': 'OPEN',
          'createdAt': row['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
          'orgId': orgId,
        };
      }).toList();
      notifyListeners();
    } catch (e) {
      print('Fetch local incidents failed: $e');
    }
  }

  Future<bool> resolveIncident(String incidentId, {String notes = 'Resolved by admin'}) async {
    try {
      final response = await _apiClient.patch(
        ApiEndpoints.incidentResolve(incidentId),
        data: {'resolution_notes': notes},
      );
      if (response.statusCode != null && response.statusCode! >= 400) {
        _lastActionError = ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Could not resolve incident.';
        return false;
      }
      final idx = _userIncidents.indexWhere((i) => i is Map && i['id']?.toString() == incidentId);
      if (idx >= 0) {
        _userIncidents[idx] = {
          ...Map<String, dynamic>.from(_userIncidents[idx] as Map),
          'resolutionStatus': 'RESOLVED',
        };
      }
      try {
        // Best-effort local status update; schema may not have this column.
        await DatabaseHelper.instance.update(
          'offline_incidents',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [incidentId],
        );
      } catch (_) {}
      notifyListeners();
      await fetchAdminStats();
      return true;
    } catch (e) {
      _lastActionError = e.toString();
      print('Resolve incident failed: $e');
      return false;
    }
  }

  Future<bool> submitOutletRating({
    required String outletId,
    required int paymentScore,
    required int volumeScore,
    required int cooperationScore,
    required int consistencyScore,
    required int relationshipScore,
  }) async {
    try {
      final response = await _api.submitRating(
        outletId: outletId,
        paymentScore: paymentScore,
        volumeScore: volumeScore,
        cooperationScore: cooperationScore,
        consistencyScore: consistencyScore,
        relationshipScore: relationshipScore,
      );
      return response.statusCode == 201;
    } catch (e) {
      print('submitOutletRating failed: $e');
      return false;
    }
  }

  Future<bool> reportIncident(String type, String description, List<String> imageUrls, List<String> videoUrls) async {
    final normalized = type.trim().toUpperCase().replaceAll(' ', '_');
    final incidentType = switch (normalized) {
      'VEHICLE' || 'VEHICLE_BREAKDOWN' => 'VEHICLE',
      'MEDICAL' || 'MEDICAL_EMERGENCY' => 'MEDICAL',
      'OUTLET_CLOSED' => 'OUTLET_CLOSED',
      'BLOCKED' || 'ROUTE_BLOCKED' => 'BLOCKED',
      _ => 'OTHER',
    };

    final localId = _uuid.v4();
    await DatabaseHelper.instance.insert('offline_incidents', {
      'id': localId,
      'incident_type': incidentType,
      'description': description,
      'image_urls': imageUrls.join(','),
      'video_urls': videoUrls.join(','),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'synced': 0,
    });

    try {
      final response = await _api.createIncident(
        incidentType: incidentType,
        description: description,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
      );
      if (response.statusCode == 201) {
        await DatabaseHelper.instance.update(
          'offline_incidents',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [localId],
        );
      }
    } catch (e) {
      print('Incident API failed, queued offline: $e');
    }

    fetchUserIncidents();
    return true;
  }

  // 7. Smart Lead Generation — potential new shops (Business Finder API)
  Future<void> findNearbyLeads(double lat, double lng, String category) async {
    await searchBusinessDirectory(
      query: category.replaceAll('_', ' '),
      latitude: lat,
      longitude: lng,
      radiusKm: 5,
    );
  }

  Future<void> searchBusinessDirectory({
    required String query,
    String? area,
    double? latitude,
    double? longitude,
    double radiusKm = 5,
  }) async {
    try {
      final results = await _businessData.searchBusinesses(
        query: query,
        area: area,
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );
      _nearbyLeads = results;
      notifyListeners();
    } catch (e) {
      print('Business directory search failed: $e');
      _nearbyLeads = [];
      notifyListeners();
      rethrow;
    }
  }

  /// Replace nearby search results (used when merging multi-area prospect searches).
  void setNearbyLeads(List<Map<String, dynamic>> leads) {
    _nearbyLeads = leads;
    notifyListeners();
  }

  Future<void> fetchSavedLeads() async {
    List<Map<String, dynamic>> apiLeads = [];
    try {
      final response = await _api.listLeads();
      if (response.statusCode == 200) {
        final rawList = _responseList(response, 'leads');
        apiLeads = rawList.map((item) {
          final map = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
          return {
            'id': map['id'],
            'businessName': map['businessName'] ?? map['name'] ?? map['business_name'] ?? 'Unknown Lead',
            'businessCategory': map['businessCategory'] ?? map['business_type'] ?? map['business_category'] ?? 'Business',
            'contactPhone': map['contactPhone'] ?? map['phone'] ?? map['contact_phone'] ?? '',
            'contactEmail': map['contactEmail'] ?? map['email'] ?? map['contact_email'] ?? '',
            'address': map['address'] ?? '',
            'gpsLat': map['gpsLat'] ?? map['gps_lat'] ?? 0,
            'gpsLng': map['gpsLng'] ?? map['gps_lng'] ?? 0,
            'leadStatus': (map['leadStatus'] ?? map['status'] ?? map['lead_status'] ?? 'NEW')
                .toString()
                .toUpperCase(),
          };
        }).toList();
      }
    } catch (e) {
      print('Fetch saved leads failed: $e. Loading from offline database.');
    }

    List<Map<String, dynamic>> localLeads = [];
    try {
      final rows = await DatabaseHelper.instance.queryAll('offline_leads');
      localLeads = rows.map((item) {
        return {
          'id': item['id'],
          'businessName': item['business_name'] ?? 'Unknown Lead',
          'businessCategory': item['business_category'] ?? 'Business',
          'contactPhone': item['contact_phone'] ?? '',
          'contactEmail': item['contact_email'] ?? '',
          'address': item['address'] ?? '',
          'gpsLat': item['gps_lat'] ?? 0,
          'gpsLng': item['gps_lng'] ?? 0,
          'leadStatus': (item['lead_status'] ?? 'NEW').toString().toUpperCase(),
        };
      }).toList();
    } catch (dbError) {
      print('Fetch offline leads failed: $dbError');
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final lead in localLeads) {
      final id = lead['id']?.toString();
      if (id != null) byId[id] = lead;
    }
    for (final lead in apiLeads) {
      final id = lead['id']?.toString();
      if (id != null) {
        final existing = byId[id];
        // Prefer converted status when merging API + local for same id.
        if (existing != null &&
            (existing['leadStatus']?.toString().toUpperCase() == 'CONVERTED') &&
            (lead['leadStatus']?.toString().toUpperCase() != 'CONVERTED')) {
          byId[id] = {...lead, 'leadStatus': 'CONVERTED'};
        } else {
          byId[id] = lead;
        }
      }
    }
    _savedLeads = _dedupeSavedLeadsList(byId.values.toList());
    notifyListeners();
  }

  String _leadIdentityKey(Map lead) {
    return _outletIdentityKey(
      lead['businessName']?.toString(),
      lead['address']?.toString(),
    );
  }

  /// One card per shop (name+address). Prefer CONVERTED when duplicates exist.
  List<Map<String, dynamic>> _dedupeSavedLeadsList(List<Map<String, dynamic>> leads) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final lead in leads) {
      final key = _leadIdentityKey(lead);
      final id = lead['id']?.toString() ?? '';
      final useKey = key != '|' ? key : 'id:$id';
      final existing = byKey[useKey];
      if (existing == null) {
        byKey[useKey] = lead;
        continue;
      }
      final existingConverted = existing['leadStatus']?.toString().toUpperCase() == 'CONVERTED';
      final incomingConverted = lead['leadStatus']?.toString().toUpperCase() == 'CONVERTED';
      if (incomingConverted && !existingConverted) {
        byKey[useKey] = lead;
      }
    }
    return byKey.values.toList();
  }

  Future<void> _markMatchingLeadsConverted({
    required String name,
    required String address,
    required String preferredLeadId,
    String? outletId,
  }) async {
    final identity = _outletIdentityKey(name, address);
    for (var i = 0; i < _savedLeads.length; i++) {
      final item = _savedLeads[i];
      if (item is! Map) continue;
      final sameId = item['id']?.toString() == preferredLeadId;
      final sameShop = identity != '|' && _leadIdentityKey(item) == identity;
      if (!sameId && !sameShop) continue;
      _savedLeads[i] = {
        ...Map<String, dynamic>.from(item),
        'leadStatus': 'CONVERTED',
        if (outletId != null) 'converted_outlet_id': outletId,
      };
    }
    _savedLeads = _dedupeSavedLeadsList(
      _savedLeads.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    );

    try {
      final rows = await DatabaseHelper.instance.queryAll('offline_leads');
      for (final row in rows) {
        final rowName = row['business_name']?.toString() ?? '';
        final rowAddress = row['address']?.toString() ?? '';
        final sameId = row['id']?.toString() == preferredLeadId;
        final sameShop = identity != '|' && _outletIdentityKey(rowName, rowAddress) == identity;
        if (!sameId && !sameShop) continue;
        await DatabaseHelper.instance.update(
          'offline_leads',
          {'lead_status': 'CONVERTED', 'synced': 1},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    } catch (_) {}
  }

  Future<bool> saveLeadRecord(
    String name,
    String category,
    String phone,
    String email,
    double lat,
    double lng, {
    String address = '',
  }) async {
    final identity = _outletIdentityKey(name, address);

    // Already saved (same shop) — keep a single entry.
    if (identity != '|') {
      for (final existing in _savedLeads) {
        if (existing is Map && _leadIdentityKey(existing) == identity) {
          _lastActionError = null;
          await fetchSavedLeads();
          return true;
        }
      }
      try {
        final rows = await DatabaseHelper.instance.queryAll('offline_leads');
        for (final row in rows) {
          if (_outletIdentityKey(row['business_name']?.toString(), row['address']?.toString()) == identity) {
            await fetchSavedLeads();
            return true;
          }
        }
      } catch (_) {}
    }

    String leadId = _uuid.v4();
    var synced = 0;

    try {
      final response = await _api.saveLead({
        'name': name,
        'businessName': name,
        'businessCategory': category,
        'category': category,
        'phone': phone,
        'contactPhone': phone,
        'email': email,
        'contactEmail': email,
        'address': address,
        'gpsLat': lat,
        'gpsLng': lng,
      });
      if (response.statusCode == 200 || response.statusCode == 201) {
        final created = _mapFrom(response.data['lead'] ?? response.data['data']);
        // Nested unwrap when FieldApiService wraps again
        final nested = _mapFrom(_mapFrom(response.data)['data']);
        final leadMap = created.isNotEmpty ? created : _mapFrom(nested['lead']);
        leadId = leadMap['id']?.toString() ?? leadId;
        synced = 1;
      }
    } catch (e) {
      print('Save lead API failed. Queuing locally: $e');
    }

    await DatabaseHelper.instance.insert('offline_leads', {
      'id': leadId,
      'business_name': name,
      'business_category': category,
      'contact_phone': phone,
      'contact_email': email,
      'address': address,
      'gps_lat': lat,
      'gps_lng': lng,
      'lead_status': 'NEW',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'synced': synced,
    });
    await fetchSavedLeads();
    return true;
  }

  String? _convertingLeadId;
  String? get convertingLeadId => _convertingLeadId;
  bool get isConvertingLead => _convertingLeadId != null;

  String _outletIdentityKey(String? name, String? address) {
    final n = (name ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final a = (address ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '$n|$a';
  }

  /// Removes duplicate planned outlets (same id or same name+address).
  void dedupePlannedOutlets() {
    final before = _plannedOutlets.length;
    _dedupePlannedOutlets();
    if (_plannedOutlets.length != before) {
      _persistTodayPlanLocally();
      notifyListeners();
    }
  }

  void _dedupePlannedOutlets() {
    final seenIds = <String>{};
    final seenKeys = <String>{};
    final seenNames = <String>{};
    final unique = <dynamic>[];
    for (final outlet in _plannedOutlets) {
      if (outlet is! Map) continue;
      final id = outlet['id']?.toString() ?? '';
      final nameOnly = (outlet['name'] ?? '')
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ');
      final key = _outletIdentityKey(outlet['name']?.toString(), outlet['address']?.toString());
      // Same server id, same name+address, or same shop name → keep first only.
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      if (key != '|' && !seenKeys.add(key)) continue;
      if (nameOnly.isNotEmpty && !seenNames.add(nameOnly)) continue;
      unique.add(outlet);
    }
    if (unique.length != _plannedOutlets.length) {
      _plannedOutlets = unique;
      _plannedVisitsCount = _plannedOutlets.length;
      if (_todayPlan != null) _todayPlan!['planned_visits'] = _plannedVisitsCount;
      if (_plannedVisitsCount > 0) {
        _completedVisitsCount = _plannedOutlets.where((o) => o is Map && o['visitStatus'] == 'COMPLETED').length;
        _planProgressPercentage = (_completedVisitsCount / _plannedVisitsCount) * 100.0;
      }
    }
  }

  Future<bool> convertLeadToOutlet(String leadId) async {
    if (_convertingLeadId != null) {
      _lastActionError = 'Conversion already in progress. Please wait.';
      return false;
    }

    _convertingLeadId = leadId;
    _lastActionError = null;
    notifyListeners();

    try {
      final lead = await _resolveLeadDetails(leadId);
      if (lead == null) {
        _lastActionError = 'Lead details not found. Save the prospect again, then convert.';
        return false;
      }

      final status = (lead['leadStatus'] ?? '').toString().toUpperCase();

      final name = lead['businessName']?.toString() ?? 'Outlet';
      final category = lead['businessCategory']?.toString() ?? 'Business';
      final phone = lead['contactPhone']?.toString() ?? '';
      final email = lead['contactEmail']?.toString() ?? '';
      final address = (lead['address']?.toString().isNotEmpty ?? false)
          ? lead['address'].toString()
          : '$name ($category)';
      final lat = double.tryParse(lead['gpsLat']?.toString() ?? '') ?? 0.0;
      final lng = double.tryParse(lead['gpsLng']?.toString() ?? '') ?? 0.0;
      final identity = _outletIdentityKey(name, address);

      // Any duplicate of this shop already converted → sync all copies and stop.
      final alreadyConvertedTwin = _savedLeads.whereType<Map>().any((l) {
        if (l['leadStatus']?.toString().toUpperCase() != 'CONVERTED') return false;
        return identity != '|' && _leadIdentityKey(l) == identity;
      });
      if (status == 'CONVERTED' || alreadyConvertedTwin) {
        await _markMatchingLeadsConverted(
          name: name,
          address: address,
          preferredLeadId: leadId,
        );
        _lastActionError = 'This lead is already converted.';
        return false;
      }

      // Already on today's plan (same shop) — mark converted, do not add again.
      final existingPlanned = _plannedOutlets.cast<dynamic>().whereType<Map>().where((o) {
        final idMatch = o['id']?.toString() == lead['converted_outlet_id']?.toString();
        final keyMatch = _outletIdentityKey(o['name']?.toString(), o['address']?.toString()) == identity;
        return idMatch || (identity != '|' && keyMatch);
      }).toList();

      String outletId = existingPlanned.isNotEmpty
          ? existingPlanned.first['id']?.toString() ?? _uuid.v4()
          : _uuid.v4();

      if (existingPlanned.isEmpty) {
        try {
          final created = await _api.production.convertLead(leadId, lead: {
            'id': leadId,
            'name': name,
            'businessName': name,
            'phone': phone,
            'contactPhone': phone,
            'email': email,
            'contactEmail': email,
            'address': address,
            'gpsLat': lat,
            'gpsLng': lng,
            'latitude': lat,
            'longitude': lng,
          });
          if (created != null && created['id'] != null) {
            outletId = created['id'].toString();
          }
        } catch (e) {
          print('Convert lead API failed: $e');
          _lastActionError = 'Could not convert on server. Try again.';
          return false;
        }

        if (_todayPlan == null) {
          _todayPlan = {
            'id': 'local-plan-${_uuid.v4()}',
            'route_id': 'converted',
            'planned_visits': 0,
          };
        }

        final alreadyPlanned = _plannedOutlets.any((o) {
          if (o is! Map) return false;
          if (o['id']?.toString() == outletId) return true;
          return _outletIdentityKey(o['name']?.toString(), o['address']?.toString()) == identity;
        });
        if (!alreadyPlanned) {
          // Newest converted outlet at the top of Planned.
          _plannedOutlets = [
            {
              'id': outletId,
              'name': name,
              'address': address,
              'latitude': lat,
              'longitude': lng,
              'visitStatus': 'PENDING',
              'source': 'converted_lead',
              'fromLeadId': leadId,
            },
            ..._plannedOutlets,
          ];
        }
        _dedupePlannedOutlets();
        _plannedVisitsCount = _plannedOutlets.length;
        _todayPlan!['planned_visits'] = _plannedVisitsCount;
        await _persistTodayPlanLocally();
      }

      await _markMatchingLeadsConverted(
        name: name,
        address: address,
        preferredLeadId: leadId,
        outletId: outletId,
      );

      _lastActionError = null;
      notifyListeners();
      return true;
    } finally {
      _convertingLeadId = null;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> _resolveLeadDetails(String leadId) async {
    Map<String, dynamic>? fromMemory;
    for (final item in _savedLeads) {
      if (item is Map && item['id']?.toString() == leadId) {
        fromMemory = Map<String, dynamic>.from(item);
        break;
      }
    }
    if (fromMemory != null &&
        (fromMemory['gpsLat'] != null || fromMemory['businessName'] != null)) {
      return fromMemory;
    }

    try {
      final rows = await DatabaseHelper.instance.queryAll(
        'offline_leads',
        where: 'id = ?',
        whereArgs: [leadId],
      );
      if (rows.isEmpty) return fromMemory;
      final row = rows.first;
      return {
        'id': row['id'],
        'businessName': row['business_name'],
        'businessCategory': row['business_category'],
        'contactPhone': row['contact_phone'] ?? '',
        'contactEmail': row['contact_email'] ?? '',
        'address': row['address'] ?? '',
        'gpsLat': row['gps_lat'] ?? 0,
        'gpsLng': row['gps_lng'] ?? 0,
        'leadStatus': row['lead_status'] ?? 'NEW',
      };
    } catch (_) {
      return fromMemory;
    }
  }

  // 8. Intelligent Route Optimization
  Future<bool> generateOptimizedRoute(List<String> outletIds, List<String> leadIds, double startLat, double startLng) async {
    final remainingOutlets = <Map<String, dynamic>>[];

    for (final outlet in _plannedOutlets) {
      if (outlet is! Map<String, dynamic>) continue;
      final outletId = outlet['id']?.toString();
      final latitude = double.tryParse(outlet['latitude']?.toString() ?? '');
      final longitude = double.tryParse(outlet['longitude']?.toString() ?? '');

      if (outletId == null || latitude == null || longitude == null) continue;
      // Skip Null Island / invalid pins that create world-spanning “routes”.
      if (latitude.abs() < 0.01 && longitude.abs() < 0.01) continue;
      if (latitude < -85 || latitude > 85 || longitude < -180 || longitude > 180) continue;
      if (outletIds.isNotEmpty && !outletIds.contains(outletId)) continue;

      remainingOutlets.add({
        ...outlet,
        'latitude': latitude,
        'longitude': longitude,
      });
    }

    // Drop far outliers from the GPS start so a bad pin can't create a continent-spanning route.
    remainingOutlets.removeWhere((o) {
      final d = _calculateHaversineDistance(
        startLat,
        startLng,
        o['latitude'] as double,
        o['longitude'] as double,
      );
      return d > 250;
    });

    if (remainingOutlets.isEmpty) {
      _optimizedRoute = null;
      notifyListeners();
      return false;
    }

    final stopSequence = <Map<String, dynamic>>[];
    var currentLat = startLat;
    var currentLng = startLng;
    var totalDistanceKm = 0.0;

    while (remainingOutlets.isNotEmpty) {
      remainingOutlets.sort((a, b) {
        final distanceA = _calculateHaversineDistance(currentLat, currentLng, a['latitude'] as double, a['longitude'] as double);
        final distanceB = _calculateHaversineDistance(currentLat, currentLng, b['latitude'] as double, b['longitude'] as double);
        return distanceA.compareTo(distanceB);
      });

      final nextOutlet = remainingOutlets.removeAt(0);
      final nextLat = nextOutlet['latitude'] as double;
      final nextLng = nextOutlet['longitude'] as double;
      final distanceFromPreviousKm = _calculateHaversineDistance(currentLat, currentLng, nextLat, nextLng);
      totalDistanceKm += distanceFromPreviousKm;

      stopSequence.add({
        'id': nextOutlet['id'],
        'name': nextOutlet['name'] ?? 'Outlet',
        'address': nextOutlet['address'] ?? 'Address not available',
        'latitude': nextLat,
        'longitude': nextLng,
        'order': stopSequence.length + 1,
        'distanceFromPreviousKm': distanceFromPreviousKm,
      });

      currentLat = nextLat;
      currentLng = nextLng;
    }

    _optimizedRoute = {
      'id': _uuid.v4(),
      'totalStops': stopSequence.length,
      'estimatedDistanceKm': totalDistanceKm,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'startLatitude': startLat,
      'startLongitude': startLng,
      'stopSequence': stopSequence,
    };
    notifyListeners();
    return true;
  }

  Future<bool> skipRouteStop(String stopId) async {
    return true;
  }

  // 11. Offline Sync Engine
  Future<void> syncOfflineData() async {
    print('[Sync Engine] Starting background sync...');

    // 1. GPS pings
    final offlinePings = await DatabaseHelper.instance.queryAll('offline_gps_pings', where: 'synced = 0');
    for (final ping in offlinePings) {
      try {
        final deviceId = await DeviceId.get();
        final response = await _api.gpsPing(
          latitude: double.parse(ping['latitude'].toString()),
          longitude: double.parse(ping['longitude'].toString()),
          trackingStartPoint: ping['tracking_start_point']?.toString() ?? _odometerStartPoint,
          timestamp: ping['timestamp']?.toString(),
          address: ping['address']?.toString(),
          deviceId: deviceId,
          offlineId: ping['id']?.toString(),
        );
        if (response.statusCode == 201 || response.statusCode == 200) {
          await DatabaseHelper.instance.update(
            'offline_gps_pings',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [ping['id']],
          );
        }
      } catch (e) {
        print('[Sync Engine] GPS ping sync failed: $e');
      }
    }

    // 2. Visits (check-in / order / checkout)
    final offlineVisits = await DatabaseHelper.instance.queryAll('offline_visits', where: 'synced = 0');
    for (final visit in offlineVisits) {
      try {
        final visitId = visit['id'].toString();
        final hasCheckout = visit['checkout_time'] != null;

        // If never checked in on server (local UUID may still be local), re-checkin
        // is skipped when already present; order + checkout are best-effort.
        if (visit['products_ordered'] != null || (visit['remarks']?.toString().isNotEmpty ?? false)) {
          List<Map<String, dynamic>> products = [];
          try {
            final decoded = jsonDecode(visit['products_ordered']?.toString() ?? '[]');
            if (decoded is List) {
              products = decoded
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          } catch (_) {}

          await _api.submitVisitOrder(
            visitId: visitId,
            productsOrdered: products
                .map((item) => {
                      'sku': item['sku'],
                      'qty': item['qty'],
                      'unitPrice': item['unitPrice'] ?? item['unit_price'],
                      'name': item['name'],
                    })
                .toList(),
            remarks: visit['remarks']?.toString(),
          );
        }

        if (hasCheckout) {
          await _api.checkoutVisit(visitId);
        }

        await DatabaseHelper.instance.update(
          'offline_visits',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [visitId],
        );
      } catch (e) {
        print('[Sync Engine] Visit sync failed: $e');
      }
    }

    // 3. Incidents
    final offlineIncidents = await DatabaseHelper.instance.queryAll('offline_incidents', where: 'synced = 0');
    for (final incident in offlineIncidents) {
      try {
        final response = await _api.createIncident(
          incidentType: incident['incident_type'].toString(),
          description: incident['description'].toString(),
          imageUrls: (incident['image_urls']?.toString() ?? '')
              .split(',')
              .where((s) => s.isNotEmpty)
              .toList(),
          videoUrls: (incident['video_urls']?.toString() ?? '')
              .split(',')
              .where((s) => s.isNotEmpty)
              .toList(),
        );
        if (response.statusCode == 201) {
          await DatabaseHelper.instance.update(
            'offline_incidents',
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [incident['id']],
          );
        }
      } catch (e) {
        print('[Sync Engine] Incident sync failed: $e');
      }
    }

    // 4. Leads
    final offlineLeads = await DatabaseHelper.instance.queryAll('offline_leads', where: 'synced = 0');
    for (final lead in offlineLeads) {
      try {
        final response = await _api.saveLead({
          'businessName': lead['business_name'],
          'businessCategory': lead['business_category'],
          'contactPhone': lead['contact_phone'],
          'contactEmail': lead['contact_email'],
          'gpsLat': lead['gps_lat'],
          'gpsLng': lead['gps_lng'],
        });
        if (response.statusCode == 201) {
          await DatabaseHelper.instance.delete('offline_leads', where: 'id = ?', whereArgs: [lead['id']]);
        }
      } catch (e) {
        print('[Sync Engine] Lead sync failed: $e');
      }
    }

    print('[Sync Engine] Sync complete.');
    if (_role == 'admin' ||
        _role == 'manager' ||
        _role == 'super_admin' ||
        _role == 'SUPER_ADMIN' ||
        _role == 'REGIONAL_MANAGER' ||
        _role == 'SALES_MANAGER') {
      fetchAdminDashboardData();
    } else {
      fetchTodayLiveSummary();
      fetchTodayPlan();
      fetchSavedLeads();
      fetchUserIncidents();
      refreshGpsSummaryFromServer();
    }
  }

  // 12. Admin & Manager Oversight Methods
  Future<void> fetchAdminDashboardData() async {
    await fetchAdminUsersList();
    await fetchAdminLiveVisitsList();
    await fetchAdminLiveGpsList();
    await fetchAdminStats();
    await fetchOrgSubscription();
    await fetchUserIncidents();
    if ((_role ?? '').toLowerCase() == 'super_admin') {
      await fetchPendingOrganisations();
      await fetchManagedOrganisations();
    }
  }

  String? _lastActionError;
  String? get lastActionError => _lastActionError;

  Future<void> fetchAdminStats() async {
    Map<String, dynamic> serverStats = {};
    try {
      final response = await _apiClient.get(ApiEndpoints.adminStats);
      if (response.statusCode == 200) {
        serverStats = Map<String, dynamic>.from(response.data['data'] ?? {});
      }
    } catch (e) {
      print('Fetch admin stats failed: $e. Generating local fallback analytics.');
    }

    final localVisits = await DatabaseHelper.instance.queryAll('offline_visits');
    final localGps = await DatabaseHelper.instance.queryAll('offline_gps_pings');
    final localIncidents = await DatabaseHelper.instance.queryAll('offline_incidents');

    final totalUsers = _adminUsersList.isNotEmpty
        ? _adminUsersList.length
        : (serverStats['total_users'] ?? 0);

    final activeExecutives = _adminUsersList
        .where((u) =>
            u is Map &&
            u['role'] == 'executive' &&
            (u['status'] == 'active' || u['status'] == null))
        .length;

    final completedVisits = localVisits.where((v) => v['checkout_time'] != null).length;

    final salesValueTotal = localVisits.fold<double>(0.0, (sum, visit) {
      return sum + (double.tryParse(visit['sales_value']?.toString() ?? '') ?? 0.0);
    });

    double distanceKm = 0.0;
    for (var i = 1; i < localGps.length; i++) {
      final prevLat = double.tryParse(localGps[i - 1]['latitude']?.toString() ?? '');
      final prevLng = double.tryParse(localGps[i - 1]['longitude']?.toString() ?? '');
      final currLat = double.tryParse(localGps[i]['latitude']?.toString() ?? '');
      final currLng = double.tryParse(localGps[i]['longitude']?.toString() ?? '');
      if (prevLat != null && prevLng != null && currLat != null && currLng != null) {
        distanceKm += _calculateHaversineDistance(prevLat, prevLng, currLat, currLng);
      }
    }

    final openIncidents = _userIncidents.where((i) {
      if (i is! Map) return false;
      return (i['resolutionStatus'] ?? 'OPEN').toString().toUpperCase() != 'RESOLVED';
    }).length;

    final orgFromServer = serverStats['org'] is Map
        ? Map<String, dynamic>.from(serverStats['org'] as Map)
        : <String, dynamic>{};

    _adminStats = {
      ...serverStats,
      'total_users': totalUsers,
      'active_executives': activeExecutives,
      'distance_covered_km': distanceKm,
      'visits_completed': completedVisits,
      'sales_value_total': salesValueTotal,
      'open_incidents_count': openIncidents,
      'org': {
        ...orgFromServer,
        'name': orgFromServer['name'] ?? 'Organisation',
        // Always show the signed-in admin email, not a generic org mailbox.
        'email': _email ?? orgFromServer['email'] ?? '—',
        'status': orgFromServer['status'] ?? 'active',
      },
    };
    if (_isPlatformSuperAdmin || _isAddPhoneBookOrg) {
      // Platform owner / AddPhoneBook — never bind a tenant trial to their session UI.
      _orgSubscription = null;
    } else if (orgFromServer.isNotEmpty) {
      _orgSubscription = {...?_orgSubscription, ...orgFromServer};
      final slug = orgFromServer['slug']?.toString();
      if (slug != null && slug.isNotEmpty) {
        _orgSlug = slug;
      }
    }

    notifyListeners();
  }

  Future<void> fetchAdminUsersList() async {
    try {
      final response = await _api.adminUsers();
      if (response.statusCode != 200) {
        _adminUsersList = [];
        notifyListeners();
        return;
      }

      final raw = _responseList(response, 'users');
      // Attendance / online is not on /users.status (that is account active/inactive).
      // Derive live presence from org attendance + open visits.
      Map<String, Map<String, dynamic>> visitByUser = {};
      Map<String, Map<String, dynamic>> attendanceByUser = {};
      try {
        final attendance = await _api.attendanceList(page: 1, perPage: 100);
        for (final row in attendance) {
          final userId = (row['user_id'] ?? row['userId'] ?? '').toString();
          if (userId.isEmpty) continue;
          final existing = attendanceByUser[userId];
          final checkIn = (row['check_in_at'] ?? row['checkInAt'] ?? '').toString();
          final existingIn = (existing?['check_in_at'] ?? '').toString();
          if (existing == null || checkIn.compareTo(existingIn) > 0) {
            attendanceByUser[userId] = Map<String, dynamic>.from(row);
          }
        }
      } catch (_) {}
      try {
        final visits = await _api.production.listVisits();
        for (final visit in visits) {
          final userId = visit['user_id']?.toString();
          if (userId == null || userId.isEmpty) continue;
          final existing = visitByUser[userId];
          final checkIn = visit['check_in_at']?.toString();
          final existingIn = existing?['check_in_at']?.toString();
          final newer = existing == null ||
              (checkIn != null &&
                  existingIn != null &&
                  checkIn.compareTo(existingIn) > 0) ||
              (checkIn != null && existingIn == null);
          if (newer) visitByUser[userId] = Map<String, dynamic>.from(visit);
        }
      } catch (_) {}

      _adminUsersList = raw.map((item) {
        final u = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
        final id = u['id']?.toString() ?? '';
        final accountStatus = (u['status'] ?? 'active').toString().toLowerCase();
        final visit = visitByUser[id];
        final attendance = attendanceByUser[id];
        final checkInAt = attendance?['check_in_at']?.toString() ??
            visit?['check_in_at']?.toString() ??
            u['check_in_at']?.toString() ??
            u['checkInAt']?.toString();
        final checkOutAt = attendance?['check_out_at']?.toString() ??
            visit?['check_out_at']?.toString() ??
            u['check_out_at']?.toString() ??
            u['checkOutAt']?.toString();
        final visitStatus = (visit?['status'] ?? '').toString().toLowerCase();
        final attendanceOpen = attendance != null &&
            (attendance['check_out_at'] == null ||
                (attendance['check_out_at']?.toString().isEmpty ?? true));
        final hasOpenVisit = visit != null &&
            checkInAt != null &&
            checkInAt.isNotEmpty &&
            (checkOutAt == null || checkOutAt.isEmpty) &&
            visitStatus != 'completed';
        final checkedInToday = checkInAt != null && _isSameLocalDay(checkInAt, DateTime.now());
        var isOnline = attendanceOpen ||
            hasOpenVisit ||
            (checkedInToday && (checkOutAt == null || checkOutAt.isEmpty));
        // Logged-in manager/admin on this device counts as online (they don't do field visits).
        if (!isOnline && id.isNotEmpty && id == _userId) {
          isOnline = true;
        }

        final role = (u['role'] ?? '').toString().toLowerCase();
        final isExecutive = role == 'executive' || role == 'sales_executive';
        final isSelf = id.isNotEmpty && id == _userId;
        final privilegedTarget =
            role == 'admin' || role == 'super_admin' || role == 'manager' || role == 'sales_manager' || role == 'regional_manager';

        return {
          'id': id,
          'name': u['name'] ?? u['email'] ?? 'User',
          'email': u['email'] ?? '',
          'phone': u['phone'] ?? '',
          'role': u['role'] ?? '',
          'accountStatus': accountStatus,
          'status': accountStatus, // keep for older UI
          'isOnline': isOnline,
          'designation': u['designation'] ?? u['role'] ?? 'Field Agent',
          'check_in_at': checkInAt,
          'check_out_at': checkOutAt,
          'lastVisitStatus': visitStatus,
          'lastVisitOutletId': visit?['outlet_id'],
          // Admin/manager: edit executives only; never delete managers/admins/self.
          'canEdit': isExecutive,
          'canDelete': isExecutive && !isSelf && !privilegedTarget,
          'raw': u,
        };
      }).where((u) {
        return !_isHiddenFromOrgActivity(
          role: u['role']?.toString(),
          name: u['name']?.toString(),
          email: u['email']?.toString(),
        );
      }).toList();
      notifyListeners();
    } catch (e) {
      print('Fetch admin users list failed: $e');
      _adminUsersList = [];
      notifyListeners();
    }
  }

  Future<bool> updateExecutive({
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? password,
    String? status,
    String? designation,
  }) async {
    _lastActionError = null;
    try {
      final body = <String, dynamic>{
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (phone != null) 'phone': phone.trim(),
        if (password != null && password.isNotEmpty) 'password': password,
        if (status != null && status.isNotEmpty) 'status': status,
        if (designation != null && designation.trim().isNotEmpty) 'designation': designation.trim(),
      };
      if (body.isEmpty) {
        _lastActionError = 'Nothing to update.';
        return false;
      }
      await _api.production.updateUser(userId, body);
      await fetchAdminUsersList();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not update user.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> deleteExecutive(String userId) async {
    _lastActionError = null;
    try {
      final ok = await _api.production.deleteUser(userId);
      if (!ok) {
        _lastActionError = 'Delete failed on server.';
        return false;
      }
      await fetchAdminUsersList();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? 'Could not delete user.';
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  /// Creates a team member. [role] is `executive`, `manager`, or `admin`.
  Future<bool> createExecutive(
    String name,
    String email,
    String password, {
    String role = 'executive',
  }) async {
    _isLoading = true;
    _lastActionError = null;
    notifyListeners();

    final normalizedRole = role.trim().toLowerCase();
    final allowed = {'executive', 'manager', 'admin'};
    if (!allowed.contains(normalizedRole)) {
      _lastActionError = 'Role must be admin, manager, or executive.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
    if (!isValidLoginEmail(email)) {
      _lastActionError = 'Invalid email address. Check for typos (e.g. .com.com).';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Managers may only create executives; org admins can create all three.
    final myRole = (_role ?? '').toLowerCase();
    if (myRole == 'manager' || myRole == 'sales_manager' || myRole == 'regional_manager') {
      if (normalizedRole != 'executive') {
        _lastActionError = 'Managers can only create executive accounts.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    }

    try {
      await _api.production.createUser({
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'role': normalizedRole,
      });
      _isLoading = false;
      await fetchAdminUsersList();
      await fetchAdminStats();
      notifyListeners();
      return true;
    } on DioException catch (e) {
      final msg = ApiClient.errorMessage(e) ?? 'Could not create user.';
      if ((e.response?.statusCode == 403) || msg.toLowerCase().contains('permission')) {
        _lastActionError =
            'Your role cannot create users on the server (needs admin). '
            'Super admin must be allowed by the API, or use an organisation admin account.';
      } else {
        _lastActionError = msg;
      }
      print('Create user failed: $_lastActionError');
    } catch (e) {
      _lastActionError = e.toString();
      print('Create user failed: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Returns null on success (sets [pendingMessage]), or an error string.
  Future<String?> registerOrganisation({
    required String orgName,
    required String orgSlug,
    required String ownerName,
    required String ownerEmail,
    required String ownerPassword,
    String? orgEmail,
    String? orgPhone,
    String? orgAddress,
    String? ownerPhone,
  }) async {
    try {
      final slug = orgSlug.trim().toLowerCase();
      await _api.production.registerOrganisation({
        'org_name': orgName.trim(),
        'org_slug': slug,
        'owner_name': ownerName.trim(),
        'owner_email': ownerEmail.trim(),
        'owner_password': ownerPassword,
        if (orgEmail != null && orgEmail.trim().isNotEmpty) 'org_email': orgEmail.trim(),
        if (orgPhone != null && orgPhone.trim().isNotEmpty) 'org_phone': orgPhone.trim(),
        if (orgAddress != null && orgAddress.trim().isNotEmpty) 'org_address': orgAddress.trim(),
        if (ownerPhone != null && ownerPhone.trim().isNotEmpty) 'owner_phone': ownerPhone.trim(),
      });

      // Keep full registration payload locally so super-admin can view slug + credentials.
      await OrganisationRegistry.upsert({
        'name': orgName.trim(),
        'slug': slug,
        'email': orgEmail?.trim(),
        'phone': orgPhone?.trim(),
        'address': orgAddress?.trim(),
        'owner_name': ownerName.trim(),
        'owner_email': ownerEmail.trim(),
        'owner_password': ownerPassword,
        'owner_phone': ownerPhone?.trim(),
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      return null;
    } on DioException catch (e) {
      return ApiClient.errorMessage(e) ?? 'Could not submit organisation request.';
    } catch (e) {
      return e.toString();
    }
  }

  List<Map<String, dynamic>> _pendingOrgs = [];
  List<Map<String, dynamic>> get pendingOrganisations => _pendingOrgs;

  List<Map<String, dynamic>> _managedOrganisations = [];
  List<Map<String, dynamic>> get managedOrganisations => _managedOrganisations;

  Future<void> fetchPendingOrganisations() async {
    try {
      final pending = await _api.production.pendingOrganisations();
      final enriched = <Map<String, dynamic>>[];
      for (final org in pending) {
        final slug = (org['slug'] ?? org['org_slug'] ?? '').toString();
        final local = slug.isNotEmpty ? await OrganisationRegistry.findBySlug(slug) : null;
        // Prefer non-null local registration details over sparse API pending payload.
        final merged = <String, dynamic>{
          ...org,
          if (local != null) ...local,
          'id': org['id'] ?? local?['id'],
          'slug': slug.isNotEmpty ? slug : (local?['slug'] ?? ''),
          'name': org['name'] ?? local?['name'] ?? 'Organisation',
          'email': _firstNonEmpty([org['email'], local?['email'], local?['org_email']]),
          'phone': _firstNonEmpty([org['phone'], local?['phone'], local?['org_phone']]),
          'address': _firstNonEmpty([org['address'], local?['address'], local?['org_address']]),
          'owner_name': _firstNonEmpty([org['owner_name'], local?['owner_name']]),
          'owner_email': _firstNonEmpty([org['owner_email'], local?['owner_email']]),
          'owner_password': _firstNonEmpty([org['owner_password'], local?['owner_password']]),
          'owner_phone': _firstNonEmpty([org['owner_phone'], local?['owner_phone']]),
          'status': org['status'] ?? local?['status'] ?? 'pending',
        };
        enriched.add(merged);
        await OrganisationRegistry.upsert(merged);
      }
      _pendingOrgs = enriched;
      await fetchManagedOrganisations();
      notifyListeners();
    } catch (e) {
      print('Fetch pending orgs failed: $e');
      _pendingOrgs = [];
      notifyListeners();
    }
  }

  Future<void> fetchManagedOrganisations() async {
    await OrganisationRegistry.ensureKnownOrganisations();
    final all = await OrganisationRegistry.loadAll();
    all.sort((a, b) {
      final aa = (a['updated_at'] ?? a['created_at'] ?? '').toString();
      final bb = (b['updated_at'] ?? b['created_at'] ?? '').toString();
      return bb.compareTo(aa);
    });
    _managedOrganisations = all;
    notifyListeners();
  }

  Future<bool> approveOrganisation(String orgId) async {
    _lastApproveSubscriptionSummary = null;
    _lastActionError = null;
    try {
      final result = await _api.production.approveOrganisation(orgId);
      if (result == null) {
        _lastActionError = 'Approve failed. Try again or check server logs.';
        return false;
      }
      final orgPayload = result['org'] is Map
          ? Map<String, dynamic>.from(result['org'] as Map)
          : (result['id'] != null ? result : <String, dynamic>{});

      final fromPending = _pendingOrgs.cast<Map<String, dynamic>?>().firstWhere(
            (o) => o?['id']?.toString() == orgId,
            orElse: () => null,
          );
      final local = fromPending ?? await OrganisationRegistry.findById(orgId);
      final trialEnds = orgPayload['trial_ends_at']?.toString();
      final graceEnds = orgPayload['grace_period_ends_at']?.toString();
      final subStatus = orgPayload['subscription_status']?.toString() ?? 'trialing';

      await OrganisationRegistry.upsert({
        ...?local,
        ...orgPayload,
        'id': orgId,
        'status': 'active',
        'subscription_status': subStatus,
        if (trialEnds != null) 'trial_ends_at': trialEnds,
        if (graceEnds != null) 'grace_period_ends_at': graceEnds,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (trialEnds != null || graceEnds != null) {
        final trialLocal = DateTime.tryParse(trialEnds ?? '')?.toLocal();
        final graceLocal = DateTime.tryParse(graceEnds ?? '')?.toLocal();
        _lastApproveSubscriptionSummary =
            'Approved with free trial'
            '${trialLocal != null ? ' until ${trialLocal.day}/${trialLocal.month}/${trialLocal.year}' : ' (7 days)'}'
            '${graceLocal != null ? '. Grace until ${graceLocal.day}/${graceLocal.month}/${graceLocal.year}' : ' + 3-day grace'}'
            '. Access locks after grace until payment.';
      } else {
        _lastApproveSubscriptionSummary =
            'Organisation approved. Server stamps 7-day trial + 3-day grace; access locks after 10 days until payment.';
      }

      await fetchPendingOrganisations();
      await fetchManagedOrganisations();
      return true;
    } on DioException catch (e) {
      if (ApiClient.isSubscriptionExpired(e)) {
        _lastActionError = ApiClient.subscriptionExpiredUserMessage;
      } else {
        _lastActionError = ApiClient.errorMessage(e) ?? e.toString();
      }
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<bool> rejectOrganisation(String orgId) async {
    try {
      final ok = await _api.production.rejectOrganisation(orgId);
      if (ok) {
        final fromPending = _pendingOrgs.cast<Map<String, dynamic>?>().firstWhere(
              (o) => o?['id']?.toString() == orgId,
              orElse: () => null,
            );
        final local = fromPending ?? await OrganisationRegistry.findById(orgId);
        await OrganisationRegistry.upsert({
          ...?local,
          'id': orgId,
          'status': 'rejected',
          'rejected_at': DateTime.now().toUtc().toIso8601String(),
        });
        await fetchPendingOrganisations();
        await fetchManagedOrganisations();
      }
      if (!ok) _lastActionError = 'Reject failed. Try again or check server logs.';
      return ok;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  /// Load subscription fields for the signed-in org admin (GET /admin/org).
  Future<void> fetchOrgSubscription() async {
    if ((_role ?? '').toLowerCase() == 'super_admin') return; // platform SA has no single tenant org
    try {
      final org = await _api.production.getAdminOrg();
      if (org != null) {
        _orgSubscription = org;
        if (_adminStats != null) {
          _adminStats = {
            ..._adminStats!,
            'org': {
              ..._mapFrom(_adminStats!['org']),
              ...org,
            },
          };
        }
        notifyListeners();
      }
    } on DioException catch (e) {
      if (ApiClient.isSubscriptionExpired(e)) {
        await consumeSubscriptionLockMessage();
        _loginError = ApiClient.subscriptionExpiredUserMessage;
        _isAuthenticated = false;
        notifyListeners();
      }
      print('fetchOrgSubscription failed: $e');
    } catch (e) {
      print('fetchOrgSubscription failed: $e');
    }
  }

  /// Super-admin: extend / reset an organisation subscription window.
  Future<bool> updateOrganisationSubscription({
    required String orgId,
    String subscriptionStatus = 'trialing',
    DateTime? trialEndsAt,
    DateTime? gracePeriodEndsAt,
  }) async {
    _lastActionError = null;
    try {
      final now = DateTime.now().toUtc();
      final trial = trialEndsAt ?? now.add(const Duration(days: 7));
      final grace = gracePeriodEndsAt ?? now.add(const Duration(days: 10));
      final result = await _api.production.updateOrgSubscription(orgId, {
        'subscription_status': subscriptionStatus,
        'trial_ends_at': trial.toIso8601String(),
        'grace_period_ends_at': grace.toIso8601String(),
      });
      if (result == null) {
        _lastActionError = 'Could not update subscription.';
        return false;
      }
      final org = result['org'] is Map
          ? Map<String, dynamic>.from(result['org'] as Map)
          : result;
      await OrganisationRegistry.upsert({
        'id': orgId,
        ...org,
        'status': org['status'] ?? 'active',
      });
      await fetchManagedOrganisations();
      return true;
    } on DioException catch (e) {
      _lastActionError = ApiClient.errorMessage(e) ?? e.toString();
      return false;
    } catch (e) {
      _lastActionError = e.toString();
      return false;
    }
  }

  Future<void> updateManagedOrganisationDetails(String orgIdOrSlug, Map<String, dynamic> fields) async {
    final existing = await OrganisationRegistry.findById(orgIdOrSlug) ??
        await OrganisationRegistry.findBySlug(orgIdOrSlug);
    await OrganisationRegistry.upsert({
      ...?existing,
      ...fields,
      if (existing?['id'] != null) 'id': existing!['id'],
      if (existing?['slug'] != null) 'slug': existing!['slug'],
    });
    await fetchManagedOrganisations();
    await fetchPendingOrganisations();
  }

  Future<void> fetchAdminLiveVisitsList() async {
    try {
      Map<String, Map<String, dynamic>> usersById = {};
      Map<String, Map<String, dynamic>> outletsById = {};
      final orderTotalByVisitId = <String, double>{};
      final latestSelfieByActor = <String, String>{};
      final latestSalesByActor = <String, double>{};
      final latestActivityTimeByActor = <String, DateTime>{};

      List<String> actorKeys({String? userId, String? email}) {
        return [
          if (userId != null && userId.trim().isNotEmpty) 'id:${userId.trim()}',
          if (email != null && email.trim().isNotEmpty) 'email:${email.trim().toLowerCase()}',
        ];
      }

      List<String> visitIdKeys(Map<String, dynamic> row) {
        final keys = <String>{};
        void add(dynamic value) {
          final text = value?.toString().trim() ?? '';
          if (text.isNotEmpty && text != 'null') keys.add(text);
        }

        add(row['visit_id']);
        add(row['visitId']);
        add(row['visitID']);
        add(row['field_visit_id']);
        add(row['fieldVisitId']);
        final visit = row['visit'];
        if (visit is Map) {
          add(visit['id']);
          add(visit['visit_id']);
          add(visit['visitId']);
        }
        return keys.toList();
      }

      double parseMoney(Map<String, dynamic> row) {
        double fromValue(dynamic value) =>
            double.tryParse((value ?? '').toString().replaceAll(',', '').trim()) ?? 0.0;
        var amount = fromValue(row['total_amount'] ??
            row['totalAmount'] ??
            row['order_total'] ??
            row['orderTotal'] ??
            row['amount'] ??
            row['sales_value'] ??
            row['salesValue'] ??
            row['grand_total'] ??
            row['grandTotal']);
        if (amount > 0) return amount;

        final items = row['items'] ?? row['products'] ?? row['order_items'] ?? row['orderItems'];
        if (items is List) {
          for (final item in items) {
            if (item is! Map) continue;
            final qty = fromValue(item['quantity'] ?? item['qty'] ?? 1);
            final price = fromValue(item['price'] ?? item['unitPrice'] ?? item['unit_price'] ?? item['rate']);
            amount += qty * price;
          }
        }
        return amount;
      }

      void rememberActorDetails({
        required Iterable<String> keys,
        String? selfieUrl,
        double? salesValue,
        dynamic when,
      }) {
        final parsedTime = DateTime.tryParse(when?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        for (final key in keys) {
          if ((selfieUrl ?? '').trim().isNotEmpty) {
            final previous = latestActivityTimeByActor[key];
            if (previous == null || parsedTime.isAfter(previous)) {
              latestSelfieByActor[key] = selfieUrl!.trim();
              latestActivityTimeByActor[key] = parsedTime;
            }
          }
          if ((salesValue ?? 0) > 0) {
            latestSalesByActor[key] = salesValue!;
          }
        }
      }

      try {
        final orders = await _api.production.listOrders();
        for (final o in orders) {
          final amount = parseMoney(o);
          for (final vid in visitIdKeys(o)) {
            orderTotalByVisitId[vid] = (orderTotalByVisitId[vid] ?? 0) + amount;
          }
          final orderUser = o['user'] ?? o['executive'] ?? o['employee'];
          final orderUserMap = orderUser is Map ? orderUser : const <String, dynamic>{};
          rememberActorDetails(
            keys: actorKeys(
              userId: (o['user_id'] ??
                      o['userId'] ??
                      o['executive_id'] ??
                      o['executiveId'] ??
                      orderUserMap['id'])
                  ?.toString(),
              email: (o['email'] ??
                      o['user_email'] ??
                      o['userEmail'] ??
                      o['executive_email'] ??
                      o['executiveEmail'] ??
                      orderUserMap['email'])
                  ?.toString(),
            ),
            salesValue: amount,
            when: o['created_at'] ?? o['createdAt'] ?? o['ordered_at'] ?? o['orderedAt'],
          );
        }
      } catch (_) {}
      try {
        final users = await _api.production.adminUsers();
        for (final u in users) {
          final id = u['id']?.toString();
          if (id != null) usersById[id] = u;
        }
      } catch (_) {}
      try {
        final outlets = await _api.production.outlets();
        for (final o in outlets) {
          final id = o['id']?.toString();
          if (id != null) outletsById[id] = o;
        }
      } catch (_) {}

      if (usersById.isNotEmpty && _adminUsersList.isEmpty) {
        _adminUsersList = usersById.values.map((u) {
          return {
            'id': u['id'],
            'name': u['name'] ?? u['email'] ?? 'User',
            'email': u['email'] ?? '',
            'role': u['role'] ?? '',
            'status': (u['status'] ?? 'active').toString().toLowerCase() == 'active' ? 'active' : 'inactive',
            'designation': u['role'] ?? 'Field Agent',
            'phone': u['phone'],
            'raw': u,
          };
        }).toList();
      }

      final merged = <Map<String, dynamic>>[];
      final seenKeys = <String>{};
      final attendanceDailyKeys = <String>{};

      void addLog(Map<String, dynamic> row) {
        final key = row['id']?.toString() ??
            '${row['executiveEmail']}|${row['checkInTime']}|${row['outletName']}';
        if (!seenKeys.add(key)) return;
        merged.add(row);
      }

      String localDayKey(dynamic value) {
        final raw = value?.toString() ?? '';
        final parsed = DateTime.tryParse(raw);
        if (parsed == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
        return parsed.toLocal().toIso8601String().substring(0, 10);
      }

      // 1) Org attendance = authoritative daily login / logout times on the server.
      try {
        final attendance = await _api.attendanceList(page: 1, perPage: 100);
        for (final row in attendance) {
          final nestedUser = row['user'] is Map
              ? Map<String, dynamic>.from(row['user'] as Map)
              : row['executive'] is Map
                  ? Map<String, dynamic>.from(row['executive'] as Map)
                  : row['employee'] is Map
                      ? Map<String, dynamic>.from(row['employee'] as Map)
                      : <String, dynamic>{};
          final userId = (row['user_id'] ??
                  row['userId'] ??
                  row['executive_id'] ??
                  row['executiveId'] ??
                  nestedUser['id'] ??
                  '')
              .toString();
          final user = {
            ...nestedUser,
            ...?usersById[userId],
          };
          final checkInTime = row['check_in_at'] ??
              row['checkInAt'] ??
              row['login_at'] ??
              row['loginAt'] ??
              row['login_time'] ??
              row['loginTime'] ??
              row['created_at'] ??
              row['createdAt'];
          final checkOutTime = row['check_out_at'] ??
              row['checkOutAt'] ??
              row['logout_at'] ??
              row['logoutAt'] ??
              row['logout_time'] ??
              row['logoutTime'];
          if (_isHiddenFromOrgActivity(
            role: user['role']?.toString() ?? row['role']?.toString(),
            name: user['name']?.toString() ?? row['name']?.toString(),
            email: user['email']?.toString() ?? row['email']?.toString(),
          )) {
            continue;
          }
          final name = (user['name'] ??
                  row['executive_name'] ??
                  row['executiveName'] ??
                  user['email'] ??
                  row['email'] ??
                  'Executive')
              .toString();
          final email = (user['email'] ?? row['email'] ?? row['executive_email'] ?? row['executiveEmail'] ?? '')
              .toString();
          final selfie = _absoluteSelfieUrl(
            (row['login_selfie_url'] ?? row['loginSelfieUrl'] ?? row['selfie_url'] ?? '').toString(),
          );
          if ((userId.isNotEmpty || email.isNotEmpty) && checkInTime != null) {
            attendanceDailyKeys.add('${userId.isNotEmpty ? userId : email}|${localDayKey(checkInTime)}');
          }
          rememberActorDetails(
            keys: actorKeys(userId: userId, email: email),
            selfieUrl: selfie,
            when: checkInTime,
          );
          addLog({
            'id': 'att-${row['id'] ?? userId}-${checkInTime ?? DateTime.now().toUtc().toIso8601String()}',
            'userId': userId,
            'executiveName': name,
            'executiveEmail': email,
            'executiveRole': user['role'] ?? row['role'] ?? 'executive',
            'outletName': 'Daily field login',
            'outletAddress': row['notes'] ?? 'Attendance check-in',
            'checkInTime': checkInTime,
            'checkOutTime': checkOutTime,
            'salesValue': 0.0,
            'remarks': 'Attendance login (GPS + device session)',
            'gpsLat': row['check_in_lat'] ?? row['checkInLat'] ?? row['latitude'],
            'gpsLng': row['check_in_lng'] ?? row['checkInLng'] ?? row['longitude'],
            'address': row['check_in_address'] ?? row['address'] ?? 'Attendance login',
            'selfieUrl': selfie,
            'status': row['status'] ?? 'checked_in',
            'isDailyLogin': true,
            'source': 'attendance',
          });
        }
      } catch (e) {
        print('Admin attendance feed failed: $e');
      }

      // 2) Outlet visits + synthetic daily-login visits.
      List<Map<String, dynamic>> visits = const [];
      try {
        visits = await _api.production.listVisits();
      } catch (e) {
        print('Admin visits feed failed: $e');
      }

      for (final visit in visits) {
        final userId = visit['user_id']?.toString() ??
            visit['userId']?.toString() ??
            visit['executiveId']?.toString() ??
            '';
        final visitId = visit['id']?.toString() ?? '';
        final outletId = visit['outlet_id']?.toString() ?? visit['outletId']?.toString() ?? '';
        final user = usersById[userId] ?? {};
        final outlet = outletsById[outletId] ?? {};
        if (_isHiddenFromOrgActivity(
          role: user['role']?.toString() ?? visit['executiveRole']?.toString(),
          name: user['name']?.toString() ?? visit['executiveName']?.toString(),
          email: user['email']?.toString() ?? visit['executiveEmail']?.toString(),
        )) {
          continue;
        }
        final notes = (visit['notes'] ?? visit['remarks'] ?? '').toString();
        final outletName = (outlet['name'] ?? visit['outletName'] ?? 'Retail Outlet').toString();
        final isDailyLogin = notes.contains(dailyLoginNotesPrefix) ||
            outletName.toLowerCase() == dailyLoginOutletName.toLowerCase();

        var selfie = visit['selfie_url']?.toString() ??
            visit['selfieUrl']?.toString() ??
            visit['login_selfie_url']?.toString() ??
            visit['loginSelfieUrl']?.toString() ??
            visit['check_in_selfie_url']?.toString() ??
            visit['checkInSelfieUrl']?.toString() ??
            visit['photo_url']?.toString() ??
            visit['photoUrl']?.toString() ??
            '';
        if (selfie.isEmpty) {
          final media = visit['selfie_media'] ?? visit['selfieMedia'] ?? visit['media'];
          if (media is Map) {
            selfie = media['url']?.toString() ??
                media['path']?.toString() ??
                media['file_url']?.toString() ??
                '';
          }
        }
        if (selfie.isEmpty && notes.contains('selfie=')) {
          final match = RegExp(r'selfie=([^|]*)').firstMatch(notes);
          selfie = match?.group(1)?.trim() ?? '';
        }
        final absoluteSelfie = _absoluteSelfieUrl(selfie);
        final name = (user['name'] ??
                visit['executiveName'] ??
                user['email'] ??
                visit['executiveEmail'] ??
                'Executive')
            .toString();
        String? placeFromNotes;
        if (notes.contains('place=')) {
          placeFromNotes = RegExp(r'place=([^|]*)').firstMatch(notes)?.group(1)?.trim();
        }
        final visitCheckInTime = visit['check_in_at'] ??
            visit['checkInTime'] ??
            visit['started_at'] ??
            visit['startedAt'] ??
            visit['created_at'] ??
            visit['createdAt'];
        if (isDailyLogin) {
          final duplicateKey = '${userId.isNotEmpty ? userId : (user['email'] ?? visit['executiveEmail'] ?? '')}|${localDayKey(visitCheckInTime)}';
          if (attendanceDailyKeys.contains(duplicateKey)) {
            continue;
          }
        }

        double salesValue = 0.0;
        salesValue = double.tryParse(
              (visit['salesValue'] ?? visit['sales_value'] ?? visit['order_total'] ?? '0').toString(),
            ) ??
            0.0;
        if (salesValue <= 0 && visitId.isNotEmpty && orderTotalByVisitId.containsKey(visitId)) {
          salesValue = orderTotalByVisitId[visitId]!;
        }
        if (salesValue <= 0 && notes.contains('ORDER_TOTAL=')) {
          final m = RegExp(r'ORDER_TOTAL=([0-9]+(?:\.[0-9]+)?)').firstMatch(notes);
          salesValue = double.tryParse(m?.group(1) ?? '') ?? 0.0;
        }
        rememberActorDetails(
          keys: actorKeys(
            userId: userId,
            email: (user['email'] ?? visit['executiveEmail'] ?? '').toString(),
          ),
          selfieUrl: absoluteSelfie,
          salesValue: salesValue,
          when: visitCheckInTime,
        );

        var displayRemarks = notes;
        if (displayRemarks.contains('ORDER_TOTAL=')) {
          displayRemarks = displayRemarks
              .split('|')
              .where((p) => !p.trim().startsWith('ORDER_TOTAL='))
              .join('|')
              .trim();
        }

        addLog({
          'id': visit['id'],
          'userId': userId,
          'executiveName': name,
          'executiveEmail': user['email'] ?? visit['executiveEmail'] ?? '',
          'executiveRole': user['role'] ?? visit['executiveRole'] ?? '',
          'outletName': isDailyLogin ? 'Daily field login' : outletName,
          'outletAddress': outlet['address'] ?? visit['outletAddress'] ?? '',
          'checkInTime': visitCheckInTime,
          'checkOutTime': visit['check_out_at'] ?? visit['checkOutTime'] ?? visit['ended_at'],
          'salesValue': salesValue,
          'remarks': displayRemarks,
          'gpsLat': visit['check_in_lat'] ??
              visit['start_latitude'] ??
              visit['gpsLat'] ??
              visit['latitude'],
          'gpsLng': visit['check_in_lng'] ??
              visit['start_longitude'] ??
              visit['gpsLng'] ??
              visit['longitude'],
          'address': placeFromNotes ??
              outlet['address'] ??
              visit['outletAddress'] ??
              visit['address'],
          'selfieUrl': absoluteSelfie,
          'status': visit['status'],
          'isDailyLogin': isDailyLogin,
          'source': 'visit',
        });
      }

      // 3) Always surface live GPS as an activity card. Attendance check-in can be hours old,
      // while GPS proves the executive is active now.
      try {
        final live = await _api.production.gpsLive();
        for (final row in live) {
          final userId = (row['user_id'] ?? row['userId'] ?? '').toString();
          final user = usersById[userId] ?? {};
          if (_isHiddenFromOrgActivity(
            role: user['role']?.toString() ?? row['role']?.toString(),
            name: user['name']?.toString() ?? row['user_name']?.toString(),
            email: user['email']?.toString() ?? row['email']?.toString(),
          )) {
            continue;
          }
          final timestamp = row['logged_at'] ?? row['timestamp'] ?? row['created_at'];
          final email = (user['email'] ?? row['email'] ?? row['user_email'] ?? '').toString();
          final keys = actorKeys(userId: userId, email: email);
          final latestSelfie = keys
                  .map((key) => latestSelfieByActor[key])
                  .firstWhere((value) => value != null && value.isNotEmpty, orElse: () => null) ??
              '';
          final latestSales = keys
                  .map((key) => latestSalesByActor[key])
                  .firstWhere((value) => value != null && value > 0, orElse: () => null) ??
              0.0;
          addLog({
            'id': 'gps-login-${row['id'] ?? userId}-${timestamp ?? ''}',
            'userId': userId,
            'executiveName': user['name'] ?? row['user_name'] ?? user['email'] ?? row['email'] ?? 'Executive',
            'executiveEmail': email,
            'executiveRole': user['role'] ?? row['role'] ?? 'executive',
            'outletName': 'Live GPS update',
            'outletAddress': row['address'] ?? 'Production GPS live ping',
            'checkInTime': timestamp,
            'checkOutTime': null,
            'salesValue': latestSales,
            'remarks': 'Production GPS live ping',
            'gpsLat': row['latitude'] ?? row['lat'],
            'gpsLng': row['longitude'] ?? row['lng'] ?? row['lon'],
            'address': row['address'] ?? 'Production GPS live ping',
            'selfieUrl': latestSelfie,
            'status': 'gps_live',
            'isDailyLogin': false,
            'source': 'gps_live',
          });
        }
      } catch (e) {
        print('Admin live GPS login fallback failed: $e');
      }

      merged.sort((a, b) {
        final ta = DateTime.tryParse(a['checkInTime']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse(b['checkInTime']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });

      _adminLiveVisitsList = merged;
      notifyListeners();
      return;
    } catch (e) {
      print('Fetch admin live visits (API) failed: $e. Falling back to local visits.');
    }

    try {
      final localVisits = await DatabaseHelper.instance.queryAll('offline_visits');

      final mappedVisits = localVisits.map((v) {
        String outletName = 'Retail Outlet';
        String outletAddress = v['address']?.toString() ?? '';

        final planned = _findOutletById(v['outlet_id']?.toString() ?? '');
        if (planned != null) {
          outletName = planned['name']?.toString() ?? outletName;
          outletAddress = planned['address']?.toString() ?? outletAddress;
        }

        final selfie = v['selfie_url']?.toString() ?? '';
        final absoluteSelfie = _absoluteSelfieUrl(selfie);

        return {
          'id': v['id'],
          'executiveName': _email?.split('@').first ?? 'Executive',
          'executiveEmail': _email ?? '',
          'outletName': outletName,
          'outletAddress': outletAddress,
          'checkInTime': v['checkin_time'],
          'checkOutTime': v['checkout_time'],
          'salesValue': double.tryParse(v['sales_value']?.toString() ?? '') ?? 0.0,
          'remarks': v['remarks'] ?? '',
          'managerOverride': v['manager_override'] == 1,
          'selfieUrl': absoluteSelfie ?? v['selfie_url'],
          'gpsLat': v['gps_lat'],
          'gpsLng': v['gps_lng'],
          'address': v['address'] ?? outletAddress,
        };
      }).toList();

      _adminLiveVisitsList = mappedVisits.reversed.toList();
      notifyListeners();
    } catch (e) {
      print('Fetch admin live visits list failed: $e');
    }
  }

  Future<void> fetchAdminLiveGpsList() async {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addPing(Map<String, dynamic> ping) {
      final lat = ping['latitude'];
      final lng = ping['longitude'];
      final ts = ping['timestamp']?.toString() ?? '';
      final key = '${ping['executiveEmail'] ?? ping['userId']}|$lat|$lng|$ts';
      if (!seen.add(key)) return;
      merged.add(ping);
    }

    Map<String, Map<String, dynamic>> usersById = {};
    try {
      final users = await _api.production.adminUsers();
      for (final u in users) {
        final id = u['id']?.toString();
        if (id != null) usersById[id] = u;
      }
    } catch (_) {}

    Map<String, dynamic> mapGpsRow(Map row, {required String source, String? startPoint}) {
      final userId = (row['user_id'] ?? row['userId'] ?? '').toString();
      final user = usersById[userId] ?? {};
      final name = (user['name'] ??
              row['user_name'] ??
              row['executiveName'] ??
              user['email'] ??
              row['email'] ??
              'Executive')
          .toString();
      final email = (user['email'] ?? row['user_email'] ?? row['email'] ?? '').toString();
      return {
        'id': row['id'] ?? _uuid.v4(),
        'latitude': row['latitude'] ?? row['lat'],
        'longitude': row['longitude'] ?? row['lng'] ?? row['lon'],
        'address': row['address'],
        'timestamp': row['logged_at'] ?? row['timestamp'] ?? row['created_at'],
        'startPoint': startPoint ?? row['tracking_start_point'] ?? (source == 'gps_live' ? 'LIVE' : 'TRACKING'),
        'userId': userId,
        'executiveName': name,
        'executiveEmail': email,
        'deviceId': row['device_id'] ?? row['deviceId'],
        'accuracy': row['accuracy'],
        'speed': row['speed'],
        'batteryLevel': row['battery_level'] ?? row['batteryLevel'],
        'source': source,
      };
    }

    // 1) Production live GPS — accurate current positions for admin tracking.
    try {
      final live = await _api.production.gpsLive();
      for (final row in live) {
        final user = usersById[row['user_id']?.toString() ?? ''] ?? {};
        if (_isHiddenFromOrgActivity(
          role: user['role']?.toString() ?? row['role']?.toString(),
          name: user['name']?.toString(),
          email: user['email']?.toString(),
        )) {
          continue;
        }
        addPing(mapGpsRow(row, source: 'gps_live', startPoint: 'LIVE'));
      }
    } catch (e) {
      print('Admin GPS live failed: $e');
    }

    // 2) Production GPS history — trail for the day / recent movement.
    try {
      final history = await _api.production.gpsHistory(page: 1, perPage: 150);
      for (final row in history) {
        final user = usersById[row['user_id']?.toString() ?? ''] ?? {};
        if (_isHiddenFromOrgActivity(
          role: user['role']?.toString() ?? row['role']?.toString(),
          name: user['name']?.toString(),
          email: user['email']?.toString(),
        )) {
          continue;
        }
        addPing(mapGpsRow(row, source: 'gps_history'));
      }
    } catch (e) {
      print('Admin GPS history failed: $e');
    }

    // 3) Fallback: visit check-in / check-out GPS if live/history empty.
    if (merged.isEmpty) {
      try {
        final visits = await _api.production.listVisits();
        for (final visit in visits) {
          final userId = visit['user_id']?.toString() ?? '';
          final user = usersById[userId] ?? {};
          if (_isHiddenFromOrgActivity(
            role: user['role']?.toString(),
            name: user['name']?.toString(),
            email: user['email']?.toString(),
          )) {
            continue;
          }
          final name = (user['name'] ?? user['email'] ?? 'Executive').toString();
          final email = (user['email'] ?? '').toString();
          final notes = (visit['notes'] ?? visit['remarks'] ?? '').toString();
          final isDailyLogin = notes.contains(dailyLoginNotesPrefix);

          final inLat = visit['check_in_lat'] ?? visit['gpsLat'] ?? visit['start_latitude'] ?? visit['latitude'];
          final inLng = visit['check_in_lng'] ?? visit['gpsLng'] ?? visit['start_longitude'] ?? visit['longitude'];
          final inTs = visit['check_in_at'] ?? visit['checkInTime'] ?? visit['created_at'];
          if (inLat != null && inLng != null) {
            addPing({
              'id': 'visit-in-${visit['id']}',
              'latitude': inLat,
              'longitude': inLng,
              'address': isDailyLogin
                  ? (visit['check_in_address'] ?? 'Daily field login')
                  : (visit['check_in_address'] ?? visit['address'] ?? 'Visit check-in'),
              'timestamp': inTs,
              'startPoint': isDailyLogin ? 'DAILY_LOGIN' : 'VISIT_CHECKIN',
              'userId': userId,
              'executiveName': name,
              'executiveEmail': email,
              'source': isDailyLogin ? 'daily_login' : 'visit',
            });
          }
        }
      } catch (e) {
        print('Admin GPS from visits failed: $e');
      }
    }

    // 4) Super-admin: enrich with device/session info when available.
    try {
      final role = (_role ?? '').toLowerCase();
      if (role == 'super_admin' || role == 'superadmin') {
        final userIds = merged
            .map((p) => p['userId']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .take(12);
        for (final uid in userIds) {
          try {
            final sessions = await _api.production.adminUserSessions(uid);
            if (sessions.isEmpty) continue;
            final active = sessions.firstWhere(
              (s) => s['is_revoked'] != true && s['revoked'] != true,
              orElse: () => sessions.first,
            );
            for (final ping in merged.where((p) => p['userId']?.toString() == uid)) {
              ping['deviceId'] ??= active['device_id'] ?? active['deviceId'];
              ping['deviceType'] ??= active['device_type'] ?? active['deviceType'];
              ping['sessionIp'] ??= active['ip_address'] ?? active['ipAddress'];
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 5) Local device pings — only when an executive is using this device.
    if (_isExecutiveRole()) {
      try {
        final localGps = await DatabaseHelper.instance.queryAll('offline_gps_pings');
        for (final ping in localGps.reversed.take(50)) {
          addPing({
            'id': ping['id'],
            'latitude': ping['latitude'],
            'longitude': ping['longitude'],
            'address': ping['address'],
            'timestamp': ping['timestamp'],
            'startPoint': ping['tracking_start_point'] ?? 'HOME',
            'userId': _userId,
            'executiveName': _email?.split('@').first ?? 'You',
            'executiveEmail': _email ?? '',
            'source': 'local',
          });
        }
      } catch (e) {
        print('Fetch local admin GPS failed: $e');
      }
    }

    merged.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });

    final filtered = merged.where((ping) {
      return !_isHiddenFromOrgActivity(
        name: ping['executiveName']?.toString(),
        email: ping['executiveEmail']?.toString(),
      );
    }).toList();

    final limited = filtered.take(200).toList();
    var geocodeBudget = 30;
    for (final ping in limited) {
      final rawAddress = ping['address']?.toString();
      if (!_isUnresolvedAddress(rawAddress)) continue;
      final lat = double.tryParse(ping['latitude']?.toString() ?? '');
      final lng = double.tryParse(ping['longitude']?.toString() ?? '');
      if (lat == null || lng == null) {
        ping['address'] = 'GPS ${ping['latitude']}, ${ping['longitude']}';
        continue;
      }
      String? resolved;
      if (geocodeBudget > 0) {
        geocodeBudget--;
        resolved = await _resolveAddressCached(lat, lng);
      }
      ping['address'] = resolved ?? 'GPS ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      if (ping['source'] == 'local' && ping['id'] != null && resolved != null) {
        try {
          await DatabaseHelper.instance.update(
            'offline_gps_pings',
            {'address': resolved},
            where: 'id = ?',
            whereArgs: [ping['id']],
          );
        } catch (_) {}
      }
    }

    _adminLiveGpsList = limited;
    notifyListeners();
  }
}
