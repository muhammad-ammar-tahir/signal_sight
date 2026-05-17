import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';

abstract class DevicesState extends Equatable {
  const DevicesState();
  @override
  List<Object?> get props => [];
}

class DevicesInitial extends DevicesState {}

class DevicesLoading extends DevicesState {}

class DevicesLoaded extends DevicesState {
  final List<NetworkDevice> devices;
  const DevicesLoaded(this.devices);
  @override
  List<Object?> get props => [devices];
}

class NewDeviceAlert extends DevicesState {
  final NetworkDevice device;
  const NewDeviceAlert(this.device);
  @override
  List<Object?> get props => [device];
}

class DevicesError extends DevicesState {
  final String message;
  const DevicesError(this.message);
  @override
  List<Object?> get props => [message];
}

class DevicesCubit extends Cubit<DevicesState> {
  final ApiService _apiService;

  DevicesCubit(this._apiService) : super(DevicesInitial());

  Future<void> scanNetwork() async {
    emit(DevicesLoading());
    try {
      final devices = await _apiService.getDevices();
      emit(DevicesLoaded(devices));
    } catch (e) {
      emit(DevicesError(e.toString()));
    }
  }

  Future<void> registerDevice(NetworkDevice device) async {
    try {
      await _apiService.registerDevice(device);
      scanNetwork();
    } catch (e) {
      emit(DevicesError(e.toString()));
    }
  }

  void markKnown(NetworkDevice device) {
    final updated = device.copyWith(isNew: false);
    registerDevice(updated);
  }
}
