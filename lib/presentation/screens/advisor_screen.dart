import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../blocs/advisor/advisor_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import 'dart:math';

class AdvisorScreen extends StatefulWidget {
  const AdvisorScreen({super.key});
  @override
  State<AdvisorScreen> createState() => _AdvisorScreenState();
}

class _AdvisorScreenState extends State<AdvisorScreen> {
  Offset? _dragStart;
  Offset? _dragEnd;
  bool _draggingRouter = false;

  double _routerX = 5.0;
  double _routerY = 5.0;
  final double _roomWidth = 10.0;
  final double _roomHeight = 10.0;

  final List<String> _materials = ['drywall', 'concrete', 'glass'];
  int _matIdx = 0;

  // Canvas key to get render box dimensions
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _predict());
  }

  void _predict() {
    context.read<AdvisorCubit>().predictCoverage(
          routerX: _routerX,
          routerY: _routerY,
          width: _roomWidth,
          height: _roomHeight,
        );
  }

  Size _canvasSize() {
    final box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) return box.size;
    final screen = MediaQuery.of(context).size;
    return Size(screen.width, screen.height * 0.5);
  }

  Offset _toRelative(Offset local) {
    final size = _canvasSize();
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdvisorCubit, AdvisorState>(
      builder: (context, state) {
        final score = state.coverageScore ?? 0.0;
        final coverageColor = score >= 70
            ? AppColors.emerald
            : score >= 40
                ? AppColors.amber
                : AppColors.rose;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('AI Placement Advisor'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded),
                color: AppColors.rose,
                tooltip: 'Clear walls',
                onPressed: () {
                  context.read<AdvisorCubit>().clearWalls();
                  _predict();
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Coverage score banner
              _CoverageBanner(score: score, color: coverageColor),

              // Wall material selector
              _MaterialSelector(
                materials: _materials,
                selectedIdx: _matIdx,
                onSelect: (i) => setState(() => _matIdx = i),
              ),

              // Drawing canvas
              Expanded(
                child: GestureDetector(
                  onPanStart: (d) {
                    final rel = _toRelative(d.localPosition);
                    final rp =
                        Offset(_routerX / _roomWidth, _routerY / _roomHeight);
                    final dist = (rel - rp).distance;
                    if (dist < 0.1) {
                      setState(() => _draggingRouter = true);
                    } else {
                      setState(() {
                        _dragStart = d.localPosition;
                        _dragEnd = null;
                      });
                    }
                  },
                  onPanUpdate: (d) {
                    if (_draggingRouter) {
                      final rel = _toRelative(d.localPosition);
                      setState(() {
                        _routerX = (rel.dx * _roomWidth).clamp(0.0, _roomWidth);
                        _routerY =
                            (rel.dy * _roomHeight).clamp(0.0, _roomHeight);
                      });
                    } else {
                      setState(() => _dragEnd = d.localPosition);
                    }
                  },
                  onPanEnd: (_) {
                    if (_draggingRouter) {
                      setState(() => _draggingRouter = false);
                      _predict();
                    } else if (_dragStart != null && _dragEnd != null) {
                      final size = _canvasSize();
                      context.read<AdvisorCubit>().addWall(
                            x1: _dragStart!.dx / size.width * _roomWidth,
                            y1: _dragStart!.dy / size.height * _roomHeight,
                            x2: _dragEnd!.dx / size.width * _roomWidth,
                            y2: _dragEnd!.dy / size.height * _roomHeight,
                            material: _materials[_matIdx],
                          );
                      setState(() {
                        _dragStart = null;
                        _dragEnd = null;
                      });
                      _predict();
                    }
                  },
                  child: ClipRect(
                    child: CustomPaint(
                      key: _canvasKey,
                      painter: _AdvisorPainter(
                        state: state,
                        dragStart: _dragStart,
                        dragEnd: _dragEnd,
                        roomWidth: _roomWidth,
                        roomHeight: _roomHeight,
                        routerX: _routerX,
                        routerY: _routerY,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),

              // Bottom controls
              _AdvisorControls(
                state: state,
                onFindBest: () async {
                  await context.read<AdvisorCubit>().findOptimalPlacement(
                        width: _roomWidth,
                        height: _roomHeight,
                      );
                  // Animate router to best spot
                  final s = context.read<AdvisorCubit>().state;
                  if (s.bestX != null && s.bestY != null) {
                    setState(() {
                      _routerX = s.bestX!;
                      _routerY = s.bestY!;
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Coverage Banner ──────────────────────────────────────────────────────────

class _CoverageBanner extends StatelessWidget {
  final double score;
  final Color color;
  const _CoverageBanner({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: AppColors.card,
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: CircularProgressIndicator(
                  value: score / 100,
                  backgroundColor: AppColors.cardBorder,
                  color: color,
                  strokeWidth: 5,
                ),
              ),
              Text(
                '${score.toInt()}%',
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coverage Score',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 3),
                Text(
                  score >= 70
                      ? 'Excellent placement'
                      : score >= 40
                          ? 'Move router to improve'
                          : 'Poor coverage – reposition router',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Material Selector ────────────────────────────────────────────────────────

class _MaterialSelector extends StatelessWidget {
  final List<String> materials;
  final int selectedIdx;
  final ValueChanged<int> onSelect;
  const _MaterialSelector(
      {required this.materials,
      required this.selectedIdx,
      required this.onSelect});

  Color _color(String m) => m == 'concrete'
      ? AppColors.rose
      : m == 'glass'
          ? AppColors.cyan
          : AppColors.amber;
  IconData _icon(String m) => m == 'concrete'
      ? Icons.foundation_rounded
      : m == 'glass'
          ? Icons.window_rounded
          : Icons.holiday_village_rounded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.card,
      child: Row(
        children: [
          const Icon(Icons.draw_rounded, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 8),
          const Text('Wall:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: materials
                    .asMap()
                    .entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => onSelect(e.key),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: e.key == selectedIdx
                                    ? _color(e.value).withOpacity(0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: e.key == selectedIdx
                                      ? _color(e.value)
                                      : AppColors.cardBorder,
                                  width: e.key == selectedIdx ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _icon(e.value),
                                    color: e.key == selectedIdx
                                        ? _color(e.value)
                                        : AppColors.textMuted,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    e.value,
                                    style: TextStyle(
                                      color: e.key == selectedIdx
                                          ? _color(e.value)
                                          : AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Controls ──────────────────────────────────────────────────────────

class _AdvisorControls extends StatelessWidget {
  final AdvisorState state;
  final VoidCallback onFindBest;
  const _AdvisorControls({required this.state, required this.onFindBest});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drag to draw walls · Drag router ⊙ to move',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${state.walls.length} wall(s) drawn',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              state.isCalculating
                  ? const CircularProgressIndicator(
                      color: AppColors.purple, strokeWidth: 3)
                  : GradientButton(
                      label: 'Find Best Spot',
                      icon: Icons.star_rounded,
                      startColor: AppColors.purple,
                      endColor: const Color(0xFF7C3AED),
                      onPressed: onFindBest,
                    ),
            ],
          ),
          if (state.reasoning.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cyanDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cyanGlow),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_rounded,
                      color: AppColors.cyan, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.reasoning,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Text(
              '⚠ ${state.error}',
              style: const TextStyle(color: AppColors.rose, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Canvas Painter ───────────────────────────────────────────────────────────

class _AdvisorPainter extends CustomPainter {
  final AdvisorState state;
  final Offset? dragStart, dragEnd;
  final double roomWidth, roomHeight;
  final double routerX, routerY;

  _AdvisorPainter({
    required this.state,
    this.dragStart,
    this.dragEnd,
    required this.roomWidth,
    required this.roomHeight,
    required this.routerX,
    required this.routerY,
  });

  Offset _toCanvas(double x, double y, Size size) =>
      Offset(x / roomWidth * size.width, y / roomHeight * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final gridPaint = Paint()..color = AppColors.cardBorder;
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Heatmap coverage grid
    if (state.grid.isNotEmpty) {
      final rows = state.grid.length;
      final cols = state.grid[0].length;
      final ch = size.height / rows;
      final cw = size.width / cols;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final rssi = state.grid[r][c];
          canvas.drawRect(
            Rect.fromLTWH(c * cw, r * ch, cw, ch),
            Paint()
              ..color =
                  AppColors.signalColor(rssi.toInt()).withOpacity(0.35),
          );
        }
      }
    }

    // Walls
    for (final wall in state.walls) {
      final material = wall['material'] as String? ?? 'drywall';
      final color = material == 'concrete'
          ? AppColors.rose
          : material == 'glass'
              ? AppColors.cyan
              : AppColors.amber;
      canvas.drawLine(
        _toCanvas(
            (wall['x1'] as num).toDouble(), (wall['y1'] as num).toDouble(), size),
        _toCanvas(
            (wall['x2'] as num).toDouble(), (wall['y2'] as num).toDouble(), size),
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }

    // Drag preview (wall being drawn)
    if (dragStart != null && dragEnd != null) {
      canvas.drawLine(
        dragStart!,
        dragEnd!,
        Paint()
          ..color = AppColors.amber.withOpacity(0.6)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }

    // Router icon (pulsing circle + WiFi icon text)
    final rx = routerX / roomWidth * size.width;
    final ry = routerY / roomHeight * size.height;
    final routerOffset = Offset(rx, ry);
    canvas.drawCircle(
        routerOffset, 22, Paint()..color = AppColors.cyan.withOpacity(0.15));
    canvas.drawCircle(
        routerOffset, 14, Paint()..color = AppColors.cyan.withOpacity(0.9));

    // Router label
    final textPainter = TextPainter(
      text: const TextSpan(
          text: '⊙',
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
        canvas, routerOffset - Offset(textPainter.width / 2, textPainter.height / 2));

    // Best spot star
    if (state.bestX != null && state.bestY != null) {
      final bx = state.bestX! / roomWidth * size.width;
      final by = state.bestY! / roomHeight * size.height;
      _drawStar(canvas, Offset(bx, by), 14, AppColors.amber);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final angle = (i * pi / 5) - pi / 2;
      final radius = i.isEven ? r : r * 0.4;
      final x = center.dx + radius * cos(angle);
      final y = center.dy + radius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_AdvisorPainter old) => true;
}

