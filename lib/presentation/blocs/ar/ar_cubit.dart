import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'dart:math';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class ArState extends Equatable {
  final double rssi;
  final double estimatedDistance;
  final List<double> rssiHistory;
  final bool followMode;
  final bool? arCoreAvailable;

  const ArState({
    this.rssi = -70.0,
    this.estimatedDistance = 0.0,
    this.rssiHistory = const [],
    this.followMode = true,
    this.arCoreAvailable,
  });

  ArState copyWith({
    double? rssi,
    double? estimatedDistance,
    List<double>? rssiHistory,
    bool? followMode,
    bool? arCoreAvailable,
  }) {
    return ArState(
      rssi: rssi ?? this.rssi,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      rssiHistory: rssiHistory ?? this.rssiHistory,
      followMode: followMode ?? this.followMode,
      arCoreAvailable: arCoreAvailable ?? this.arCoreAvailable,
    );
  }

  @override
  List<Object?> get props => [rssi, estimatedDistance, rssiHistory, followMode, arCoreAvailable];
}

class ArCubit extends Cubit<ArState> {
  // Path-loss parameters (calibrated)
  static const _refRssi = -40.0;
  static const _pathLossExp = 2.5;
  static const _refDist = 1.0;

  ArCubit() : super(const ArState()) {
    _checkArCore();
  }

  Future<void> _checkArCore() async {
    try {
      final isAvailable = await ArCoreController.checkArCoreAvailability();
      final isInstalled = await ArCoreController.checkIsArCoreInstalled();
      emit(state.copyWith(arCoreAvailable: isAvailable && isInstalled));
    } catch (_) {
      emit(state.copyWith(arCoreAvailable: false));
    }
  }

  void updateRssi(double rssi) {
    final dist = _rssiToDistance(rssi);
    final history = List<double>.from(state.rssiHistory)..add(rssi);
    if (history.length > 30) {
      history.removeAt(0);
    }
    emit(state.copyWith(
      rssi: rssi,
      estimatedDistance: dist,
      rssiHistory: history,
    ));
  }

  void toggleFollowMode() {
    emit(state.copyWith(followMode: !state.followMode));
  }

  double _rssiToDistance(double rssi) {
    return _refDist * pow(10, (_refRssi - rssi) / (10 * _pathLossExp)).toDouble();
  }
}
