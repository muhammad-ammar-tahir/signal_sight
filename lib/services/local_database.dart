import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../data/models/models.dart';

class LocalDatabase {
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'signalsight_local.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scan_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            networks_json TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE devices (
            mac TEXT PRIMARY KEY,
            ip TEXT,
            vendor TEXT,
            device_type TEXT,
            first_seen TEXT,
            last_seen TEXT,
            is_new INTEGER DEFAULT 1
          )
        ''');
      },
    );
  }

  Future<void> saveScanLocal(List<WifiNetwork> networks) async {
    final db = await database;
    await db.insert('scan_history', {
      'timestamp': DateTime.now().toIso8601String(),
      'networks_json': jsonEncode(networks.map((n) => n.toMap()).toList()),
    });
  }

  Future<List<ScanSession>> getScanHistoryLocal() async {
    final db = await database;
    final rows = await db.query('scan_history', orderBy: 'timestamp DESC', limit: 100);
    return rows.map((row) {
      final nets = (jsonDecode(row['networks_json'] as String) as List<dynamic>)
          .map((n) => WifiNetwork.fromMap(Map<String, dynamic>.from(n as Map)))
          .toList();
      return ScanSession(
        id: row['id'] as int,
        timestamp: DateTime.parse(row['timestamp'] as String),
        networks: nets,
      );
    }).toList();
  }

  Future<void> upsertDeviceLocal(NetworkDevice device) async {
    final db = await database;
    await db.insert('devices', device.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<NetworkDevice>> getDevicesLocal() async {
    final db = await database;
    final rows = await db.query('devices', orderBy: 'last_seen DESC');
    return rows.map((r) => NetworkDevice.fromMap(r)).toList();
  }
}
