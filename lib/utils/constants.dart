import 'package:flutter/material.dart';

/// A task category with the icon and colour used to represent it everywhere
/// in the app (task cards, calendar dots, analytics breakdown).
class TaskCategory {
  final String name;
  final IconData icon;
  final Color color;

  const TaskCategory(this.name, this.icon, this.color);
}

class AppConstants {
  AppConstants._();

  static const String appName = 'TaskFlow';
  static const String appTagline = 'Organize • Focus • Achieve';
  static const String appVersion = '1.0.0';

  // ===========================
  // CATEGORIES
  // ===========================

  /// Colour order is deliberate, not decorative: these six hues were checked
  /// against the dark chart surface for lightness, chroma, contrast and
  /// colour-vision separation, and each category keeps its hue everywhere so
  /// filtering a list never repaints the rest. Adjacent Shopping/Study sit in
  /// the acceptable-with-labels band, which is why the analytics breakdown
  /// always shows an icon and a name beside every bar.
  static const List<TaskCategory> categories = [
    TaskCategory('Work', Icons.work_outline_rounded, Color(0xFF3B82F6)),
    TaskCategory('Personal', Icons.person_outline_rounded, Color(0xFFEA580C)),
    TaskCategory('Study', Icons.menu_book_outlined, Color(0xFF16A34A)),
    TaskCategory('Shopping', Icons.shopping_bag_outlined, Color(0xFFDB2777)),
    TaskCategory('Health', Icons.favorite_outline_rounded, Color(0xFF7C3AED)),
    TaskCategory('Other', Icons.category_outlined, Color(0xFF0D9488)),
  ];

  static List<String> get categoryNames =>
      categories.map((c) => c.name).toList();

  /// Never throws — unknown categories fall back to "Other".
  static TaskCategory categoryOf(String name) {
    return categories.firstWhere(
      (c) => c.name.toLowerCase() == name.toLowerCase(),
      orElse: () => categories.last,
    );
  }

  // ===========================
  // PRIORITIES
  // ===========================

  static const String priorityLow = 'Low';
  static const String priorityMedium = 'Medium';
  static const String priorityHigh = 'High';

  static const List<String> priorities = [
    priorityLow,
    priorityMedium,
    priorityHigh,
  ];

  static Color priorityColor(String priority) {
    switch (priority) {
      case priorityHigh:
        return const Color(0xFFEF4444);
      case priorityLow:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  /// Higher number = more urgent. Used for sorting.
  static int priorityWeight(String priority) {
    switch (priority) {
      case priorityHigh:
        return 3;
      case priorityMedium:
        return 2;
      default:
        return 1;
    }
  }

  // ===========================
  // NOTIFICATIONS
  // ===========================

  static const String notificationChannelId = 'taskflow_reminders';
  static const String notificationChannelName = 'Task Reminders';
  static const String notificationChannelDescription =
      'Reminders for tasks you scheduled in TaskFlow';
}

/// How the task list is ordered on the Home screen.
enum TaskSort { dueDate, priority, created, title }

extension TaskSortLabel on TaskSort {
  String get label {
    switch (this) {
      case TaskSort.dueDate:
        return 'Due date';
      case TaskSort.priority:
        return 'Priority';
      case TaskSort.created:
        return 'Recently added';
      case TaskSort.title:
        return 'Title (A-Z)';
    }
  }
}

/// Which tasks the Home screen is currently showing.
enum TaskFilter { all, pending, completed, today, overdue }

extension TaskFilterLabel on TaskFilter {
  String get label {
    switch (this) {
      case TaskFilter.all:
        return 'All';
      case TaskFilter.pending:
        return 'Pending';
      case TaskFilter.completed:
        return 'Completed';
      case TaskFilter.today:
        return 'Today';
      case TaskFilter.overdue:
        return 'Overdue';
    }
  }
}
