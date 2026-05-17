import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart'; // compute()
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/models.dart';
import '../../../data/services/wifi_scan_service.dart';
import '../../../data/services/sensor_service.dart';
import '../../../data/services/database_service.dart';

// ─── Isolate payload ─────────────────────────────────────────────────────────

class _GridPayload {
  final List<Map<String, double>> pts; // [{x, y, rssi}]
  final int gridSize;
  const _GridPayload(this.pts, this.gridSize);
}

class _Pt {
  final double x;
  final double y;
  final double rssi;
  const _Pt(this.x, this.y, this.rssi);
}

class _GridResult {
  final List<List<double>> grid;
  final List<Map<String, double>> hull; // [{x, y}]
  final double area;
  final double minRssi;
  final double maxRssi;
  const _GridResult(this.grid, this.hull, this.area, this.minRssi, this.maxRssi);
}

/// Top-level function (required for compute())
_GridResult _runGridInIsolate(_GridPayload payload) {
  final pts = payload.pts
      .map((m) => _Pt(m['x']!, m['y']!, m['rssi']!))
      .toList();

  if (pts.isEmpty) return const _GridResult([], [], 0, -90, -50);

  final gridSize = payload.gridSize;

  double minR = 0, maxR = -100;
  for (final p in pts) {
    if (p.rssi < minR) minR = p.rssi;
    if (p.rssi > maxR) maxR = p.rssi;
  }

  // ── Bilinear grid (Laplacian interpolation) ────────────────────────
  final xs = pts.map((p) => p.x).toList();
  final ys = pts.map((p) => p.y).toList();
  final minX = xs.reduce(min), maxX = xs.reduce(max);
  final minY = ys.reduce(min), maxY = ys.reduce(max);
  final rX = (maxX - minX).abs().clamp(1e-9, double.infinity);
  final rY = (maxY - minY).abs().clamp(1e-9, double.infinity);

  final grid = List.generate(gridSize, (_) => List<double>.filled(gridSize, double.nan));

  for (final p in pts) {
    int c = ((p.x - minX) / rX * (gridSize - 1)).round().clamp(0, gridSize - 1);
    int r = ((p.y - minY) / rY * (gridSize - 1)).round().clamp(0, gridSize - 1);
    grid[r][c] = grid[r][c].isNaN ? p.rssi : (grid[r][c] + p.rssi) / 2.0;
  }

  // Laplacian fill for empty cells (20 iterations)
  for (int iter = 0; iter < 20; iter++) {
    final ng = List.generate(gridSize, (r) => List<double>.from(grid[r]));
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (grid[r][c].isNaN) {
          double sum = 0; int cnt = 0;
          if (r > 0 && !grid[r-1][c].isNaN) { sum += grid[r-1][c]; cnt++; }
          if (r < gridSize-1 && !grid[r+1][c].isNaN) { sum += grid[r+1][c]; cnt++; }
          if (c > 0 && !grid[r][c-1].isNaN) { sum += grid[r][c-1]; cnt++; }
          if (c < gridSize-1 && !grid[r][c+1].isNaN) { sum += grid[r][c+1]; cnt++; }
          if (cnt > 0) ng[r][c] = sum / cnt;
        }
      }
    }
    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) grid[r][c] = ng[r][c];
    }
  }

  // 3×3 Gaussian blur
  final blurred = List.generate(gridSize, (_) => List<double>.filled(gridSize, double.nan));
  const kernel = [[1/16, 2/16, 1/16],[2/16, 4/16, 2/16],[1/16, 2/16, 1/16]];
  for (int r = 0; r < gridSize; r++) {
    for (int c = 0; c < gridSize; c++) {
      if (grid[r][c].isNaN) { blurred[r][c] = double.nan; continue; }
      double s = 0, w = 0;
      for (int kr = -1; kr <= 1; kr++) {
        for (int kc = -1; kc <= 1; kc++) {
          final nr = r + kr; final nc = c + kc;
          if (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize && !grid[nr][nc].isNaN) {
            final wt = kernel[kr+1][kc+1];
            s += grid[nr][nc] * wt; w += wt;
          }
        }
      }
      blurred[r][c] = w > 0 ? s / w : grid[r][c];
    }
  }

  // ── Convex hull ────────────────────────────────────────────────────
  double cross(_Pt o, _Pt a, _Pt b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  List<Map<String, double>> hull = [];
  if (pts.length >= 3) {
    final sorted = List<_Pt>.from(pts)
      ..sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    final lower = <_Pt>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length-2], lower.last, p) <= 0) lower.removeLast();
      lower.add(p);
    }
    final upper = <_Pt>[];
    for (var i = sorted.length - 1; i >= 0; i--) {
      final p = sorted[i];
      while (upper.length >= 2 && cross(upper[upper.length-2], upper.last, p) <= 0) upper.removeLast();
      upper.add(p);
    }
    upper.removeLast(); lower.removeLast();
    hull = [...lower, ...upper].map((p) => {'x': p.x, 'y': p.y}).toList();
  }

  // ── Bounding-box area ──────────────────────────────────────────────
  final area = (xs.reduce(max) - xs.reduce(min)).abs() *
               (ys.reduce(max) - ys.reduce(min)).abs();

  return _GridResult(blurred, hull, area, minR, maxR);
}

