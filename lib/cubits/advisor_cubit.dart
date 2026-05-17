import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../services/api_service.dart';

abstract class AdvisorState extends Equatable {
  const AdvisorState();
  @override
  List<Object?> get props => [];
}

class AdvisorInitial extends AdvisorState {}

class AdvisorCalculating extends AdvisorState {}

class AdvisorResult extends AdvisorState {
  final Map<String, dynamic> optimalPosition;
  final double coverageScore;
  final List<List<double>> grid;
  
  const AdvisorResult(this.optimalPosition, this.coverageScore, this.grid);
  
  @override
  List<Object?> get props => [optimalPosition, coverageScore, grid];
}

class AdvisorError extends AdvisorState {
  final String message;
  const AdvisorError(this.message);
  @override
  List<Object?> get props => [message];
}

class AdvisorCubit extends Cubit<AdvisorState> {
  final ApiService _apiService;
  final List<Map<String, dynamic>> _walls = [];

  AdvisorCubit(this._apiService) : super(AdvisorInitial());

  void addWall(Map<String, dynamic> wall) {
    _walls.add(wall);
    // Might trigger recalculation if needed
  }

  void removeWall(int index) {
    if (index >= 0 && index < _walls.length) {
      _walls.removeAt(index);
    }
  }

  Future<void> findOptimalPlacement(double width, double height) async {
    emit(AdvisorCalculating());
    try {
      final result = await _apiService.getOptimalPlacement({
        'width': width,
        'height': height,
        'frequency': 2412,
        'tx_power': -30.0,
        'walls': _walls,
        'target_rssi': -70.0,
        'resolution': 0.5,
      });
      
      final grid = (result['grid'] as List<dynamic>)
          .map((row) => (row as List<dynamic>).map((val) => val as double).toList())
          .toList();
          
      emit(AdvisorResult(
        {'x': result['best_x'], 'y': result['best_y']},
        result['coverage_score'],
        grid
      ));
    } catch (e) {
      emit(AdvisorError(e.toString()));
    }
  }
}
