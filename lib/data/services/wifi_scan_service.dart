import 'dart:async';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../../core/utils/algorithms.dart';

class WifiScanService {
  static const _channel = MethodChannel('com.signalsight/wifi');
  static const _eventChannel = EventChannel('com.signalsight/wifi_stream');

  Stream<List<WifiNetwork>>? _scanStream;

  Stream<List<WifiNetwork>> get scanStream {
    _scanStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((data) => _parseResults(data))
        .asBroadcastStream();
    return _scanStream!;
  }

  Future<void> startForegroundScan() async {
    try {
      await _channel.invokeMethod('startForegroundScan');
    } on PlatformException catch (e) {
      throw Exception('Failed to start scan: ${e.message}');
    }
  }

  Future<void> stopForegroundScan() async {
    try {
      await _channel.invokeMethod('stopForegroundScan');
    } on PlatformException catch (e) {
      throw Exception('Failed to stop scan: ${e.message}');
    }
  }

  Future<List<WifiNetwork>> getResults() async {
    try {
      final result = await _channel.invokeMethod('getResults');
      return _parseResults(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to get results: ${e.message}');
    }
  }

  Future<String?> getConnectedBSSID() async {
    try {
      return await _channel.invokeMethod('getConnectedBSSID');
    } catch (_) {
      return null;
    }
  }

  List<WifiNetwork> _parseResults(dynamic data) {
    if (data == null) return [];
    final List<dynamic> raw = data as List<dynamic>;
    return raw.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final caps = map['capabilities'] as String? ?? '';
      final freq = (map['frequency'] as int?) ?? 2412;
      final ch = _freqToChannel(freq);
      return WifiNetwork(
        ssid: map['SSID'] as String? ?? '',
        bssid: map['BSSID'] as String? ?? '',
        rssi: (map['level'] as int?) ?? -100,
        frequency: freq,
        capabilities: caps,
        channel: ch,
        security: SecurityUtils.classify(caps),
        securityTag: SecurityUtils.securityTag(caps),
        timestamp: DateTime.now(),
      );
    }).toList();
  }

  int _freqToChannel(int freq) {
    if (freq >= 2412 && freq <= 2484) {
      if (freq == 2484) return 14;
      return (freq - 2412) ~/ 5 + 1;
    }
    if (freq >= 5170 && freq <= 5825) {
      return (freq - 5170) ~/ 5 + 34;
    }
    return 0;
  }
}