// ─── State ────────────────────────────────────────────────────────────────────

class HeatmapState extends Equatable {
  final List<HeatmapPoint> points;
  final bool isMapping;
  final int stepCount;
  final double currentX;
  final double currentY;
  final double? startX;
  final double? startY;
  final String? targetBssid;
  final List<List<double>> heatmapGrid;
  final bool hasResult;
  final int? sessionId;
  final String? errorMessage;
  final double areaSqM;
  final double calibrationRssiAtOneMeter;
  final DateTime? calibrationTimestamp;
  final double idwPower;
  final bool clipToWalkingArea;
  final bool useDynamicScale;
  final double minRssi;
  final double maxRssi;
  final List<Point<double>> convexHull;
  final bool isAnalyzing;

  const HeatmapState({
    this.points = const [],
    this.isMapping = false,
    this.stepCount = 0,
    this.currentX = 0,
    this.currentY = 0,
    this.startX,
    this.startY,
    this.targetBssid,
    this.heatmapGrid = const [],
    this.hasResult = false,
    this.sessionId,
    this.errorMessage,
    this.areaSqM = 0,
    this.calibrationRssiAtOneMeter = -30.0,
    this.calibrationTimestamp,
    this.idwPower = 2.0,
    this.clipToWalkingArea = true,
    this.useDynamicScale = true,
    this.minRssi = -90.0,
    this.maxRssi = -50.0,
    this.convexHull = const [],
    this.isAnalyzing = false,
  });

  HeatmapState copyWith({
    List<HeatmapPoint>? points,
    bool? isMapping,
    bool? isAnalyzing,
    int? stepCount,
    double? currentX,
    double? currentY,
    double? startX,
    double? startY,
    String? targetBssid,
    List<List<double>>? heatmapGrid,
    bool? hasResult,
    int? sessionId,
    String? errorMessage,
    double? areaSqM,
    double? calibrationRssiAtOneMeter,
    DateTime? calibrationTimestamp,
    double? idwPower,
    bool? clipToWalkingArea,
    bool? useDynamicScale,
    double? minRssi,
    double? maxRssi,
    List<Point<double>>? convexHull,
    bool clearError = false,
  }) =>
      HeatmapState(
        points: points ?? this.points,
        isMapping: isMapping ?? this.isMapping,
        isAnalyzing: isAnalyzing ?? this.isAnalyzing,
        stepCount: stepCount ?? this.stepCount,
        currentX: currentX ?? this.currentX,
        currentY: currentY ?? this.currentY,
        startX: startX ?? this.startX,
        startY: startY ?? this.startY,
        targetBssid: targetBssid ?? this.targetBssid,
        heatmapGrid: heatmapGrid ?? this.heatmapGrid,
        hasResult: hasResult ?? this.hasResult,
        sessionId: sessionId ?? this.sessionId,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        areaSqM: areaSqM ?? this.areaSqM,
        calibrationRssiAtOneMeter: calibrationRssiAtOneMeter ?? this.calibrationRssiAtOneMeter,
        calibrationTimestamp: calibrationTimestamp ?? this.calibrationTimestamp,
        idwPower: idwPower ?? this.idwPower,
        clipToWalkingArea: clipToWalkingArea ?? this.clipToWalkingArea,
        useDynamicScale: useDynamicScale ?? this.useDynamicScale,
        minRssi: minRssi ?? this.minRssi,
        maxRssi: maxRssi ?? this.maxRssi,
        convexHull: convexHull ?? this.convexHull,
      );

