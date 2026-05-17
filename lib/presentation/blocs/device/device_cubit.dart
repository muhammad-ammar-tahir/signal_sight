import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/models.dart';
import '../../../data/services/device_db.dart';
import '../../../data/services/oui_lookup.dart';
import '../../../data/services/network_analytics.dart';

// ─── States ──────────────────────────────────────────────────────────────────

abstract class DeviceState extends Equatable {
  const DeviceState();
  @override
  List<Object?> get props => [];
}

class DeviceInitial extends DeviceState {
  const DeviceInitial();
}

/// Emitted while the native scan is running – [devices] grows incrementally.
class DeviceScanning extends DeviceState {
  final List<NetworkDevice> devices;
  const DeviceScanning({required this.devices});
  @override
  List<Object?> get props => [devices];
}

class DeviceLoading extends DeviceState {
  const DeviceLoading();
}

class DeviceLoaded extends DeviceState {
  final List<NetworkDevice> devices;
  final String? warning;
  final DateTime lastScan;
  final List<NetworkDevice> unknownDevices;

  const DeviceLoaded({
    required this.devices,
    this.warning,
    required this.lastScan,
    required this.unknownDevices,
  });

  @override
  List<Object?> get props => [devices, warning, lastScan, unknownDevices];
}

class DeviceEmpty extends DeviceState {
  const DeviceEmpty();
}

