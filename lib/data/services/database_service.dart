import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';
import '../../core/constants/app_constants.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static Database? _db;

  DatabaseService._();
  factory DatabaseService() => _instance ??= DatabaseService._();

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableScanHistory} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        networks_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE ${AppConstants.tableDevices} (
        mac TEXT PRIMARY KEY,
        ip TEXT,
        vendor TEXT,
        device_type TEXT,
        first_seen INTEGER,
        last_seen INTEGER,
        is_new INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE ${AppConstants.tableHeatmapSessions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        target_bssid TEXT,
        step_count INTEGER,
        name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE ${AppConstants.tableHeatmapPoints} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        x REAL, y REAL, rssi REAL,
        timestamp INTEGER,
        FOREIGN KEY(session_id) REFERENCES ${AppConstants.tableHeatmapSessions}(id)
      )
    ''');
  }

  // ── Scan History ──────────────────────────────────────────────────────────

  Future<void> saveScan(List<WifiNetwork> networks) async {
    final db = await database;
    final json = jsonEncode(networks.map((n) => n.toMap()).toList());
    await db.insert(AppConstants.tableScanHistory, {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'networks_json': json,
    });
    // Keep only last 500 scan sessions
    await db.rawDelete('''
      DELETE FROM ${AppConstants.tableScanHistory}
      WHERE id NOT IN (
        SELECT id FROM ${AppConstants.tableScanHistory}
        ORDER BY timestamp DESC LIMIT 500
      )
    ''');
  }

  Future<List<ScanSession>> getScanHistory({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      AppConstants.tableScanHistory,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.asMap().entries.map((e) {
      final row = e.value;
      final rawJson = row['networks_json'] as String;
      List<WifiNetwork> nets = [];
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        nets = decoded.map((m) => WifiNetwork.fromMap(Map<String, dynamic>.from(m as Map))).toList();
      } catch (_) {}

      return ScanSession(
        id: row['id'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        networks: nets,
      );
    }).toList();
  }

  // ── Device Registry ───────────────────────────────────────────────────────

  Future<void> upsertDevice(NetworkDevice device) async {
    final db = await database;
    final existing = await db.query(
      AppConstants.tableDevices,
      where: 'mac = ?',
      whereArgs: [device.mac],
    );
    if (existing.isEmpty) {
      await db.insert(AppConstants.tableDevices, {
        ...device.toMap(),
        'is_new': 1,
      });
    } else {
      await db.update(
        AppConstants.tableDevices,
        {
          'ip': device.ip,
          'last_seen': device.lastSeen.millisecondsSinceEpoch,
          'is_new': 0,
        },
        where: 'mac = ?',
        whereArgs: [device.mac],
      );
    }
  }

  Future<List<NetworkDevice>> getDevices() async {
    final db = await database;
    final rows = await db.query(
      AppConstants.tableDevices,
      orderBy: 'last_seen DESC',
    );
    return rows.map(NetworkDevice.fromMap).toList();
  }

  Future<bool> isNewDevice(String mac) async {
    final db = await database;
    final rows = await db.query(
      AppConstants.tableDevices,
      where: 'mac = ?',
      whereArgs: [mac],
    );
    return rows.isEmpty;
  }

  // ── Heatmap Sessions ──────────────────────────────────────────────────────

  Future<int> createHeatmapSession({
    required String targetBssid,
    required String name,
  }) async {
    final db = await database;
    return db.insert(AppConstants.tableHeatmapSessions, {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'target_bssid': targetBssid,
      'step_count': 0,
      'name': name,
    });
  }

  Future<void> saveHeatmapPoint(int sessionId, HeatmapPoint point) async {
    final db = await database;
    await db.insert(AppConstants.tableHeatmapPoints, {
      'session_id': sessionId,
      ...point.toMap(),
    });
  }

  Future<List<HeatmapPoint>> getHeatmapPoints(int sessionId) async {
    final db = await database;
    final rows = await db.query(
      AppConstants.tableHeatmapPoints,
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    return rows.map(HeatmapPoint.fromMap).toList();
  }

  Future<void> updateSessionStepCount(int sessionId, int steps) async {
    final db = await database;
    await db.update(
      AppConstants.tableHeatmapSessions,
      {'step_count': steps},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}
