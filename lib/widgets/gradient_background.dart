import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// The dark gradient plus the three soft glows that every screen sits on.
class GradientBackground extends StatelessWidget {
  final Widget child;

  /// Splash and login use stronger glows than the content screens.
  final double glowOpacity;

  const GradientBackground({
    super.key,
    required this.child,
    this.glowOpacity = .25,
  });

  Widget _glow({
    required double size,
    required Color color,
    required Alignment alignment,
  }) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: glowOpacity),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: Stack(
        children: [
          _glow(
            size: 250,
            color: AppColors.pink,
            alignment: Alignment.topLeft,
          ),
          _glow(
            size: 220,
            color: AppColors.blue,
            alignment: Alignment.bottomRight,
          ),
          _glow(
            size: 180,
            color: AppColors.purple,
            alignment: Alignment.centerRight,
          ),
          child,
        ],
      ),
    );
  }
}

/// Frosted panel used for cards, search fields and list tiles.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: .12),
        ),
      ),
      child: child,
    );

    if (onTap == null) return panel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: panel,
      ),
    );
  }
}
