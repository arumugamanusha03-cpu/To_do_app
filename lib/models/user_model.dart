/// An account stored in the local `users` table.
///
/// The password itself is never held here — only the PBKDF2 digest and the
/// salt it was derived with.
class UserModel {
  final int? id;
  final String name;

  /// Always stored lower-cased so sign-in is case-insensitive.
  final String email;

  final String passwordHash;
  final String salt;
  final int iterations;
  final String createdAt;

  const UserModel({
    this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.salt,
    required this.iterations,
    required this.createdAt,
  });

  /// Tasks are keyed by the owner's id as a string.
  String get userId => id?.toString() ?? '';

  String get initial {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed[0].toUpperCase();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return '?';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'passwordHash': passwordHash,
        'salt': salt,
        'iterations': iterations,
        'createdAt': createdAt,
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        id: map['id'] as int?,
        name: (map['name'] as String?) ?? '',
        email: (map['email'] as String?) ?? '',
        passwordHash: (map['passwordHash'] as String?) ?? '',
        salt: (map['salt'] as String?) ?? '',
        iterations: (map['iterations'] as int?) ?? 0,
        createdAt: (map['createdAt'] as String?) ?? '',
      );

  UserModel copyWith({
    String? name,
    String? passwordHash,
    String? salt,
    int? iterations,
  }) =>
      UserModel(
        id: id,
        name: name ?? this.name,
        email: email,
        passwordHash: passwordHash ?? this.passwordHash,
        salt: salt ?? this.salt,
        iterations: iterations ?? this.iterations,
        createdAt: createdAt,
      );
}
