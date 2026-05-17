import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../data/services/wifi_scan_service.dart';

abstract class ScanState extends Equatable {
  const ScanState();
  @override
  List<Object?> get props => [];
}

class ScanInitial extends ScanState {}

class ScanLoading extends ScanState {}

class ScanLoaded extends ScanState {
  final List<WifiNetwork> networks;
  const ScanLoaded(this.networks);
  @override
  List<Object?> get props => [networks];
}

class ScanError extends ScanState {
  final String message;
  const ScanError(this.message);
  @override
  List<Object?> get props => [message];
}

class ScanCubit extends Cubit<ScanState> {
  final WifiScanService _wifiService;
  final ApiService _apiService;

  ScanCubit(this._wifiService, this._apiService) : super(ScanInitial());

  Future<void> startScan() async {
    emit(ScanLoading());
    try {
      await _wifiService.startForegroundScan();
      refreshScan();
    } catch (e) {
      emit(ScanError(e.toString()));
    }
  }

  void stopScan() {
    _wifiService.stopForegroundScan();
    emit(ScanInitial());
  }

  Future<void> refreshScan() async {
    try {
      final networks = await _wifiService.getResults();
      await _apiService.uploadScan(networks);
      emit(ScanLoaded(networks));
    } catch (e) {
      emit(ScanError("Failed to fetch scan results: ${e.toString()}"));
    }
  }
}
