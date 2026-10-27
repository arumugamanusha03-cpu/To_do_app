import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/task_model.dart';
import '../utils/constants.dart';
import 'shared_pref_service.dart';

/// Schedules the local reminder that fires at a task's due time.
///
/// Every method is safe to call on any platform — on desktop and web the
/// plugin is simply not initialised and the calls become no-ops, so screens
/// don't need platform checks.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialised = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  // ===========================
  // SETUP
  // ===========================

  static Future<void> init() async {
    if (_initialised || !_supported) return;

    tz_data.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // An unknown IANA name would throw; UTC keeps scheduling working.
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );

    if (_isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              AppConstants.notificationChannelId,
              AppConstants.notificationChannelName,
              description: AppConstants.notificationChannelDescription,
              importance: Importance.high,
            ),
          );
    }

    _initialised = true;
  }

  /// Asks for the runtime notification permission (Android 13+ / iOS).
  /// Returns true when reminders are allowed to show.
  static Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();

    if (_isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      final granted = await android?.requestNotificationsPermission() ?? false;

      // Exact alarms are a separate grant on Android 12+. Without it the
      // reminder still fires, just batched by the system.
      await android?.requestExactAlarmsPermission();

      return granted;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  static Future<bool> areEnabled() async {
    if (!_isAndroid) return _supported;
    return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled() ??
        false;
  }

  // ===========================
  // SCHEDULING
  // ===========================

  static NotificationDetails get _details {
    const android = AndroidNotificationDetails(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      channelDescription: AppConstants.notificationChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return const NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
  }

  /// Schedules (or re-schedules) the reminder for [task].
  ///
  /// Any existing reminder for the same task is cancelled first, so calling
  /// this after an edit is always correct. Tasks that are completed, have the
  /// reminder switch off, or are already due are simply left unscheduled.
  static Future<void> scheduleForTask(TaskModel task) async {
    if (!_supported || task.id == null) return;
    await init();

    await cancelForTask(task.id!);

    if (!task.reminder || task.isCompleted) return;
    if (!await SharedPrefService.getNotificationsEnabled()) return;

    final due = task.dueDateTime;
    if (!due.isAfter(DateTime.now())) return;

    final scheduled = tz.TZDateTime.from(due, tz.local);

    try {
      await _plugin.zonedSchedule(
        id: task.notificationId,
        title: task.title,
        body: task.description.trim().isEmpty
            ? '${task.priority} priority • ${task.displayTime}'
            : task.description.trim(),
        scheduledDate: scheduled,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: task.id.toString(),
      );
    } on PlatformException catch (error) {
      // Thrown when the user denied the exact-alarm permission. Fall back to
      // an inexact reminder rather than losing it altogether.
      debugPrint('Exact alarm unavailable (${error.code}), using inexact.');
      await _plugin.zonedSchedule(
        id: task.notificationId,
        title: task.title,
        body: task.description.trim().isEmpty
            ? '${task.priority} priority • ${task.displayTime}'
            : task.description.trim(),
        scheduledDate: scheduled,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: task.id.toString(),
      );
    }
  }

  static Future<void> cancelForTask(int taskId) async {
    if (!_supported) return;
    await init();
    await _plugin.cancel(id: taskId);
  }

  static Future<void> cancelAll() async {
    if (!_supported) return;
    await init();
    await _plugin.cancelAll();
  }

  /// Rebuilds the whole schedule from the given tasks. Used when the user
  /// toggles notifications back on in Settings.
  static Future<void> rescheduleAll(List<TaskModel> tasks) async {
    if (!_supported) return;
    await cancelAll();
    for (final task in tasks) {
      await scheduleForTask(task);
    }
  }

  /// Fires immediately — the "Test notification" button in Settings.
  static Future<void> showTestNotification() async {
    if (!_supported) return;
    await init();
    await _plugin.show(
      id: 999999,
      title: '${AppConstants.appName} reminders are on',
      body: 'This is how your task reminders will look.',
      notificationDetails: _details,
    );
  }

  static Future<int> pendingCount() async {
    if (!_supported) return 0;
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    return pending.length;
  }
}
