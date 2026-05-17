import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../blocs/scan/scan_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dashboard_screen.dart';
import 'heatmap_screen.dart';
import 'ar_view_screen.dart';
import 'devices_screen.dart';
import 'advisor_screen.dart';
import '../widgets/permission_gate.dart';
import '../../core/theme/app_theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _screens = [
    DashboardScreen(),
    HeatmapScreen(),
    ArViewScreen(),
    DevicesScreen(),
    AdvisorScreen(),
  ];

  static const _labels = ['Dashboard', 'Heatmap', 'AR View', 'Devices', 'Advisor'];

  static const _icons = [
    Icons.dashboard_rounded,
    Icons.map_rounded,
    Icons.view_in_ar_rounded,
    Icons.devices_rounded,
    Icons.psychology_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return PermissionGateWidget(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(
          index: _tab,
          children: _screens,
        ),
        bottomNavigationBar: _CyberpunkNavBar(
          currentIndex: _tab,
          labels: _labels,
          icons: _icons,
          onTap: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

class _CyberpunkNavBar extends StatelessWidget {
  final int currentIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onTap;

  const _CyberpunkNavBar({
    required this.currentIndex,
    required this.labels,
    required this.icons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: List.generate(icons.length, (i) {
              final isActive = i == currentIndex;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.cyanDim : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          icons[i],
                          color: isActive ? AppColors.cyan : AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        labels[i],
                        style: TextStyle(
                          color: isActive ? AppColors.cyan : AppColors.textMuted,
                          fontSize: 9.5,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
