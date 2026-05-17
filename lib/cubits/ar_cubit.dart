import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

abstract class ARState extends Equatable {
  const ARState();
  @override
  List<Object?> get props => [];
}

class ARInitial extends ARState {}

class ARTracking extends ARState {
  final Map<String, double> routerPosition;
  final double signalStrength;
  
  const ARTracking(this.routerPosition, this.signalStrength);
  
  @override
  List<Object?> get props => [routerPosition, signalStrength];
}

class ARError extends ARState {
  final String message;
  const ARError(this.message);
  @override
  List<Object?> get props => [message];
}

class ARCubit extends Cubit<ARState> {
  ARCubit() : super(ARInitial());

  void startARSession() {
    emit(const ARTracking({'x': 0, 'y': 0, 'z': 0}, -90.0));
  }

  void stopARSession() {
    emit(ARInitial());
  }

  void calibrateReference() {
    if (state is ARTracking) {
      emit(ARTracking({'x': 0, 'y': 0, 'z': 0}, (state as ARTracking).signalStrength));
    }
  }
}
