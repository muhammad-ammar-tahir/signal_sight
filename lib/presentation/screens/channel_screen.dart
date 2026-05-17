import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../blocs/channel/channel_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';

class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key});
  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  double _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) {
        context.read<ChannelCubit>().fetchRecommendations(band: _tabCtrl.index == 0 ? '2.4GHz' : '5GHz');
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChannelCubit>().fetchRecommendations(band: '2.4GHz');
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChannelCubit, ChannelState>(
      builder: (context, state) {
        final congestion = state.congestionScores;
        final details = state.channelDetails;
        final overallScore = congestion.isNotEmpty
            ? congestion.values.fold(0.0, (a, b) => a + b) / congestion.length
            : 0.0;
        final is5GHz = state.band == '5GHz';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Channel Congestion'),
            bottom: TabBar(
              controller: _tabCtrl,
              indicatorColor: AppColors.cyan,
              labelColor: AppColors.cyan,
              unselectedLabelColor: AppColors.textMuted,
              tabs: const [
                Tab(text: '2.4 GHz'),
                Tab(text: '5 GHz'),
              ],
            ),
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
              : state.error != null
                  ? Center(child: Text('Error: ${state.error}', style: const TextStyle(color: AppColors.rose)))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        GlassCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('Spectrum View', style: Theme.of(context).textTheme.headlineMedium),
                                  const Spacer(),
                                  Text(
                                    state.band,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onScaleUpdate: (d) {
                                  setState(() {
                                    _zoom = (_zoom * d.scale).clamp(0.5, 4.0);
                                  });
                                },
                                child: SizedBox(
                                  height: 200,
                                  child: congestion.isEmpty
                                      ? const Center(child: Text('No data', style: TextStyle(color: AppColors.textMuted)))
                                      : _SpectrumChart(
                                          congestion: congestion,
                                          details: details,
                                          zoom: _zoom,
                                          is5GHz: is5GHz,
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(duration: 400.ms),
                        const SizedBox(height: 16),
                        _CongestionScoreWidget(score: overallScore),
                        const SizedBox(height: 16),
                        if (state.bestChannel != null)
                          GlassCard(
                            borderColor: AppColors.emerald.withOpacity(0.3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.recommend_rounded, color: AppColors.emerald, size: 20),
                                    const SizedBox(width: 8),
                                    Text('Recommended Channel', style: Theme.of(context).textTheme.headlineMedium),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _RecommendRow(
                                  rank: 1,
                                  channel: state.bestChannel!,
                                  score: (100 - (congestion[state.bestChannel] ?? 0)).clamp(0, 100).toInt(),
                                ),
                                if (state.reasoning.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(state.reasoning, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.emerald)),
                                ],
                                const SizedBox(height: 14),
                                _HowToGuide(),
                              ],
                            ),
                          ).animate(delay: 200.ms).fadeIn(),
                        const SizedBox(height: 16),
                        SectionHeader(title: 'Channel Details'),
                        const SizedBox(height: 10),
                        ...details.map((n) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                const Icon(Icons.wifi_channel_rounded, color: AppColors.cyan, size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Channel ${n['channel']}', style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600)),
                                      Text('Score: ${n['score'].toStringAsFixed(1)} · ${n['ap_count']} APs', style: Theme.of(context).textTheme.bodySmall),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                      ],
                    ),
        );
      },
    );
  }
}

class _SpectrumChart extends StatelessWidget {
  final Map<int, double> congestion;
  final List<Map<String, dynamic>> details;
  final double zoom;
  final bool is5GHz;

  const _SpectrumChart({
    required this.congestion,
    required this.details,
    required this.zoom,
    required this.is5GHz,
  });

