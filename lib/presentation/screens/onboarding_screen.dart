import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/common_widgets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.wifi_tethering_rounded,
      color: AppColors.cyan,
      title: 'Smart WiFi Intelligence',
      body: 'SignalSight scans all nearby networks in real-time, shows signal strength, security status, and recommends the best channel — all without root access.',
    ),
    _Slide(
      icon: Icons.map_rounded,
      color: AppColors.emerald,
      title: 'Indoor Signal Heatmap',
      body: 'Walk around your home and SignalSight uses your phone\'s step detector to map WiFi signal strength across every room automatically.',
    ),
    _Slide(
      icon: Icons.security_rounded,
      color: AppColors.amber,
      title: 'Security Audit',
      body: 'Instantly identify open or weakly-encrypted networks near you. Get plain-English advice on how to secure your own router.',
    ),
    _Slide(
      icon: Icons.psychology_rounded,
      color: AppColors.purple,
      title: 'AI Placement Advisor',
      body: 'Draw your floor plan, add walls, and our ITU propagation model shows you exactly where to place your router for maximum coverage.',
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefOnboardingDone, true);
    if (mounted) Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip', style: TextStyle(color: AppColors.textMuted)),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _OnboardingPage(slide: _slides[i], pageIndex: i),
              ),
            ),
            // Dots + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Row(
                children: [
                  // Dots
                  Row(
                    children: List.generate(_slides.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.cyan : AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )),
                  ),
                  const Spacer(),
                  // Next / Get Started
                  GradientButton(
                    label: _page == _slides.length - 1 ? 'Get Started' : 'Next',
                    icon: _page == _slides.length - 1 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                    onPressed: () {
                      if (_page == _slides.length - 1) {
                        _finish();
                      } else {
                        _ctrl.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Slide({required this.icon, required this.color, required this.title, required this.body});
}

class _OnboardingPage extends StatelessWidget {
  final _Slide slide;
  final int pageIndex;
  const _OnboardingPage({required this.slide, required this.pageIndex});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slide.color.withOpacity(0.08),
              border: Border.all(color: slide.color.withOpacity(0.2), width: 2),
              boxShadow: [BoxShadow(color: slide.color.withOpacity(0.2), blurRadius: 40, spreadRadius: 10)],
            ),
            child: Icon(slide.icon, color: slide.color, size: 64),
          ).animate(key: ValueKey(pageIndex)).scale(begin: const Offset(0.6, 0.6), end: const Offset(1, 1), duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: 40),
          Text(
            slide.title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ).animate(key: ValueKey('t$pageIndex')).fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
          const SizedBox(height: 16),
          Text(
            slide.body,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(height: 1.6),
            textAlign: TextAlign.center,
          ).animate(key: ValueKey('b$pageIndex')).fadeIn(delay: 350.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }
}
