import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../blocs/history/history_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';

/// WiFi Time Machine – browse historical scan sessions via an interactive timeline.
class TimeMachineScreen extends StatefulWidget {
  const TimeMachineScreen({super.key});
  @override
  State<TimeMachineScreen> createState() => _TimeMachineScreenState();
}

class _TimeMachineScreenState extends State<TimeMachineScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryCubit>().load();
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _onSliderChanged(double value) {
    _animCtrl.forward(from: 0);
    context.read<HistoryCubit>().seekTo(value.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HistoryCubit, HistoryState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.cyanDim,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.history_edu_rounded,
                      color: AppColors.cyan, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'WiFi Time Machine',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (state.sessions.isNotEmpty) ...[
                // Replay toggle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: state.isReplaying
                        ? AppColors.roseDim
                        : AppColors.emeraldDim,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Icon(
                      state.isReplaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: state.isReplaying
                          ? AppColors.rose
                          : AppColors.emerald,
                    ),
                    tooltip:
                        state.isReplaying ? 'Stop Replay' : 'Auto Replay',
                    onPressed: () {
                      if (state.isReplaying) {
                        context.read<HistoryCubit>().stopReplay();
                      } else {
                        context.read<HistoryCubit>().startReplay();
                      }
                    },
                  ),
                ),
              ],
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan),
                tooltip: 'Reload history',
                onPressed: () => context.read<HistoryCubit>().load(),
              ),
            ],
          ),
          body: state.isLoading
              ? _LoadingState()
              : state.error != null
                  ? _ErrorState(
                      error: state.error!,
                      onRetry: () => context.read<HistoryCubit>().load())
                  : state.sessions.isEmpty
                      ? const _EmptyState()
                      : _buildContent(context, state),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, HistoryState state) {
    final session = state.currentSession;
    final idx = state.currentIndex;
    final total = state.sessions.length;

    return Column(
      children: [
        // ── Stats row ────────────────────────────────────────────────────
        _StatsRow(state: state),

        // ── Animated session content ─────────────────────────────────────
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: session == null
                ? const Center(
                    child: Text('Select a point on the timeline',
                        style: TextStyle(color: AppColors.textMuted)))
                : _SessionContent(session: session),
          ),
        ),

        // ── Timeline slider ──────────────────────────────────────────────
        _TimelineSlider(
          currentIndex: idx,
          total: total,
          sessions: state.sessions,
          isReplaying: state.isReplaying,
          onChanged: _onSliderChanged,
        ),
      ],
    );
  }
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final HistoryState state;
  const _StatsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final session = state.currentSession;
    final ts = session?.timestamp;
    final networkCount = session?.networks.length ?? 0;
    final idx = state.currentIndex;
    final total = state.sessions.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ts != null ? _fmtDateTime(ts) : 'No session',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '$networkCount networks  ·  Session ${idx + 1} of $total',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (state.isReplaying)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.emeraldDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.emerald.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScanDot(active: true),
                  const SizedBox(width: 6),
                  const Text('REPLAYING',
                      style: TextStyle(
                          color: AppColors.emerald,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                ],
              ),
            )
          else ...[
            _MiniStat(
                label: 'Sessions',
                value: '$total',
                color: AppColors.cyan),
            const SizedBox(width: 8),
            _MiniStat(
                label: 'Networks',
                value: '$networkCount',
                color: AppColors.purple),
          ],
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    final pad = (int n) => n.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year}  '
        '${pad(dt.hour)}:${pad(dt.minute)}';
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 9)),
        ]),
      );
}

// ─── Session Content ──────────────────────────────────────────────────────────

class _SessionContent extends StatelessWidget {
  final ScanSession session;
  const _SessionContent({required this.session});

  @override
  Widget build(BuildContext context) {
    final nets = session.networks;
    if (nets.isEmpty) {
      return const Center(
          child: Text('No networks in this session.',
              style: TextStyle(color: AppColors.textMuted)));
    }

    // Channel distribution
    final channelCounts = <int, int>{};
    for (final n in nets.where((n) => !n.is5GHz)) {
      channelCounts[n.channel] = (channelCounts[n.channel] ?? 0) + 1;
    }
    final maxCount =
        channelCounts.values.fold(1, (a, b) => a > b ? a : b);

    // Security breakdown
    final open = nets.where((n) => n.security == 'Open').length;
    final wpa2 = nets.where((n) => n.security.contains('WPA2')).length;
    final wpa3 = nets.where((n) => n.security.contains('WPA3')).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      children: [
        // Security overview pills
        if (open > 0 || wpa2 > 0 || wpa3 > 0) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (open > 0) _SecurityPill(label: '$open Open', color: AppColors.rose),
              if (wpa2 > 0) _SecurityPill(label: '$wpa2 WPA2', color: AppColors.amber),
              if (wpa3 > 0) _SecurityPill(label: '$wpa3 WPA3', color: AppColors.emerald),
            ],
          ).animate().fadeIn(duration: 250.ms),
          const SizedBox(height: 14),
        ],

        // Channel usage bar chart
        if (channelCounts.isNotEmpty) ...[
          SectionHeader(title: 'Channel Usage (2.4 GHz)'),
          const SizedBox(height: 10),
          _ChannelBarChart(
              channelCounts: channelCounts, maxCount: maxCount),
          const SizedBox(height: 20),
        ],

        // Network list
        SectionHeader(title: 'Networks (${nets.length})'),
        const SizedBox(height: 10),
        ...nets.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  _HistoryNetworkRow(network: e.value, index: e.key),
            )),
      ],
    );
  }
}