class DeviceError extends DeviceState {
  final String message;
  const DeviceError(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class DeviceCubit extends Cubit<DeviceState> {
  final DeviceDb _db;

  static const MethodChannel _networkChannel =
      MethodChannel('com.signalsight/network');
  static const EventChannel _networkStream =
      EventChannel('com.signalsight/network_stream');

  Timer? _autoRefreshTimer;
  Timer? _liveStatusTimer;
  StreamSubscription? _scanStreamSub;

  /// Accumulator during a live scan – keyed by IP for deduplication.
  final Map<String, NetworkDevice> _liveDevices = {};

  /// DB snapshot loaded once at scan start – keyed by MAC.
  /// Avoids calling loadAllDevices() for every incoming device.
  final Map<String, NetworkDevice> _dbCache = {};

  DeviceCubit(this._db) : super(const DeviceInitial()) {
    _init();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    await OuiLookup.load();
    await loadFromDb();
    _startLiveMonitoring();
  }

  // ── Load from DB ──────────────────────────────────────────────────────────

  Future<void> loadFromDb() async {
    try {
      final cached = await _db.loadAllDevices();
      if (isClosed) return;
      if (cached.isEmpty) {
        emit(const DeviceEmpty());
      } else {
        final unknown = cached.where((d) => !d.isKnown).toList();
        emit(DeviceLoaded(
          devices: cached,
          lastScan: DateTime.now(),
          warning: 'Showing cached devices. Pull to refresh.',
          unknownDevices: unknown,
        ));
      }
    } catch (_) {}
  }

  // ── Main scan ─────────────────────────────────────────────────────────────

  Future<void> scan({bool isAutoRefresh = false}) async {
    // Cancel any running scan
    await _scanStreamSub?.cancel();
    _scanStreamSub = null;
    _liveDevices.clear();

    if (!isAutoRefresh) emit(const DeviceScanning(devices: []));

    // Load DB once so _handleIncomingDevice never does per-device DB reads
    try {
      final cached = await _db.loadAllDevices();
      _dbCache
        ..clear()
        ..addEntries(cached.map((d) => MapEntry(d.mac, d)));
    } catch (_) {}

    // Tell native plugin to start – it returns immediately;
    // results arrive via the EventChannel below.
    try {
      await _networkChannel.invokeMethod('scanDevices');
    } on PlatformException catch (e) {
      if (!isClosed) emit(DeviceError(e.message ?? 'Scan failed'));
      return;
    }

    // Subscribe to real-time device events.
    // 30-second timeout ensures finalize fires even if native endOfStream() is
    // never called (e.g. scan cancelled mid-way or exception in Kotlin).
    _scanStreamSub = _networkStream
        .receiveBroadcastStream()
        .timeout(
          const Duration(seconds: 30),
          onTimeout: (sink) => sink.close(),
        )
        .listen(
          (event) {
            if (isClosed) return;
            _handleIncomingDevice(Map<String, dynamic>.from(event as Map));
          },
          onDone: () {
            if (!isClosed) _finalizeScan();
          },
          onError: (Object err) {
            if (!isClosed) emit(DeviceError(err.toString()));
          },
          cancelOnError: false,
        );
  }

  /// Process one device map emitted by the native EventChannel.
  /// This is synchronous – no awaits – so it can't block the event loop.
  void _handleIncomingDevice(Map<String, dynamic> map) {
    final ip          = map['ip']          as String? ?? '';
    final mac         = map['mac']         as String? ?? _pseudoMac(ip);
    final deviceName  = map['deviceName']  as String? ?? ip;
    final serviceType = map['serviceType'] as String? ?? '';
    final deviceType  = map['deviceType']  as String? ?? 'IoT/Other';

    if (ip.isEmpty) return;

    final vendor   = OuiLookup.getVendor(mac);
    final category = NetworkAnalytics.categorizeDevice(
        vendor, deviceName, [serviceType], []);

    final now     = DateTime.now();
    final dbEntry = _dbCache[mac]; // O(1) – no DB call

    final NetworkDevice device;
    if (dbEntry != null) {
      device = dbEntry.copyWith(
        ip: ip,
        lastSeen: now,
        vendor:   vendor.isNotEmpty    ? vendor      : dbEntry.vendor,
        hostname: deviceName.isNotEmpty ? deviceName : dbEntry.hostname,
        category: category,
        isOnline: true,
        isNew:    false,
      );
    } else {
      device = NetworkDevice(
        ip:           ip,
        mac:          mac,
        vendor:       vendor.isNotEmpty ? vendor : 'Unknown',
        deviceType:   deviceType,
        firstSeen:    now,
        lastSeen:     now,
        isNew:        true,
        isKnown:      false,
        hostname:     deviceName,
        mdnsServices: [],
        ssdpServices: serviceType.isNotEmpty ? [serviceType] : [],
        category:     category,
        isOnline:     true,
      );
      _showNotification(
        'New Device Found',
        '$deviceName joined ($ip)',
        isUnknownAlert: true,
      );
    }

    _liveDevices[ip] = device;
    _db.saveDevice(device); // fire-and-forget; doesn't block event processing

    if (!isClosed) {
      emit(DeviceScanning(devices: _sortedList(_liveDevices.values.toList())));
    }
  }

  void _finalizeScan() {
    final list = _sortedList(_liveDevices.values.toList());
    if (list.isEmpty) {
      _db.loadAllDevices().then((cached) {
        if (isClosed) return;
        if (cached.isEmpty) {
          emit(const DeviceEmpty());
        } else {
          emit(DeviceLoaded(
            devices: cached,
            lastScan: DateTime.now(),
            warning: 'No new devices found on network.',
            unknownDevices: cached.where((d) => !d.isKnown).toList(),
          ));
        }
      });
      return;
    }
    _db.recordDailyCount(list.length);
    emit(DeviceLoaded(
      devices: list,
      lastScan: DateTime.now(),
      unknownDevices: list.where((d) => !d.isKnown).toList(),
    ));
  }

  List<NetworkDevice> _sortedList(List<NetworkDevice> list) {
    return list
      ..sort((a, b) {
        if (!a.isKnown && b.isKnown) return -1;
        if (a.isKnown && !b.isKnown) return 1;
        return _ipToInt(a.ip).compareTo(_ipToInt(b.ip));
      });
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────────

  void toggleAutoRefresh(bool enabled) {
    if (enabled) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer =
          Timer.periodic(const Duration(seconds: 45), (_) {
        if (!isClosed) scan(isAutoRefresh: true);
      });
      scan();
    } else {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    }
  }

  // ── Live presence monitoring ──────────────────────────────────────────────

  void _startLiveMonitoring() {
    _liveStatusTimer?.cancel();
    _liveStatusTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      final current = state;
      if (current is! DeviceLoaded) return;

      bool changed = false;
      final updated = <NetworkDevice>[];

      for (final device in current.devices) {
        if (!device.isKnown) { updated.add(device); continue; }

        final wasOnline = device.isOnline;
        final isOnline  = await _pingDevice(device.ip);

        if (wasOnline && !isOnline) {
          final diff = DateTime.now().difference(device.lastSeen);
          if (diff.inMinutes > 5) {
            _showNotification(
              'Device Offline',
              '${device.label ?? device.hostname ?? device.vendor} went offline',
            );
          }
        }

        if (wasOnline != isOnline) {
          changed = true;
          updated.add(device.copyWith(
            isOnline: isOnline,
            lastSeen: isOnline ? DateTime.now() : device.lastSeen,
          ));
          await _db.updateDeviceStatus(device.mac, isOnline);
        } else {
          updated.add(device);
        }
      }

      if (changed && !isClosed) {
        emit(DeviceLoaded(
          devices: updated,
          lastScan: current.lastScan,
          unknownDevices: updated.where((d) => !d.isKnown).toList(),
        ));
      }
    });
  }

