import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/task_model.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';

/// A task the user adds often enough that it is worth offering as a shortcut.
class FrequentTask {
  final String title;
  final String category;
  final String priority;
  final int count;

  /// 1 = Monday … 7 = Sunday, set only when the task clearly repeats on one
  /// day of the week.
  final int? weekday;

  const FrequentTask({
    required this.title,
    required this.category,
    required this.priority,
    required this.count,
    this.weekday,
  });

  bool get isRecurring => weekday != null;
}

/// A suggested value plus the reason behind it. The reason is always shown —
/// a suggestion the user cannot explain is one they cannot trust.
class Suggestion<T> {
  final T value;
  final String reason;

  const Suggestion(this.value, this.reason);
}

/// One line in the "what I noticed" list.
class TaskInsight {
  final IconData icon;
  final String title;
  final String detail;

  const TaskInsight({
    required this.icon,
    required this.title,
    required this.detail,
  });
}

/// One task placed at a time by [TaskProfile.planDay].
class PlannedSlot {
  final TaskModel task;
  final TimeOfDay start;
  final bool moved;

  const PlannedSlot({
    required this.task,
    required this.start,
    required this.moved,
  });
}

/// Everything the app has worked out about how this person uses it.
///
/// Built entirely from their own rows in SQLite — nothing leaves the phone and
/// there is no model to download. It gets better the more the app is used, and
/// it says so honestly when it has not seen enough to have an opinion.
class TaskProfile {
  /// Median scheduled time per category, once there are enough samples.
  final Map<String, TimeOfDay> timeByCategory;

  /// The priority most often chosen per category.
  final Map<String, String> priorityByCategory;

  /// Titles the user adds repeatedly, most frequent first.
  final List<FrequentTask> frequentTasks;

  /// Hours of the day the user actually completes things, most productive
  /// first. Derived from `completedAt`, so it reflects behaviour, not intent.
  final List<int> productiveHours;

  /// Completion rate per category, 0–1.
  final Map<String, double> completionByCategory;

  /// 1 = Monday … 7 = Sunday. Null until there is a clear winner.
  final int? bestWeekday;

  final int totalTasks;
  final int completedTasks;

  /// Median days between the due date and the completion date, for tasks that
  /// were finished late. Null when nothing runs late.
  final int? typicalSlipDays;

  const TaskProfile({
    this.timeByCategory = const {},
    this.priorityByCategory = const {},
    this.frequentTasks = const [],
    this.productiveHours = const [],
    this.completionByCategory = const {},
    this.bestWeekday,
    this.totalTasks = 0,
    this.completedTasks = 0,
    this.typicalSlipDays,
  });

  /// Below this the app has not seen enough to suggest anything, and says so
  /// rather than guessing from one or two rows.
  static const int minimumSamples = 3;

  bool get hasLearnedEnough => totalTasks >= minimumSamples;

  // ===========================
  // SUGGESTIONS
  // ===========================

  /// When to schedule a [category] task the user did not give a time for.
  Suggestion<TimeOfDay>? suggestTime(String category) {
    final learned = timeByCategory[category];
    if (learned != null) {
      return Suggestion(
        learned,
        'You usually schedule $category tasks around '
        '${_format(learned)}',
      );
    }

    if (productiveHours.isNotEmpty) {
      final hour = productiveHours.first;
      return Suggestion(
        TimeOfDay(hour: hour, minute: 0),
        'You finish most tasks around ${_formatHour(hour)}',
      );
    }

    return null;
  }

  Suggestion<String>? suggestPriority(String category) {
    final learned = priorityByCategory[category];
    if (learned == null) return null;

    return Suggestion(
      learned,
      'Your $category tasks are usually $learned priority',
    );
  }

  /// Quick-add chips: the things this person adds again and again.
  List<FrequentTask> suggestionsFor(DateTime day, {int limit = 4}) {
    final today = day.weekday;

    // A task that repeats on today's weekday is the most useful thing to
    // offer, so those come first.
    final ranked = [...frequentTasks]..sort((a, b) {
        final aToday = a.weekday == today ? 1 : 0;
        final bToday = b.weekday == today ? 1 : 0;
        if (aToday != bToday) return bToday - aToday;
        return b.count.compareTo(a.count);
      });

    return ranked.take(limit).toList();
  }

  // ===========================
  // INSIGHTS
  // ===========================

