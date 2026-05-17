import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../core/theme/app_theme.dart';

/// Full-featured heatmap painter that draws:
///   1. Dotted grid background
///   2. Optional floor-plan image (faded)
///   3. Start-point cyan pin
///   4. Walking path as a dashed cyan line
///   5. Coloured RSSI dots along the path
///   6. Smooth interpolated heatmap overlay with dynamic scaling and clipping
///   7. Current-position cursor
class HeatmapPainter extends CustomPainter {
  final List<HeatmapPoint> points;
  final List<List<double>> heatmapGrid;
  final double currentX;
  final double currentY;
  final double? startX;
  final double? startY;
  final bool isMapping;
  final bool hasResult;
  final bool clipToWalkingArea;
  final bool useDynamicScale;
  final double minRssi;
  final double maxRssi;
  final List<Point<double>> convexHull;

  HeatmapPainter({
    required this.points,
    required this.heatmapGrid,
    required this.currentX,
    required this.currentY,
    this.startX,
    this.startY,
    required this.isMapping,
    required this.hasResult,
    required this.clipToWalkingArea,
    required this.useDynamicScale,
    required this.minRssi,
    required this.maxRssi,
    required this.convexHull,
  });

  // ── Coordinate mapping helpers ────────────────────────────────────────────

  ({double minX, double maxX, double minY, double maxY}) _bounds() {
    if (points.isEmpty) {
      return (minX: 0, maxX: 1, minY: 0, maxY: 1);
    }
    final xs = points.map((p) => p.x).toList();
    final ys = points.map((p) => p.y).toList();
    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);
    return (
      minX: minX,
      maxX: maxX == minX ? minX + 1 : maxX,
      minY: minY,
      maxY: maxY == minY ? minY + 1 : maxY,
    );
  }

  Offset _toCanvas(double x, double y, Size size,
      {double pad = 40}) {
    final b = _bounds();
    final rX = b.maxX - b.minX;
    final rY = b.maxY - b.minY;
    return Offset(
      pad + (x - b.minX) / rX * (size.width - pad * 2),
      pad + (y - b.minY) / rY * (size.height - pad * 2),
    );
  }

  Color _getColor(double rssi) {
    // Green = -50dBm, Red = -90dBm
    final clampedRssi = rssi.clamp(-90.0, -50.0);
    final ratio = (clampedRssi - -90.0) / (-50.0 - -90.0);
    
    // 0.0 (weak/red) = Hue 0
    // 1.0 (strong/green) = Hue 120
    final hue = ratio * 120.0;
    return HSLColor.fromAHSL(1.0, hue, 0.9, 0.5).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawDotGrid(canvas, size);
    
    if (hasResult && heatmapGrid.isNotEmpty) {
      canvas.save();
      if (clipToWalkingArea && convexHull.isNotEmpty) {
        final path = Path();
        final first = _toCanvas(convexHull.first.x, convexHull.first.y, size);
        path.moveTo(first.dx, first.dy);
        for (var p in convexHull.skip(1)) {
          final mapped = _toCanvas(p.x, p.y, size);
          path.lineTo(mapped.dx, mapped.dy);
        }
        path.close();
        canvas.clipPath(path);
      }
      _drawHeatmap(canvas, size);
      canvas.restore();
    }
    
    if (startX != null && startY != null) {
      _drawStartPin(canvas, size);
    }
    if (points.isNotEmpty) {
      _drawPath(canvas, size);
      _drawDots(canvas, size);
    }
    if (isMapping && points.isNotEmpty) {
      _drawCursor(canvas, size);
    }
  }

  void _drawDotGrid(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.cardBorder;
    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  void _drawHeatmap(Canvas canvas, Size size) {
    final rows = heatmapGrid.length;
    final cols = heatmapGrid[0].length;
    const pad = 40.0;
    final drawWidth = size.width - pad * 2;
    final drawHeight = size.height - pad * 2;
    final cw = drawWidth / cols;
    final ch = drawHeight / rows;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final v = heatmapGrid[r][c];
        final rect = Rect.fromLTWH(pad + c * cw, pad + r * ch, cw + 0.5, ch + 0.5);
        if (v.isNaN || v.isInfinite) {
          // Low confidence crosshatch
          final p1 = Paint()..color = AppColors.cardBorder.withOpacity(0.3)..strokeWidth = 1.0;
          canvas.drawLine(rect.topLeft, rect.bottomRight, p1);
          canvas.drawLine(rect.topRight, rect.bottomLeft, p1);
          continue;
        }
        final color = _getColor(v).withOpacity(0.62);
        canvas.drawRect(rect, Paint()..color = color);
      }
    }
  }

  void _drawStartPin(Canvas canvas, Size size) {
    final o = _toCanvas(startX!, startY!, size);
    canvas.drawCircle(
        o, 14, Paint()..color = AppColors.cyan.withOpacity(0.18));
    canvas.drawCircle(o, 8, Paint()..color = AppColors.cyan);
    // pin line
    canvas.drawLine(
      o,
      Offset(o.dx, o.dy - 22),
      Paint()
        ..color = AppColors.cyan
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawPath(Canvas canvas, Size size) {
    final pathPaint = Paint()
      ..color = AppColors.cyan.withOpacity(0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final first = _toCanvas(points.first.x, points.first.y, size);
    path.moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final o = _toCanvas(p.x, p.y, size);
      path.lineTo(o.dx, o.dy);
    }

    // Dashed
    const dashLen = 8.0, gapLen = 5.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(
            metric.extractPath(dist, dist + dashLen), pathPaint);
        dist += dashLen + gapLen;
      }
    }
  }

  void _drawDots(Canvas canvas, Size size) {
    for (final p in points) {
      final o = _toCanvas(p.x, p.y, size);
      canvas.drawCircle(
        o,
        5.5,
        Paint()
          ..color = _getColor(p.rssi).withOpacity(0.88),
      );
    }
  }

  void _drawCursor(Canvas canvas, Size size) {
    final o = _toCanvas(currentX, currentY, size);
    canvas.drawCircle(
        o, 16, Paint()..color = AppColors.cyan.withOpacity(0.18));
    canvas.drawCircle(
        o, 9, Paint()..color = AppColors.cyan.withOpacity(0.9));
    canvas.drawCircle(
      o,
      9,
      Paint()
        ..color = AppColors.cyan
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(HeatmapPainter old) =>
      old.points != points ||
      old.currentX != currentX ||
      old.currentY != currentY ||
      old.hasResult != hasResult ||
      old.isMapping != isMapping ||
      old.clipToWalkingArea != clipToWalkingArea ||
      old.useDynamicScale != useDynamicScale ||
      old.minRssi != minRssi ||
      old.maxRssi != maxRssi;
}
