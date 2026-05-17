import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models/models.dart';
import 'local_database.dart';

/// Central HTTP client for the SignalSight FastAPI backend.
///
/// Every method tries the remote API first; on any network error it falls back
/// to the local SQLite mirror so the app stays functional offline.
class ApiService {
  String baseUrl;
  final LocalDatabase _localDb;
  final Duration _timeout;

  ApiService(
    this._localDb, {
    this.baseUrl = 'http://10.0.2.2:8000/api', // Android emulator host
    Duration timeout = const Duration(seconds: 12),
  }) : _timeout = timeout;

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query != null ? uri.replace(queryParameters: query) : uri;
  }

  Future<Map<String, dynamic>> _getJson(String path,
      [Map<String, String>? query]) async {
    final resp =
        await http.get(_uri(path, query), headers: _headers).timeout(_timeout);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('GET $path → HTTP ${resp.statusCode}: ${resp.body}');
  }

  Future<List<dynamic>> _getJsonList(String path,
      [Map<String, String>? query]) async {
    final resp =
        await http.get(_uri(path, query), headers: _headers).timeout(_timeout);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as List<dynamic>;
    }
    throw Exception('GET $path → HTTP ${resp.statusCode}: ${resp.body}');
  }

  Future<Map<String, dynamic>> _postJson(
      String path, Map<String, dynamic> body) async {
    final resp = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('POST $path → HTTP ${resp.statusCode}: ${resp.body}');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Health check
  // ──────────────────────────────────────────────────────────────────────────

  Future<bool> isBackendReachable() async {
    try {
      final resp = await http
          .get(Uri.parse(baseUrl.replaceAll('/api', '/health')))
          .timeout(const Duration(seconds: 4));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Scan endpoints
  // ──────────────────────────────────────────────────────────────────────────

  /// POST /api/scan/upload
  /// Uploads a fresh WiFi scan to the backend and persists locally as fallback.
  Future<void> uploadScan(List<WifiNetwork> networks) async {
    // Always persist locally first (offline safety)
    await _localDb.saveScanLocal(networks);
    try {
      await _postJson('/scan/upload', {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'networks': networks
            .map((n) => {
                  'ssid': n.ssid,
                  'bssid': n.bssid,
                  'rssi': n.rssi,
                  'frequency': n.frequency,
                  'capabilities': n.capabilities,
                  'channel': n.channel,
                  'security': n.security,
                  'security_tag': n.securityTag,
                  'vendor': n.vendor,
                  'is_own': n.isOwn,
                })
            .toList(),
      });
    } catch (_) {
      // silently absorbed – local DB already has the data
    }
  }

  /// GET /api/scan/latest
  Future<Map<String, dynamic>?> getLatestScan() async {
    try {
      return await _getJson('/scan/latest');
    } catch (_) {
      return null;
    }
  }

  /// GET /api/scan/history?limit=N&bssid=XX
  Future<List<ScanSession>> getScanHistory({
    int limit = 100,
    String? bssid,
  }) async {
    try {
      final query = <String, String>{'limit': '$limit'};
      if (bssid != null) query['bssid'] = bssid;
      final raw = await _getJsonList('/scan/history', query);
      return raw.map((json) {
        final j = json as Map<String, dynamic>;
        final nets = (j['networks'] as List<dynamic>)
            .map((n) => WifiNetwork.fromMap(Map<String, dynamic>.from(n as Map)))
            .toList();
        return ScanSession(
          id: j['id'] as int,
          timestamp: DateTime.parse(j['timestamp'] as String),
          networks: nets,
        );
      }).toList();
    } catch (_) {
      return _localDb.getScanHistoryLocal();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Channel analysis
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/channel/recommendation?band=2.4GHz|5GHz
  Future<Map<String, dynamic>> getChannelRecommendation(
      String band) async {
    final raw = await _getJson('/channel/recommendation', {'band': band});
    // Normalise congestion_scores keys to int
    final scores = <int, double>{};
    (raw['congestion_scores'] as Map<String, dynamic>).forEach((k, v) {
      scores[int.parse(k)] = (v as num).toDouble();
    });
    return {
      ...raw,
      'congestion_scores': scores,
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Security audit
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/security/audit
  Future<Map<String, dynamic>> getSecurityAudit() async {
    return _getJson('/security/audit');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Device management
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/devices
  Future<List<NetworkDevice>> getDevices() async {
    try {
      final raw = await _getJsonList('/devices');
      return raw.map((d) {
        final m = Map<String, dynamic>.from(d as Map);
        // Backend uses ISO string timestamps; convert to ms for the model
        return NetworkDevice(
          ip: m['ip'] as String? ?? '',
          mac: m['mac'] as String? ?? '',
          vendor: m['vendor'] as String? ?? 'Unknown',
          deviceType: m['device_type'] as String? ?? 'unknown',
          firstSeen: _parseTs(m['first_seen']),
          lastSeen: _parseTs(m['last_seen']),
          isNew: (m['is_new'] == true || m['is_new'] == 1),
        );
      }).toList();
    } catch (_) {
      return _localDb.getDevicesLocal();
    }
  }

  DateTime _parseTs(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  /// POST /api/devices/update  — bulk device list sync
  Future<void> updateDevices(List<NetworkDevice> devices) async {
    try {
      await _postJson('/devices/update', {
        'devices': devices
            .map((d) => {
                  'ip': d.ip,
                  'mac': d.mac,
                  'vendor': d.vendor,
                  'device_type': d.deviceType,
                  'first_seen': d.firstSeen.toIso8601String(),
                  'last_seen': d.lastSeen.toIso8601String(),
                  'is_new': d.isNew,
                })
            .toList(),
      });
    } catch (_) {
      for (final d in devices) {
        await _localDb.upsertDeviceLocal(d);
      }
    }
  }

  /// POST /api/devices/register  — single device
  Future<void> registerDevice(NetworkDevice device) async {
    try {
      await _postJson('/devices/register', {
        'ip': device.ip,
        'mac': device.mac,
        'vendor': device.vendor,
        'device_type': device.deviceType,
        'first_seen': device.firstSeen.toIso8601String(),
        'last_seen': device.lastSeen.toIso8601String(),
        'is_new': device.isNew,
      });
    } catch (_) {
      await _localDb.upsertDeviceLocal(device);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Coverage prediction
  // ──────────────────────────────────────────────────────────────────────────

  /// POST /api/predict/coverage
  Future<Map<String, dynamic>> predictCoverage(
      Map<String, dynamic> requestData) async {
    return _postJson('/predict/coverage', requestData);
  }

  /// POST /api/predict/optimal-placement
  Future<Map<String, dynamic>> getOptimalPlacement(
      Map<String, dynamic> requestData) async {
    // Ensure tx_power is reasonable (frontend may pass negative dBm)
    final data = Map<String, dynamic>.from(requestData);
    data['tx_power'] ??= 20.0;
    data['frequency'] ??= 2437;
    data['resolution'] ??= 0.5;
    data['target_rssi'] ??= -70.0;
    data['walls'] ??= <dynamic>[];
    return _postJson('/predict/optimal-placement', data);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ML
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/ml/status
  Future<Map<String, dynamic>> getMlStatus() async {
    return _getJson('/ml/status');
  }

  /// POST /api/ml/train  — trigger retraining
  Future<Map<String, dynamic>> triggerTraining() async {
    return _postJson('/ml/train', {});
  }

  /// POST /api/ml/predict
  Future<double> predictRssi({
    required double distanceM,
    required int frequency,
    required int walls,
    double timeOfDay = 12.0,
    int channel = 6,
  }) async {
    final result = await _postJson('/ml/predict', {
      'distance_m': distanceM,
      'frequency': frequency,
      'walls': walls,
      'time_of_day': timeOfDay,
      'channel': channel,
    });
    return (result['predicted_rssi'] as num).toDouble();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // History / Time Machine
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/history/timeline
  Future<List<Map<String, dynamic>>> getTimeline({int limit = 200}) async {
    try {
      final raw = await _getJson('/history/timeline', {'limit': '$limit'});
      return List<Map<String, dynamic>>.from(
          (raw['entries'] as List<dynamic>).cast<Map<String, dynamic>>());
    } catch (_) {
      return [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Alerts
  // ──────────────────────────────────────────────────────────────────────────

  /// GET /api/alerts?unread_only=true
  Future<List<Map<String, dynamic>>> getAlerts(
      {bool unreadOnly = false}) async {
    try {
      final raw = await _getJsonList(
          '/alerts', {'unread_only': '$unreadOnly'});
      return raw.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// PATCH /api/alerts/{id}/read
  Future<void> markAlertRead(int alertId) async {
    try {
      final resp = await http
          .patch(_uri('/alerts/$alertId/read'), headers: _headers)
          .timeout(_timeout);
      if (resp.statusCode != 200) {
        throw Exception('PATCH alerts/$alertId/read → ${resp.statusCode}');
      }
    } catch (_) {}
  }
}