  @override
  List<Object?> get props => [
        points, isMapping, isAnalyzing, stepCount, currentX, currentY, startX, startY,
        targetBssid, heatmapGrid, hasResult, errorMessage, areaSqM,
        calibrationRssiAtOneMeter, calibrationTimestamp, idwPower,
        clipToWalkingArea, useDynamicScale, minRssi, maxRssi, convexHull,
      ];
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class HeatmapCubit extends Cubit<HeatmapState> {
  final SensorService _sensors;
  final WifiScanService _wifi;
  final DatabaseService _db;

  double _latestRssi = -90.0;
  
  /// Minimum steps required to produce a heatmap
  static const int _minPoints = 10;
  static const double _strideM = 0.75;
  
  // Buffering and throttling
  List<HeatmapPoint> _pointBuffer = [];
  Timer? _throttleTimer;
  bool _pendingEmit = false;

  HeatmapCubit(this._sensors, this._wifi, this._db) : super(const HeatmapState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final calRssi = prefs.getDouble('calibrationRssiAtOneMeter') ?? -30.0;
      final tsStr = prefs.getString('calibrationTimestamp');
      final idw = prefs.getDouble('idwPower') ?? 2.0;
      final clip = prefs.getBool('clipToWalkingArea') ?? true;
      final dyn = prefs.getBool('useDynamicScale') ?? true;
      
      emit(state.copyWith(
        calibrationRssiAtOneMeter: calRssi,
        calibrationTimestamp: tsStr != null ? DateTime.tryParse(tsStr) : null,
        idwPower: idw,
        clipToWalkingArea: clip,
        useDynamicScale: dyn,
      ));
    } catch (_) {}
  }
  
  void updateSettings({double? idwPower, bool? clipToWalkingArea, bool? useDynamicScale}) async {
    final prefs = await SharedPreferences.getInstance();
    if (idwPower != null) {
      prefs.setDouble('idwPower', idwPower);
    }
    if (clipToWalkingArea != null) {
      prefs.setBool('clipToWalkingArea', clipToWalkingArea);
    }
    if (useDynamicScale != null) {
      prefs.setBool('useDynamicScale', useDynamicScale);
    }
    emit(state.copyWith(
      idwPower: idwPower,
      clipToWalkingArea: clipToWalkingArea,
      useDynamicScale: useDynamicScale,
    ));
    if (state.hasResult && state.points.isNotEmpty) {
      // Re-run analysis with new settings
      _analyzeData();
    }
  }
  
  Future<void> calibrateReference() async {
    if (state.targetBssid == null) {
      emit(state.copyWith(errorMessage: 'Select a network to calibrate.'));
      return;
    }
    try {
      final networks = await _wifi.getResults();
      final target = networks.where((n) => n.bssid == state.targetBssid).toList();
      if (target.isNotEmpty) {
        final rssi = target.first.rssi.toDouble();
        final prefs = await SharedPreferences.getInstance();
        prefs.setDouble('calibrationRssiAtOneMeter', rssi);
        final ts = DateTime.now();
        prefs.setString('calibrationTimestamp', ts.toIso8601String());
        emit(state.copyWith(
          calibrationRssiAtOneMeter: rssi,
          calibrationTimestamp: ts,
          clearError: true,
        ));
      } else {
        emit(state.copyWith(errorMessage: 'Target network not in range for calibration.'));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Calibration failed: $e'));
    }
  }
  
  Future<void> resetCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('calibrationRssiAtOneMeter');
    prefs.remove('calibrationTimestamp');
    emit(state.copyWith(
      calibrationRssiAtOneMeter: -30.0,
      calibrationTimestamp: null,
    ));
   }
  
  void resetHeading() {
    // Sensor plugin recalibrates compass by resetting the current heading baseline
    MethodChannel('com.signalsight/sensors').invokeMethod('calibrateCompass');
  }

  void setTarget(String bssid) => emit(state.copyWith(targetBssid: bssid, clearError: true));
  void setStartPoint(double x, double y) => emit(state.copyWith(startX: x, startY: y, clearError: true));

