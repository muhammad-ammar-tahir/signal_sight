import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../blocs/scan/scan_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../blocs/ar/ar_cubit.dart';
import 'dart:math';

class ArViewScreen extends StatefulWidget {
  const ArViewScreen({super.key});
  @override
  State<ArViewScreen> createState() => _ArViewScreenState();
}

class _ArViewScreenState extends State<ArViewScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  Timer? _sampleTimer;
  late ArCubit _arCubit;

  ArCoreController? arCoreController;
  ArCoreNode? sphereNode;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  double _pitch = 0.0;
  double _yaw = 0.0;

  @override
  void initState() {
    super.initState();
    _arCubit = ArCubit();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _sampleTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sampleRssi());
    
    _gyroSub = gyroscopeEvents.listen((event) {
      setState(() {
        _pitch += event.x * 0.05;
        _yaw += event.y * 0.05;
      });
    });
  }

  void _sampleRssi() {
    final state = context.read<ScanCubit>().state;
    final own = state.networks.where((n) => n.isOwn).firstOrNull;
    final rssi = own?.rssi.toDouble() ?? (state.networks.isNotEmpty ? state.networks.first.rssi.toDouble() : -70.0);
    _arCubit.updateRssi(rssi);

    _updateArSphere(rssi, _arCubit.state.estimatedDistance);
  }

  void _onArCoreViewCreated(ArCoreController controller) {
    arCoreController = controller;
    _addSphere();
  }

  void _addSphere() {
    final material = ArCoreMaterial(
      color: AppColors.signalColor(_arCubit.state.rssi.toInt()),
      metallic: 1.0,
    );
    final sphere = ArCoreSphere(
      materials: [material],
      radius: 0.1,
    );
    sphereNode = ArCoreNode(
      shape: sphere,
      position: vector.Vector3(0, 0, -1.5),
    );
    arCoreController?.addArCoreNode(sphereNode!);
  }

  void _updateArSphere(double rssi, double distance) {
    if (arCoreController != null && sphereNode != null) {
      final material = ArCoreMaterial(
        color: AppColors.signalColor(rssi.toInt()),
        metallic: 1.0,
      );
      // Change size based on distance/RSSI
      final radius = max(0.05, min(0.3, 0.1 + (rssi + 70) * 0.005));
      final sphere = ArCoreSphere(
        materials: [material],
        radius: radius,
      );
      // Remove old and add new to update
      arCoreController?.removeNode(nodeName: sphereNode!.name);
      sphereNode = ArCoreNode(
        shape: sphere,
        position: vector.Vector3(0, 0, -max(0.5, distance)),
      );
      arCoreController?.addArCoreNode(sphereNode!);
    }
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    arCoreController?.dispose();
    _pulseCtrl.dispose();
    _sampleTimer?.cancel();
    _arCubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _arCubit,
      child: BlocBuilder<ScanCubit, ScanState>(
        builder: (context, scanState) {
          return BlocBuilder<ArCubit, ArState>(
            builder: (context, arState) {
              final network = scanState.networks.where((n) => n.isOwn).firstOrNull ?? scanState.networks.firstOrNull;
              final rssi = arState.rssi;
              final quality = ((rssi + 100).clamp(0, 50)) / 50.0;

              return Scaffold(
                backgroundColor: AppColors.background,
                body: Stack(
                  children: [
                    if (arState.arCoreAvailable == true)
                      ArCoreView(
                        onArCoreViewCreated: _onArCoreViewCreated,
                        enableTapRecognizer: true,
                      )
                    else if (arState.arCoreAvailable == false)
                      _buildFallbackView(rssi, bubbleColor: AppColors.signalColor(rssi.toInt()))
                    else
                      const Center(child: CircularProgressIndicator()),

                    if (arState.arCoreAvailable == false)
                      Positioned(
                        top: 100,
                        left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.rose.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ARCore not available on this device',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),

                    // Top bar
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            GlassCard(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.view_in_ar_rounded, color: AppColors.cyan, size: 18),
                                  const SizedBox(width: 6),
                                  Text('AR View', style: Theme.of(context).textTheme.headlineMedium),
                                ],
                              ),
                            ),
                            const Spacer(),
                            GlassCard(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              onTap: () => context.read<ArCubit>().toggleFollowMode(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(arState.followMode ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded, color: arState.followMode ? AppColors.cyan : AppColors.textSecondary, size: 16),
                                  const SizedBox(width: 6),
                                  Text(arState.followMode ? 'Follow' : 'Local', style: Theme.of(context).textTheme.labelLarge),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    if (network != null && arState.arCoreAvailable == true)
                      Positioned(
                        top: 120,
                        left: 0, right: 0,
                        child: Center(
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Text(network.displaySsid, style: Theme.of(context).textTheme.headlineMedium),
                          ).animate().fadeIn(duration: 300.ms),
                        ),
                      ),
                      
                    // Bottom sheet info
                    DraggableScrollableSheet(
                      initialChildSize: 0.28,
                      minChildSize: 0.12,
                      maxChildSize: 0.55,
                      builder: (_, ctrl) => Container(
                        decoration: const BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          border: Border(top: BorderSide(color: AppColors.cardBorder)),
                        ),
                        child: ListView(
                          controller: ctrl,
                          padding: const EdgeInsets.all(20),
                          children: [
                            Center(
                              child: Container(
                                width: 40, height: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2)),
                              ),
                            ),
                            Row(
                              children: [
                                _ArStat(label: 'RSSI', value: '${rssi.toInt()} dBm', color: AppColors.signalColor(rssi.toInt())),
                                const SizedBox(width: 12),
                                _ArStat(label: 'Distance', value: '~${arState.estimatedDistance.toStringAsFixed(1)} m', color: AppColors.cyan),
                                const SizedBox(width: 12),
                                _ArStat(label: 'Quality', value: '${(quality * 100).toInt()}%', color: AppColors.purple),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SectionHeader(title: 'RSSI History'),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 100,
                              child: arState.rssiHistory.length < 2
                                  ? const Center(child: Text('Sampling…', style: TextStyle(color: AppColors.textMuted)))
                                  : LineChart(
                                      LineChartData(
                                        gridData: const FlGridData(show: false),
                                        borderData: FlBorderData(show: false),
                                        titlesData: const FlTitlesData(show: false),
                                        lineBarsData: [
                                          LineChartBarData(
                                            spots: arState.rssiHistory.asMap().entries
                                                .map((e) => FlSpot(e.key.toDouble(), e.value))
                                                .toList(),
                                            isCurved: true,
                                            color: AppColors.cyan,
                                            barWidth: 2,
                                            dotData: const FlDotData(show: false),
                                            belowBarData: BarAreaData(show: true, color: AppColors.cyanDim),
                                          ),
                                        ],
                                        minY: -100, maxY: -30,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFallbackView(double rssi, {required Color bubbleColor}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF0D1520), Color(0xFF050810)],
        ),
      ),
      child: Center(
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // perspective
            ..rotateX(_pitch)
            ..rotateY(_yaw),
          alignment: FractionalOffset.center,
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final pulse = 0.85 + 0.15 * sin(_pulseCtrl.value * 2 * pi);
              final bubbleSize = 120.0;
              return Container(
                width: bubbleSize * pulse,
                height: bubbleSize * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bubbleColor.withOpacity(0.3),
                  border: Border.all(color: bubbleColor, width: 2),
                  boxShadow: [BoxShadow(color: bubbleColor.withOpacity(0.5), blurRadius: 20)],
                ),
                child: Center(
                  child: Icon(Icons.router_rounded, color: Colors.white, size: bubbleSize * 0.4),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ArStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _ArStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ]),
    ),
  );
}
