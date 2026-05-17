import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import '../blocs/heatmap/heatmap_cubit.dart';
import '../blocs/scan/scan_cubit.dart';
import '../widgets/common_widgets.dart';
import '../widgets/heatmap_painter.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../services/heatmap_export.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  Uint8List? _floorPlan;
  String? _selectedBssid;
  bool _settingStart = false;

  void _showSettings(BuildContext context, HeatmapState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      builder: (ctx) {
        double idw = state.idwPower;
        bool dynScale = state.useDynamicScale;
        bool clipHull = state.clipToWalkingArea;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Heatmap Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Dynamic Color Scale', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Scale colors based on max/min RSSI', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: dynScale,
                    activeColor: AppColors.cyan,
                    onChanged: (v) => setState(() => dynScale = v),
                  ),
                  SwitchListTile(
                    title: const Text('Clip to Walking Area', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Prevent colors from bleeding outside the path hull', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: clipHull,
                    activeColor: AppColors.cyan,
                    onChanged: (v) => setState(() => clipHull = v),
                  ),
                  ListTile(
                    title: const Text('Interpolation Power (IDW)', style: TextStyle(color: Colors.white)),
                    subtitle: Slider(
                      value: idw,
                      min: 1.5,
                      max: 3.0,
                      divisions: 3,
                      activeColor: AppColors.cyan,
                      label: idw.toStringAsFixed(1),
                      onChanged: (v) => setState(() => idw = v),
                    ),
                  ),
                  ListTile(
                    title: const Text('Reset Calibration', style: TextStyle(color: AppColors.rose)),
                    leading: const Icon(Icons.settings_backup_restore, color: AppColors.rose),
                    onTap: () {
                      context.read<HeatmapCubit>().resetCalibration();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Calibration reset.')));
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white),
                      onPressed: () {
                        context.read<HeatmapCubit>().updateSettings(
                          idwPower: idw,
                          useDynamicScale: dynScale,
                          clipToWalkingArea: clipHull,
                        );
                        Navigator.pop(context);
                      },
                      child: const Text('Apply Settings'),
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _showExportMenu(BuildContext context, HeatmapState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image, color: AppColors.cyan),
                title: const Text('Export Image (PNG)', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  HeatmapExport.saveHeatmapImage(context, _repaintKey);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart, color: AppColors.emerald),
                title: const Text('Export Data (CSV)', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  HeatmapExport.exportSessionCSV(context, state);
                },
              ),
              ListTile(
                leading: const Icon(Icons.data_object, color: AppColors.amber),
                title: const Text('Export Metadata (JSON)', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  HeatmapExport.exportSessionJSON(context, state);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HeatmapCubit, HeatmapState>(
      listenWhen: (prev, curr) => curr.errorMessage != null && prev.errorMessage != curr.errorMessage,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.errorMessage!, overflow: TextOverflow.ellipsis, maxLines: 2),
            backgroundColor: AppColors.amber,
            duration: const Duration(seconds: 5),
          ));
        }
      },
      builder: (context, heatState) {
        return BlocBuilder<ScanCubit, ScanState>(
          builder: (context, scanState) {
            return Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                title: const Text('Signal Mapper'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Heatmap Settings',
                    onPressed: () => _showSettings(context, heatState),
                  ),
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    tooltip: 'Upload floor plan',
                    onPressed: () async {
                      final img = await ImagePicker().pickImage(source: ImageSource.gallery);
                      if (img != null) {
                        final bytes = await img.readAsBytes();
                        setState(() => _floorPlan = bytes);
                      }
                    },
                  ),
                  if (heatState.hasResult)
                    IconButton(
                      icon: const Icon(Icons.share_rounded, color: AppColors.cyan),
                      tooltip: 'Export',
                      onPressed: () => _showExportMenu(context, heatState),
                    ),
                ],
              ),
              body: Column(
                children: [
                  if (heatState.errorMessage != null && !heatState.isMapping)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 48),
                      child: Container(
                        width: double.infinity,
                        color: AppColors.amber.withOpacity(0.15),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                heatState.errorMessage!,
                                style: const TextStyle(color: AppColors.amber, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (!heatState.isMapping && !heatState.hasResult && !heatState.isAnalyzing)
                    _buildBssidSelector(context, scanState.networks),

                  // "Walk more" live hint while mapping
                  if (heatState.isMapping && heatState.stepCount < 10)
                    Container(
                      width: double.infinity,
                      color: AppColors.cyanDim,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_walk_rounded, color: AppColors.cyan, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Walk more to map the area — ${heatState.stepCount}/10 steps',
                              style: const TextStyle(color: AppColors.cyan, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  Expanded(
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            onTapUp: _settingStart
                                ? (details) {
                                    final box = context.findRenderObject() as RenderBox?;
                                    if (box != null) {
                                      final local = box.globalToLocal(details.globalPosition);
                                      final size = box.size;
                                      const pad = 40.0;
                                      final wx = (local.dx - pad) / (size.width - pad * 2);
                                      final wy = (local.dy - pad) / (size.height - pad * 2);
                                      context.read<HeatmapCubit>().setStartPoint(wx, wy);
                                      setState(() => _settingStart = false);
                                    }
                                  }
                                : null,
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0, // Capped at 4.0 for zoom stability
                              clipBehavior: Clip.none,
                              child: SizedBox(
                                width: constraints.maxWidth,
                                height: constraints.maxHeight,
                                child: Stack(
                                  children: [
                                    if (_floorPlan != null)
                                      Positioned.fill(
                                        child: Opacity(
                                          opacity: 0.22,
                                          child: Image.memory(_floorPlan!, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                                        ),
                                      ),

                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: HeatmapPainter(
                                          points: heatState.points,
                                          heatmapGrid: heatState.heatmapGrid,
                                          currentX: heatState.currentX,
                                          currentY: heatState.currentY,
                                          startX: heatState.startX,
                                          startY: heatState.startY,
                                          isMapping: heatState.isMapping,
                                          hasResult: heatState.hasResult,
                                          clipToWalkingArea: heatState.clipToWalkingArea,
                                          useDynamicScale: heatState.useDynamicScale,
                                          minRssi: heatState.minRssi,
                                          maxRssi: heatState.maxRssi,
                                          convexHull: heatState.convexHull,
                                        ),
                                      ),
                                    ),

                                    if (!heatState.isMapping && !heatState.hasResult && !heatState.isAnalyzing && heatState.points.isEmpty)
                                      Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: AppColors.cyan,
                                                shape: BoxShape.circle,
                                                boxShadow: [BoxShadow(color: AppColors.cyan.withOpacity(0.5), blurRadius: 16, spreadRadius: 4)],
                                              ),
                                            ).animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(1, 1), end: const Offset(1.3, 1.3), duration: 1000.ms).then().scale(begin: const Offset(1.3, 1.3), end: const Offset(1, 1), duration: 1000.ms),
                                            const SizedBox(height: 14),
                                            Text(
                                              _settingStart
                                                  ? 'Tap on the map to set start point'
                                                  : _selectedBssid == null
                                                      ? 'Select a network above to begin'
                                                      : 'Ready. Set start point & start mapping',
                                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),

                                    // ── Analyzing overlay (isolate running) ──
                                    if (heatState.isAnalyzing)
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.black54,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const SizedBox(
                                                width: 48,
                                                height: 48,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 3,
                                                  color: AppColors.cyan,
                                                ),
                                              ),
                                              const SizedBox(height: 18),
                                              const Text(
                                                'Analyzing signal map…',
                                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 6),
                                              const Text(
                                                'Running interpolation in background',
                                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                    if (heatState.hasResult)
                                      Positioned(bottom: 8, right: 8, child: _HeatmapLegend(state: heatState)),

                                    if (_settingStart)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: Container(color: AppColors.cyan.withOpacity(0.06)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  _InfoPanel(state: heatState),

                  _ControlsBar(
                    state: heatState,
                    settingStart: _settingStart,
                    hasTarget: _selectedBssid != null || heatState.targetBssid != null,
                    onSetStart: () => setState(() => _settingStart = true),
                    onStart: () => context.read<HeatmapCubit>().startMapping(),
                    onStop: () => context.read<HeatmapCubit>().stopAndAnalyze(),
                    onClear: () {
                      context.read<HeatmapCubit>().clear();
                      setState(() {
                        _selectedBssid = null;
                        _settingStart = false;
                      });
                    },
                    onCalibrate: () => context.read<HeatmapCubit>().calibrateReference(),
                    onResetHeading: () => context.read<HeatmapCubit>().resetHeading(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBssidSelector(BuildContext context, List<WifiNetwork> networks) {
    if (networks.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: AppColors.card, border: const Border(bottom: BorderSide(color: AppColors.cardBorder))),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.textMuted.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No networks detected', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('Go to Dashboard and run a WiFi scan first', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final seen = <String>{};
    final uniqueNetworks = networks.where((n) {
      if (seen.contains(n.bssid)) return false;
      seen.add(n.bssid);
      return true;
    }).toList();

    final validBssids = uniqueNetworks.map((n) => n.bssid).toSet();
    if (_selectedBssid != null && !validBssids.contains(_selectedBssid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedBssid = null);
      });
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.card, border: const Border(bottom: BorderSide(color: AppColors.cardBorder))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: AppColors.cyanDim, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.wifi_tethering_rounded, color: AppColors.cyan, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: (_selectedBssid != null && validBssids.contains(_selectedBssid)) ? _selectedBssid : null,
                hint: Text('Select network (${uniqueNetworks.length} found)', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                icon: const Icon(Icons.expand_more_rounded, color: AppColors.cyan, size: 18),
                isExpanded: true,
                items: uniqueNetworks.map((n) {
                  final bars = n.rssi > -60 ? '▂▄▆█' : n.rssi > -75 ? '▂▄▆' : n.rssi > -85 ? '▂▄' : '▂';
                  return DropdownMenuItem<String>(
                    value: n.bssid,
                    child: Row(
                      children: [
                        Text(bars, style: TextStyle(color: AppColors.signalColor(n.rssi), fontSize: 10)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(n.displaySsid, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(n.bssid, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Text('${n.rssi} dBm', style: TextStyle(color: AppColors.signalColor(n.rssi), fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedBssid = v);
                    context.read<HeatmapCubit>().setTarget(v);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final HeatmapState state;
  const _InfoPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final avgRssi = state.points.isEmpty
        ? '—'
        : '${(state.points.map((p) => p.rssi).reduce((a, b) => a + b) / state.points.length).toInt()} dBm';

    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatChip(icon: Icons.memory, label: 'Points', value: '${state.points.length}/2000'),
          _StatChip(icon: Icons.directions_walk_rounded, label: 'Steps', value: '${state.stepCount}'),
          _StatChip(icon: Icons.area_chart_rounded, label: 'Area', value: state.points.length > 1 ? '~${state.areaSqM.toStringAsFixed(1)} m²' : '—'),
          _StatChip(icon: Icons.signal_wifi_4_bar_rounded, label: 'Avg RSSI', value: avgRssi),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: AppColors.cyan, size: 15),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ],
  );
}

class _ControlsBar extends StatelessWidget {
  final HeatmapState state;
  final bool settingStart;
  final bool hasTarget;
  final VoidCallback onSetStart;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onClear;
  final VoidCallback onCalibrate;
  final VoidCallback onResetHeading;

  const _ControlsBar({
    required this.state,
    required this.settingStart,
    required this.hasTarget,
    required this.onSetStart,
    required this.onStart,
    required this.onStop,
    required this.onClear,
    required this.onCalibrate,
    required this.onResetHeading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: const BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.cardBorder))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (!state.isMapping && !state.hasResult)
                OutlinedButton.icon(
                  onPressed: hasTarget ? onSetStart : null,
                  icon: const Icon(Icons.my_location_rounded, size: 16),
                  label: Text(settingStart ? 'Tap map…' : 'Set Start', style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: settingStart ? AppColors.amber : AppColors.cyan,
                    side: BorderSide(color: settingStart ? AppColors.amber : AppColors.cyan.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              if (!state.isMapping && !state.hasResult) const SizedBox(width: 10),
              Expanded(
                child: state.isMapping
                    ? GradientButton(
                        label: 'Stop & Analyze',
                        icon: Icons.stop_circle_rounded,
                        startColor: AppColors.amber,
                        endColor: const Color(0xFFB45309),
                        onPressed: state.isAnalyzing ? null : onStop,
                      )
                    : state.isAnalyzing
                    ? GradientButton(
                        label: 'Analyzing…',
                        icon: Icons.hourglass_top_rounded,
                        startColor: AppColors.textMuted,
                        endColor: AppColors.textMuted,
                        onPressed: null,
                      )
                    : GradientButton(
                        label: state.hasResult ? 'Re-map' : 'Start Mapping',
                        icon: state.hasResult ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                        startColor: hasTarget ? AppColors.cyan : AppColors.textMuted,
                        endColor: hasTarget ? const Color(0xFF0099CC) : AppColors.textMuted,
                        onPressed: hasTarget ? onStart : null,
                      ),
              ),
            ],
          ),
          if ((state.points.isNotEmpty || state.hasResult) && !state.isMapping) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_outline_rounded, size: 15),
                    label: const Text('Clear All', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.rose,
                      side: BorderSide(color: AppColors.rose.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (state.isMapping) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: onResetHeading,
                  icon: const Icon(Icons.explore, size: 16, color: AppColors.cyan),
                  label: const Text('Reset Heading (Point North)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ],
          if (!state.isMapping && !state.hasResult) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Calib. Ref: ${state.calibrationRssiAtOneMeter.toInt()} dBm', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                TextButton(
                  onPressed: hasTarget ? onCalibrate : null,
                  child: const Text('Calibrate Reference (1m)', style: TextStyle(fontSize: 12, color: AppColors.cyan)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  final HeatmapState state;
  const _HeatmapLegend({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.useDynamicScale) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.card.withOpacity(0.9), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Dynamic Signal', style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
            const SizedBox(height: 6),
            Container(
              width: 80,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: LinearGradient(
                  colors: [HSLColor.fromAHSL(1.0, 0, 0.9, 0.5).toColor(), HSLColor.fromAHSL(1.0, 60, 0.9, 0.5).toColor(), HSLColor.fromAHSL(1.0, 120, 0.9, 0.5).toColor()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${state.minRssi.toInt()}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                const SizedBox(width: 40),
                Text('${state.maxRssi.toInt()}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              ],
            ),
          ],
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.card.withOpacity(0.9), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.cardBorder)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Signal', style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
          SizedBox(height: 4),
          _LegendRow(color: AppColors.emerald, label: 'Strong (>-60)'),
          _LegendRow(color: AppColors.amber, label: 'Fair (-75)'),
          _LegendRow(color: AppColors.rose, label: 'Weak (<-85)'),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
      ],
    ),
  );
}
