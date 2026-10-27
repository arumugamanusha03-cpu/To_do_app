import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/date_helper.dart';

class TaskModel {
  int? id;

  /// Firebase uid of the owner. Tasks are always queried by this so two
  /// accounts on the same phone never see each other's list.
  String userId;

  String title;
  String description;
  String category;
  String priority;

  /// `yyyy-MM-dd`
  String date;

  /// `HH:mm` (24 hour)
  String time;

  bool reminder;
  bool isCompleted;

  /// ISO-8601 timestamps.
  String createdAt;
  String? completedAt;

  TaskModel({
    this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.category,
    required this.priority,
    required this.date,
    required this.time,
    required this.reminder,
    this.isCompleted = false,
    String? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  // ===========================
  // DERIVED VALUES
  // ===========================

  DateTime get dueDate => DateHelper.parseDate(date);

  TimeOfDay get dueTime => DateHelper.parseTime(time);

  DateTime get dueDateTime => DateHelper.combine(dueDate, dueTime);

  /// Pending and the scheduled moment has already passed.
  bool get isOverdue =>
      !isCompleted && dueDateTime.isBefore(DateTime.now());

  bool get isToday => DateHelper.isSameDate(dueDate, DateTime.now());

  TaskCategory get categoryInfo => AppConstants.categoryOf(category);

  Color get priorityColor => AppConstants.priorityColor(priority);

  String get displayTime => DateHelper.prettyTimeFromStored(time);

  String get displayDate => DateHelper.relativeLabel(dueDate);

  /// Stable id for the scheduled reminder. Notification ids must fit in a
  /// 32-bit int, and row ids never come close to that ceiling.
  int get notificationId => id ?? 0;

  // ===========================
  // SERIALISATION
  // ===========================

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
      'date': date,
      'time': time,
      'reminder': reminder ? 1 : 0,
      'isCompleted': isCompleted ? 1 : 0,
      'createdAt': createdAt,
      'completedAt': completedAt,
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      id: map['id'] as int?,
      userId: (map['userId'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      category: (map['category'] as String?) ?? 'Other',
      priority: (map['priority'] as String?) ?? AppConstants.priorityMedium,
      date: DateHelper.normaliseDate((map['date'] as String?) ?? ''),
      time: DateHelper.normaliseTime((map['time'] as String?) ?? ''),
      reminder: map['reminder'] == 1,
      isCompleted: map['isCompleted'] == 1,
      createdAt: (map['createdAt'] as String?)?.isNotEmpty == true
          ? map['createdAt'] as String
          : DateTime.now().toIso8601String(),
      completedAt: map['completedAt'] as String?,
    );
  }

  TaskModel copyWith({
    int? id,
    String? userId,
    String? title,
    String? description,
    String? category,
    String? priority,
    String? date,
    String? time,
    bool? reminder,
    bool? isCompleted,
    String? createdAt,
    String? completedAt,
    bool clearCompletedAt = false,
  }) {
    return TaskModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      date: date ?? this.date,
      time: time ?? this.time,
      reminder: reminder ?? this.reminder,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }
}
