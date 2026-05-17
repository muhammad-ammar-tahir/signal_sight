import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../services/api_service.dart';
import '../../../data/models/models.dart';
import '../../../core/utils/algorithms.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class AdvisorState extends Equatable {
  final bool isCalculating;
  final double? bestX;
  final double? bestY;
  final double? coverageScore;
  final List<List<double>> grid;
  final String reasoning;
  final String? error;
  final List<Map<String, dynamic>> walls;

  const AdvisorState({
    this.isCalculating = false,
    this.bestX,
    this.bestY,
    this.coverageScore,
    this.grid = const [],
    this.reasoning = '',
    this.error,
    this.walls = const [],
  });

  bool get hasResult => bestX != null && bestY != null;

  AdvisorState copyWith({
    bool? isCalculating,
    double? bestX,
    double? bestY,
    double? coverageScore,
    List<List<double>>? grid,
    String? reasoning,
    String? error,
    List<Map<String, dynamic>>? walls,
  }) =>
      AdvisorState(
        isCalculating: isCalculating ?? this.isCalculating,
        bestX: bestX ?? this.bestX,
        bestY: bestY ?? this.bestY,
        coverageScore: coverageScore ?? this.coverageScore,
        grid: grid ?? this.grid,
        reasoning: reasoning ?? this.reasoning,
        error: error,
        walls: walls ?? this.walls,
      );

  @override
  List<Object?> get props => [
        isCalculating,
        bestX,
        bestY,
        coverageScore,
        reasoning,
        error,
        walls.length,
      ];
}

// ─── Propagation Model (Offline) ─────────────────────────────────────────────

class _PropagationModel {
  /// Simplified free-space path loss + wall attenuation.
  /// pathLoss = 20*log10(freqMHz) + 10*n*log10(dist) - 28 + wallLoss
  static double calculateRssi({
    required double frequencyMHz,
    required double txPowerDbm,
    required double distanceM,
    required List<Map<String, dynamic>> walls,
    double n = 2.8,
  }) {
    final dist = distanceM < 0.1 ? 0.1 : distanceM;
    final pathLoss = 20 * log(frequencyMHz) / ln10 +
        10 * n * log(dist) / ln10 -
        28;

    double wallLoss = 0;
    for (final wall in walls) {
      final material = wall['material'] as String? ?? 'drywall';
      wallLoss += _attenuation(material);
    }

    return txPowerDbm - pathLoss - wallLoss;
  }

  static double _attenuation(String material) {
    switch (material) {
      case 'concrete':
        return 12.0;
      case 'glass':
        return 2.0;
      case 'drywall':
      default:
        return 3.0;
    }
  }

  /// Counts walls that a ray from (rx,ry) to (tx,ty) crosses.
  static List<Map<String, dynamic>> wallsBetween(
    double tx,
    double ty,
    double rx,
    double ry,
    List<Map<String, dynamic>> walls,
  ) {
    final hit = <Map<String, dynamic>>[];
    for (final wall in walls) {
      final x1 = (wall['x1'] as num).toDouble();
      final y1 = (wall['y1'] as num).toDouble();
      final x2 = (wall['x2'] as num).toDouble();
      final y2 = (wall['y2'] as num).toDouble();
      if (_segmentsIntersect(tx, ty, rx, ry, x1, y1, x2, y2)) {
        hit.add(wall);
      }
    }
    return hit;
  }

  static bool _segmentsIntersect(
    double ax, double ay, double bx, double by,
    double cx, double cy, double dx, double dy,
  ) {
    final d1x = bx - ax, d1y = by - ay;
    final d2x = dx - cx, d2y = dy - cy;
    final cross = d1x * d2y - d1y * d2x;
    if (cross.abs() < 1e-10) return false;
    final t = ((cx - ax) * d2y - (cy - ay) * d2x) / cross;
    final u = ((cx - ax) * d1y - (cy - ay) * d1x) / cross;
    return t >= 0 && t <= 1 && u >= 0 && u <= 1;
  }

