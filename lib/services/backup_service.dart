import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../models/task_model.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';
import 'notification_service.dart';

/// Thrown when a chosen file is not a backup this app can read.
class BackupFailure implements Exception {
  final String message;

  const BackupFailure(this.message);

  @override
  String toString() => message;
}

/// What an import actually did, so the user gets a real answer rather than
/// a bare "done".
class ImportSummary {
  final int imported;
  final int skipped;

  const ImportSummary({required this.imported, required this.skipped});

  int get total => imported + skipped;
}

/// Tasks live only on this device, so this is the way off it: write every
/// task to a JSON file the user can keep, and read one back on a new phone.
class BackupService {
  BackupService._();

  static const String _appTag = 'TaskFlow';

  /// Bumped only if the file shape changes in a way older builds cannot read.
  static const int formatVersion = 1;

  // ===========================
  // EXPORT
  // ===========================

  /// The backup document. Row ids and the owner id are deliberately left out —
  /// they mean nothing on another device.
  static Future<String> buildJson({
    required String userId,
    String? accountEmail,
  }) async {
    final tasks = await DatabaseHelper.instance.getTasks(
      userId: userId,
      sort: TaskSort.created,
    );

    final document = {
      'app': _appTag,
      'formatVersion': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      if (accountEmail != null && accountEmail.isNotEmpty)
        'account': accountEmail,
      'taskCount': tasks.length,
      'tasks': tasks.map(_taskToJson).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(document);
  }

  static Map<String, dynamic> _taskToJson(TaskModel task) => {
        'title': task.title,
        'description': task.description,
        'category': task.category,
        'priority': task.priority,
        'date': task.date,
        'time': task.time,
        'reminder': task.reminder,
        'isCompleted': task.isCompleted,
        'createdAt': task.createdAt,
        'completedAt': task.completedAt,
      };

  /// Writes the backup into the app's cache directory and returns the file.
  /// The cache is fine because the file's real home is wherever the user
  /// sends it from the share sheet.
  static Future<File> writeBackupFile({
    required String userId,
    String? accountEmail,
  }) async {
    final json = await buildJson(userId: userId, accountEmail: accountEmail);

    final directory = await getTemporaryDirectory();
    final stamp = DateHelper.toIsoDate(DateTime.now());
    final file = File('${directory.path}/taskflow-backup-$stamp.json');

    return file.writeAsString(json);
  }

  /// Writes the backup and opens the system share sheet so the user can put
  /// it in Drive, Files, WhatsApp — wherever they keep things.
  static Future<int> exportAndShare({
    required String userId,
    String? accountEmail,
  }) async {
    final tasks = await DatabaseHelper.instance.getTasks(userId: userId);

    if (tasks.isEmpty) {
      throw const BackupFailure('There are no tasks to back up yet.');
    }

    final file = await writeBackupFile(
      userId: userId,
      accountEmail: accountEmail,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'TaskFlow backup',
        text: 'TaskFlow backup — ${tasks.length} '
            'task${tasks.length == 1 ? '' : 's'}',
      ),
    );

    return tasks.length;
  }

  // ===========================
  // IMPORT
  // ===========================

  /// Reads [path], validates it, and adds its tasks to [userId].
  ///
  /// Importing never deletes anything, and a task that already exists with the
  /// same title, date and time is skipped — so importing the same file twice
  /// does not double the list.
  static Future<ImportSummary> importFromFile({
    required String path,
    required String userId,
  }) async {
    final file = File(path);

    if (!await file.exists()) {
      throw const BackupFailure('That file could not be opened.');
    }

    late final Map<String, dynamic> document;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not an object');
      }
      document = decoded;
    } on FormatException {
      throw const BackupFailure(
        'That file is not a TaskFlow backup — pick the .json file the app '
        'exported.',
      );
    }

    if (document['app'] != _appTag) {
      throw const BackupFailure(
        'That file was not created by TaskFlow.',
      );
    }

    final version = document['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw const BackupFailure(
        'That backup was made by a newer version of TaskFlow. Update the app '
        'and try again.',
      );
    }

    final rawTasks = document['tasks'];
    if (rawTasks is! List) {
      throw const BackupFailure('That backup has no tasks in it.');
    }

    final db = DatabaseHelper.instance;

    // Existing tasks, keyed the same way duplicates are detected.
    final existing = await db.getTasks(userId: userId);
    final seen = existing.map(_dedupeKey).toSet();

    var imported = 0;
    var skipped = 0;

    for (final entry in rawTasks) {
      if (entry is! Map<String, dynamic>) {
        skipped++;
        continue;
      }

      final task = _taskFromJson(entry, userId);
      if (task == null) {
        skipped++;
        continue;
      }

      final key = _dedupeKey(task);
      if (seen.contains(key)) {
        skipped++;
        continue;
      }

      task.id = await db.insertTask(task);
      seen.add(key);
      imported++;

      // Restore the reminder too, if it is still in the future.
      await NotificationService.scheduleForTask(task);
    }

    return ImportSummary(imported: imported, skipped: skipped);
  }

  static String _dedupeKey(TaskModel task) =>
      '${task.title.trim().toLowerCase()}|${task.date}|${task.time}';

  /// Returns null for a row that cannot be read, so one bad entry does not
  /// abort the whole import.
  static TaskModel? _taskFromJson(Map<String, dynamic> json, String userId) {
    final title = (json['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    final category = json['category'] as String?;
    final priority = json['priority'] as String?;

    return TaskModel(
      userId: userId,
      title: title,
      description: (json['description'] as String?) ?? '',
      category: AppConstants.categoryOf(category ?? '').name,
      priority: AppConstants.priorities.contains(priority)
          ? priority!
          : AppConstants.priorityMedium,
      date: DateHelper.normaliseDate((json['date'] as String?) ?? ''),
      time: DateHelper.normaliseTime((json['time'] as String?) ?? ''),
      reminder: json['reminder'] == true,
      isCompleted: json['isCompleted'] == true,
      createdAt: (json['createdAt'] as String?)?.isNotEmpty == true
          ? json['createdAt'] as String
          : DateTime.now().toIso8601String(),
      completedAt: json['completedAt'] as String?,
    );
  }
}
