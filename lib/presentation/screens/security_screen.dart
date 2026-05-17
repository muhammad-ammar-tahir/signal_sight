import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../blocs/security/security_cubit.dart';
import '../blocs/scan/scan_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAudit();
    });
  }

  void _runAudit() {
    // Feed the latest scanned networks to the cubit so offline classification works
    final scanState = context.read<ScanCubit>().state;
    if (scanState.networks.isNotEmpty) {
      context.read<SecurityCubit>().runAuditOnNetworks(scanState.networks);
    } else {
      context.read<SecurityCubit>().runAudit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SecurityCubit, SecurityState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Security Audit'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GradientButton(
                  label: 'Run Audit',
                  icon: Icons.security_rounded,
                  startColor: AppColors.purple,
                  endColor: const Color(0xFF7C3AED),
                  onPressed: _runAudit,
                ),
              ),
            ],
          ),
          body: _buildBody(context, state),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, SecurityState state) {
    if (state.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.purple),
            SizedBox(height: 16),
            Text('Analyzing security…',
                style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.rose, size: 56),
              const SizedBox(height: 16),
              Text('Audit Error',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium!
                      .copyWith(color: AppColors.rose)),
              const SizedBox(height: 8),
              Text(state.error!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              GradientButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: _runAudit,
              ),
            ],
          ),
        ),
      );
    }

    if (state.overallStatus == 'NO_DATA' || state.advice.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: AppColors.textMuted, size: 64),
              const SizedBox(height: 16),
              Text('No networks scanned. Pull to refresh first.',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium!
                      .copyWith(color: AppColors.textMuted, fontSize: 16)),
              const SizedBox(height: 24),
              GradientButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                onPressed: _runAudit,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ScoreBanner(
          score: state.score ?? 0,
          status: state.overallStatus ?? 'UNKNOWN',
        ).animate().fadeIn(duration: 400.ms),
        const SizedBox(height: 20),
        SectionHeader(title: 'Network Risk Assessment (${state.advice.length})'),
        const SizedBox(height: 12),
        ...state.advice.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SecurityAdviceCard(
                  advice: e.value,
                  index: e.key,
                ),
              ),
            ),
      ],
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  final int score;
  final String status;
  const _ScoreBanner({required this.score, required this.status});

  Color get _color {
    if (status == 'SECURE') return AppColors.emerald;
    if (status == 'CAUTION') return AppColors.amber;
    return AppColors.rose;
  }

  String get _label {
    if (status == 'SECURE') return 'SECURE';
    if (status == 'CAUTION') return 'CAUTION';
    if (status == 'NO_DATA') return 'NO DATA';
    return 'CRITICAL';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: score / 100,
                  backgroundColor: AppColors.cardBorder,
                  color: _color,
                  strokeWidth: 6,
                ),
              ),
              Text(
                '$score',
                style: TextStyle(
                    color: _color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overall Security',
                    style: Theme.of(context).textTheme.bodySmall),
                Text(
                  _label,
                  style: TextStyle(
                      color: _color,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 80
                      ? 'Your networks are well protected.'
                      : score >= 50
                          ? 'Some networks need attention.'
                          : 'Immediate action required!',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: _color.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityAdviceCard extends StatefulWidget {
  final Map<String, dynamic> advice;
  final int index;
  const _SecurityAdviceCard({required this.advice, required this.index});

  @override
  State<_SecurityAdviceCard> createState() => _SecurityAdviceCardState();
}

class _SecurityAdviceCardState extends State<_SecurityAdviceCard> {
  bool _expanded = false;

  Color get _color {
    final risk = widget.advice['risk_level'] as String? ?? 'LOW';
    switch (risk) {
      case 'LOW':
        return AppColors.emerald;
      case 'MEDIUM':
        return AppColors.amber;
      case 'HIGH':
        return AppColors.rose;
      case 'CRITICAL':
        return AppColors.rose;
      default:
        return AppColors.textMuted;
    }
  }

  IconData get _icon {
    final risk = widget.advice['risk_level'] as String? ?? 'LOW';
    switch (risk) {
      case 'LOW':
        return Icons.lock_rounded;
      case 'MEDIUM':
        return Icons.lock_open_rounded;
      default:
        return Icons.no_encryption_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ssid = widget.advice['ssid'] as String? ?? '';
    final bssid = widget.advice['bssid'] as String? ?? '';
    final protocol = widget.advice['protocol'] as String? ?? '';
    final riskLevel = widget.advice['risk_level'] as String? ?? '';
    final recommendation = widget.advice['recommendation'] as String? ?? '';

    return GlassCard(
      borderColor: _color.withOpacity(0.2),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: _color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ssid.isEmpty ? '<Hidden Network>' : ssid,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge!
                          .copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bssid,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                    Text(
                      protocol,
                      style: TextStyle(
                          color: _color,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _color.withOpacity(0.3)),
                    ),
                    child: Text(
                      riskLevel,
                      style: TextStyle(
                          color: _color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 14),
            Divider(color: _color.withOpacity(0.2), height: 1),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: _color, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recommendation,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate(delay: (widget.index * 50).ms).fadeIn(duration: 300.ms).slideX(begin: 0.05, end: 0);
  }
}
