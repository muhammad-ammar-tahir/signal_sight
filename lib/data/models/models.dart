import 'package:equatable/equatable.dart';

class WifiNetwork extends Equatable {
  final String ssid;
  final String bssid;
  final int rssi;
  final int frequency;
  final String capabilities;
  final int channel;
  final String security;
  final String securityTag;
  final String vendor;
  final DateTime timestamp;
  final bool isOwn;

  const WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.frequency,
    required this.capabilities,
    required this.channel,
    required this.security,
    required this.securityTag,
    this.vendor = 'Unknown',
    required this.timestamp,
    this.isOwn = false,
  });

  bool get is5GHz => frequency >= 5000;
  String get displaySsid => ssid.isEmpty ? '<Hidden Network>' : ssid;
  double get signalQuality => ((rssi + 100).clamp(0, 50)) / 50.0;

  WifiNetwork copyWith({
    String? ssid,
    String? bssid,
    int? rssi,
    int? frequency,
    String? capabilities,
    int? channel,
    String? security,
    String? securityTag,
    String? vendor,
    DateTime? timestamp,
    bool? isOwn,
  }) {
    return WifiNetwork(
      ssid: ssid ?? this.ssid,
      bssid: bssid ?? this.bssid,
      rssi: rssi ?? this.rssi,
      frequency: frequency ?? this.frequency,
      capabilities: capabilities ?? this.capabilities,
      channel: channel ?? this.channel,
      security: security ?? this.security,
      securityTag: securityTag ?? this.securityTag,
      vendor: vendor ?? this.vendor,
      timestamp: timestamp ?? this.timestamp,
      isOwn: isOwn ?? this.isOwn,
    );
  }

  Map<String, dynamic> toMap() => {
        'ssid': ssid,
        'bssid': bssid,
        'rssi': rssi,
        'frequency': frequency,
        'capabilities': capabilities,
        'channel': channel,
        'security': security,
        'security_tag': securityTag,
        'vendor': vendor,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'is_own': isOwn ? 1 : 0,
      };

  factory WifiNetwork.fromMap(Map<String, dynamic> map) => WifiNetwork(
        ssid: map['ssid'] ?? '',
        bssid: map['bssid'] ?? '',
        rssi: map['rssi'] ?? -100,
        frequency: map['frequency'] ?? 2412,
        capabilities: map['capabilities'] ?? '',
        channel: map['channel'] ?? 1,
        security: map['security'] ?? 'Unknown',
        securityTag: map['security_tag'] ?? 'Unknown',
        vendor: map['vendor'] ?? 'Unknown',
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
        isOwn: (map['is_own'] ?? 0) == 1,
      );

  @override
  List<Object?> get props => [bssid, timestamp];
}

class NetworkDevice extends Equatable {
  final String ip;
  final String mac;
  final String vendor;
  final String deviceType;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool isNew;
  final String? label;
  final bool isKnown;
  final String? hostname;
  final List<String> mdnsServices;
  final List<String> ssdpServices;
  final String category;
  final bool isOnline;

  const NetworkDevice({
    required this.ip,
    required this.mac,
    required this.vendor,
    required this.deviceType,
    required this.firstSeen,
    required this.lastSeen,
    this.isNew = false,
    this.label,
    this.isKnown = false,
    this.hostname,
    this.mdnsServices = const [],
    this.ssdpServices = const [],
    this.category = 'Unknown',
    this.isOnline = true,
  });

  NetworkDevice copyWith({
    String? ip,
    String? mac,
    String? vendor,
    String? deviceType,
    DateTime? firstSeen,
    DateTime? lastSeen,
    bool? isNew,
    String? label,
    bool? isKnown,
    String? hostname,
    List<String>? mdnsServices,
    List<String>? ssdpServices,
    String? category,
    bool? isOnline,
  }) {
    return NetworkDevice(
      ip: ip ?? this.ip,
      mac: mac ?? this.mac,
      vendor: vendor ?? this.vendor,
      deviceType: deviceType ?? this.deviceType,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      isNew: isNew ?? this.isNew,
      label: label ?? this.label,
      isKnown: isKnown ?? this.isKnown,
      hostname: hostname ?? this.hostname,
      mdnsServices: mdnsServices ?? this.mdnsServices,
      ssdpServices: ssdpServices ?? this.ssdpServices,
      category: category ?? this.category,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Map<String, dynamic> toMap() => {
        'ip': ip,
        'mac': mac,
        'vendor': vendor,
        'device_type': deviceType,
        'first_seen': firstSeen.millisecondsSinceEpoch,
        'last_seen': lastSeen.millisecondsSinceEpoch,
        'is_new': isNew ? 1 : 0,
        'label': label,
        'is_known': isKnown ? 1 : 0,
        'hostname': hostname,
        'mdns_services': mdnsServices.join(','),
        'ssdp_services': ssdpServices.join(','),
        'category': category,
        'is_online': isOnline ? 1 : 0,
      };

  factory NetworkDevice.fromMap(Map<String, dynamic> map) => NetworkDevice(
        ip: map['ip'] ?? '',
        mac: map['mac'] ?? '',
        vendor: map['vendor'] ?? 'Unknown',
        deviceType: map['device_type'] ?? 'unknown',
        firstSeen: DateTime.fromMillisecondsSinceEpoch(map['first_seen'] ?? 0),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen'] ?? 0),
        isNew: (map['is_new'] ?? 0) == 1,
        label: map['label'],
        isKnown: (map['is_known'] ?? 0) == 1,
        hostname: map['hostname'],
        mdnsServices: (map['mdns_services'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
        ssdpServices: (map['ssdp_services'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
        category: map['category'] ?? 'Unknown',
        isOnline: (map['is_online'] ?? 1) == 1,
      );

  @override
  List<Object?> get props => [mac];
}

class HeatmapPoint extends Equatable {
  final double x;
  final double y;
  final double rssi;
  final DateTime timestamp;

  const HeatmapPoint({
    required this.x,
    required this.y,
    required this.rssi,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'x': x,
        'y': y,
        'rssi': rssi,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory HeatmapPoint.fromMap(Map<String, dynamic> map) => HeatmapPoint(
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        rssi: (map['rssi'] as num).toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      );

  @override
  List<Object?> get props => [x, y, timestamp];
}

class ScanSession extends Equatable {
  final int id;
  final DateTime timestamp;
  final List<WifiNetwork> networks;

  const ScanSession({
    required this.id,
    required this.timestamp,
    required this.networks,
  });

  @override
  List<Object?> get props => [id];
}

class WallSegment extends Equatable {
  final double x1, y1, x2, y2;
  final String material; // drywall, concrete, glass
  double get attenuation {
    switch (material) {
      case 'concrete': return 12.0;
      case 'glass': return 2.0;
      case 'drywall': return 3.0;
      default: return 3.0;
    }
  }

  const WallSegment({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.material,
  });

  @override
  List<Object?> get props => [x1, y1, x2, y2, material];
}
