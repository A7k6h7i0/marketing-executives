import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fieldforce.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Table for offline GPS pings
    await db.execute('''
      CREATE TABLE offline_gps_pings (
        id TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        address TEXT,
        timestamp TEXT NOT NULL,
        tracking_start_point TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 2. Table for offline outlet visits (check-ins, orders, checkouts)
    await db.execute('''
      CREATE TABLE offline_visits (
        id TEXT PRIMARY KEY,
        outlet_id TEXT NOT NULL,
        gps_lat REAL NOT NULL,
        gps_lng REAL NOT NULL,
        address TEXT,
        selfie_url TEXT NOT NULL,
        checkin_time TEXT NOT NULL,
        checkout_time TEXT,
        products_ordered TEXT, -- JSON string of ordered items
        sales_value REAL DEFAULT 0.0,
        remarks TEXT,
        manager_override INTEGER NOT NULL DEFAULT 0,
        auto_detected INTEGER NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 3. Table for offline incident reports
    await db.execute('''
      CREATE TABLE offline_incidents (
        id TEXT PRIMARY KEY,
        incident_type TEXT NOT NULL,
        description TEXT NOT NULL,
        image_urls TEXT, -- Comma-separated or JSON array of URLs
        video_urls TEXT, -- Comma-separated or JSON array of URLs
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 4. Table for offline leads
    await db.execute('''
      CREATE TABLE offline_leads (
        id TEXT PRIMARY KEY,
        business_name TEXT NOT NULL,
        business_category TEXT NOT NULL,
        contact_phone TEXT,
        contact_email TEXT,
        gps_lat REAL NOT NULL,
        gps_lng REAL NOT NULL,
        lead_status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE offline_custom_routes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        region TEXT NOT NULL,
        outlets_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE offline_breaks (
        id TEXT PRIMARY KEY,
        break_type TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        break_date TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE offline_gps_pings ADD COLUMN address TEXT');
      await db.execute('ALTER TABLE offline_visits ADD COLUMN address TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_custom_routes (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          region TEXT NOT NULL,
          outlets_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE offline_visits ADD COLUMN auto_detected INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_breaks (
          id TEXT PRIMARY KEY,
          break_type TEXT NOT NULL,
          start_time TEXT NOT NULL,
          end_time TEXT,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          break_date TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
  }

  // Generic helper methods for CRUD operations
  Future<int> insert(String table, Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> queryAll(String table, {String? where, List<dynamic>? whereArgs}) async {
    final db = await instance.database;
    return await db.query(table, where: where, whereArgs: whereArgs);
  }

  Future<int> update(String table, Map<String, dynamic> row, {required String where, required List<dynamic> whereArgs}) async {
    final db = await instance.database;
    return await db.update(table, row, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table, {required String where, required List<dynamic> whereArgs}) async {
    final db = await instance.database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}
