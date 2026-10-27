import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/task_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';

/// Aggregate counts for the Home overview and the Analytics screen.
class TaskStats {
  final int total;
  final int completed;
  final int pending;
  final int highPriority;
  final int overdue;
  final int dueToday;

  /// How many of today's tasks are already ticked off — what the coach line
  /// on the home screen is built from.
  final int completedToday;

  const TaskStats({
    this.total = 0,
    this.completed = 0,
    this.pending = 0,
    this.highPriority = 0,
    this.overdue = 0,
    this.dueToday = 0,
    this.completedToday = 0,
  });

  int get pendingToday =>
      (dueToday - completedToday) < 0 ? 0 : dueToday - completedToday;

  /// 0.0 – 1.0. An empty list counts as 0% rather than NaN.
  double get completionRate => total == 0 ? 0 : completed / total;

  int get completionPercent => (completionRate * 100).round();
}

/// One bar of the weekly chart.
class DayProgress {
  final DateTime day;
  final int total;
  final int completed;

  const DayProgress({
    required this.day,
    required this.total,
    required this.completed,
  });

  double get rate => total == 0 ? 0 : completed / total;

  int get percent => (rate * 100).round();
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  DatabaseHelper._init();

  static Database? _database;

  /// v1 → the original schema (no owner, `d/M/yyyy` dates).
  /// v2 → per-user tasks, ISO dates, created/completed timestamps.
  /// v3 → local accounts in a `users` table.
  static const int _schemaVersion = 3;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('todo.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        priority TEXT NOT NULL,
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        reminder INTEGER NOT NULL,
        isCompleted INTEGER NOT NULL,
        createdAt TEXT NOT NULL DEFAULT '',
        completedAt TEXT
      )
    ''');

    await _createUsersTable(db);
    await _createIndexes(db);
  }

  Future<void> _createUsersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE COLLATE NOCASE,
        passwordHash TEXT NOT NULL,
        salt TEXT NOT NULL,
        iterations INTEGER NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_user_date '
      'ON tasks(userId, date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_user_completed '
      'ON tasks(userId, isCompleted)',
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE tasks ADD COLUMN userId TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE tasks ADD COLUMN createdAt TEXT NOT NULL DEFAULT ''",
      );
      await db.execute('ALTER TABLE tasks ADD COLUMN completedAt TEXT');

      // Rewrite the legacy `d/M/yyyy` + `9:00 AM` values into the sortable
      // formats the rest of the app now assumes.
      final rows = await db.query('tasks');
      final batch = db.batch();

      for (final row in rows) {
        batch.update(
          'tasks',
          {
            'date': DateHelper.normaliseDate((row['date'] as String?) ?? ''),
            'time': DateHelper.normaliseTime((row['time'] as String?) ?? ''),
            'createdAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }

      await batch.commit(noResult: true);
      await _createIndexes(db);
    }

    if (oldVersion < 3) {
      await _createUsersTable(db);
    }
  }

  // ===========================
  // USERS
  // ===========================

  String _normaliseEmail(String email) => email.trim().toLowerCase();

  Future<bool> emailExists(String email) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['id'],
      where: 'email = ?',
      whereArgs: [_normaliseEmail(email)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Returns the stored account, id included.
  Future<UserModel> createUser(UserModel user) async {
    final db = await database;
    final map = user.toMap()
      ..remove('id')
      ..['email'] = _normaliseEmail(user.email);

    final id = await db.insert('users', map);
    final saved = await getUserById(id);

    // The row was just written, so this is only a null-safety formality.
    return saved ?? user;
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [_normaliseEmail(email)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserModel.fromMap(rows.first);
  }

  Future<UserModel?> getUserById(int id) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserModel.fromMap(rows.first);
  }

  Future<int> countUsers() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM users');
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<int> updateUser(UserModel user) async {
    final db = await database;
    return db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  /// Legacy rows have no owner. The first account to sign in on this device
  /// adopts them so the user does not silently lose their old tasks.
  Future<int> claimOrphanTasks(String userId) async {
    if (userId.isEmpty) return 0;
    final db = await database;
    return db.update(
      'tasks',
      {'userId': userId},
      where: "userId = '' OR userId IS NULL",
    );
  }

  // ===========================
  // WRITES
  // ===========================

  Future<int> insertTask(TaskModel task) async {
    final db = await database;
    final map = task.toMap()..remove('id');
    return db.insert('tasks', map);
  }

  Future<int> updateTask(TaskModel task) async {
    final db = await database;
    return db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<int> deleteTask(int id) async {
    final db = await database;
    return db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  /// Flips the completed flag and stamps (or clears) `completedAt`.
  /// Returns the saved task so callers can update their local list.
  Future<TaskModel> toggleCompleted(TaskModel task) async {
    final nowCompleted = !task.isCompleted;

    final updated = task.copyWith(
      isCompleted: nowCompleted,
      completedAt: nowCompleted ? DateTime.now().toIso8601String() : null,
      clearCompletedAt: !nowCompleted,
    );

    await updateTask(updated);
    return updated;
  }

  Future<int> deleteCompleted(String userId) async {
    final db = await database;
    return db.delete(
      'tasks',
      where: 'userId = ? AND isCompleted = 1',
      whereArgs: [userId],
    );
  }

  Future<int> deleteAllForUser(String userId) async {
    final db = await database;
    return db.delete('tasks', where: 'userId = ?', whereArgs: [userId]);
  }

  // ===========================
  // READS
  // ===========================

  Future<TaskModel?> getTaskById(int id) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TaskModel.fromMap(rows.first);
  }

  /// The single query behind the Home screen: owner + optional search,
  /// category, filter and sort.
  Future<List<TaskModel>> getTasks({
    required String userId,
    String search = '',
    String? category,
    TaskFilter filter = TaskFilter.all,
    TaskSort sort = TaskSort.dueDate,
  }) async {
    final db = await database;

    final where = <String>['userId = ?'];
    final args = <Object?>[userId];

    final term = search.trim();
    if (term.isNotEmpty) {
      where.add('(title LIKE ? OR description LIKE ?)');
      args
        ..add('%$term%')
        ..add('%$term%');
    }

    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }

    final todayIso = DateHelper.toIsoDate(DateTime.now());
    final nowTime = DateHelper.storedTimeOf(DateTime.now());

    switch (filter) {
      case TaskFilter.pending:
        where.add('isCompleted = 0');
        break;
      case TaskFilter.completed:
        where.add('isCompleted = 1');
        break;
      case TaskFilter.today:
        where.add('date = ?');
        args.add(todayIso);
        break;
      case TaskFilter.overdue:
        // Earlier day, or today at a time that has already passed.
        where.add(
          'isCompleted = 0 AND (date < ? OR (date = ? AND time < ?))',
        );
        args
          ..add(todayIso)
          ..add(todayIso)
          ..add(nowTime);
        break;
      case TaskFilter.all:
        break;
    }

    final rows = await db.query(
      'tasks',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: _orderBy(sort),
    );

    final tasks = rows.map(TaskModel.fromMap).toList();

    // Priority is stored as text, so its ordering is applied in Dart.
    if (sort == TaskSort.priority) {
      tasks.sort((a, b) {
        final byPriority = AppConstants.priorityWeight(b.priority)
            .compareTo(AppConstants.priorityWeight(a.priority));
        if (byPriority != 0) return byPriority;
        return a.dueDateTime.compareTo(b.dueDateTime);
      });
    }

    return tasks;
  }

  String _orderBy(TaskSort sort) {
    switch (sort) {
      case TaskSort.dueDate:
        return 'isCompleted ASC, date ASC, time ASC';
      case TaskSort.created:
        return 'createdAt DESC, id DESC';
      case TaskSort.title:
        return 'title COLLATE NOCASE ASC';
      case TaskSort.priority:
        // Sorted in Dart; keep a stable base order.
        return 'date ASC, time ASC';
    }
  }

  Future<List<TaskModel>> getTasksForDate({
    required String userId,
    required DateTime date,
  }) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'userId = ? AND date = ?',
      whereArgs: [userId, DateHelper.toIsoDate(date)],
      orderBy: 'isCompleted ASC, time ASC',
    );
    return rows.map(TaskModel.fromMap).toList();
  }

  /// Every task in the given month, grouped by day — feeds the calendar dots.
  Future<Map<DateTime, List<TaskModel>>> getTasksGroupedByDay({
    required String userId,
    required DateTime month,
  }) async {
    final db = await database;

    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);

    final rows = await db.query(
      'tasks',
      where: 'userId = ? AND date >= ? AND date <= ?',
      whereArgs: [
        userId,
        DateHelper.toIsoDate(first),
        DateHelper.toIsoDate(last),
      ],
      orderBy: 'time ASC',
    );

    final grouped = <DateTime, List<TaskModel>>{};
    for (final row in rows) {
      final task = TaskModel.fromMap(row);
      final key = DateHelper.dateOnly(task.dueDate);
      grouped.putIfAbsent(key, () => []).add(task);
    }
    return grouped;
  }

  Future<List<TaskModel>> getUpcoming({
    required String userId,
    int limit = 5,
  }) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'userId = ? AND isCompleted = 0 AND date >= ?',
      whereArgs: [userId, DateHelper.toIsoDate(DateTime.now())],
      orderBy: 'date ASC, time ASC',
      limit: limit,
    );
    return rows.map(TaskModel.fromMap).toList();
  }

  /// Pending tasks with a reminder that is still in the future — used to
  /// rebuild the notification schedule after a reboot or a settings change.
  Future<List<TaskModel>> getPendingReminders(String userId) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'userId = ? AND isCompleted = 0 AND reminder = 1',
      whereArgs: [userId],
    );

    final now = DateTime.now();
    return rows
        .map(TaskModel.fromMap)
        .where((t) => t.dueDateTime.isAfter(now))
        .toList();
  }

  // ===========================
  // STATS
  // ===========================

  Future<TaskStats> getStats(String userId) async {
    final db = await database;

    final todayIso = DateHelper.toIsoDate(DateTime.now());
    final nowTime = DateHelper.storedTimeOf(DateTime.now());

    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN isCompleted = 1 THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN isCompleted = 0 THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN isCompleted = 0 AND priority = ? THEN 1 ELSE 0 END)
          AS highPriority,
        SUM(CASE WHEN date = ? THEN 1 ELSE 0 END) AS dueToday,
        SUM(CASE WHEN date = ? AND isCompleted = 1 THEN 1 ELSE 0 END)
          AS completedToday,
        SUM(CASE WHEN isCompleted = 0
                  AND (date < ? OR (date = ? AND time < ?))
             THEN 1 ELSE 0 END) AS overdue
      FROM tasks
      WHERE userId = ?
      ''',
      [
        AppConstants.priorityHigh, // highPriority
        todayIso, // dueToday
        todayIso, // completedToday
        todayIso, // overdue: earlier day
        todayIso, // overdue: today…
        nowTime, // …at a time already past
        userId,
      ],
    );

    if (rows.isEmpty) return const TaskStats();

    int read(String key) => (rows.first[key] as int?) ?? 0;

    return TaskStats(
      total: read('total'),
      completed: read('completed'),
      pending: read('pending'),
      highPriority: read('highPriority'),
      dueToday: read('dueToday'),
      completedToday: read('completedToday'),
      overdue: read('overdue'),
    );
  }

  /// Completion rate for each of the last 7 days, oldest first.
  Future<List<DayProgress>> getWeeklyProgress(String userId) async {
    final db = await database;
    final days = DateHelper.lastSevenDays();

    final rows = await db.rawQuery(
      '''
      SELECT date,
             COUNT(*) AS total,
             SUM(CASE WHEN isCompleted = 1 THEN 1 ELSE 0 END) AS completed
      FROM tasks
      WHERE userId = ? AND date >= ? AND date <= ?
      GROUP BY date
      ''',
      [
        userId,
        DateHelper.toIsoDate(days.first),
        DateHelper.toIsoDate(days.last),
      ],
    );

    final byDate = {
      for (final row in rows) row['date'] as String: row,
    };

    return days.map((day) {
      final row = byDate[DateHelper.toIsoDate(day)];
      return DayProgress(
        day: day,
        total: (row?['total'] as int?) ?? 0,
        completed: (row?['completed'] as int?) ?? 0,
      );
    }).toList();
  }

  /// Task count per category, highest first — drives the analytics breakdown.
  Future<List<MapEntry<String, int>>> getCategoryBreakdown(
    String userId,
  ) async {
    final db = await database;

    final rows = await db.rawQuery(
      '''
      SELECT category, COUNT(*) AS count
      FROM tasks
      WHERE userId = ?
      GROUP BY category
      ORDER BY count DESC
      ''',
      [userId],
    );

    return rows
        .map((r) => MapEntry(r['category'] as String, (r['count'] as int?) ?? 0))
        .toList();
  }

  /// Tasks created this calendar month, and how many of them are done.
  Future<(int created, int completed)> getMonthlySummary(String userId) async {
    final db = await database;

    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1).toIso8601String();

    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS created,
             SUM(CASE WHEN isCompleted = 1 THEN 1 ELSE 0 END) AS completed
      FROM tasks
      WHERE userId = ? AND createdAt >= ?
      ''',
      [userId, first],
    );

    if (rows.isEmpty) return (0, 0);
    return (
      (rows.first['created'] as int?) ?? 0,
      (rows.first['completed'] as int?) ?? 0,
    );
  }

  /// Longest run of consecutive days (ending today or yesterday) on which
  /// at least one task was completed.
  Future<int> getCurrentStreak(String userId) async {
    final db = await database;

    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT substr(completedAt, 1, 10) AS day
      FROM tasks
      WHERE userId = ? AND isCompleted = 1 AND completedAt IS NOT NULL
      ORDER BY day DESC
      ''',
      [userId],
    );

    final days = rows
        .map((r) => r['day'] as String?)
        .whereType<String>()
        .map(DateHelper.parseDate)
        .toList();

    if (days.isEmpty) return 0;

    final today = DateHelper.dateOnly(DateTime.now());
    var cursor = today;

    // A streak may legitimately end yesterday if nothing is done yet today.
    if (!days.any((d) => DateHelper.isSameDate(d, today))) {
      cursor = today.subtract(const Duration(days: 1));
      if (!days.any((d) => DateHelper.isSameDate(d, cursor))) return 0;
    }

    var streak = 0;
    while (days.any((d) => DateHelper.isSameDate(d, cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
