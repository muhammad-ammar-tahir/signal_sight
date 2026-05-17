import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import '../blocs/history/history_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    context.read<HistoryCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HistoryCubit, HistoryState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('WiFi Time-Machine'),
            actions: [
              IconButton(
                icon: const Icon(Icons.travel_explore_rounded,
                    color: AppColors.cyan),
                tooltip: 'Full Time Machine View',
                onPressed: () =>
                    Navigator.pushNamed(context, '/time_machine'),
              ),
              IconButton(
                icon: Icon(
                  state.isReplaying
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  color: state.isReplaying ? AppColors.rose : AppColors.emerald,
                ),
                onPressed: () {
                  if (state.isReplaying) {
                    context.read<HistoryCubit>().stopReplay();
                  } else {
                    context.read<HistoryCubit>().startReplay();
                  }
                },
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
              : state.error != null
                  ? Center(child: Text('Error: ${state.error}', style: const TextStyle(color: AppColors.rose)))
                  : state.sessions.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_rounded, color: AppColors.textMuted, size: 64),
                              SizedBox(height: 16),
                              Text('No scan history yet', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
                              SizedBox(height: 8),
                              Text('Start scanning to record history', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                            ],
                          ),
                        )
              : Column(
                  children: [
                    // Timeline slider
                    _TimelineSlider(state: state),
                    // Current session info
                    if (state.currentSession != null)
                      _SessionInfo(session: state.currentSession!)
                          .animate(key: ValueKey(state.currentIndex))
                          .fadeIn(duration: 200.ms),
                    // Content
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.timeline_rounded, color: AppColors.cyan, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Scan Timeline', style: Theme.of(context).textTheme.headlineMedium),
                                ]),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 120,
                                  child: _TimelineChart(sessions: state.sessions, currentIndex: state.currentIndex),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(duration: 400.ms),
                          const SizedBox(height: 16),
                          SectionHeader(
                            title: 'All Sessions (${state.sessions.length})',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (state.isReplaying)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.emeraldDim,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.play_circle_filled_rounded, color: AppColors.emerald, size: 12),
                                        SizedBox(width: 4),
                                        Text('REPLAYING', style: TextStyle(color: AppColors.emerald, fontSize: 10, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...state.sessions.asMap().entries.map((e) {
                            final isActive = e.key == state.currentIndex;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassCard(
                                borderColor: isActive ? AppColors.cyan.withOpacity(0.5) : null,
                                glowing: isActive,
                                onTap: () => context.read<HistoryCubit>().seekTo(e.key),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32, height: 32,
                                      decoration: BoxDecoration(
                                        color: (isActive ? AppColors.cyan : AppColors.textMuted).withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${e.key + 1}',
                                          style: TextStyle(
                                            color: isActive ? AppColors.cyan : AppColors.textMuted,
                                            fontSize: 11, fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            DateFormat('MMM d, yyyy HH:mm:ss').format(e.value.timestamp),
                                            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                                              color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.cyanDim,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('NOW', style: TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w700)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _TimelineSlider extends StatelessWidget {
  final HistoryState state;
  const _TimelineSlider({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_rounded, color: AppColors.cyan, size: 16),
              const SizedBox(width: 6),
              Text(
                state.sessions.isEmpty ? 'No data' : 'Session ${state.currentIndex + 1} of ${state.sessions.length}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Slider(
            value: state.sessions.isEmpty ? 0 : state.currentIndex.toDouble(),
            min: 0,
            max: state.sessions.isEmpty ? 1 : (state.sessions.length - 1).toDouble(),
            divisions: state.sessions.length <= 1 ? null : state.sessions.length - 1,
            activeColor: AppColors.cyan,
            inactiveColor: AppColors.cardBorder,
            onChanged: (v) => context.read<HistoryCubit>().seekTo(v.toInt()),
          ),
        ],
      ),
    );
  }
}

class _SessionInfo extends StatelessWidget {
  final ScanSession session;
  const _SessionInfo({required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: AppColors.cyan, size: 14),
          const SizedBox(width: 6),
          Text(
            DateFormat('EEEE, MMM d yyyy  HH:mm:ss').format(session.timestamp),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.cyan),
          ),
        ],
      ),
    );
  }
}

class _TimelineChart extends StatelessWidget {
  final List<ScanSession> sessions;
  final int currentIndex;
  const _TimelineChart({required this.sessions, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    if (sessions.length < 2) {
      return const Center(child: Text('Need at least 2 sessions', style: TextStyle(color: AppColors.textMuted)));
    }
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.cardBorder, strokeWidth: 0.5),
          getDrawingVerticalLine: (_) => const FlLine(color: Colors.transparent),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= sessions.length) return const SizedBox();
                if (idx % (sessions.length ~/ 4).clamp(1, 999) != 0) return const SizedBox();
                return Text(DateFormat('HH:mm').format(sessions[idx].timestamp),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 9));
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          // Scan index line (shows progress)
          LineChartBarData(
            spots: sessions.asMap().entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.networks.length.toDouble()))
                .toList(),
            isCurved: true,
            color: AppColors.cyan.withOpacity(0.5),
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: AppColors.cyanDim),
          ),
        ],
        // Vertical line at current position
        extraLinesData: ExtraLinesData(
          verticalLines: [
            VerticalLine(
              x: currentIndex.toDouble(),
              color: AppColors.cyan,
              strokeWidth: 2,
              dashArray: [4, 4],
            ),
          ],
        ),
      ),
    );
  }
}
