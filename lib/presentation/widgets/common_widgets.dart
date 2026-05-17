import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';

/// Glassmorphism card
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double borderRadius;
  final bool glowing;
  final Color glowColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.borderRadius = 16,
    this.glowing = false,
    this.glowColor = AppColors.cyan,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? (glowing ? glowColor.withOpacity(0.5) : AppColors.cardBorder),
          width: glowing ? 1.5 : 1,
        ),
        boxShadow: glowing
            ? [BoxShadow(color: glowColor.withOpacity(0.2), blurRadius: 20, spreadRadius: 2)]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          splashColor: AppColors.cyan.withOpacity(0.08),
          highlightColor: AppColors.cyan.withOpacity(0.04),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Animated scanning status dot
class ScanDot extends StatelessWidget {
  final bool active;
  const ScanDot({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.emerald : AppColors.rose;
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
      ),
    ).animate(onPlay: (c) => c.repeat())
        .scale(begin: const Offset(1, 1), end: const Offset(1.4, 1.4), duration: 800.ms, curve: Curves.easeInOut)
        .then()
        .scale(begin: const Offset(1.4, 1.4), end: const Offset(1, 1), duration: 800.ms, curve: Curves.easeInOut);
  }
}

/// Animated RSSI signal bars
class SignalBars extends StatelessWidget {
  final int rssi;
  final double height;
  final double width;

  const SignalBars({super.key, required this.rssi, this.height = 20, this.width = 24});

  @override
  Widget build(BuildContext context) {
    final quality = ((rssi + 100).clamp(0, 50)) / 50.0;
    final filledBars = (quality * 4).round().clamp(0, 4);
    final color = AppColors.signalColor(rssi);

    return SizedBox(
      width: width, height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final barHeight = height * (0.25 + i * 0.25);
          final filled = i < filledBars;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: barHeight,
                decoration: BoxDecoration(
                  color: filled ? color : AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Security badge chip
class SecurityBadge extends StatelessWidget {
  final String tag;
  final String classification;

  const SecurityBadge({super.key, required this.tag, required this.classification});

  Color get _color {
    switch (classification) {
      case 'Strong': return AppColors.emerald;
      case 'Caution': return AppColors.amber;
      case 'Weak': return AppColors.rose;
      case 'Open': return AppColors.rose;
      default: return AppColors.textMuted;
    }
  }

  IconData get _icon {
    switch (classification) {
      case 'Strong': return Icons.lock_rounded;
      case 'Caution': return Icons.lock_open_rounded;
      case 'Weak': return Icons.lock_open_rounded;
      case 'Open': return Icons.no_encryption_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, color: _color, size: 11),
          const SizedBox(width: 4),
          Text(
            tag,
            style: TextStyle(
              color: _color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Channel chip
class ChannelChip extends StatelessWidget {
  final int channel;
  final bool is5GHz;

  const ChannelChip({super.key, required this.channel, required this.is5GHz});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (is5GHz ? AppColors.purple : AppColors.cyan).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (is5GHz ? AppColors.purple : AppColors.cyan).withOpacity(0.3),
        ),
      ),
      child: Text(
        'Ch $channel',
        style: TextStyle(
          color: is5GHz ? AppColors.purple : AppColors.cyan,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Cyan pill badge (large)
class CyanPill extends StatelessWidget {
  final String label;
  final String? value;

  const CyanPill({super.key, required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cyanDim,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cyanGlow),
        boxShadow: [
          BoxShadow(color: AppColors.cyan.withOpacity(0.15), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Text(
              value!,
              style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Gradient button
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color startColor;
  final Color endColor;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.startColor = AppColors.cyan,
    this.endColor = const Color(0xFF0099CC),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [startColor, endColor]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: startColor.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: AppColors.background, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.background,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Particle background painter
class ParticleBackground extends StatefulWidget {
  final bool active;
  final Widget child;
  const ParticleBackground({super.key, required this.active, required this.child});

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.active)
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _ParticlePainter(_ctrl.value),
              child: const SizedBox.expand(),
            ),
          ),
        widget.child,
      ],
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final double t;
  _ParticlePainter(this.t);

  static final _particles = List.generate(20, (i) => (
    x: (i * 0.137) % 1.0,
    y: (i * 0.241) % 1.0,
    speed: 0.3 + (i % 5) * 0.1,
    size: 1.0 + (i % 3) * 0.5,
  ));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.cyan.withOpacity(0.15);
    for (final p in _particles) {
      final y = ((p.y + t * p.speed) % 1.0) * size.height;
      final x = p.x * size.width;
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}