  /// Build a coverage grid for given router position.
  static List<List<double>> buildGrid({
    required double routerX,
    required double routerY,
    required double width,
    required double height,
    required List<Map<String, dynamic>> walls,
    int gridSize = 30,
    double frequencyMHz = 2437,
    double txPowerDbm = 20.0,
  }) {
    final grid = List.generate(gridSize, (_) => List.filled(gridSize, 0.0));
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        final rx = width * c / (gridSize - 1);
        final ry = height * r / (gridSize - 1);
        final dist =
            sqrt(pow(routerX - rx, 2) + pow(routerY - ry, 2));
        final penetratedWalls =
            wallsBetween(routerX, routerY, rx, ry, walls);
        grid[r][c] = calculateRssi(
          frequencyMHz: frequencyMHz,
          txPowerDbm: txPowerDbm,
          distanceM: dist,
          walls: penetratedWalls,
        );
      }
    }
    return grid;
  }

  /// Score = % of cells above targetRssi.
  static double coverageScore(
      List<List<double>> grid, double targetRssi) {
    int total = 0, above = 0;
    for (final row in grid) {
      for (final v in row) {
        total++;
        if (v >= targetRssi) above++;
      }
    }
    return total > 0 ? (above / total) * 100 : 0;
  }
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class AdvisorCubit extends Cubit<AdvisorState> {
  final ApiService _api;

  AdvisorCubit(this._api) : super(const AdvisorState());

  // ── Wall management ───────────────────────────────────────────────────────

  void addWall({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    String material = 'drywall',
  }) {
    final updated = List<Map<String, dynamic>>.from(state.walls)
      ..add({'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2, 'material': material});
    emit(state.copyWith(walls: updated));
  }

  void removeWall(int index) {
    final updated = List<Map<String, dynamic>>.from(state.walls);
    if (index >= 0 && index < updated.length) {
      updated.removeAt(index);
      emit(state.copyWith(walls: updated));
    }
  }

  void clearWalls() {
    emit(state.copyWith(walls: []));
  }

  // ── Live coverage prediction (offline ITU + wall model) ───────────────────

  Future<void> predictCoverage({
    required double routerX,
    required double routerY,
    required double width,
    required double height,
    double frequencyMHz = 2437,
    double txPowerDbm = 20.0,
    double targetRssi = -70.0,
  }) async {
    emit(state.copyWith(isCalculating: true, error: null));
    try {
      // Try backend first (non-blocking on error)
      Map<String, dynamic>? backendResult;
      try {
        backendResult = await _api.predictCoverage({
          'router_x': routerX,
          'router_y': routerY,
          'frequency': frequencyMHz.toInt(),
          'tx_power': txPowerDbm,
          'walls': state.walls,
          'width': width,
          'height': height,
          'resolution': 0.5,
        }).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Use offline model below
      }

      List<List<double>> grid;
      double coverage;
      String reasoning;

      if (backendResult != null) {
        grid = _parseGrid(backendResult['grid']);
        coverage = (backendResult['coverage_score'] as num).toDouble();
        reasoning = backendResult['reasoning'] as String? ??
            _buildReasoning(routerX, routerY, coverage, null);
      } else {
        // Offline computation
        grid = _PropagationModel.buildGrid(
          routerX: routerX,
          routerY: routerY,
          width: width,
          height: height,
          walls: state.walls,
          frequencyMHz: frequencyMHz,
          txPowerDbm: txPowerDbm,
        );
        coverage = _PropagationModel.coverageScore(grid, targetRssi);
        reasoning = _buildReasoning(routerX, routerY, coverage, null);
      }

      if (!isClosed) {
        emit(state.copyWith(
          isCalculating: false,
          bestX: routerX,
          bestY: routerY,
          coverageScore: coverage,
          grid: grid,
          reasoning: reasoning,
          error: null,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(isCalculating: false, error: e.toString()));
      }
    }
  }

  // ── Find best spot (brute-force grid search, offline) ─────────────────────

  Future<void> findOptimalPlacement({
    required double width,
    required double height,
    double frequencyMHz = 2437,
    double txPowerDbm = 20.0,
    double targetRssi = -70.0,
    double resolution = 0.5,
  }) async {
    emit(state.copyWith(isCalculating: true, error: null));

    try {
      // Try backend first
      Map<String, dynamic>? backendResult;
      try {
        backendResult = await _api.getOptimalPlacement({
          'width': width,
          'height': height,
          'frequency': frequencyMHz.toInt(),
          'tx_power': txPowerDbm,
          'walls': state.walls,
          'target_rssi': targetRssi,
          'resolution': resolution,
        }).timeout(const Duration(seconds: 10));
      } catch (_) {}

      double bestX, bestY, bestCoverage;
      List<List<double>> bestGrid;
      String reasoning;

      if (backendResult != null) {
        bestX = (backendResult['best_x'] as num).toDouble();
        bestY = (backendResult['best_y'] as num).toDouble();
        bestCoverage = (backendResult['coverage_score'] as num).toDouble();
        bestGrid = _parseGrid(backendResult['grid']);
        reasoning = backendResult['reasoning'] as String? ??
            _buildReasoning(bestX, bestY, bestCoverage,
                state.coverageScore);
      } else {
        // Offline brute-force
        final result = AIRouterPlacement.optimizePlacement(
          minX: 0,
          maxX: width,
          minY: 0,
          maxY: height,
          txPowerDbm: txPowerDbm,
          frequencyMHz: frequencyMHz,
          gridResolutionM: resolution,
          targetRssiDbm: targetRssi,
        );
        bestX = result.x;
        bestY = result.y;
        bestCoverage = result.coveragePercent;

        bestGrid = _PropagationModel.buildGrid(
          routerX: bestX,
          routerY: bestY,
          width: width,
          height: height,
          walls: state.walls,
          frequencyMHz: frequencyMHz,
          txPowerDbm: txPowerDbm,
        );

        reasoning = _buildReasoning(
            bestX, bestY, bestCoverage, state.coverageScore);
      }

      if (!isClosed) {
        emit(state.copyWith(
          isCalculating: false,
          bestX: bestX,
          bestY: bestY,
          coverageScore: bestCoverage,
          grid: bestGrid,
          reasoning: reasoning,
          error: null,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(isCalculating: false, error: e.toString()));
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _buildReasoning(
      double x, double y, double coverage, double? prevCoverage) {
    final xFmt = x.toStringAsFixed(1);
    final yFmt = y.toStringAsFixed(1);
    final covFmt = coverage.toStringAsFixed(1);

    // Find dominant wall material near best position
    String wallHint = '';
    if (state.walls.isNotEmpty) {
      final nearestWall = state.walls.reduce((a, b) {
        final dA = sqrt(pow((a['x1'] as num) + (a['x2'] as num) - 2 * x, 2) +
            pow((a['y1'] as num) + (a['y2'] as num) - 2 * y, 2));
        final dB = sqrt(pow((b['x1'] as num) + (b['x2'] as num) - 2 * x, 2) +
            pow((b['y1'] as num) + (b['y2'] as num) - 2 * y, 2));
        return dA < dB ? a : b;
      });
      final mat = nearestWall['material'] as String? ?? 'wall';
      wallHint = ' Avoid proximity to the $mat segment.';
    }

    if (prevCoverage != null && prevCoverage > 0) {
      final gain = coverage - prevCoverage;
      return 'Optimal spot: ($xFmt m, $yFmt m). '
          'Coverage: $covFmt% (${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB gain).$wallHint';
    }

    return 'Router at ($xFmt m, $yFmt m). '
        'Coverage: $covFmt% of room above −70 dBm.$wallHint';
  }

  List<List<double>> _parseGrid(dynamic raw) {
    if (raw == null) return [];
    return (raw as List<dynamic>).map((row) {
      return (row as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
    }).toList();
  }
}
