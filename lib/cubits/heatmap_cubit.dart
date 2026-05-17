import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

abstract class HeatmapState extends Equatable {
  const HeatmapState();
  @override
  List<Object?> get props => [];
}

class HeatmapInitial extends HeatmapState {}

class HeatmapMapping extends HeatmapState {
  final List<Map<String, double>> points;
  const HeatmapMapping(this.points);
  @override
  List<Object?> get props => [points];
}

class HeatmapGenerated extends HeatmapState {
  final Uint8List heatmapImage;
  const HeatmapGenerated(this.heatmapImage);
  @override
  List<Object?> get props => [heatmapImage];
}

class HeatmapError extends HeatmapState {
  final String message;
  const HeatmapError(this.message);
  @override
  List<Object?> get props => [message];
}

class HeatmapCubit extends Cubit<HeatmapState> {
  HeatmapCubit() : super(HeatmapInitial());

  void startMapping() {
    emit(const HeatmapMapping([]));
  }

  void addPoint(double x, double y, double rssi) {
    if (state is HeatmapMapping) {
      final currentPoints = List<Map<String, double>>.from((state as HeatmapMapping).points);
      currentPoints.add({'x': x, 'y': y, 'rssi': rssi});
      emit(HeatmapMapping(currentPoints));
    }
  }

  void stopMapping() {
    // End mapping state
    generateHeatmap();
  }

  void generateHeatmap() {
    // Generate empty/dummy image for now
    emit(HeatmapGenerated(Uint8List(0)));
  }
}