  Future<bool> _pingDevice(String ip) async {
    try {
      return await _networkChannel.invokeMethod('pingDevice', {'ip': ip})
          as bool;
    } catch (_) {
      return false;
    }
  }

  // ── Device label management ───────────────────────────────────────────────

  Future<void> updateDeviceLabel(
      String mac, String label, bool isKnown) async {
    await _db.updateDeviceLabel(mac, label, isKnown);
    final current = state;
    if (current is DeviceLoaded) {
      final updatedList = current.devices.map((d) {
        if (d.mac == mac) {
          return d.copyWith(label: label, isKnown: isKnown, isNew: false);
        }
        return d;
      }).toList();
      if (!isClosed) {
        emit(DeviceLoaded(
          devices: updatedList,
          lastScan: current.lastScan,
          unknownDevices: updatedList.where((d) => !d.isKnown).toList(),
        ));
      }
    }
  }

  Future<void> markUnknown(String mac) async {
    await _db.updateDeviceLabel(mac, null, false);
    final current = state;
    if (current is DeviceLoaded) {
      final updatedList = current.devices.map((d) {
        if (d.mac == mac) return d.copyWith(isKnown: false, label: null);
        return d;
      }).toList();
      if (!isClosed) {
        emit(DeviceLoaded(
          devices: updatedList,
          lastScan: current.lastScan,
          unknownDevices: updatedList.where((d) => !d.isKnown).toList(),
        ));
      }
    }
  }

  // ── Notification ─────────────────────────────────────────────────────────

  Future<void> _showNotification(
    String title,
    String body, {
    bool isUnknownAlert = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pref  = prefs.getString('pref_notification_pref') ?? 'unknown_only';
    if (pref == 'silence') return;
    if (pref == 'unknown_only' && !isUnknownAlert) return;
    try {
      await _networkChannel.invokeMethod('showNotification', {
        'title': title,
        'body':  body,
      });
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _ipToInt(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length == 4 && parts.every((p) => p != null)) {
      return (parts[0]! << 24) | (parts[1]! << 16) |
             (parts[2]! << 8)  |  parts[3]!;
    }
    return 0;
  }

  String _pseudoMac(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return '00:00:00:00:00:00';
    return '02:00:${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}'
        ':${parts[2].padLeft(2, '0')}:${parts[3].padLeft(2, '0')}';
  }

  @override
  Future<void> close() async {
    await _scanStreamSub?.cancel();
    _autoRefreshTimer?.cancel();
    _liveStatusTimer?.cancel();
    return super.close();
  }
}
