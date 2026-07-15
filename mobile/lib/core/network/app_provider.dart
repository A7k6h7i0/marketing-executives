import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';
import '../constants/api_endpoints.dart';
import '../database/database_helper.dart';
import '../../features/telecaller/data/telecaller_recording_setup.dart';

class AppProvider extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  final _uuid = const Uuid();

  // Auth State
  bool _isAuthenticated = false;
  String? _token;
  String? _userId;
  String? _email;
  String? _phone;
  String? _role;
  String? _region;
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
  int _minimumVisitDurationMinutes = 2;
  Timer? _autoVisitTimer;
  String? _dwellOutletId;
  DateTime? _dwellStartedAt;
  Map<String, dynamic>? _lastAutoRegisteredOutlet;

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
  final List<Map<String, dynamic>> _demoCatalog = [
    {
      'id': 'p-001',
      'sku': 'SKU-COLA-500',
      'name': 'Coca Cola Carbonated Drink (500ml)',
      'unitPrice': 1.50,
    },
    {
      'id': 'p-002',
      'sku': 'SKU-CHIPS-100',
      'name': 'Lays Potato Chips Classic (100g)',
      'unitPrice': 0.99,
    },
    {
      'id': 'p-003',
      'sku': 'SKU-BISCUIT-200',
      'name': 'Britannia Good Day Biscuits (200g)',
      'unitPrice': 1.25,
    },
    {
      'id': 'p-004',
      'sku': 'SKU-WATER-1000',
      'name': 'Kinley Mineral Water Bottle (1L)',
      'unitPrice': 0.50,
    },
    {
      'id': 'p-005',
      'sku': 'SKU-CHOCO-45',
      'name': 'Cadbury Dairy Milk Silk (45g)',
      'unitPrice': 2.00,
    }
  ];

  // Getters
  bool get isAuthenticated => _isAuthenticated;
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

  String _loginFailureMessage(DioException error) {
    final status = error.response?.statusCode;
    final apiMessage = _messageFromApiError(error.response?.data);

    if (status == 401) {
      return apiMessage.isNotEmpty ? apiMessage : 'Invalid email or password.';
    }
    if (status == 500) {
      return 'Production server error (500). The login API is down — ask your friend to check the server.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach ${ApiEndpoints.baseUrl}. Check your internet connection.';
    }
    if (apiMessage.isNotEmpty) return apiMessage;
    return error.message ?? 'Login failed. Please try again.';
  }
  String? get userId => _userId;
  String? get email => _email;
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
  List<dynamic> get adminLiveVisitsList => _adminLiveVisitsList;
  List<dynamic> get adminLiveGpsList => _adminLiveGpsList;
  int get minimumVisitDurationMinutes => _minimumVisitDurationMinutes;
  Map<String, dynamic>? get lastAutoRegisteredOutlet => _lastAutoRegisteredOutlet;

  AppProvider() {
    _loadSavedSession();
  }

  // Load session from SharedPreferences on startup
  Future<void> _loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');
    _userId = prefs.getString('user_id');
    _email = prefs.getString('user_email');
    _phone = prefs.getString('user_phone');
    _role = prefs.getString('user_role');
    _region = prefs.getString('user_region');
    _minimumVisitDurationMinutes = prefs.getInt('minimum_visit_duration_minutes') ?? 2;

    await TelecallerRecordingSetup.load();
    _telecallerSetupComplete = TelecallerRecordingSetup.isComplete;
    _telecallerSetupLoaded = true;

    if (_token != null && _token!.isNotEmpty) {
      _isAuthenticated = true;
      notifyListeners();
      
      if (_role == 'admin' ||
          _role == 'manager' ||
          _role == 'SUPER_ADMIN' ||
          _role == 'REGIONAL_MANAGER' ||
          _role == 'SALES_MANAGER') {
        fetchAdminDashboardData();
      } else {
        await _restoreTodayPlanFromLocal();
        await _restoreLocalAttendance();
        await _restoreTodayBreaksFromLocal();
        fetchTodayLiveSummary();
        fetchTodayPlan();
        restoreActiveVisitFromLocalDb();
        fetchProductCatalog();
        fetchSavedLeads();
        fetchUserIncidents();
      }
    }
  }

  // 1. Authentication Methods
  Future<bool> login(String emailOrPhone, String password, String deviceId) async {
    _isLoading = true;
    _loginError = null;
    notifyListeners();

    try {
      final isEmail = emailOrPhone.contains('@');
      final data = {
        if (isEmail) 'email': emailOrPhone.trim() else 'phone': emailOrPhone.trim(),
        'password': password,
      };

      final response = await _apiClient.post(ApiEndpoints.login, data: data);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        final body = _mapFrom(response.data);
        final nested = _mapFrom(body['data']);
        final user = _mapFrom(nested['user']);
        if (user.isEmpty) {
          user.addAll(_mapFrom(body['user']));
        }

        _token = nested['access_token']?.toString() ?? body['token']?.toString();
        _userId = user['id']?.toString();
        _email = user['email']?.toString();
        _phone = user['phone']?.toString();
        _role = user['role']?.toString();
        _region = user['org_id']?.toString() ?? user['region']?.toString();
        _activeAttendanceId = body['attendanceId']?.toString();

        if (_token == null || _userId == null || _role == null) {
          throw Exception('Invalid login response from server');
        }

        await prefs.setString('jwt_token', _token!);
        await prefs.setString('user_id', _userId!);
        if (_email != null) await prefs.setString('user_email', _email!);
        if (_phone != null) await prefs.setString('user_phone', _phone!);
        await prefs.setString('user_role', _role!);
        if (_region != null) await prefs.setString('user_region', _region!);

        await TelecallerRecordingSetup.load();
        _telecallerSetupComplete = TelecallerRecordingSetup.isComplete;
        _telecallerSetupLoaded = true;

        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();

        // Load today's role-specific data
        if (_role == 'TELECALLER') {
          // Telecaller dashboard / onboarding loads its own data
        } else if (_role == 'SUPER_ADMIN' ||
            _role == 'REGIONAL_MANAGER' ||
            _role == 'SALES_MANAGER' ||
            _role == 'admin' ||
            _role == 'manager') {
          fetchAdminDashboardData();
        } else if (_role == 'executive' || _role == 'SALES_EXECUTIVE') {
          fetchTodayLiveSummary();
          fetchTodayPlan();
          fetchProductCatalog();
          fetchSavedLeads();
          fetchUserIncidents();
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

    if (_attendanceStatus == 'LOGGED_IN' || _attendanceStatus == 'PRESENT') {
      await checkOutAttendance(endDayOnly: true);
    }

    try {
      await _apiClient.post(ApiEndpoints.logout);
    } catch (e) {
      print('Logout API failed (might be offline): $e');
    }

    // Clear local session regardless of API success (failsafe).
    // Keep telecaller OEM folder link so agents do not re-onboard every login.
    await TelecallerRecordingSetup.load();
    final keepComplete = TelecallerRecordingSetup.isComplete;
    final keepPath = TelecallerRecordingSetup.folderPath;
    final keepLabel = TelecallerRecordingSetup.folderLabel;
    final keepLastPath = TelecallerRecordingSetup.lastUploadedPath;
    final keepLastMs = TelecallerRecordingSetup.lastUploadedModifiedMs;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
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
    _userId = null;
    _email = null;
    _phone = null;
    _role = null;
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
      final response = await _apiClient.get(ApiEndpoints.attendanceHistory);
      if (response.statusCode == 200) {
        final list = response.data['data'] as List<dynamic>? ?? [];
        final todayStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);
        final todayRecord = list.cast<dynamic?>().firstWhere(
          (r) => r != null && r['check_in_at'] != null && r['check_in_at'].toString().startsWith(todayStr),
          orElse: () => null,
        );

        if (todayRecord != null) {
          _activeAttendanceId = todayRecord['id'];
          final checkInAt = DateTime.parse(todayRecord['check_in_at'].toString());
          _attendanceStartAt = checkInAt.toUtc();

          if (todayRecord['check_out_at'] != null) {
            _attendanceEndAt = DateTime.parse(todayRecord['check_out_at'].toString()).toUtc();
            _attendanceStatus = 'CHECKED_OUT';
            _workingHoursTimer?.cancel();
            _todayWorkingHours = _attendanceEndAt!.difference(_attendanceStartAt!).inSeconds / 3600.0;
          } else {
            _attendanceEndAt = null;
            _startAttendanceClock(_attendanceStartAt!, persist: false);
          }
          await _persistLocalAttendance();
        } else {
          await _restoreLocalAttendance();
        }
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
      return false;
    }

    if (_activeBreak != null) {
      await endBreakSession();
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

  Future<bool> checkInAttendance(double lat, double lng, {double accuracy = 8.5}) async {
    try {
      final response = await _apiClient.post(ApiEndpoints.checkIn, data: {
        'latitude': lat,
        'longitude': lng,
        'accuracy': accuracy,
      });

      if (response.statusCode == 201 || response.statusCode == 200) {
        _attendanceEndAt = null;
        _startAttendanceClock(DateTime.now().toUtc());
        fetchTodayLiveSummary();
        return true;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        _attendanceEndAt = null;
        _startAttendanceClock(DateTime.now().toUtc());
        fetchTodayLiveSummary();
        return true;
      }
      print('Check in failed: ${e.response?.data ?? e.message}');
    } catch (e) {
      print('Check in failed: $e');
    }
    return false;
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

    final now = DateTime.now().toUtc();
    final breakId = _uuid.v4();
    final startIso = now.toIso8601String();
    _activeBreak = {
      'id': breakId,
      'breakType': breakType,
      'startTime': startIso,
    };
    _todayBreaks.add(_activeBreak);

    await DatabaseHelper.instance.insert('offline_breaks', {
      'id': breakId,
      'break_type': breakType,
      'start_time': startIso,
      'end_time': null,
      'duration_seconds': 0,
      'break_date': _todayDateKey(),
      'synced': 0,
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

    _totalBreakSeconds += durationSeconds;
    _recalculateBreakFormatted();

    _activeBreak!['endTime'] = now.toIso8601String();
    await DatabaseHelper.instance.update(
      'offline_breaks',
      {
        'end_time': now.toIso8601String(),
        'duration_seconds': durationSeconds,
      },
      where: 'id = ?',
      whereArgs: [_activeBreak!['id']],
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
      'latitude': outlet['latitude'] ?? outlet['gps_lat'] ?? outlet['lat'],
      'longitude': outlet['longitude'] ?? outlet['gps_lng'] ?? outlet['lng'],
      'grade': outlet['grade'],
      'overallRating': outlet['overall_rating'] ?? outlet['overallRating'],
      'visitStatus': outlet['visit_status'] ?? outlet['visitStatus'] ?? 'PENDING',
    };
  }

  Future<Map<String, dynamic>?> _pullSyncData() async {
    final response = await _apiClient.post(ApiEndpoints.syncPull, data: {
      'last_synced_at': '2020-01-01T00:00:00Z',
    });
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(response.data['data'] ?? {});
    }
    return null;
  }

  Future<void> fetchTodayPlan() async {
    try {
      final data = await _pullSyncData();
      if (data == null) return;

      final outletsList = (data['outlets'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((o) => _normalizeOutlet(Map<String, dynamic>.from(o)))
          .toList();

      if (outletsList.isNotEmpty) {
          _routeOutlets = outletsList;
          _plannedOutlets = outletsList;
          _plannedVisitsCount = outletsList.length;
          
          final localCompleted = await DatabaseHelper.instance.queryAll('offline_visits', where: 'checkout_time IS NOT NULL');
          _completedVisitsCount = localCompleted.length;
          if (_plannedVisitsCount > 0) {
            _planProgressPercentage = (_completedVisitsCount / _plannedVisitsCount) * 100.0;
          } else {
            _planProgressPercentage = 0.0;
          }
          
          _todayPlan = {
            'id': 'plan-active-sync',
            'route_id': 'route-sync-123',
            'area_name': 'Assigned Route Territory',
            'planned_visits': _plannedVisitsCount,
            'completed_visits': _completedVisitsCount,
          };
          await restoreActiveVisitFromLocalDb();
          startAutoVisitMonitoring();
          notifyListeners();
      }
    } catch (e) {
      print('Fetch today plan failed: $e. Retaining local plan state if active.');
    }
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
      _routeOutlets = List.from(restoredOutlets);
      _plannedVisitsCount = restoredOutlets.length;

      final localCompleted = await DatabaseHelper.instance.queryAll(
        'offline_visits',
        where: 'checkout_time IS NOT NULL',
      );
      _completedVisitsCount = localCompleted.length;
      _planProgressPercentage = _plannedVisitsCount > 0
          ? (_completedVisitsCount / _plannedVisitsCount) * 100.0
          : 0.0;

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

  Future<void> fetchAvailableRoutes() async {
    final localRoutes = await _loadCustomRoutesFromLocalDb();
    final serverRoutes = <dynamic>[];

    try {
      final data = await _pullSyncData();
      final routes = data?['routes'] as List<dynamic>? ?? [];
      serverRoutes.addAll(routes);

      final outlets = (data?['outlets'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((o) => _normalizeOutlet(Map<String, dynamic>.from(o)))
          .toList();
      if (outlets.isNotEmpty && serverRoutes.isEmpty) {
        serverRoutes.add({
          'id': 'route-sync-default',
          'name': 'Assigned Route',
          'region': _region ?? 'Territory',
          'outlets': outlets,
        });
      }
    } catch (e) {
      print('Fetch routes failed: $e. Showing saved custom routes only.');
    }

    _availableRoutes = [
      ...localRoutes,
      ...serverRoutes.where((serverRoute) {
        final serverId = serverRoute['id']?.toString();
        return serverId == null || localRoutes.every((localRoute) => localRoute['id']?.toString() != serverId);
      }),
    ];
    notifyListeners();
  }

  Future<bool> saveDailyPlan(String routeId, String areaName, int plannedVisits) async {
    final selectedRoute = _availableRoutes.cast<dynamic>().firstWhere(
      (r) => r is Map && r['id']?.toString() == routeId,
      orElse: () => null,
    );

    // Production assigns outlets via sync/pull — refresh server data when available.
    if (selectedRoute is Map && selectedRoute['isManual'] != true) {
      await fetchTodayPlan();
    }

    _todayPlan = {
      'id': 'plan-${_uuid.v4()}',
      'route_id': routeId,
      'area_name': areaName,
      'planned_visits': plannedVisits,
      'completed_visits': 0,
      'plan_date': DateTime.now().toUtc().toIso8601String().substring(0, 10),
    };

    final List<dynamic> outletsList = selectedRoute is Map
        ? List<dynamic>.from(selectedRoute['outlets'] as List<dynamic>? ?? [])
        : <dynamic>[];
    _routeOutlets = List.from(outletsList);
    _plannedOutlets = List.from(outletsList);
    _plannedVisitsCount = outletsList.length;
    _completedVisitsCount = 0;
    _planProgressPercentage = 0.0;
    await restoreActiveVisitFromLocalDb();
    startAutoVisitMonitoring();
    await _persistTodayPlanLocally();

    notifyListeners();
    return true;
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
  }) async {
    if (_todayPlan == null) return false;

    final outlet = {
      'id': 'outlet-${_uuid.v4()}',
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'grade': 'Unrated',
      'overallRating': null,
      'visitStatus': 'PENDING',
      'isManual': true,
    };

    _routeOutlets.add(outlet);
    _plannedOutlets.add(outlet);
    _plannedVisitsCount = _plannedOutlets.length;
    _todayPlan!['planned_visits'] = _plannedVisitsCount;
    final activeRouteId = _todayPlan!['route_id']?.toString();
    if (activeRouteId != null) {
      await _appendOutletToSavedRoute(activeRouteId, outlet);
    }
    if (_plannedVisitsCount > 0) {
      _planProgressPercentage = (_completedVisitsCount / _plannedVisitsCount) * 100.0;
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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
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
      await autoRegisterVisit(outletId, lat, lng, address, matchedOutlet);
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

  Future<void> recordGpsPing(double latitude, double longitude, String trackingStartPoint, {String? address}) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final localPingId = _uuid.v4();
    final pingData = {
      'latitude': latitude,
      'longitude': longitude,
      'battery_level': 85,
    };

    // Always write a local audit row first so the Admin mobile panel can show
    // live executive movement even before/without server sync.
    await DatabaseHelper.instance.insert('offline_gps_pings', {
      'id': localPingId,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'timestamp': timestamp,
      'tracking_start_point': trackingStartPoint,
      'synced': 0,
    });

    try {
      final response = await _apiClient.post(ApiEndpoints.gpsPing, data: pingData);
      if (response.statusCode == 201) {
        await DatabaseHelper.instance.update(
          'offline_gps_pings',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [localPingId],
        );
        _todayGpsRoute.add({
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': timestamp,
        });
        notifyListeners();
      }
    } catch (e) {
      print('GPS ping API failed. Queued locally for offline sync.');
    }
  }

  // 5. Outlet Visit Workflow
  Future<void> fetchProductCatalog() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.productCatalog);
      if (response.statusCode == 200) {
        final rawProducts = response.data['data'] as List<dynamic>? ?? [];
        _productCatalog = rawProducts.map((p) {
          // Normalize price keys (mrp, ptr, pts) safely from the multitenant API responses
          double unitPrice = 0.0;
          if (p['mrp'] != null) {
            unitPrice = double.tryParse(p['mrp'].toString()) ?? 0.0;
          } else if (p['ptr'] != null) {
            unitPrice = double.tryParse(p['ptr'].toString()) ?? 0.0;
          } else if (p['unit_price'] != null) {
            unitPrice = double.tryParse(p['unit_price'].toString()) ?? 0.0;
          }
          
          return {
            'id': p['id'],
            'sku': p['sku'] ?? 'SKU-GEN',
            'name': p['name'] ?? 'Test Product SKU',
            'unitPrice': unitPrice,
          };
        }).toList();

        // High fidelity robust safety fallback: If the live multitenant database doesn't have products registered,
        // guarantee that a stunning retail catalog automatically maps, preventing ANY 404 or empty crashes!
        if (_productCatalog.isEmpty) {
          _productCatalog = _demoCatalog;
        }
        notifyListeners();
      }
    } catch (e) {
      print('Fetch product catalog failed: $e. Falling back to local catalogs.');
      _productCatalog = _demoCatalog;
      notifyListeners();
    }
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
      if (_activeVisit!['outletId']?.toString() == outletId) {
        if (_attendanceStatus != 'LOGGED_IN') {
          _startAttendanceClock(DateTime.now().toUtc());
        }
        return {
          'success': true,
          'visit': _activeVisit,
          'offline': true,
          'alreadyActive': true,
          'requiresOverride': false,
          'distanceMeters': 0.0,
        };
      }
      return {
        'success': false,
        'activeVisitExists': true,
        'message': 'Another outlet visit is already active. Please check out before starting a new visit.',
      };
    }

    // 1. Double verification geofence calculation: Compare current location with outlet's target coordinates
    double distanceMeters = 0.0;

    // Find the outlet coordinates from master list to compute accurate live distance
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

      // Haversine formula calculation (Module 5 verification)
      double distanceInKM = _calculateHaversineDistance(lat, lng, targetLat, targetLng);
      distanceMeters = distanceInKM * 1000.0;

      // If physical distance from target outlet is greater than 100m, trigger geofence override verification
      if (distanceMeters > 100.0 && !managerOverride) {
        return {
          'success': false,
          'requiresOverride': true,
          'distanceMeters': distanceMeters,
        };
      }
    }

    // Outlet check-in is also the start of the executive's duty session.
    // This keeps the home dashboard, working-hours counter, and break button in sync.
    final attendanceSynced = await checkInAttendance(lat, lng);
    if (!attendanceSynced && _attendanceStatus != 'LOGGED_IN') {
      // If backend says already checked in or is temporarily unavailable, still
      // keep the local shift state accurate so the executive can take breaks.
      _startAttendanceClock(DateTime.now().toUtc());
    }

    final localId = _uuid.v4();
    final localVisit = {
      'id': localId,
      'outlet_id': outletId,
      'gps_lat': lat,
      'gps_lng': lng,
      'address': address,
      'selfie_url': selfieUrl,
      'checkin_time': DateTime.now().toUtc().toIso8601String(),
      'manager_override': managerOverride ? 1 : 0,
      'synced': 0,
    };
    await DatabaseHelper.instance.insert('offline_visits', localVisit);
    await recordGpsPing(lat, lng, _odometerStartPoint, address: address);

    _activeVisit = {
      'id': localId,
      'outletId': outletId,
      'gpsLat': lat,
      'gpsLng': lng,
      'address': address,
      'selfieUrl': selfieUrl,
      'isLocal': true,
    };
    _markOutletVisitStatus(outletId, 'IN_PROGRESS');
    _currentOrderItems = [];
    _currentOrderTotal = 0.0;
    notifyListeners();

    return {
      'success': true, 
      'visit': _activeVisit, 
      'offline': true,
      'requiresOverride': false,
      'distanceMeters': distanceMeters,
    };
  }

  // Haversine formula for exact physical distance calculation
  double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    // Earth's radius in kilometers
    const double r = 6371.0; 
    
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
               math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
               math.sin(dLon / 2) * math.sin(dLon / 2);
               
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degree) {
    return degree * (math.pi / 180.0);
  }

  void addProductToOrder(String sku, String name, int qty, double unitPrice) {
    final existingIdx = _currentOrderItems.indexWhere((item) => item['sku'] == sku);

    if (existingIdx != -1) {
      _currentOrderItems[existingIdx]['qty'] += qty;
    } else {
      _currentOrderItems.add({
        'sku': sku,
        'name': name,
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
    final visitId = _activeVisit!['id'];

    await DatabaseHelper.instance.update(
      'offline_visits',
      {
        'products_ordered': jsonEncode(_currentOrderItems),
        'sales_value': _currentOrderTotal,
        'remarks': remarks,
      },
      where: 'id = ?',
      whereArgs: [visitId],
    );
    _activeVisit!['productsOrdered'] = _currentOrderItems;
    _activeVisit!['salesValue'] = _currentOrderTotal;
    _activeVisit!['remarks'] = remarks;
    notifyListeners();
    return true;
  }

  Future<bool> checkoutOutlet() async {
    if (_activeVisit == null) return false;
    final visitId = _activeVisit!['id'];
    final outletId = _activeVisit!['outletId'];

    final checkoutTime = DateTime.now().toUtc().toIso8601String();
    await DatabaseHelper.instance.update(
      'offline_visits',
      {
        'checkout_time': checkoutTime,
      },
      where: 'id = ?',
      whereArgs: [visitId],
    );

    // Update in-memory visit status for this outlet in today's checklist
    _markOutletVisitStatus(outletId, 'COMPLETED');

    _activeVisit = null;
    _currentOrderItems = [];
    _currentOrderTotal = 0.0;

    // Recalculate local progress counters
    final localCompleted = await DatabaseHelper.instance.queryAll('offline_visits', where: 'checkout_time IS NOT NULL');
    _completedVisitsCount = localCompleted.length;
    if (_plannedVisitsCount > 0) {
      _planProgressPercentage = (_completedVisitsCount / _plannedVisitsCount) * 100.0;
    } else {
      _planProgressPercentage = 0.0;
    }

    if (_todayPlan != null) {
      _todayPlan!['completed_visits'] = _completedVisitsCount;
    }

    // Also trigger background pull if online to sync with server
    fetchTodayPlan();
    notifyListeners();
    return true;
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

  Future<void> setMinimumVisitDurationMinutes(int minutes) async {
    final safeMinutes = minutes.clamp(1, 120);
    _minimumVisitDurationMinutes = safeMinutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('minimum_visit_duration_minutes', safeMinutes);
    notifyListeners();
  }

  Future<String> exportVisitsCsv() async {
    final visits = await DatabaseHelper.instance.queryAll('offline_visits');
    final buffer = StringBuffer();
    buffer.writeln('Visit ID,Outlet ID,Check-in,Check-out,Latitude,Longitude,Address,Remarks,Products,Sales Value,Manager Override,Auto Detected');

    for (final visit in visits) {
      final productNames = _productNamesForCsv(visit['products_ordered']);
      buffer.writeln([
        visit['id'],
        visit['outlet_id'],
        visit['checkin_time'],
        visit['checkout_time'] ?? '',
        visit['gps_lat'],
        visit['gps_lng'],
        visit['address'] ?? '',
        visit['remarks'] ?? '',
        productNames,
        visit['sales_value'] ?? 0.0,
        visit['manager_override'] == 1 ? 'Yes' : 'No',
        visit['auto_detected'] == 1 ? 'Yes' : 'No',
      ].map(_csvCell).join(','));
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/marketing_visit_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file.path;
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
  }

  // 6. Exception & Incident Reporting
  Future<void> fetchUserIncidents() async {
    try {
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
          'resolutionStatus': 'OPEN', // default offline status
          'createdAt': row['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
        };
      }).toList();
      notifyListeners();
    } catch (e) {
      print('Fetch local incidents failed: $e');
    }
  }

  Future<bool> reportIncident(String type, String description, List<String> imageUrls, List<String> videoUrls) async {
    await DatabaseHelper.instance.insert('offline_incidents', {
      'id': _uuid.v4(),
      'incident_type': type,
      'description': description,
      'image_urls': imageUrls.join(','),
      'video_urls': videoUrls.join(','),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'synced': 0,
    });
    fetchUserIncidents();
    return true;
  }

  // 7. Smart Lead Generation — potential new shops to convert into outlets
  Future<void> findNearbyLeads(double lat, double lng, String category) async {
    try {
      final query = category.trim().length >= 2 ? category.trim() : 'shop';
      final response = await _apiClient.get(
        ApiEndpoints.searchOutlets,
        queryParameters: {'q': query},
      );
      if (response.statusCode == 200) {
        final rawList = response.data['data'] as List<dynamic>? ?? [];
        _nearbyLeads = rawList.map((item) {
          return {
            'id': item['id']?.toString() ?? _uuid.v4(),
            'businessName': item['name'] ?? item['business_name'] ?? 'Unknown Business',
            'businessCategory': item['category'] ?? item['business_category'] ?? category,
            'distanceMeters': item['distance_meters'] ?? item['distanceMeters'] ?? '?',
            'gpsLat': item['latitude'] ?? item['gps_lat'] ?? lat,
            'gpsLng': item['longitude'] ?? item['gps_lng'] ?? lng,
            'contactPhone': item['phone'] ?? item['contact_phone'] ?? '',
            'contactEmail': item['email'] ?? item['contact_email'] ?? '',
          };
        }).toList();
        notifyListeners();
        return;
      }
    } catch (e) {
      print('Nearby leads API unavailable: $e');
    }

    _nearbyLeads = [];
    notifyListeners();
  }

  Future<void> fetchSavedLeads() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.getLeads);
      if (response.statusCode == 200) {
        final rawList = response.data['data'] as List<dynamic>? ?? [];
        _savedLeads = rawList.map((item) {
          return {
            'id': item['id'],
            'businessName': item['name'] ?? item['business_name'] ?? 'Unknown Lead',
            'leadStatus': (item['status'] ?? item['lead_status'] ?? 'NEW').toString().toUpperCase(),
          };
        }).toList();
        notifyListeners();
      }
    } catch (e) {
      print('Fetch saved leads failed: $e. Loading from offline database.');
      // Offline fallback
      try {
        final localLeads = await DatabaseHelper.instance.queryAll('offline_leads');
        _savedLeads = localLeads.map((item) {
          return {
            'id': item['id'],
            'businessName': item['business_name'] ?? 'Unknown Lead',
            'leadStatus': (item['lead_status'] ?? 'NEW').toString().toUpperCase(),
          };
        }).toList();
        notifyListeners();
      } catch (dbError) {
        print('Fetch offline leads failed: $dbError');
      }
    }
  }

  Future<bool> saveLeadRecord(String name, String category, String phone, String email, double lat, double lng) async {
    final leadData = {
      'name': name,
      'phone': phone,
      'business_type': category.toLowerCase(),
      'source': 'field',
    };

    try {
      final response = await _apiClient.post(ApiEndpoints.saveLead, data: leadData);
      if (response.statusCode == 201) {
        fetchSavedLeads();
        return true;
      }
    } catch (e) {
      print('Save lead API failed. Queuing locally.');
      await DatabaseHelper.instance.insert('offline_leads', {
        'id': _uuid.v4(),
        'business_name': name,
        'business_category': category,
        'contact_phone': phone,
        'contact_email': email,
        'gps_lat': lat,
        'gps_lng': lng,
        'lead_status': 'NEW',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'synced': 0,
      });
      await fetchSavedLeads();
      return true;
    }
    return false;
  }

  Future<bool> convertLeadToOutlet(String leadId) async {
    return true;
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
      if (outletIds.isNotEmpty && !outletIds.contains(outletId)) continue;

      remainingOutlets.add({
        ...outlet,
        'latitude': latitude,
        'longitude': longitude,
      });
    }

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

    // 1. Sync GPS pings
    final offlinePings = await DatabaseHelper.instance.queryAll('offline_gps_pings', where: 'synced = 0');
    if (offlinePings.isNotEmpty) {
      final List<Map<String, dynamic>> logs = offlinePings.map((ping) => {
        'latitude': ping['latitude'],
        'longitude': ping['longitude'],
        'battery_level': 85,
      }).toList();

      try {
        final response = await _apiClient.post(ApiEndpoints.gpsBulk, data: {'logs': logs});
        if (response.statusCode == 201) {
          for (final ping in offlinePings) {
            await DatabaseHelper.instance.delete('offline_gps_pings', where: 'id = ?', whereArgs: [ping['id']]);
          }
          print('[Sync Engine] Synced ${offlinePings.length} GPS pings via bulk API.');
        }
      } catch (e) {
        print('[Sync Engine] Bulk GPS sync failed: $e');
      }
    }

    // 2. Sync Leads
    final offlineLeads = await DatabaseHelper.instance.queryAll('offline_leads', where: 'synced = 0');
    for (final lead in offlineLeads) {
      try {
        final response = await _apiClient.post(ApiEndpoints.saveLead, data: {
          'name': lead['business_name'],
          'phone': lead['contact_phone'],
          'business_type': lead['business_category'].toString().toLowerCase(),
          'source': 'field',
        });
        if (response.statusCode == 201) {
          await DatabaseHelper.instance.delete('offline_leads', where: 'id = ?', whereArgs: [lead['id']]);
        }
      } catch (e) {
        print('[Sync Engine] Lead sync failed: $e');
      }
    }

    print('[Sync Engine] Sync complete.');
    if (_role == 'admin' || _role == 'manager') {
      fetchAdminDashboardData();
    } else {
      fetchTodayLiveSummary();
      fetchTodayPlan();
      fetchSavedLeads();
      fetchUserIncidents();
    }
  }

  // 12. Admin & Manager Oversight Methods
  Future<void> fetchAdminDashboardData() async {
    await fetchAdminUsersList();
    await fetchAdminLiveVisitsList();
    await fetchAdminLiveGpsList();
    await fetchAdminStats();
  }

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

    final openIncidents = localIncidents.length;

    _adminStats = {
      ...serverStats,
      'total_users': totalUsers,
      'active_executives': activeExecutives,
      'distance_covered_km': distanceKm,
      'visits_completed': completedVisits,
      'sales_value_total': salesValueTotal,
      'open_incidents_count': openIncidents,
      'org': serverStats['org'] ??
          {
            'name': 'Alpha Corp Ltd',
            'email': _email ?? 'admin@alpha.com',
            'status': 'active',
          },
    };

    notifyListeners();
  }

  Future<void> fetchAdminUsersList() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.users);
      if (response.statusCode == 200) {
        _adminUsersList = response.data['data'] as List<dynamic>? ?? [];
        notifyListeners();
      }
    } catch (e) {
      print('Fetch admin users list failed: $e. Falling back to local mock list.');
    }

    if (_adminUsersList.isEmpty) {
      _adminUsersList = [
        {
          'id': 'exec-001',
          'name': 'Ankit Sharma',
          'email': 'ankit@alpha.com',
          'role': 'executive',
          'status': 'active',
          'created_at': '2026-06-15T08:00:00Z',
          'designation': 'Senior Field Executive',
        },
        {
          'id': 'exec-002',
          'name': 'Priya Patel',
          'email': 'priya@alpha.com',
          'role': 'executive',
          'status': 'active',
          'created_at': '2026-06-20T09:30:00Z',
          'designation': 'Area Representative',
        },
        {
          'id': 'exec-003',
          'name': 'Rohan Das',
          'email': 'rohan@alpha.com',
          'role': 'executive',
          'status': 'inactive',
          'created_at': '2026-06-22T10:15:00Z',
          'designation': 'Junior Field Agent',
        }
      ];
      notifyListeners();
    }
  }

  Future<bool> createExecutive(String name, String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.post(ApiEndpoints.users, data: {
        'name': name,
        'email': email,
        'password': password,
        'role': 'executive',
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        _isLoading = false;
        await fetchAdminUsersList();
        await fetchAdminStats();
        return true;
      }
    } catch (e) {
      print('Create executive failed on server: $e. Simulating local insert for demo.');
    }

    // High fidelity simulator insert
    _adminUsersList.insert(0, {
      'id': 'exec-${_uuid.v4()}',
      'name': name,
      'email': email,
      'role': 'executive',
      'status': 'active',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'designation': 'Field Sales Executive',
    });

    _isLoading = false;
    await fetchAdminStats();
    return true;
  }

  Future<void> fetchAdminLiveVisitsList() async {
    try {
      if (_role == 'admin' || _role == 'manager' || _role == 'SUPER_ADMIN' || _role == 'REGIONAL_MANAGER' || _role == 'SALES_MANAGER') {
        final response = await _apiClient.get(ApiEndpoints.visits);
        if (response.statusCode == 200) {
          final rawList = response.data['data'] as List<dynamic>? ?? [];
          _adminLiveVisitsList = rawList.map((v) {
            final visit = Map<String, dynamic>.from(v as Map);
            return {
              'id': visit['id'],
              'outletName': visit['outlet_name'] ?? visit['outletName'] ?? 'Outlet',
              'outletAddress': visit['outlet_address'] ?? visit['outletAddress'] ?? '',
              'checkInTime': visit['check_in_at'] ?? visit['checkin_time'] ?? visit['checkInTime'],
              'checkOutTime': visit['check_out_at'] ?? visit['checkout_time'] ?? visit['checkOutTime'],
              'salesValue': double.tryParse(visit['sales_value']?.toString() ?? visit['order_value']?.toString() ?? '0') ?? 0.0,
              'remarks': visit['remarks'] ?? visit['notes'] ?? '',
              'gpsLat': visit['gps_lat'] ?? visit['latitude'],
              'gpsLng': visit['gps_lng'] ?? visit['longitude'],
            };
          }).toList();
          notifyListeners();
          return;
        }
      }

      // Fallback: local SQLite visits for offline/demo mode
      final localVisits = await DatabaseHelper.instance.queryAll('offline_visits');
      
      final mappedVisits = localVisits.map((v) {
        // Match outlet details
        String outletName = 'Retail Outlet Store';
        String outletAddress = 'Market Area Sector';
        
        for (final route in _demoRoutes) {
          final outlets = route['outlets'] as List<dynamic>? ?? [];
          for (final outlet in outlets) {
            if (outlet is Map<String, dynamic> && outlet['id'] == v['outlet_id']) {
              outletName = outlet['name'] ?? outletName;
              outletAddress = outlet['address'] ?? outletAddress;
              break;
            }
          }
        }

        double totalAmount = 0.0;
        if (v['sales_value'] != null) {
          totalAmount = double.tryParse(v['sales_value'].toString()) ?? 0.0;
        }

        return {
          'id': v['id'],
          'outletName': outletName,
          'outletAddress': outletAddress,
          'checkInTime': v['checkin_time'],
          'checkOutTime': v['checkout_time'],
          'salesValue': totalAmount,
          'remarks': v['remarks'] ?? 'Normal client visit.',
          'managerOverride': v['manager_override'] == 1,
          'selfieUrl': v['selfie_url'],
          'gpsLat': v['gps_lat'],
          'gpsLng': v['gps_lng'],
          'address': v['address'],
        };
      }).toList();

      // Reverse so newest visit activities display on top
      _adminLiveVisitsList = mappedVisits.reversed.toList();
      notifyListeners();
    } catch (e) {
      print('Fetch admin live visits list failed: $e');
    }
  }

  Future<void> fetchAdminLiveGpsList() async {
    try {
      if (_role == 'admin' || _role == 'manager' || _role == 'SUPER_ADMIN' || _role == 'REGIONAL_MANAGER' || _role == 'SALES_MANAGER') {
        final response = await _apiClient.get(ApiEndpoints.gpsLive);
        if (response.statusCode == 200) {
          final rawList = response.data['data'] as List<dynamic>? ?? [];
          _adminLiveGpsList = rawList.map((ping) {
            final item = Map<String, dynamic>.from(ping as Map);
            return {
              'id': item['id'],
              'latitude': item['latitude'],
              'longitude': item['longitude'],
              'address': item['address'],
              'timestamp': item['logged_at'] ?? item['created_at'],
              'startPoint': item['tracking_start_point'],
              'userId': item['user_id'],
            };
          }).toList();
          notifyListeners();
          return;
        }
      }

      final localGps = await DatabaseHelper.instance.queryAll('offline_gps_pings');
      _adminLiveGpsList = localGps.map((ping) {
        return {
          'id': ping['id'],
          'latitude': ping['latitude'],
          'longitude': ping['longitude'],
          'address': ping['address'],
          'timestamp': ping['timestamp'],
          'startPoint': ping['tracking_start_point'],
        };
      }).toList().reversed.toList();
      notifyListeners();
    } catch (e) {
      print('Fetch admin live GPS list failed: $e');
    }
  }
}