class _SecurityPill extends StatelessWidget {
  final String label;
  final Color color;
  const _SecurityPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

// ─── Channel Bar Chart ────────────────────────────────────────────────────────

class _ChannelBarChart extends StatelessWidget {
  final Map<int, int> channelCounts;
  final int maxCount;
  const _ChannelBarChart(
      {required this.channelCounts, required this.maxCount});

  @override
  Widget build(BuildContext context) {
    final channels = List.generate(13, (i) => i + 1);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: SizedBox(
        height: 72,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: channels.map((ch) {
            final count = channelCounts[ch] ?? 0;
            final ratio = count / maxCount;
            final isHighest = count == maxCount && count > 0;
            final isBusy = count > 0 && !isHighest;
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    height: count > 0 ? (ratio * 48).clamp(4.0, 48.0) : 2,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isHighest
                          ? AppColors.rose
                          : isBusy
                              ? AppColors.amber
                              : AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: isHighest
                          ? [
                              BoxShadow(
                                  color: AppColors.rose.withOpacity(0.4),
                                  blurRadius: 6)
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$ch',
                    style: TextStyle(
                      color: isHighest
                          ? AppColors.rose
                          : isBusy
                              ? AppColors.textSecondary
                              : AppColors.textMuted,
                      fontSize: 8,
                      fontWeight: isHighest
                          ? FontWeight.w800
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── History Network Row ──────────────────────────────────────────────────────

class _HistoryNetworkRow extends StatelessWidget {
  final WifiNetwork network;
  final int index;
  const _HistoryNetworkRow({required this.network, required this.index});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SignalBars(rssi: network.rssi, height: 22, width: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network.displaySsid,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge!
                      .copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  network.bssid,
                  style: GoogleFonts.sourceCodePro(
                      color: AppColors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SecurityBadge(
                  tag: network.securityTag,
                  classification: network.security),
              const SizedBox(height: 4),
              ChannelChip(
                  channel: network.channel, is5GHz: network.is5GHz),
            ],
          ),
          const SizedBox(width: 8),
          Text(
            '${network.rssi}',
            style: TextStyle(
              color: AppColors.signalColor(network.rssi),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ).animate(delay: (index * 30).ms).fadeIn(duration: 250.ms).slideX(
        begin: 0.04, end: 0);
  }
}

// ─── Timeline Slider ──────────────────────────────────────────────────────────

class _TimelineSlider extends StatelessWidget {
  final int currentIndex, total;
  final List<ScanSession> sessions;
  final bool isReplaying;
  final ValueChanged<double> onChanged;
  const _TimelineSlider({
    required this.currentIndex,
    required this.total,
    required this.sessions,
    required this.isReplaying,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  sessions.isNotEmpty ? _fmtShort(sessions.first.timestamp) : '',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cyanDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.history_rounded,
                      color: AppColors.cyan, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '${currentIndex + 1} / $total',
                    style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              Flexible(
                child: Text(
                  sessions.isNotEmpty ? _fmtShort(sessions.last.timestamp) : '',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: isReplaying ? AppColors.emerald : AppColors.cyan,
              inactiveTrackColor: AppColors.cardBorder,
              thumbColor: isReplaying ? AppColors.emerald : AppColors.cyan,
              overlayColor: isReplaying
                  ? AppColors.emerald.withOpacity(0.2)
                  : AppColors.cyanDim,
            ),
            child: Slider(
              min: 0,
              max: (total - 1).toDouble().clamp(0, double.infinity),
              value: currentIndex.toDouble().clamp(0, (total - 1).toDouble()),
              divisions: total > 1 ? total - 1 : 1,
              onChanged: total > 1 ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtShort(DateTime dt) {
    final pad = (int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.day)}/${pad(dt.month)}\n${pad(dt.hour)}:${pad(dt.minute)}';
  }
}

// ─── Loading / Empty / Error States ──────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.cyan),
            const SizedBox(height: 16),
            Text('Loading scan history…',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: AppColors.textMuted)),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cyanDim,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.history_toggle_off_rounded,
                    color: AppColors.cyan, size: 52),
              ),
              const SizedBox(height: 20),
              Text('No scan history yet',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium!
                      .copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                'Run a WiFi scan from the Dashboard\nto start recording history.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.rose, size: 52),
              const SizedBox(height: 16),
              Text('Failed to load history',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium!
                      .copyWith(color: AppColors.rose)),
              const SizedBox(height: 8),
              Text(error,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              GradientButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry),
            ],
          ),
        ),
      );
}
