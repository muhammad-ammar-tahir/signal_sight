import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../blocs/settings/settings_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../data/services/database_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                title: 'Scanning',
                icon: Icons.wifi_tethering_rounded,
                children: [
                  _SettingRow(
                    label: 'Scan Interval',
                    subtitle: '${state.scanInterval} seconds between scans',
                    child: SizedBox(
                      width: 160,
                      child: Slider(
                        value: state.scanInterval.toDouble(),
                        min: AppConstants.minScanIntervalSec.toDouble(),
                        max: AppConstants.maxScanIntervalSec.toDouble(),
                        divisions: 19,
                        activeColor: AppColors.cyan,
                        inactiveColor: AppColors.cardBorder,
                        onChanged: (v) => cubit.updateScanInterval(v.toInt()),
                      ),
                    ),
                  ),
                  _SwitchRow(
                    label: 'Background Scanning',
                    subtitle: 'Keep scanning when app is in background',
                    value: state.bgScan,
                    onChanged: (v) => cubit.updateBgScan(v),
                  ),
                ],
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: 16),
              _Section(
                title: 'Alerts',
                icon: Icons.notifications_rounded,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Notification Preference', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                        const Text('Control when you receive device alerts', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: state.notificationPref,
                          dropdownColor: AppColors.card,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.cardBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.cardBorder)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All (Online/Offline & Unknown)')),
                            DropdownMenuItem(value: 'unknown_only', child: Text('Only Unknown Devices')),
                            DropdownMenuItem(value: 'silence', child: Text('Silence All Alerts')),
                          ],
                          onChanged: (v) {
                            if (v != null) cubit.updateNotificationPref(v);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ).animate(delay: 100.ms).fadeIn(duration: 300.ms),
              const SizedBox(height: 16),
              _Section(
                title: 'Heatmap / PDR',
                icon: Icons.map_rounded,
                children: [
                  _SettingRow(
                    label: 'Your Height',
                    subtitle: '${state.userHeight.toStringAsFixed(2)} m (affects stride length)',
                    child: SizedBox(
                      width: 160,
                      child: Slider(
                        value: state.userHeight,
                        min: 1.40,
                        max: 2.10,
                        divisions: 14,
                        activeColor: AppColors.cyan,
                        inactiveColor: AppColors.cardBorder,
                        onChanged: (v) => cubit.updateUserHeight(v),
                      ),
                    ),
                  ),
                ],
              ).animate(delay: 150.ms).fadeIn(duration: 300.ms),
              const SizedBox(height: 16),
              _Section(
                title: 'Appearance',
                icon: Icons.palette_rounded,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Accent Color', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        const Text('Dark mode only. Choose your accent.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _ColorOption(name: 'cyan', color: AppColors.cyan, selected: state.accentColor == 'cyan', onTap: () => cubit.updateAccentColor('cyan')),
                            const SizedBox(width: 12),
                            _ColorOption(name: 'purple', color: AppColors.purple, selected: state.accentColor == 'purple', onTap: () => cubit.updateAccentColor('purple')),
                            const SizedBox(width: 12),
                            _ColorOption(name: 'emerald', color: AppColors.emerald, selected: state.accentColor == 'emerald', onTap: () => cubit.updateAccentColor('emerald')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ).animate(delay: 200.ms).fadeIn(duration: 300.ms),
              const SizedBox(height: 16),
              _Section(
                title: 'Advanced / Data',
                icon: Icons.data_usage_rounded,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Export History', style: TextStyle(color: AppColors.cyan, fontSize: 14)),
                    subtitle: const Text('Export scan history to CSV', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    trailing: const Icon(Icons.download_rounded, color: AppColors.cyan, size: 20),
                    onTap: () async {
                      final csv = await cubit.exportHistory(DatabaseService());
                      final dir = await getTemporaryDirectory();
                      final file = File('${dir.path}/scan_history.csv');
                      await file.writeAsString(csv);
                      await Share.shareXFiles([XFile(file.path)], text: 'SignalSight Scan History');
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Clear Cache', style: TextStyle(color: AppColors.rose, fontSize: 14)),
                    subtitle: const Text('Delete local database', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    trailing: const Icon(Icons.delete_forever_rounded, color: AppColors.rose, size: 20),
                    onTap: () async {
                      await cubit.clearCache(DatabaseService());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared')));
                      }
                    },
                  ),
                ],
              ).animate(delay: 220.ms).fadeIn(duration: 300.ms),
              const SizedBox(height: 16),
              _Section(
                title: 'About',
                icon: Icons.info_outline_rounded,
                children: [
                  _InfoRow(label: 'App', value: 'SignalSight v1.0.0'),
                  _InfoRow(label: 'Target', value: 'Android 11+ (Unrooted)'),
                  _InfoRow(label: 'Features', value: 'WiFi Scan · Heatmap · AR · Devices · AI Advisor'),
                ],
              ).animate(delay: 250.ms).fadeIn(duration: 300.ms),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _Section({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.cyan, size: 18),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(color: AppColors.cardBorder, height: 20),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label, subtitle;
  final Widget child;
  const _SettingRow({required this.label, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              child,
            ],
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.cyan,
            inactiveTrackColor: AppColors.cardBorder,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
      ],
    ),
  );
}

class _ColorOption extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorOption({required this.name, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(selected ? 0.3 : 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: selected ? color : Colors.transparent, width: 3),
        boxShadow: selected ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 12)] : [],
      ),
      child: selected ? Icon(Icons.check_rounded, color: color, size: 20) : null,
    ),
  );
}
