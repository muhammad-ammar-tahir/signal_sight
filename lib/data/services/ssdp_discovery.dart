import 'package:flutter/services.dart';

class SSDPDiscovery {
  static const MethodChannel _channel = MethodChannel('com.signalsight/network');

  /// Scan for SSDP (UPnP) devices on the local network natively
  static Future<Map<String, List<String>>> scanServices() async {
    final Map<String, List<String>> discovered = {};
    
    try {
      final List<dynamic> results = await _channel.invokeMethod('discoverSSDP');
      
      for (final item in results) {
        final map = item as Map;
        final ip = map['ip'] as String;
        final server = map['server'] as String;
        final st = map['st'] as String;
        
        if (!discovered.containsKey(ip)) {
          discovered[ip] = [];
        }
        
        if (server.isNotEmpty && !discovered[ip]!.contains(server)) {
          discovered[ip]!.add(server);
        }
        if (st.isNotEmpty && !discovered[ip]!.contains(st)) {
          discovered[ip]!.add(st);
        }
      }
    } catch (_) {
      // Handle gracefully
    }
    
    return discovered;
  }
}
