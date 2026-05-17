import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../blocs/scan/scan_cubit.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';

/// Permission request screen shown before scanning starts
class PermissionGateWidget extends StatefulWidget {
  final Widget child;
  const PermissionGateWidget({super.key, required this.child});

  @override
  State<PermissionGateWidget> createState() => _PermissionGateWidgetState();
}

class _PermissionGateWidgetState extends State<PermissionGateWidget> {
  bool _checked = false;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final loc = await Permission.location.isGranted;
    setState(() {
      _granted = loc;
      _checked = true;
    });
  }

  Future<void> _request() async {
    final statuses = await [
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();
    final granted = statuses.values.any((s) => s.isGranted);
    setState(() => _granted = granted);
    if (granted && mounted) {
      context.read<ScanCubit>().startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    if (_granted) return widget.child;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cyan.withOpacity(0.08),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                ),
                child: const Icon(Icons.location_on_rounded, color: AppColors.cyan, size: 56),
              ).animate().scale(begin: const Offset(0.5, 0.5), end: const Offset(1, 1), duration: 500.ms, curve: Curves.elasticOut),
              const SizedBox(height: 32),
              Text(
                'Location Permission Required',
                style: Theme.of(context).textTheme.displayMedium,
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 16),
              Text(
                'Android requires Location permission to scan for nearby WiFi networks. SignalSight never uses your GPS location — it only uses this permission to see network names.',
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.6),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 350.ms),
              const SizedBox(height: 40),
              GradientButton(
                label: 'Grant Permission',
                icon: Icons.check_circle_rounded,
                onPressed: _request,
              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.3, end: 0),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text(
                  'Open App Settings',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ).animate().fadeIn(delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}
