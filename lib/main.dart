import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/shared_pref_service.dart';
import 'utils/app_theme.dart';
import 'utils/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SharedPrefService.init();

  // Puts the user straight back into the app if they were signed in.
  await AuthService.restoreSession();

  // Notification setup must never block startup.
  try {
    await NotificationService.init();
  } catch (error) {
    debugPrint('Notification setup skipped: $error');
  }

  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const SplashScreen(),
    );
  }
}
