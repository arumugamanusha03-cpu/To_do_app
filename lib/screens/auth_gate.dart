import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';
import 'main_shell.dart';

/// Decides between the login screen and the app itself, and keeps doing so —
/// signing out anywhere in the app lands back on login automatically.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: AuthService.authState,
      builder: (context, user, _) {
        if (user == null) return const LoginScreen();
        return _SignedInApp(userId: user.userId);
      },
    );
  }
}

/// Runs the one-time per-account setup (adopting pre-login tasks, rebuilding
/// reminders) before showing the main shell.
class _SignedInApp extends StatefulWidget {
  final String userId;

  const _SignedInApp({required this.userId});

  @override
  State<_SignedInApp> createState() => _SignedInAppState();
}

class _SignedInAppState extends State<_SignedInApp> {
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(_SignedInApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _prepare();
  }

  Future<void> _prepare() async {
    final db = DatabaseHelper.instance;

    await db.claimOrphanTasks(widget.userId);

    // Reminders live in the OS, not the database, so they are rebuilt on
    // every sign-in (a reinstall or a reboot clears them).
    final pending = await db.getPendingReminders(widget.userId);
    await NotificationService.rescheduleAll(pending);
  }

  @override
  Widget build(BuildContext context) => const MainShell();
}
