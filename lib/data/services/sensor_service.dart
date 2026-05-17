import 'dart:async';
import 'package:flutter/services.dart';

typedef StepCallback = void Function(double x, double y, int count);

/// Simple class to avoid record type issues if Dart version is older.
class SensorPosition {
  final double x;
  final double y;
  final int stepCount;
  SensorPosition({required this.x, required this.y, required this.stepCount});
}

/// Dart-side PDR bridge.
///
/// SensorPlugin.kt maintains all PDR state internally and emits
/// pre-calculated (x, y) on every step.
class SensorService {
  static const EventChannel _sensorChannel =
      EventChannel('com.signalsight/sensors/events');
  static const MethodChannel _methodChannel =
      MethodChannel('com.signalsight/sensors');

  StreamSubscription? _sensorSub;
  StepCallback? onStep;
  bool _active = false;

  double _x = 0.0;
  double _y = 0.0;
  int _stepCount = 0;

  void startPDR({double strideLength = 0.75, StepCallback? stepCallback}) {
    onStep = stepCallback;
    _active = true;
    _x = 0.0;
    _y = 0.0;
    _stepCount = 0;

    // Tell native plugin stride length
    _methodChannel.invokeMethod('setStrideLength', {'strideLength': strideLength});
    _methodChannel.invokeMethod('startTracking');

    _sensorSub = _sensorChannel.receiveBroadcastStream().listen((event) {
      if (!_active) return;
      if (event is! Map) return;

      // Native plugin sends pre-computed (x, y) from its internal PDR.
      final x     = (event['x'] as num?)?.toDouble()         ?? _x;
      final y     = (event['y'] as num?)?.toDouble()         ?? _y;
      final count = (event['stepCount'] as int?)             ?? _stepCount + 1;

      _x = x;
      _y = y;
      _stepCount = count;

      onStep?.call(_x, _y, _stepCount);
    }, onError: (_) {});
  }

  void stopPDR() {
    _active = false;
    _methodChannel.invokeMethod('stopTracking');
    _sensorSub?.cancel();
    _sensorSub = null;
  }

  SensorPosition get currentPosition => SensorPosition(x: _x, y: _y, stepCount: _stepCount);

  void dispose() => stopPDR();
}