  Future<void> startMapping() async {
    if (state.targetBssid == null) {
      emit(state.copyWith(errorMessage: 'Select a target network before mapping.'));
      return;
    }

    int sessionId;
    try {
      sessionId = await _db.createHeatmapSession(
        targetBssid: state.targetBssid!,
        name: 'Session ${DateTime.now().toIso8601String().substring(0, 16)}',
      );
    } catch (_) {
      sessionId = DateTime.now().millisecondsSinceEpoch;
    }

    _latestRssi = -90.0;
    _pointBuffer = [];

    emit(state.copyWith(
      isMapping: true,
      hasResult: false,
      points: [],
      stepCount: 0,
      currentX: state.startX ?? 0,
      currentY: state.startY ?? 0,
      heatmapGrid: [],
      sessionId: sessionId,
      clearError: true,
    ));

    _throttleTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_pendingEmit && !isClosed) {
        emit(state.copyWith(
          points: List.from(_pointBuffer),
          currentX: _pointBuffer.isNotEmpty ? _pointBuffer.last.x : state.currentX,
          currentY: _pointBuffer.isNotEmpty ? _pointBuffer.last.y : state.currentY,
          stepCount: _pointBuffer.length,
        ));
        _pendingEmit = false;
      }
    });

    _sensors.startPDR(
      strideLength: _strideM,
      stepCallback: (x, y, count) async {
        if (isClosed) return;

        try {
          // Fetch current RSSI of the target BSSID on each step
          final networks = await _wifi.getResults();
          final target = networks.where((n) => n.bssid == state.targetBssid).toList();
          if (target.isNotEmpty) {
            _latestRssi = target.first.rssi.toDouble();
          }
        } catch (_) {}

        double currentRssi = _latestRssi.clamp(-100.0, -10.0);

        final point = HeatmapPoint(
          x: x,
          y: y,
          rssi: currentRssi,
          timestamp: DateTime.now(),
        );

        if (state.sessionId != null) {
          try {
            await _db.saveHeatmapPoint(state.sessionId!, point);
            await _db.updateSessionStepCount(state.sessionId!, count);
          } catch (_) {}
        }
        
        _pointBuffer.add(point);
        _pendingEmit = true;
      },
    );
  }

  Future<void> stopAndAnalyze() async {
    _sensors.stopPDR();
    _throttleTimer?.cancel();
    _throttleTimer = null;

    // Flush any pending point
    if (_pendingEmit) {
      emit(state.copyWith(
        points: List.from(_pointBuffer),
        currentX: _pointBuffer.isNotEmpty ? _pointBuffer.last.x : state.currentX,
        currentY: _pointBuffer.isNotEmpty ? _pointBuffer.last.y : state.currentY,
        stepCount: _pointBuffer.length,
      ));
      _pendingEmit = false;
    }

    if (state.points.length < _minPoints) {
      emit(state.copyWith(
        isMapping: false,
        hasResult: false,
        errorMessage:
            'Only ${state.points.length} point(s) collected. '
            'Walk more to generate a map (need at least $_minPoints steps).',
      ));
      return;
    }

    _applyLoopClosure();
    await _analyzeData();
  }
  
  void _applyLoopClosure() {
    final pts = List<HeatmapPoint>.from(state.points);
    if (pts.length > 20) {
      final start = pts.first;
      final end = pts.last;
      final dist = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2));
      
      // If ended within 2 meters of start, distribute the error
      if (dist < 2.0 && dist > 0.1) {
        final errX = start.x - end.x;
        final errY = start.y - end.y;
        final totalSteps = pts.length;
        
        for (int i = 0; i < totalSteps; i++) {
          final factor = i / (totalSteps - 1);
          pts[i] = HeatmapPoint(
            x: pts[i].x + errX * factor,
            y: pts[i].y + errY * factor,
            rssi: pts[i].rssi,
            timestamp: pts[i].timestamp,
          );
        }
        _pointBuffer = pts;
        emit(state.copyWith(points: pts));
      }
    }
  }

  Future<void> _analyzeData() async {
    List<HeatmapPoint> pts = List.from(state.points);

    // Cap to 2000 points to avoid OOM
    if (pts.length > 2000) {
      final step = (pts.length / 2000).ceil();
      pts = [for (var i = 0; i < pts.length; i += step) pts[i]];
    }

    // Signal UI to show "Analyzing..." spinner
    emit(state.copyWith(isMapping: false, isAnalyzing: true));

    // Build serializable payload for the isolate
    final payload = _GridPayload(
      pts.map((p) => {'x': p.x, 'y': p.y, 'rssi': p.rssi}).toList(),
      50, // 50×50 grid
    );

    try {
      final result = await compute(_runGridInIsolate, payload);

      if (isClosed) return;

      // Convert hull maps back to Point<double>
      final hull = result.hull
          .map((m) => Point<double>(m['x']!, m['y']!))
          .toList();

      emit(state.copyWith(
        isAnalyzing: false,
        heatmapGrid: result.grid,
        convexHull: hull,
        minRssi: result.minRssi,
        maxRssi: result.maxRssi,
        hasResult: true,
        areaSqM: result.area,
        points: pts,
        clearError: true,
      ));
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          isAnalyzing: false,
          errorMessage: 'Analysis failed: $e',
        ));
      }
    }

    _pointBuffer = [];
  }

  void clear() {
    _sensors.stopPDR();
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _latestRssi = -90.0;
    _pointBuffer = [];
    emit(state.copyWith(
      points: const [],
      isMapping: false,
      hasResult: false,
      heatmapGrid: const [],
      stepCount: 0,
      errorMessage: null,
      convexHull: const [],
      clearError: true,
    ));
  }

  @override
  Future<void> close() {
    _sensors.dispose();
    _throttleTimer?.cancel();
    return super.close();
  }
}
