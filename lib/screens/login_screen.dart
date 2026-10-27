import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/shared_pref_service.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/gradient_background.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scale = Tween<double>(begin: .95, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
    _restoreSavedEmail();
  }

  Future<void> _restoreSavedEmail() async {
    final remember = await SharedPrefService.getRememberMe();
    if (!remember || !mounted) return;

    final email = await SharedPrefService.getSavedEmail();
    if (!mounted) return;

    setState(() {
      _rememberMe = true;
      _emailController.text = email;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ===========================
  // ACTIONS
  // ===========================

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );

      await SharedPrefService.saveLoginPreference(
        rememberMe: _rememberMe,
        email: _emailController.text.trim(),
      );

      // AuthGate swaps this screen out when the auth state changes.
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong: $error';
      });
    }
  }

  /// There is no server and no email, so a forgotten password cannot be
  /// reset — saying so plainly beats a button that quietly does nothing.
  Future<void> _forgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot your password?'),
        content: const Text(
          'Accounts in TaskFlow live only on this device, so there is no '
          'email reset link to send.\n\n'
          'If you are still signed in on this phone you can change your '
          'password from Settings. Otherwise you will need to create a new '
          'account — the tasks saved under the old one stay on the device '
          'but will not be visible from the new account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Got it',
              style: TextStyle(
                color: AppColors.pink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================
  // UI
  // ===========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        glowOpacity: .45,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.purple.withValues(alpha: .25),
                              blurRadius: 35,
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _logo(),
                              const SizedBox(height: 28),

                              ShaderMask(
                                shaderCallback: (rect) => AppColors
                                    .primaryGradient
                                    .createShader(rect),
                                child: const Text(
                                  'Welcome Back',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              const Text(
                                'Sign in to pick up where you left off.',
                                style: TextStyle(
                                  color: AppColors.grey,
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                              ),

                              const SizedBox(height: 28),

                              CustomTextField(
                                controller: _emailController,
                                hintText: 'Email address',
                                prefixIcon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: AuthService.validateEmail,
                              ),

                              const SizedBox(height: 18),

                              CustomTextField(
                                controller: _passwordController,
                                hintText: 'Password',
                                prefixIcon: Icons.lock_outline_rounded,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _login(),
                                validator: AuthService.validatePassword,
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _obscurePassword =
                                        !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 6),

                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    activeColor: AppColors.pink,
                                    side: const BorderSide(
                                      color: Colors.white54,
                                    ),
                                    onChanged: (value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                                  ),
                                  const Text(
                                    'Remember me',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed:
                                        _busy ? null : _forgotPassword,
                                    child: const Text(
                                      'Forgot?',
                                      style: TextStyle(
                                        color: AppColors.blue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              if (_error != null) ...[
                                const SizedBox(height: 8),
                                _errorBox(_error!),
                              ],

                              const SizedBox(height: 20),

                              CustomButton(
                                text: 'LOGIN',
                                loading: _busy,
                                onPressed: _busy ? null : _login,
                              ),

                              const SizedBox(height: 24),

                              Center(
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      "Don't have an account? ",
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 15,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _busy
                                          ? null
                                          : () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const SignupScreen(),
                                                ),
                                              ),
                                      child: const Text(
                                        'Create account',
                                        style: TextStyle(
                                          color: AppColors.pink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.phonelink_lock_outlined,
                                    size: 15,
                                    color: Colors.white38,
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      'Your account and tasks stay on this '
                                      'device',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: .38,
                                        ),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 14),

                              const Center(
                                child: Text(
                                  '${AppConstants.appName} '
                                  'v${AppConstants.appVersion}',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.pink.withValues(alpha: .4),
            blurRadius: 30,
          ),
        ],
      ),
      child: const Icon(
        Icons.task_alt_rounded,
        color: Colors.white,
        size: 34,
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: .4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFB4B4),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
