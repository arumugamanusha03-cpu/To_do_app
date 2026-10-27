import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/shared_pref_service.dart';
import '../services/task_events.dart';
import '../services/voice_input.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';
import '../widgets/gradient_background.dart';
import '../widgets/sort_sheet.dart';
import 'plan_day_sheet.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _notifications = true;
  bool _systemNotificationsAllowed = true;
  TaskSort _sort = TaskSort.dueDate;
  TaskStats _stats = const TaskStats();
  bool _tanglish = false;
  String _voiceLocale = VoiceInput.defaultLocale;
  List<VoiceLocale> _voiceLocales = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    tasksChanged.addListener(_loadStats);
    _load();
  }

  @override
  void dispose() {
    tasksChanged.removeListener(_loadStats);
    super.dispose();
  }

  Future<void> _load() async {
    final notifications = await SharedPrefService.getNotificationsEnabled();
    final allowed = await NotificationService.areEnabled();
    final sort = await SharedPrefService.getSort();
    final tanglish = await SharedPrefService.getTanglish();
    final voiceLocale = await SharedPrefService.getVoiceLocale();
    final voiceLocales = await VoiceInput.availableLocales();

    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _systemNotificationsAllowed = allowed;
      _sort = sort;
      _tanglish = tanglish;
      _voiceLocale = voiceLocale;
      _voiceLocales = voiceLocales;
    });

    await _loadStats();
  }

  Future<void> _setTanglish(bool value) async {
    setState(() => _tanglish = value);
    await SharedPrefService.setTanglish(value);

    // The home greeting is built from this, so it has to rebuild.
    notifyTasksChanged();

    if (!mounted) return;
    _toast(value ? 'Ippo Tanglish-la pesuven 👋' : 'Back to English 👋');
  }

  Future<void> _pickVoiceLocale() async {
    if (_voiceLocales.isEmpty) {
      _toast('No speech languages are installed on this phone');
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Voice language',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Indian English understands Tanglish best — English and '
                  'Tamil words in one sentence.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
            ..._voiceLocales.map(
              (locale) => ListTile(
                onTap: () => Navigator.pop(sheetContext, locale.id),
                leading: Icon(
                  locale.id == _voiceLocale
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: locale.id == _voiceLocale
                      ? AppColors.pink
                      : Colors.white38,
                ),
                title: Text(
                  locale.label,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );

    if (picked == null || !mounted) return;

    await SharedPrefService.setVoiceLocale(picked);
    if (!mounted) return;
    setState(() => _voiceLocale = picked);
  }

  String get _voiceLocaleLabel {
    for (final locale in _voiceLocales) {
      if (locale.id == _voiceLocale) return locale.label;
    }
    return _voiceLocale;
  }

  Future<void> _loadStats() async {
    final userId = AuthService.uid;
    if (userId.isEmpty) return;

    final stats = await DatabaseHelper.instance.getStats(userId);
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  // ===========================
  // ACTIONS
  // ===========================

  Future<void> _setNotifications(bool enabled) async {
    setState(() => _notifications = enabled);
    await SharedPrefService.setNotificationsEnabled(enabled);

    if (enabled) {
      final granted = await NotificationService.requestPermission();

      if (!mounted) return;
      setState(() => _systemNotificationsAllowed = granted);

      if (!granted) {
        _toast('Android is blocking notifications — allow them in system '
            'settings for this app.');
        return;
      }

      // Reminders live in the OS, so turning the switch back on has to
      // recreate every pending one.
      final pending = await DatabaseHelper.instance
          .getPendingReminders(AuthService.uid);
      await NotificationService.rescheduleAll(pending);

      if (!mounted) return;
      _toast('${pending.length} reminder${pending.length == 1 ? '' : 's'} '
          'scheduled');
    } else {
      await NotificationService.cancelAll();
      if (!mounted) return;
      _toast('All reminders turned off');
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: AuthService.displayName);

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your name',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: .06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.pink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name == null || name.isEmpty || !mounted) return;

    try {
      await AuthService.updateDisplayName(name);
      if (!mounted) return;
      setState(() {});
      _toast('Name updated');
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      _toast(failure.message);
    }
  }

  /// Kept short on purpose — the full "On this device since Thursday, 10
  /// September 2026" ran past the edge of the profile card.
  String get _memberSince {
    final created = AuthService.currentUser?.createdAt;
    final date = created == null ? null : DateTime.tryParse(created);
    if (date == null) return 'Stored on this device';
    return 'On this device since ${DateHelper.shortDate(date)} ${date.year}';
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    Widget field(
      TextEditingController controller,
      String hint,
      String? Function(String?) validator,
    ) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          obscureText: true,
          validator: validator,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: .06),
            errorStyle: const TextStyle(color: Color(0xFFFF8A8A)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );
    }

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(
                currentController,
                'Current password',
                (value) => (value ?? '').isEmpty
                    ? 'Enter your current password'
                    : null,
              ),
              field(
                newController,
                'New password',
                AuthService.validatePassword,
              ),
              field(
                confirmController,
                'Confirm new password',
                (value) => value != newController.text
                    ? 'Passwords do not match'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text(
              'Update',
              style: TextStyle(
                color: AppColors.pink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    final current = currentController.text;
    final replacement = newController.text;

    currentController.dispose();
    newController.dispose();
    confirmController.dispose();

    if (submitted != true || !mounted) return;

    try {
      await AuthService.changePassword(
        currentPassword: current,
        newPassword: replacement,
      );
      if (!mounted) return;
      _toast('Password updated');
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      _toast(failure.message);
    }
  }

  Future<void> _pickSort() async {
    final picked = await showSortSheet(context, _sort);
    if (picked == null || !mounted) return;

    await SharedPrefService.setSort(picked);
    if (!mounted) return;
    setState(() => _sort = picked);
    notifyTasksChanged();
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);

    try {
      final count = await BackupService.exportAndShare(
        userId: AuthService.uid,
        accountEmail: AuthService.email,
      );
      if (!mounted) return;
      _toast('$count task${count == 1 ? '' : 's'} exported');
    } on BackupFailure catch (failure) {
      if (!mounted) return;
      _toast(failure.message);
    } catch (error) {
      if (!mounted) return;
      _toast('Could not export: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose a TaskFlow backup',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'Tasks in the file will be added to your list. Nothing is deleted, '
          'and anything you already have is skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Restore',
              style: TextStyle(
                color: AppColors.pink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final summary = await BackupService.importFromFile(
        path: path,
        userId: AuthService.uid,
      );

      notifyTasksChanged();
      if (!mounted) return;

      _toast(
        summary.imported == 0
            ? 'Nothing new to restore — all ${summary.total} tasks were '
                'already here'
            : '${summary.imported} task'
                '${summary.imported == 1 ? '' : 's'} restored'
                '${summary.skipped > 0 ? ' • ${summary.skipped} skipped' : ''}',
      );
    } on BackupFailure catch (failure) {
      if (!mounted) return;
      _toast(failure.message);
    } catch (error) {
      if (!mounted) return;
      _toast('Could not restore: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearCompleted() async {
    if (_stats.completed == 0) {
      _toast('No completed tasks to clear');
      return;
    }

    final confirmed = await _confirm(
      title: 'Clear completed tasks?',
      message:
          '${_stats.completed} completed task'
          '${_stats.completed == 1 ? '' : 's'} will be deleted permanently.',
      confirmLabel: 'Clear',
    );

    if (confirmed != true) return;

    final removed =
        await DatabaseHelper.instance.deleteCompleted(AuthService.uid);
    notifyTasksChanged();

    if (!mounted) return;
    _toast('$removed task${removed == 1 ? '' : 's'} cleared');
  }

  Future<void> _deleteAll() async {
    if (_stats.total == 0) {
      _toast('There is nothing to delete');
      return;
    }

    final confirmed = await _confirm(
      title: 'Delete every task?',
      message: _stats.total == 1
          ? 'Your task and its reminder will be removed. This cannot be '
              'undone — export a backup first if you might want it back.'
          : 'All ${_stats.total} tasks and their reminders will be removed. '
              'This cannot be undone — export a backup first if you might '
              'want them back.',
      confirmLabel: 'Delete all',
    );

    if (confirmed != true) return;

    await NotificationService.cancelAll();
    final removed =
        await DatabaseHelper.instance.deleteAllForUser(AuthService.uid);
    notifyTasksChanged();

    if (!mounted) return;
    _toast('$removed task${removed == 1 ? '' : 's'} deleted');
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: 'Sign out?',
      message:
          'Your tasks stay on this device and come back when you sign in '
          'again.',
      confirmLabel: 'Sign out',
    );

    if (confirmed != true) return;

    setState(() => _busy = true);

    // Reminders are per-account, so they go with the session.
    await NotificationService.cancelAll();
    await SharedPrefService.clearSession();
    await AuthService.signOut();

    // AuthGate reacts to the auth change and shows the login screen.
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================
  // UI
  // ===========================

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(height: 20),

        _profileCard(),

        const SizedBox(height: 28),

        _sectionTitle('Account'),
        const SizedBox(height: 16),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.badge_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Your name',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  AuthService.displayName,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: _editName,
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.password_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Change password',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Needs your current password',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: _changePassword,
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        _sectionTitle('Preferences'),
        const SizedBox(height: 16),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(
                  Icons.notifications_active_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Task reminders',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _notifications
                      ? (_systemNotificationsAllowed
                          ? 'Notify me at each task\'s time'
                          : 'Blocked by Android — tap to allow')
                      : 'Reminders are off',
                  style: TextStyle(
                    color: _notifications && !_systemNotificationsAllowed
                        ? Colors.orangeAccent
                        : Colors.white60,
                    fontSize: 13,
                  ),
                ),
                value: _notifications,
                activeThumbColor: AppColors.pink,
                onChanged: _busy ? null : _setNotifications,
              ),

              const Divider(color: Colors.white12, height: 1),

              ListTile(
                leading: const Icon(Icons.sort_rounded, color: Colors.white),
                title: const Text(
                  'Default sort',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _sort.label,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: _pickSort,
              ),

              const Divider(color: Colors.white12, height: 1),

              SwitchListTile(
                secondary: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Talk to me in Tanglish',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _tanglish
                      ? 'Hi Anusha 👋 innaikku 3 task irukku…'
                      : 'Greetings and nudges in Tamil + English',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
                value: _tanglish,
                activeThumbColor: AppColors.pink,
                onChanged: _busy ? null : _setTanglish,
              ),

              const Divider(color: Colors.white12, height: 1),

              ListTile(
                leading: const Icon(
                  Icons.mic_none_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Voice language',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _voiceLocales.isEmpty
                      ? 'No speech languages installed'
                      : _voiceLocaleLabel,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: _pickVoiceLocale,
              ),

              const Divider(color: Colors.white12, height: 1),

              ListTile(
                leading: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Send a test notification',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Check that reminders reach you',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                onTap: () async {
                  await NotificationService.requestPermission();
                  await NotificationService.showTestNotification();
                  if (!mounted) return;
                  _toast('Test notification sent');
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        _sectionTitle('Back up & Restore'),
        const SizedBox(height: 8),
        const Text(
          'Your tasks live only on this phone. Export a backup before you '
          'uninstall the app or move to a new device.',
          style: TextStyle(
            color: AppColors.grey,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                enabled: !_busy,
                leading: const Icon(
                  Icons.ios_share_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Export backup',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Save a .json file to Drive, Files or anywhere else',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: _exportBackup,
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                enabled: !_busy,
                leading: const Icon(
                  Icons.settings_backup_restore_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Restore from backup',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Adds tasks from a file — nothing is deleted',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: _importBackup,
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        _sectionTitle('Your Data'),
        const SizedBox(height: 16),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Stored tasks',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${_stats.total} total • ${_stats.completed} completed',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              ListTile(
                leading: const Icon(
                  Icons.cleaning_services_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Clear completed tasks',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Keep only what is still open',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                onTap: _clearCompleted,
              ),

              const Divider(color: Colors.white12, height: 1),

              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete all tasks',
                  style: TextStyle(color: Colors.redAccent),
                ),
                subtitle: const Text(
                  'Cannot be undone',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                onTap: _deleteAll,
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        _sectionTitle('About'),
        const SizedBox(height: 16),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.info_outline, color: Colors.white),
                title: const Text(
                  'App version',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  AppConstants.appVersion,
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'AI Assist',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Tap + to write a task the way you would say it. It fills '
                  'in what you leave out from your own habits, can split a '
                  'big task into steps, and can lay out your day. All of it '
                  'runs on this phone — no account, no network, no data '
                  'leaves the device.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                isThreeLine: true,
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.event_note_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Plan my day',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Lay out today\'s open tasks across the rest of the day',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: () => PlanDaySheet.show(context),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _logout,
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            label: const Text(
              'Sign out',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),

        const SizedBox(height: 26),

        Center(
          child: Column(
            children: [
              const Text(
                AppConstants.appName,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Version ${AppConstants.appVersion}',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                'Made with ❤️ using Flutter',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 21,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _profileCard() {
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      radius: 25,
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
            ),
            child: Center(
              child: Text(
                AuthService.initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(width: 18),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AuthService.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AuthService.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Row(
                  children: [
                    const Icon(
                      Icons.phonelink_lock_outlined,
                      size: AppSpacing.iconChip,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    // Flexible + ellipsis: a long date must clip, never
                    // overflow the card.
                    Flexible(
                      child: Text(
                        _memberSince,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // No edit pencil here — Account → Your name does the same job and
          // this card needs the width for the email.
        ],
      ),
    );
  }
}