  @override
  Widget build(BuildContext context) {
    if (congestion.isEmpty) return const SizedBox();

    final channels = congestion.keys.toList()..sort();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceEvenly,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) {
              final ch = channels[group.x.toInt()];
              final detail = details.firstWhere((element) => element['channel'] == ch, orElse: () => {});
              final count = detail['ap_count'] ?? 0;
              return BarTooltipItem(
                'Ch $ch\n$count AP(s)',
                const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= channels.length) return const SizedBox();
                if (!is5GHz && channels[idx] % 3 != 1) return const SizedBox();
                return Text(
                  '${channels[idx]}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                );
              },
              reservedSize: 20,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (val, _) => Text(
                val.toInt().toString(),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.cardBorder, strokeWidth: 0.5),
          getDrawingVerticalLine: (_) => const FlLine(color: Colors.transparent),
        ),
        borderData: FlBorderData(show: false),
        barGroups: channels.asMap().entries.map((e) {
          final score = congestion[e.value] ?? 0;
          final color = score < 30
              ? AppColors.emerald
              : score < 60
                  ? AppColors.amber
                  : AppColors.rose;
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: score,
                color: color.withOpacity(0.8),
                width: is5GHz ? 8 : 12,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 100,
                  color: AppColors.cardBorder.withOpacity(0.3),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _CongestionScoreWidget extends StatelessWidget {
  final double score;
  const _CongestionScoreWidget({required this.score});

  Color get _color {
    if (score < 30) return AppColors.emerald;
    if (score < 60) return AppColors.amber;
    return AppColors.rose;
  }

  String get _label {
    if (score < 30) return 'Low Congestion';
    if (score < 60) return 'Moderate';
    return 'High Congestion';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          SizedBox(
            width: 64, height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  backgroundColor: AppColors.cardBorder,
                  color: _color,
                  strokeWidth: 6,
                ),
                Text(
                  '${score.toInt()}',
                  style: TextStyle(color: _color, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_label, style: Theme.of(context).textTheme.headlineMedium!.copyWith(color: _color)),
              const SizedBox(height: 4),
              Text('Average congestion score across all channels', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendRow extends StatelessWidget {
  final int rank;
  final int channel;
  final int score;
  const _RecommendRow({required this.rank, required this.channel, required this.score});

  @override
  Widget build(BuildContext context) {
    final colors = [AppColors.emerald, AppColors.cyan, AppColors.purple];
    final c = colors[(rank - 1).clamp(0, 2)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: c.withOpacity(0.15), shape: BoxShape.circle),
            child: Center(child: Text('$rank', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Channel $channel', style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600))),
          SizedBox(
            width: 80,
            child: LinearProgressIndicator(value: score / 100, color: c, backgroundColor: AppColors.cardBorder, minHeight: 5),
          ),
          const SizedBox(width: 8),
          Text('$score%', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HowToGuide extends StatefulWidget {
  @override
  State<_HowToGuide> createState() => _HowToGuideState();
}

class _HowToGuideState extends State<_HowToGuide> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.amberDim,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.help_outline_rounded, color: AppColors.amber, size: 16),
                const SizedBox(width: 8),
                const Expanded(child: Text('How to change WiFi channel', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600, fontSize: 13))),
                Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.amber),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _Step(n: 1, text: 'Open a browser and go to 192.168.1.1 or 192.168.0.1'),
                SizedBox(height: 6),
                _Step(n: 2, text: 'Log in with your router credentials (often admin/admin)'),
                SizedBox(height: 6),
                _Step(n: 3, text: 'Navigate to Wireless Settings → Basic Settings'),
                SizedBox(height: 6),
                _Step(n: 4, text: 'Change the Channel from Auto to the recommended channel'),
                SizedBox(height: 6),
                _Step(n: 5, text: 'Save settings. Your devices will reconnect automatically.'),
              ],
            ),
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18, height: 18,
          decoration: BoxDecoration(color: AppColors.cyan.withOpacity(0.15), shape: BoxShape.circle),
          child: Center(child: Text('$n', style: const TextStyle(color: AppColors.cyan, fontSize: 10, fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
