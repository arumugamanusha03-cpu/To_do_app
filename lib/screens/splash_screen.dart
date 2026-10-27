import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../widgets/gradient_background.dart';
import 'auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        glowOpacity: .5,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) => Transform.scale(
                  scale: 0.95 + (_controller.value * .08),
                  child: child,
                ),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    color: AppColors.glass,
                    border: Border.all(color: AppColors.glassBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.glowPink,
                        blurRadius: 40,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 72,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              ShaderMask(
                shaderCallback: (rect) =>
                    AppColors.primaryGradient.createShader(rect),
                child: const Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                AppConstants.appTagline,
                style: TextStyle(color: AppColors.grey, fontSize: 16),
              ),

              const SizedBox(height: 60),

              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: AppColors.progressBg,
                    valueColor: AlwaysStoppedAnimation(AppColors.pink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
