import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The stored form of a password: a PBKDF2-HMAC-SHA256 digest plus the salt
/// and iteration count it was produced with.
///
/// Keeping the iteration count with the record means the cost can be raised
/// later without invalidating existing accounts.
class HashedPassword {
  final String hash;
  final String salt;
  final int iterations;

  const HashedPassword({
    required this.hash,
    required this.salt,
    required this.iterations,
  });
}

/// Arguments for the isolate; `compute` only takes a single value.
class _Pbkdf2Request {
  final String password;
  final String salt;
  final int iterations;

  const _Pbkdf2Request(this.password, this.salt, this.iterations);
}

class PasswordHasher {
  PasswordHasher._();

  /// High enough to make guessing expensive, low enough that sign-in on a
  /// mid-range phone stays well under a second. Hashing runs off the UI
  /// thread, so this never janks the form.
  static const int defaultIterations = 30000;

  static const int _saltBytes = 16;
  static const int _keyBytes = 32;

  static final Random _random = Random.secure();

  static String _newSalt() {
    final bytes =
        List<int>.generate(_saltBytes, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Hashes [password] with a fresh salt.
  static Future<HashedPassword> hash(String password) async {
    final salt = _newSalt();
    final digest = await compute(
      _derive,
      _Pbkdf2Request(password, salt, defaultIterations),
    );

    return HashedPassword(
      hash: digest,
      salt: salt,
      iterations: defaultIterations,
    );
  }

  /// Re-derives the digest for [password] and compares it to [expectedHash].
  static Future<bool> verify({
    required String password,
    required String expectedHash,
    required String salt,
    required int iterations,
  }) async {
    if (salt.isEmpty || iterations <= 0) return false;

    final digest = await compute(
      _derive,
      _Pbkdf2Request(password, salt, iterations),
    );

    return _constantTimeEquals(digest, expectedHash);
  }

  /// Compares every character regardless of where the first difference is,
  /// so the comparison time does not leak how much of the hash matched.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;

    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}

/// Top-level so it can run in a background isolate.
String _derive(_Pbkdf2Request request) {
  final password = utf8.encode(request.password);
  final salt = base64Decode(request.salt);

  final hmac = Hmac(sha256, password);
  final output = <int>[];

  var block = 1;
  while (output.length < PasswordHasher._keyBytes) {
    // U1 = HMAC(password, salt || INT_32_BE(block))
    final seed = <int>[...salt, ...__int32be(block)];
    var u = hmac.convert(seed).bytes;
    final accumulated = List<int>.from(u);

    for (var i = 1; i < request.iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < accumulated.length; j++) {
        accumulated[j] ^= u[j];
      }
    }

    output.addAll(accumulated);
    block++;
  }

  return base64Encode(
    Uint8List.fromList(output.sublist(0, PasswordHasher._keyBytes)),
  );
}

List<int> __int32be(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
