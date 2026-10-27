import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/user_model.dart';
import 'password_hasher.dart';
import 'shared_pref_service.dart';

/// Thrown for every failure the UI is expected to show to the user.
class AuthFailure implements Exception {
  final String message;

  const AuthFailure(this.message);

  @override
  String toString() => message;
}

/// Accounts live in the app's own SQLite database — there is no server and no
/// network call, so sign-in works offline and needs no setup.
///
/// Passwords are stored as PBKDF2-HMAC-SHA256 digests with a per-account salt;
/// the plain password is never written anywhere.
class AuthService {
  AuthService._();

  /// The signed-in account, or null. Screens listen to this instead of a
  /// stream, and [AuthGate] rebuilds the whole app when it changes.
  static final ValueNotifier<UserModel?> authState =
      ValueNotifier<UserModel?>(null);

  static UserModel? get currentUser => authState.value;

  static String get uid => authState.value?.userId ?? '';

  static bool get isSignedIn => authState.value != null;

  static String get displayName {
    final user = authState.value;
    if (user == null) return 'Guest';

    final name = user.name.trim();
    if (name.isNotEmpty) return name;

    final email = user.email;
    if (email.contains('@')) return email.split('@').first;

    return 'User';
  }

  static String get email => authState.value?.email ?? '';

  static String get initial => authState.value?.initial ?? '?';

  // ===========================
  // SESSION
  // ===========================

  /// Restores the previous session at startup. Called once from `main()`.
  static Future<void> restoreSession() async {
    final id = await SharedPrefService.getSignedInUserId();
    if (id == null) return;

    final user = await DatabaseHelper.instance.getUserById(id);

    // The account could have been removed since the session was saved.
    if (user == null) {
      await SharedPrefService.setSignedInUserId(null);
      return;
    }

    authState.value = user;
  }

  static Future<void> _startSession(UserModel user) async {
    await SharedPrefService.setSignedInUserId(user.id);
    authState.value = user;
  }

  // ===========================
  // SIGN UP / SIGN IN
  // ===========================

  static Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final db = DatabaseHelper.instance;

    if (await db.emailExists(email)) {
      throw const AuthFailure(
        'An account already exists for this email. Sign in instead.',
      );
    }

    try {
      final hashed = await PasswordHasher.hash(password);

      final created = await db.createUser(
        UserModel(
          name: name.trim(),
          email: email.trim().toLowerCase(),
          passwordHash: hashed.hash,
          salt: hashed.salt,
          iterations: hashed.iterations,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      await _startSession(created);
      return created;
    } catch (error) {
      debugPrint('Sign-up failed: $error');
      throw const AuthFailure('Could not create the account. Try again.');
    }
  }

  static Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final user = await DatabaseHelper.instance.getUserByEmail(email);

    // Deliberately the same message for an unknown email and a wrong
    // password, so the form cannot be used to discover which emails exist.
    const failure = AuthFailure('Email or password is incorrect.');

    if (user == null) throw failure;

    final matches = await PasswordHasher.verify(
      password: password,
      expectedHash: user.passwordHash,
      salt: user.salt,
      iterations: user.iterations,
    );

    if (!matches) throw failure;

    await _startSession(user);
    return user;
  }

  static Future<void> signOut() async {
    await SharedPrefService.setSignedInUserId(null);
    authState.value = null;
  }

  // ===========================
  // ACCOUNT CHANGES
  // ===========================

  static Future<void> updateDisplayName(String name) async {
    final user = authState.value;
    if (user == null) return;

    final updated = user.copyWith(name: name.trim());
    await DatabaseHelper.instance.updateUser(updated);
    authState.value = updated;
  }

  /// Requires the current password — this is the only password change path,
  /// since a local-only app has no way to email a reset link.
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = authState.value;
    if (user == null) {
      throw const AuthFailure('You are signed out.');
    }

    final matches = await PasswordHasher.verify(
      password: currentPassword,
      expectedHash: user.passwordHash,
      salt: user.salt,
      iterations: user.iterations,
    );

    if (!matches) {
      throw const AuthFailure('Current password is incorrect.');
    }

    if (currentPassword == newPassword) {
      throw const AuthFailure('New password must be different.');
    }

    final hashed = await PasswordHasher.hash(newPassword);
    final updated = user.copyWith(
      passwordHash: hashed.hash,
      salt: hashed.salt,
      iterations: hashed.iterations,
    );

    await DatabaseHelper.instance.updateUser(updated);
    authState.value = updated;
  }

  // ===========================
  // VALIDATION
  // ===========================

  static final RegExp _emailPattern = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? validateEmail(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  static String? validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < 6) return 'Use at least 6 characters';
    return null;
  }

  static String? validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Name is required';
    if (name.length < 2) return 'Name is too short';
    return null;
  }
}