  List<TaskInsight> insights() {
    final found = <TaskInsight>[];

    if (!hasLearnedEnough) return found;

    if (productiveHours.isNotEmpty) {
      final hour = productiveHours.first;
      found.add(TaskInsight(
        icon: Icons.bolt_rounded,
        title: 'Your peak hour is ${_formatHour(hour)}',
        detail: 'That is when you tick the most tasks off. '
            'Worth putting the hard ones there.',
      ));
    }

    if (bestWeekday != null) {
      found.add(TaskInsight(
        icon: Icons.event_available_rounded,
        title: '${_weekdayName(bestWeekday!)} is your strongest day',
        detail: 'You complete more on this day than any other.',
      ));
    }

    // The gap between the category you finish most and least is usually the
    // most actionable thing in the whole list.
    if (completionByCategory.length >= 2) {
      final sorted = completionByCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final best = sorted.first;
      final worst = sorted.last;

      if (best.value - worst.value > 0.25) {
        found.add(TaskInsight(
          icon: Icons.insights_rounded,
          title: '${worst.key} is slipping',
          detail: 'You finish ${(best.value * 100).round()}% of '
              '${best.key} tasks but only '
              '${(worst.value * 100).round()}% of ${worst.key} ones.',
        ));
      }
    }

    if (typicalSlipDays != null && typicalSlipDays! > 0) {
      found.add(TaskInsight(
        icon: Icons.schedule_rounded,
        title: 'Late tasks slip about '
            '$typicalSlipDays day${typicalSlipDays == 1 ? '' : 's'}',
        detail: 'When something misses its date, that is usually by how much. '
            'Padding new due dates by that much tends to help.',
      ));
    }

    final recurring = frequentTasks.where((t) => t.isRecurring).toList();
    if (recurring.isNotEmpty) {
      final task = recurring.first;
      found.add(TaskInsight(
        icon: Icons.repeat_rounded,
        title: '"${task.title}" looks weekly',
        detail: 'You have added it ${task.count} times, usually on '
            '${_weekdayName(task.weekday!)}.',
      ));
    }

    return found;
  }

  // ===========================
  // PLAN MY DAY
  // ===========================

  /// Lays today's open work out across the rest of the day.
  ///
  /// Overdue first, then by priority, starting at the next quarter hour and
  /// preferring the hours this person actually gets things done in. Nothing is
  /// saved until the user accepts the plan.
  List<PlannedSlot> planDay(
    List<TaskModel> pending, {
    DateTime? now,
    int slotMinutes = 45,
    int gapMinutes = 15,
  }) {
    final reference = now ?? DateTime.now();

    // Overdue is judged against the same instant the slots are laid out from.
    // Reading the wall clock here instead would let the ordering and the
    // schedule disagree about what time it is.
    bool isLate(TaskModel task) =>
        !task.isCompleted && task.dueDateTime.isBefore(reference);

    final ordered = [...pending]..sort((a, b) {
        final overdue = (isLate(b) ? 1 : 0) - (isLate(a) ? 1 : 0);
        if (overdue != 0) return overdue;

        final priority = AppConstants.priorityWeight(b.priority)
            .compareTo(AppConstants.priorityWeight(a.priority));
        if (priority != 0) return priority;

        return a.dueDateTime.compareTo(b.dueDateTime);
      });

    // Start at the next quarter hour so the first slot is not already gone.
    var cursor = DateTime(
      reference.year,
      reference.month,
      reference.day,
      reference.hour,
      ((reference.minute ~/ 15) + 1) * 15,
    );

    // Jump forward to the first productive hour if the day has not started.
    if (productiveHours.isNotEmpty) {
      final earliest = productiveHours.reduce((a, b) => a < b ? a : b);
      if (cursor.hour < earliest) {
        cursor = DateTime(cursor.year, cursor.month, cursor.day, earliest);
      }
    }

    final slots = <PlannedSlot>[];

    for (final task in ordered) {
      // Stop rather than schedule into the small hours.
      if (cursor.hour >= 22) break;

      final start = TimeOfDay(hour: cursor.hour, minute: cursor.minute);
      final moved = task.dueTime.hour != start.hour ||
          task.dueTime.minute != start.minute;

      slots.add(PlannedSlot(task: task, start: start, moved: moved));
      cursor = cursor.add(Duration(minutes: slotMinutes + gapMinutes));
    }

    return slots;
  }

  // ===========================
  // FORMATTING
  // ===========================

  static String _format(TimeOfDay time) => DateHelper.prettyTime(time);

  static String _formatHour(int hour) =>
      DateHelper.prettyTime(TimeOfDay(hour: hour, minute: 0));

  static String _weekdayName(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[(weekday - 1).clamp(0, 6)];
  }
}

/// Builds a [TaskProfile] from the user's own task history.
class TaskIntelligence {
  TaskIntelligence._();

  /// Reads every task for [userId] and works out the patterns in it.
  static Future<TaskProfile> learn(String userId) async {
    if (userId.isEmpty) return const TaskProfile();

    final tasks = await DatabaseHelper.instance.getTasks(userId: userId);
    return profileFrom(tasks);
  }

  /// Pure so it can be tested without a database.
  static TaskProfile profileFrom(List<TaskModel> tasks) {
    if (tasks.isEmpty) return const TaskProfile();

    final completed = tasks.where((t) => t.isCompleted).toList();

    return TaskProfile(
      timeByCategory: _timeByCategory(tasks),
      priorityByCategory: _priorityByCategory(tasks),
      frequentTasks: _frequentTasks(tasks),
      productiveHours: _productiveHours(completed),
      completionByCategory: _completionByCategory(tasks),
      bestWeekday: _bestWeekday(completed),
      totalTasks: tasks.length,
      completedTasks: completed.length,
      typicalSlipDays: _typicalSlipDays(completed),
    );
  }

