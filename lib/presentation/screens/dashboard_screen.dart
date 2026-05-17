import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../blocs/scan/scan_cubit.dart';
import '../blocs/channel/channel_cubit.dart';
import '../blocs/device/device_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../data/services/device_db.dart';
import '../../data/services/network_analytics.dart';
import 'package:fl_chart/fl_chart.dart';
import 'channel_screen.dart';
import '../blocs/security/security_cubit.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScanCubit, ScanState>(
      builder: (context, state) {
        // ChannelCubit now manages its own API calls
        return ParticleBackground(
          active: state.isScanning,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _buildAppBar(context, state),
            floatingActionButton: _buildFab(context, state),
            body: RefreshIndicator(
              color: AppColors.cyan,
              backgroundColor: AppColors.card,
              onRefresh: () async {
                context.read<ScanCubit>().startScan();
                final nets = state.networks;
                if (nets.isNotEmpty) {
                  context.read<ChannelCubit>().computeFromNetworks(networks: nets);
                  context.read<SecurityCubit>().runAuditOnNetworks(nets);
                } else {
                  context.read<ChannelCubit>().fetchRecommendations(band: '2.4GHz', localNetworks: nets);
                  context.read<SecurityCubit>().runAudit();
                }
                await Future.delayed(const Duration(seconds: 2));
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  _RadarCard(state: state),
                  const SizedBox(height: 16),
                  _AnalyticsCard(),
                  const SizedBox(height: 16),
                  _HealthScoreCard(scanState: state),
                  const SizedBox(height: 16),
                  _buildActions(context, state),
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: 'Networks (${state.networks.length})',
                    trailing: GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ChannelScreen())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.cyanDim,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.cyanGlow),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.bar_chart_rounded, color: AppColors.cyan, size: 14),
                            const SizedBox(width: 4),
                            Text('Channels', style: Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (state.networks.isEmpty)
                    _EmptyState(scanning: state.isScanning)
                  else
                    ...state.networks.asMap().entries.map((e) =>
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NetworkCard(network: e.value, index: e.key),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ScanState state) {
    return AppBar(
      backgroundColor: AppColors.background,
      title: Row(
        children: [
          ScanDot(active: state.isScanning),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SignalSight',
                  style: Theme.of(context).textTheme.headlineLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  state.isScanning ? 'Live Scanning…' : 'Tap scan to start',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: state.isScanning ? AppColors.emerald : AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (state.lastScan != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                _fmtTime(state.lastScan!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.security_rounded, color: AppColors.cyan),
          tooltip: 'Security Audit',
          onPressed: () => Navigator.pushNamed(context, '/security'),
        ),
        IconButton(
          icon: const Icon(Icons.history_rounded),
          tooltip: 'History',
          onPressed: () => Navigator.pushNamed(context, '/history'),
        ),
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, ScanState state) {
    return Row(
      children: [
        Expanded(
          child: GradientButton(
            label: state.isScanning ? 'Stop Scan' : 'Start Scan',
            icon: state.isScanning ? Icons.stop_rounded : Icons.wifi_tethering_rounded,
            startColor: state.isScanning ? AppColors.rose : AppColors.cyan,
            endColor: state.isScanning ? const Color(0xFFB91C3A) : const Color(0xFF0099CC),
            onPressed: () {
              if (state.isScanning) {
                context.read<ScanCubit>().stopScan();
              } else {
                context.read<ScanCubit>().startScan();
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GradientButton(
            label: 'Best Channel',
            icon: Icons.recommend_rounded,
            startColor: AppColors.purple,
            endColor: const Color(0xFF7C3AED),
            onPressed: () => _showChannelSheet(context, state),
          ),
        ),
      ],
    );
  }

  Widget _buildFab(BuildContext context, ScanState state) {
    return FloatingActionButton.extended(
      heroTag: 'dashFab',
      backgroundColor: AppColors.card,
      icon: Icon(
        state.isScanning ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded,
        color: state.isScanning ? AppColors.rose : AppColors.emerald,
      ),
      label: Text(
        state.isScanning ? 'Stop Service' : 'Run Service',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      ),
      onPressed: () {
        if (state.isScanning) {
          context.read<ScanCubit>().stopScan();
        } else {
          context.read<ScanCubit>().startScan();
        }
      },
    );
  }

  void _showChannelSheet(BuildContext context, ScanState state) {
    final channelState = context.read<ChannelCubit>().state;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.recommend_rounded, color: AppColors.purple, size: 22),
                const SizedBox(width: 10),
                Text('Top Channel Recommendations', style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
            const SizedBox(height: 20),
            if (channelState.bestChannel == null)
              const Text('No data available. Go to Channels tab to fetch recommendations.')
            else ...[
              _ChannelRankRow(
                rank: 1,
                channel: channelState.bestChannel!,
                score: (100 - (channelState.congestionScores[channelState.bestChannel!] ?? 0)).clamp(0, 100).toInt(),
              ),
              if (channelState.reasoning.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(channelState.reasoning, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.emerald)),
              ]
            ],
            const SizedBox(height: 16),
            GlassCard(
              borderColor: AppColors.amberDim,
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.amber, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'To change your channel, open your router admin at 192.168.1.1 or 192.168.0.1 and look for Wireless Settings.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _ChannelRankRow extends StatelessWidget {
  final int rank;
  final int channel;
  final int score;
  const _ChannelRankRow({required this.rank, required this.channel, required this.score});

  Color get _rankColor {
    if (rank == 1) return AppColors.emerald;
    if (rank == 2) return AppColors.amber;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: _rankColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: TextStyle(color: _rankColor, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('Channel $channel', style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / 100,
                backgroundColor: AppColors.cardBorder,
                color: _rankColor,
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$score%', style: TextStyle(color: _rankColor, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _RadarCard extends StatelessWidget {
  final ScanState state;
  const _RadarCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final nets5 = state.networks.where((n) => n.is5GHz).length;
    final nets24 = state.networks.where((n) => !n.is5GHz).length;

    return GlassCard(
      glowing: state.isScanning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded, color: AppColors.cyan, size: 20),
              const SizedBox(width: 8),
              Text('Network Radar', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              if (state.isScanning)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldDim,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      ScanDot(active: true),
                      const SizedBox(width: 5),
                      const Text('LIVE', style: TextStyle(color: AppColors.emerald, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatChip(label: 'Total APs', value: '${state.networks.length}', icon: Icons.wifi_rounded, color: AppColors.cyan),
              const SizedBox(width: 10),
              _StatChip(label: '2.4 GHz', value: '$nets24', icon: Icons.signal_wifi_4_bar_rounded, color: AppColors.emerald),
              const SizedBox(width: 10),
              _StatChip(label: '5 GHz', value: '$nets5', icon: Icons.signal_wifi_statusbar_4_bar_rounded, color: AppColors.purple),
            ],
          ),
          if (state.bestChannel != null) ...[
            const SizedBox(height: 16),
            CyanPill(
              label: 'Best 2.4 GHz Channel:',
              value: 'Ch ${state.bestChannel}',
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _HealthScoreCard extends StatelessWidget {
  final ScanState scanState;
  const _HealthScoreCard({required this.scanState});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChannelCubit, ChannelState>(
      builder: (context, channelState) {
        return BlocBuilder<SecurityCubit, SecurityState>(
          builder: (context, securityState) {
            final ownNet = scanState.networks.where((n) => n.isOwn).firstOrNull;
            if (ownNet == null) return const SizedBox(); // Wait for user to mark a network as own

            int score = 100;
            List<String> suggestions = [];

            // 1. Signal Coverage
            if (ownNet.rssi < -75) {
              score -= 30;
              suggestions.add('Signal is weak. Move closer or reposition router.');
            } else if (ownNet.rssi < -60) {
              score -= 10;
              suggestions.add('Signal is fair. Minor optimizations possible.');
            }

            // 2. Congestion & Channel
            final bestCh = channelState.bestChannel;
            if (bestCh != null && ownNet.channel != bestCh) {
              score -= 20;
              suggestions.add('Change channel to $bestCh to reduce interference.');
            }

            // 3. Security
            final isVulnerable = securityState.advice.any((a) =>
                a['bssid'] == ownNet.bssid &&
                (a['risk_level'] == 'CRITICAL' || a['risk_level'] == 'HIGH'));
            if (isVulnerable) {
              score -= 40;
              suggestions.add('URGENT: Upgrade security to WPA2/WPA3.');
            } else if (ownNet.security == 'WEP' || ownNet.security == 'Open') {
              score -= 40;
              suggestions.add('URGENT: Network is unsecured. Enable WPA2/WPA3.');
            }

            score = score.clamp(0, 100);
            Color color = AppColors.emerald;
            String status = 'Excellent';
            if (score < 50) { color = AppColors.rose; status = 'Critical'; }
            else if (score < 80) { color = AppColors.amber; status = 'Fair'; }

            return GlassCard(
              borderColor: color.withOpacity(0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.health_and_safety_rounded, color: AppColors.cyan, size: 20),
                      const SizedBox(width: 8),
                      Text('Network Health', style: Theme.of(context).textTheme.headlineMedium),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        width: 64, height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(value: score / 100, backgroundColor: AppColors.cardBorder, color: color, strokeWidth: 6),
                            Text('$score', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Auto-Optimization', style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, color: AppColors.cyan)),
                            const SizedBox(height: 6),
                            if (suggestions.isEmpty)
                              const Text('Your network is perfectly optimized!', style: TextStyle(color: AppColors.emerald, fontSize: 12))
                            else
                              ...suggestions.map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.arrow_right_rounded, color: AppColors.cyan, size: 16),
                                    Expanded(child: Text(s, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                                  ],
                                ),
                              )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool scanning;
  const _EmptyState({required this.scanning});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 64)
              .animate(onPlay: (c) => c.repeat())
              .then(delay: 1000.ms)
              .fadeOut(duration: 600.ms)
              .then()
              .fadeIn(duration: 600.ms),
          const SizedBox(height: 16),
          Text(
            scanning ? 'Scanning…' : 'No networks found',
            style: Theme.of(context).textTheme.headlineMedium!.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            scanning ? 'Looking for nearby WiFi networks' : 'Tap "Start Scan" to discover networks',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final WifiNetwork network;
  final int index;
  const _NetworkCard({required this.network, required this.index});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      glowing: network.isOwn,
      glowColor: AppColors.emerald,
      borderColor: network.isOwn ? AppColors.emerald.withOpacity(0.4) : null,
      onTap: () => _showDetail(context),
      child: Row(
        children: [
          SignalBars(rssi: network.rssi, height: 24, width: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        network.displaySsid,
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (network.isOwn)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldDim,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('MINE', style: TextStyle(color: AppColors.emerald, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  network.bssid,
                  style: GoogleFonts.sourceCodePro(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SecurityBadge(tag: network.securityTag, classification: network.security),
                    const SizedBox(width: 6),
                    ChannelChip(channel: network.channel, is5GHz: network.is5GHz),
                    const Spacer(),
                    Text(
                      '${network.rssi} dBm',
                      style: TextStyle(
                        color: AppColors.signalColor(network.rssi),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
        ],
      ),
    ).animate(delay: (index * 40).ms).fadeIn(duration: 300.ms).slideX(begin: 0.05, end: 0);
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(network.displaySsid, style: Theme.of(context).textTheme.displayMedium),
                ),
                SecurityBadge(tag: network.securityTag, classification: network.security),
              ],
            ),
            const SizedBox(height: 20),
            _DetailRow(label: 'BSSID', value: network.bssid, mono: true),
            _DetailRow(label: 'Signal', value: '${network.rssi} dBm (${(network.signalQuality * 100).toInt()}%)'),
            _DetailRow(label: 'Frequency', value: '${network.frequency} MHz (${network.is5GHz ? "5 GHz" : "2.4 GHz"})'),
            _DetailRow(label: 'Channel', value: '${network.channel}'),
            _DetailRow(label: 'Security', value: network.security),
            _DetailRow(label: 'Capabilities', value: network.capabilities.isEmpty ? 'N/A' : network.capabilities, mono: true),
            _DetailRow(label: 'Vendor', value: network.vendor.isEmpty ? 'Unknown' : network.vendor),
            _DetailRow(label: 'Last Seen', value: _fmtDateTime(network.timestamp)),
            const SizedBox(height: 20),
            SignalBars(rssi: network.rssi, height: 32, width: 48),
          ],
        ),
      ),
    );
  }

  String _fmtDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _DetailRow({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              style: mono
                  ? GoogleFonts.sourceCodePro(color: AppColors.cyan, fontSize: 12)
                  : Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsCard extends StatefulWidget {
  @override
  State<_AnalyticsCard> createState() => _AnalyticsCardState();
}

class _AnalyticsCardState extends State<_AnalyticsCard> {
  int _totalToday = 0;
  int _unknownCount = 0;
  List<Map<String, dynamic>> _history = [];
  final NetworkAnalytics _analytics = NetworkAnalytics(DeviceDb());

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final total = await _analytics.getTodayTotal();
    final unknown = await _analytics.getUnknownCount();
    final history = await _analytics.getHistoricalData();
    if (mounted) {
      setState(() {
        _totalToday = total;
        _unknownCount = unknown;
        _history = history.reversed.toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DeviceCubit, DeviceState>(
      listener: (context, state) {
        if (state is DeviceLoaded) _loadAnalytics();
      },
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_rounded, color: AppColors.purple, size: 20),
                const SizedBox(width: 8),
                Text('Device Analytics', style: Theme.of(context).textTheme.headlineMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_totalToday', style: const TextStyle(color: AppColors.purple, fontSize: 24, fontWeight: FontWeight.bold)),
                      const Text('Total Today', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      const SizedBox(height: 8),
                      Text('$_unknownCount', style: const TextStyle(color: AppColors.rose, fontSize: 24, fontWeight: FontWeight.bold)),
                      const Text('Unknown', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 80,
                    child: _history.isEmpty 
                        ? const Center(child: Text('No historical data', style: TextStyle(color: AppColors.textMuted, fontSize: 10)))
                        : LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              minX: 0,
                              maxX: (_history.length - 1).toDouble(),
                              minY: 0,
                              maxY: (_history.map((e) => e['count'] as int).reduce((a, b) => a > b ? a : b) + 5).toDouble(),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _history.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value['count'] as int).toDouble())).toList(),
                                  isCurved: true,
                                  color: AppColors.purple,
                                  barWidth: 3,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: AppColors.purple.withOpacity(0.2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
