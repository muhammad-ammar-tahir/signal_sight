import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class DeviceDb {
  static final DeviceDb _instance = DeviceDb._internal();
  factory DeviceDb() => _instance;
  DeviceDb._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'signalsight_devices.db');

    return await openDatabase(
      path,
      version: 2, // Migrating to V2
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // In a real app we'd use ALTER TABLE, but for simplicity here we can recreate or just add columns
          try {
            await db.execute('ALTER TABLE known_devices ADD COLUMN hostname TEXT');
            await db.execute('ALTER TABLE known_devices ADD COLUMN mdnsServices TEXT');
            await db.execute('ALTER TABLE known_devices ADD COLUMN ssdpServices TEXT');
            await db.execute('ALTER TABLE known_devices ADD COLUMN category TEXT');
            await db.execute('ALTER TABLE known_devices ADD COLUMN isOnline INTEGER');
          } catch (_) {}
          
          await db.execute('''
            CREATE TABLE IF NOT EXISTS daily_device_counts (
              date TEXT PRIMARY KEY,
              count INTEGER
            )
          ''');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE known_devices (
            mac TEXT PRIMARY KEY,
            label TEXT,
            vendor TEXT,
            deviceType TEXT,
            isKnown INTEGER,
            firstSeen TEXT,
            lastSeen TEXT,
            hostname TEXT,
            mdnsServices TEXT,
            ssdpServices TEXT,
            category TEXT,
            isOnline INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE daily_device_counts (
            date TEXT PRIMARY KEY,
            count INTEGER
          )
        ''');
      },
    );
  }

  Future<List<NetworkDevice>> loadAllDevices() async {
    final db = await database;
    final maps = await db.query('known_devices');
    
    return maps.map((map) {
      return NetworkDevice(
        ip: '', 
        mac: map['mac'] as String,
        vendor: map['vendor'] as String,
        deviceType: map['deviceType'] as String,
        firstSeen: DateTime.parse(map['firstSeen'] as String),
        lastSeen: DateTime.parse(map['lastSeen'] as String),
        label: map['label'] as String?,
        isKnown: (map['isKnown'] as int) == 1,
        hostname: map['hostname'] as String?,
        mdnsServices: (map['mdnsServices'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
        ssdpServices: (map['ssdpServices'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
        category: map['category'] as String? ?? 'Unknown',
        isOnline: (map['isOnline'] as int?) == 1,
      );
    }).toList();
  }

  Future<void> saveDevice(NetworkDevice device) async {
    final db = await database;
    await db.insert(
      'known_devices',
      {
        'mac': device.mac,
        'label': device.label,
        'vendor': device.vendor,
        'deviceType': device.deviceType,
        'isKnown': device.isKnown ? 1 : 0,
        'firstSeen': device.firstSeen.toIso8601String(),
        'lastSeen': device.lastSeen.toIso8601String(),
        'hostname': device.hostname,
        'mdnsServices': device.mdnsServices.join(','),
        'ssdpServices': device.ssdpServices.join(','),
        'category': device.category,
        'isOnline': device.isOnline ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateDeviceLabel(String mac, String? label, bool isKnown) async {
    final db = await database;
    await db.update(
      'known_devices',
      {
        'label': label,
        'isKnown': isKnown ? 1 : 0,
      },
      where: 'mac = ?',
      whereArgs: [mac],
    );
  }
  
  Future<void> updateDeviceStatus(String mac, bool isOnline) async {
    final db = await database;
    await db.update(
      'known_devices',
      {'isOnline': isOnline ? 1 : 0},
      where: 'mac = ?',
      whereArgs: [mac],
    );
  }

  Future<void> recordDailyCount(int count) async {
    final db = await database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await db.insert(
      'daily_device_counts',
      {'date': today, 'count': count},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getDailyCounts(int days) async {
    final db = await database;
    return await db.query(
      'daily_device_counts',
      orderBy: 'date DESC',
      limit: days,
    );
  }
}
