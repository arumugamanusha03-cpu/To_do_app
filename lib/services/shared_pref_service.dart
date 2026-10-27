import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// Small typed wrapper around SharedPreferences so screens never deal with
/// raw string keys.
class SharedPrefService {
  SharedPrefService._();

  static const String _kRememberMe = 'remember_me';
  static const String _kSavedEmail = 'saved_email';
  static const String _kNotifications = 'notifications_enabled';
  static const String _kSort = 'task_sort';
  static const String _kSeenIntro = 'seen_intro';
  static const String _kSignedInUserId = 'signed_in_user_id';
  static const String _kTanglish = 'talk_tanglish';
  static const String _kVoiceLocale = 'voice_locale';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Called once from `main()` so later reads are synchronous-fast.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ===========================
  // LOGIN
  // ===========================

  /// The signed-in account's row id, or null when signed out. This is what
  /// keeps the user logged in across app restarts.
  static Future<int?> getSignedInUserId() async =>
      (await _instance).getInt(_kSignedInUserId);

  static Future<void> setSignedInUserId(int? id) async {
    final prefs = await _instance;
    if (id == null) {
      await prefs.remove(_kSignedInUserId);
    } else {
      await prefs.setInt(_kSignedInUserId, id);
    }
  }

  /// Only controls whether the email is pre-filled on the login form.
  static Future<bool> getRememberMe() async =>
      (await _instance).getBool(_kRememberMe) ?? false;

  static Future<String> getSavedEmail() async =>
      (await _instance).getString(_kSavedEmail) ?? '';

  static Future<void> saveLoginPreference({
    required bool rememberMe,
    required String email,
  }) async {
    final prefs = await _instance;
    await prefs.setBool(_kRememberMe, rememberMe);
    if (rememberMe) {
      await prefs.setString(_kSavedEmail, email);
    } else {
      await prefs.remove(_kSavedEmail);
    }
  }

  // ===========================
  // PREFERENCES
  // ===========================

  static Future<bool> getNotificationsEnabled() async =>
      (await _instance).getBool(_kNotifications) ?? true;

  static Future<void> setNotificationsEnabled(bool value) async =>
      (await _instance).setBool(_kNotifications, value);

  static Future<TaskSort> getSort() async {
    final index = (await _instance).getInt(_kSort) ?? 0;
    if (index < 0 || index >= TaskSort.values.length) return TaskSort.dueDate;
    return TaskSort.values[index];
  }

  static Future<void> setSort(TaskSort sort) async =>
      (await _instance).setInt(_kSort, sort.index);

  /// Whether the app greets and nudges in Tanglish instead of English.
  /// Only the coach lines change — task content is always the user's own.
  static Future<bool> getTanglish() async =>
      (await _instance).getBool(_kTanglish) ?? false;

  static Future<void> setTanglish(bool value) async =>
      (await _instance).setBool(_kTanglish, value);

  /// Speech-recognition language id, e.g. `en_IN`.
  static Future<String> getVoiceLocale() async =>
      (await _instance).getString(_kVoiceLocale) ?? 'en_IN';

  static Future<void> setVoiceLocale(String value) async =>
      (await _instance).setString(_kVoiceLocale, value);

  static Future<bool> getSeenIntro() async =>
      (await _instance).getBool(_kSeenIntro) ?? false;

  static Future<void> setSeenIntro(bool value) async =>
      (await _instance).setBool(_kSeenIntro, value);

  /// Wipes device-local preferences on logout. Tasks stay in SQLite so the
  /// same account still finds them after signing back in.
  static Future<void> clearSession() async {
    final prefs = await _instance;
    await prefs.remove(_kRememberMe);
    await prefs.remove(_kSavedEmail);
  }
}
