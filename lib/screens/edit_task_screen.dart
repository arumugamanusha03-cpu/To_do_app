import 'package:flutter/material.dart';

import '../models/task_model.dart';
import '../widgets/task_form.dart';

/// Editing an existing task — same form as [AddTaskScreen], plus delete.
class EditTaskScreen extends StatelessWidget {
  final TaskModel task;

  const EditTaskScreen({super.key, required this.task});

  @override
  Widget build(BuildContext context) => TaskForm(task: task);
}