  // ===========================
  // LEARNERS
  // ===========================

  static Map<String, TimeOfDay> _timeByCategory(List<TaskModel> tasks) {
    final buckets = <String, List<int>>{};

    for (final task in tasks) {
      final minutes = task.dueTime.hour * 60 + task.dueTime.minute;
      buckets.putIfAbsent(task.category, () => []).add(minutes);
    }

    final result = <String, TimeOfDay>{};
    buckets.forEach((category, minutes) {
      if (minutes.length < TaskProfile.minimumSamples) return;

      // Median, not mean: one 3am task should not drag the whole category.
      minutes.sort();
      final median = minutes[minutes.length ~/ 2];
      result[category] = TimeOfDay(hour: median ~/ 60, minute: median % 60);
    });

    return result;
  }

  static Map<String, String> _priorityByCategory(List<TaskModel> tasks) {
    final counts = <String, Map<String, int>>{};

    for (final task in tasks) {
      final byPriority = counts.putIfAbsent(task.category, () => {});
      byPriority[task.priority] = (byPriority[task.priority] ?? 0) + 1;
    }

    final result = <String, String>{};
    counts.forEach((category, byPriority) {
      final total = byPriority.values.fold(0, (a, b) => a + b);
      if (total < TaskProfile.minimumSamples) return;

      final winner = byPriority.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );

      // Only claim a habit when it is actually dominant.
      if (winner.value / total >= 0.6) result[category] = winner.key;
    });

    return result;
  }

  static List<FrequentTask> _frequentTasks(List<TaskModel> tasks) {
    final groups = <String, List<TaskModel>>{};

    for (final task in tasks) {
      final key = normaliseTitle(task.title);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(task);
    }

    final frequent = <FrequentTask>[];

    groups.forEach((_, group) {
      if (group.length < 2) return;

      // Use the most recent spelling of the title.
      group.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final latest = group.first;

      frequent.add(FrequentTask(
        title: latest.title,
        category: latest.category,
        priority: latest.priority,
        count: group.length,
        weekday: _dominantWeekday(group),
      ));
    });

    frequent.sort((a, b) => b.count.compareTo(a.count));
    return frequent;
  }

  /// The weekday a repeated task lands on, when it clearly favours one.
  static int? _dominantWeekday(List<TaskModel> group) {
    if (group.length < 3) return null;

    final counts = <int, int>{};
    for (final task in group) {
      final weekday = task.dueDate.weekday;
      counts[weekday] = (counts[weekday] ?? 0) + 1;
    }

    final winner = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return winner.value / group.length >= 0.6 ? winner.key : null;
  }

  /// Hours ranked by how many tasks were completed in them.
  static List<int> _productiveHours(List<TaskModel> completed) {
    final counts = <int, int>{};

    for (final task in completed) {
      final stamp = task.completedAt;
      if (stamp == null) continue;

      final when = DateTime.tryParse(stamp);
      if (when == null) continue;

      counts[when.hour] = (counts[when.hour] ?? 0) + 1;
    }

    if (counts.length < 2) return const [];

    final hours = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return hours.map((e) => e.key).toList();
  }

  static Map<String, double> _completionByCategory(List<TaskModel> tasks) {
    final totals = <String, int>{};
    final done = <String, int>{};

    for (final task in tasks) {
      totals[task.category] = (totals[task.category] ?? 0) + 1;
      if (task.isCompleted) {
        done[task.category] = (done[task.category] ?? 0) + 1;
      }
    }

    final result = <String, double>{};
    totals.forEach((category, total) {
      if (total < TaskProfile.minimumSamples) return;
      result[category] = (done[category] ?? 0) / total;
    });

    return result;
  }

  static int? _bestWeekday(List<TaskModel> completed) {
    final counts = <int, int>{};

    for (final task in completed) {
      final stamp = task.completedAt;
      if (stamp == null) continue;

      final when = DateTime.tryParse(stamp);
      if (when == null) continue;

      counts[when.weekday] = (counts[when.weekday] ?? 0) + 1;
    }

    if (counts.length < 2) return null;

    final winner = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final total = counts.values.fold(0, (a, b) => a + b);

    return winner.value / total >= 0.3 ? winner.key : null;
  }

  /// Median lateness, in days, across tasks that were finished after their
  /// due date.
  static int? _typicalSlipDays(List<TaskModel> completed) {
    final slips = <int>[];

    for (final task in completed) {
      final stamp = task.completedAt;
      if (stamp == null) continue;

      final when = DateTime.tryParse(stamp);
      if (when == null) continue;

      final days = DateHelper.dateOnly(when)
          .difference(DateHelper.dateOnly(task.dueDate))
          .inDays;

      if (days > 0) slips.add(days);
    }

    if (slips.length < TaskProfile.minimumSamples) return null;

    slips.sort();
    return slips[slips.length ~/ 2];
  }

  // ===========================
  // HELPERS
  // ===========================

  /// Lower-cased, punctuation stripped, spaces collapsed — so "Gym!" and
  /// "gym" count as the same recurring task.
  static String normaliseTitle(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
