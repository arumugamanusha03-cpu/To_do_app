import 'package:flutter/material.dart';

import '../widgets/task_form.dart';

/// Creating a task. The form itself lives in [TaskForm], which the edit
/// screen reuses.
class AddTaskScreen extends StatelessWidget {
  /// Pre-selects a date when opened from the calendar tab.
  final DateTime? initialDate;

  const AddTaskScreen({super.key, this.initialDate});

  @override
  Widget build(BuildContext context) => TaskForm(initialDate: initialDate);
}
