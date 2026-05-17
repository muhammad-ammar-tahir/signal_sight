import 'package:flutter/services.dart';

class PortScanner {
  static const MethodChannel _channel = MethodChannel('com.signalsight/network');

  /// Scan common open TCP ports on the target IP
  static Future<List<int>> scanPorts(String ip) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('scanPorts', {'ip': ip});
      return result.map((e) => e as int).toList();
    } catch (_) {
      return [];
    }
  }

  static String getServiceName(int port) {
    switch (port) {
      case 21: return 'FTP';
      case 22: return 'SSH';
      case 23: return 'Telnet';
      case 53: return 'DNS';
      case 80: return 'HTTP (Web)';
      case 111: return 'RPCBind';
      case 135: return 'RPC';
      case 139: return 'NetBIOS';
      case 443: return 'HTTPS (Secure Web)';
      case 445: return 'SMB (Windows Share)';
      case 554: return 'RTSP (Media/Camera)';
      case 3306: return 'MySQL';
      case 3389: return 'RDP (Remote Desktop)';
      case 5000: return 'UPnP / Web UI';
      case 5900: return 'VNC';
      case 8000: return 'HTTP Alternate';
      case 8080: return 'HTTP Proxy / Web UI';
      case 8443: return 'HTTPS Alternate';
      case 9000: return 'Portainer / Media';
      default: return 'Unknown Service';
    }
  }
}
