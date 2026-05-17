import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../data/models/models.dart';
import '../../../data/services/wifi_scan_service.dart';
import '../../../data/services/database_service.dart';
import '../../../core/utils/algorithms.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/api_service.dart';
import '../channel/channel_cubit.dart';
import '../security/security_cubit.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class ScanState extends Equatable {
  final List<WifiNetwork> networks;
  final bool isScanning;
  final String? connectedBSSID;
  final String? error;
  final DateTime? lastScan;
  final int? bestChannel;
  final bool backendOnline;

  const ScanState({
    this.networks = const [],
    this.isScanning = false,
    this.connectedBSSID,
    this.error,
    this.lastScan,
    this.bestChannel,
    this.backendOnline = false,
  });

  ScanState copyWith({
    List<WifiNetwork>? networks,
    bool? isScanning,
    String? connectedBSSID,
    String? error,
    DateTime? lastScan,
    int? bestChannel,
    bool? backendOnline,
  }) =>
      ScanState(
        networks: networks ?? this.networks,
        isScanning: isScanning ?? this.isScanning,
        connectedBSSID: connectedBSSID ?? this.connectedBSSID,
        error: error,
        lastScan: lastScan ?? this.lastScan,
        bestChannel: bestChannel ?? this.bestChannel,
        backendOnline: backendOnline ?? this.backendOnline,
      );

  @override
  List<Object?> get props => [
        networks,
        isScanning,
        connectedBSSID,
        error,
        lastScan,
        bestChannel,
        backendOnline,
      ];
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class ScanCubit extends Cubit<ScanState> {
  final WifiScanService _wifiService;
  final DatabaseService _db;
  final ApiService _api;

  // Optional sibling cubits for offline push-updates
  ChannelCubit? _channelCubit;
  SecurityCubit? _securityCubit;

  Timer? _pollTimer;

  ScanCubit(this._wifiService, this._db, this._api)
      : super(const ScanState()) {
    _api.isBackendReachable().then((online) {
      if (!isClosed) emit(state.copyWith(backendOnline: online));
    });
  }

  /// Inject sibling cubits so ScanCubit can push data after each scan.
  void bindSiblings({
    ChannelCubit? channelCubit,
    SecurityCubit? securityCubit,
  }) {
    _channelCubit = channelCubit;
    _securityCubit = securityCubit;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  void startScan({int intervalSec = AppConstants.defaultScanIntervalSec}) {
    if (state.isScanning) return;
    emit(state.copyWith(isScanning: true, error: null));

    _wifiService.startForegroundScan().catchError((e) {
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    });

    _fetchResults();
    _pollTimer = Timer.periodic(
      Duration(seconds: intervalSec),
      (_) => _fetchResults(),
    );
  }

  void stopScan() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _wifiService.stopForegroundScan();
    if (!isClosed) {
      emit(state.copyWith(isScanning: false));
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _fetchResults() async {
    try {
      final networks = await _wifiService.getResults();
      if (networks.isEmpty) return;

      final connectedBssid = await _wifiService.getConnectedBSSID();

      // Tag own network
      final tagged = networks.map((n) {
        return n.copyWith(isOwn: n.bssid == connectedBssid);
      }).toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));

      // Compute best 2.4 GHz channel locally (always available offline)
      final aps24 = tagged
          .where((n) => !n.is5GHz)
          .map((n) => (channel: n.channel, rssi: n.rssi))
          .toList();
      final congestion = ChannelUtils.computeCongestion(aps24);
      final bestList = ChannelUtils.bestChannels(congestion);
      final bestCh = bestList.isNotEmpty ? bestList.first.channel : null;

      if (!isClosed) {
        emit(state.copyWith(
          networks: tagged,
          connectedBSSID: connectedBssid,
          lastScan: DateTime.now(),
          bestChannel: bestCh,
          error: null,
        ));
      }

      // ── Push fresh data to sibling cubits (offline-first) ─────────────────
      _channelCubit?.computeFromNetworks(networks: tagged);
      _securityCubit?.runAuditOnNetworks(tagged);

      // Persist locally
      await _db.saveScan(tagged);

      // Upload to backend (non-blocking)
      _uploadToBackend(tagged);
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: e.toString()));
    }
  }

  void _uploadToBackend(List<WifiNetwork> networks) {
    _api.uploadScan(networks).then((_) {
      if (!isClosed && !state.backendOnline) {
        emit(state.copyWith(backendOnline: true));
      }
    }).catchError((_) {
      if (!isClosed && state.backendOnline) {
        emit(state.copyWith(backendOnline: false));
      }
    });
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
