import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/task_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/shared_pref_service.dart';
import '../services/smart_parser.dart';
import '../services/task_events.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';
import 'category_dropdown.dart';
import 'custom_button.dart';
import 'custom_textfield.dart';
import 'date_time_card.dart';
import 'gradient_background.dart';
import 'priority_chip.dart';
import 'section_title.dart';

/// The Add and Edit screens are the same form; [task] decides which.
class TaskForm extends StatefulWidget {
  final TaskModel? task;

  /// Pre-selects a date when the form is opened from the calendar.
  final DateTime? initialDate;

  const TaskForm({super.key, this.task, this.initialDate});

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();

  final _smartController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  late String _category;
  late String _priority;
  late DateTime _date;
  late TimeOfDay _time;
  late bool _reminder;

  List<String> _detections = [];
  bool _saving = false;

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();

    final task = widget.task;

    if (task != null) {
      _titleController.text = task.title;
      _descriptionController.text = task.description;
      _category = AppConstants.categoryOf(task.category).name;
      _priority = AppConstants.priorities.contains(task.priority)
          ? task.priority
          : AppConstants.priorityMedium;
      _date = task.dueDate;
      _time = task.dueTime;
      _reminder = task.reminder;
    } else {
      _category = AppConstants.categoryNames.first;
      _priority = AppConstants.priorityMedium;
      _date = DateHelper.dateOnly(widget.initialDate ?? DateTime.now());
      _time = _defaultTime();
      _reminder = true;
    }
  }

  /// The next round half hour, so a new task is never scheduled in the past.
  TimeOfDay _defaultTime() {
    final soon = DateTime.now().add(const Duration(hours: 1));
    return TimeOfDay(hour: soon.hour, minute: soon.minute < 30 ? 0 : 30);
  }

  @override
  void dispose() {
    _smartController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ===========================
  // SMART INPUT
  // ===========================

  void _applySmartInput() {
    final raw = _smartController.text.trim();
    if (raw.isEmpty) return;

    final parsed = SmartTaskParser.parse(raw);

    setState(() {
      _titleController.text = parsed.title;

      if (parsed.date != null) _date = DateHelper.dateOnly(parsed.date!);
      if (parsed.time != null) _time = parsed.time!;
      if (parsed.priority != null) _priority = parsed.priority!;
      if (parsed.category != null) _category = parsed.category!;

      _detections = parsed.detections;
    });

    FocusScope.of(context).unfocus();

    if (!parsed.hasAnything) {
      _toast('Added as the title — no date or priority spotted.');
    }
  }

  // ===========================
  // PICKERS
  // ===========================

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  // ===========================
  // SAVE / DELETE
  // ===========================

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = AuthService.uid;
    if (userId.isEmpty) {
      _toast('You are signed out. Sign in again to save tasks.');
      return;
    }

    setState(() => _saving = true);

    try {
      final due = DateHelper.combine(_date, _time);

      final base = widget.task;
      final task = TaskModel(
        id: base?.id,
        userId: userId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        priority: _priority,
        date: DateHelper.toIsoDate(_date),
        time: DateHelper.toStoredTime(_time),
        reminder: _reminder,
        isCompleted: base?.isCompleted ?? false,
        createdAt: base?.createdAt,
        completedAt: base?.completedAt,
      );

      if (_isEditing) {
        await DatabaseHelper.instance.updateTask(task);
      } else {
        task.id = await DatabaseHelper.instance.insertTask(task);
      }

      await NotificationService.scheduleForTask(task);
      notifyTasksChanged();

      if (!mounted) return;

      final remindersOn = await SharedPrefService.getNotificationsEnabled();
      final willRemind =
          _reminder && remindersOn && due.isAfter(DateTime.now());

      if (!mounted) return;

      Navigator.pop(context, true);

      _toast(
        _isEditing ? 'Task updated' : 'Task saved',
        detail: willRemind
            ? 'Reminder set for ${DateHelper.relativeLabel(_date)} '
                '${DateHelper.prettyTime(_time)}'
            : null,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save the task: $error');
    }
  }

  Future<void> _delete() async {
    final task = widget.task;
    if (task?.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(
          '"${task!.title}" will be removed permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await NotificationService.cancelForTask(task!.id!);
    await DatabaseHelper.instance.deleteTask(task.id!);
    notifyTasksChanged();

    if (!mounted) return;
    Navigator.pop(context, true);
    _toast('Task deleted');
  }

  void _toast(String message, {String? detail}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================
  // UI
  // ===========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 24),

                  if (!_isEditing) ...[
                    _smartInputCard(),
                    const SizedBox(height: 28),
                  ],

                  const SectionTitle(title: 'Task Title'),
                  CustomTextField(
                    controller: _titleController,
                    hintText: 'What needs to be done?',
                    prefixIcon: Icons.edit_note_rounded,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return 'Give the task a title';
                      if (text.length < 3) return 'Title is too short';
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  const SectionTitle(title: 'Description (optional)'),
                  CustomTextField(
                    controller: _descriptionController,
                    hintText: 'Add any details you want to remember',
                    prefixIcon: Icons.description_outlined,
                    maxLines: 4,
                  ),

                  const SizedBox(height: 24),

                  const SectionTitle(title: 'Category'),
                  CategoryDropdown(
                    value: _category,
                    items: AppConstants.categoryNames,
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
                    },
                  ),

                  const SizedBox(height: 24),

                  const SectionTitle(title: 'Priority'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: AppConstants.priorities.map((priority) {
                      return PriorityChip(
                        text: priority,
                        color: AppConstants.priorityColor(priority),
                        selected: _priority == priority,
                        onTap: () => setState(() => _priority = priority),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 28),

                  const SectionTitle(title: 'Date & Time'),
                  Row(
                    children: [
                      DateTimeCard(
                        icon: Icons.calendar_today_rounded,
                        title: 'Date',
                        value: DateHelper.shortDate(_date),
                        subtitle: DateHelper.relativeLabel(_date),
                        onTap: _pickDate,
                      ),
                      const SizedBox(width: 15),
                      DateTimeCard(
                        icon: Icons.access_time_rounded,
                        title: 'Time',
                        value: DateHelper.prettyTime(_time),
                        onTap: _pickTime,
                      ),
                    ],
                  ),

                  if (DateHelper.combine(_date, _time)
                      .isBefore(DateTime.now())) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isEditing
                                ? 'This time has passed — no reminder will fire.'
                                : 'That time has already passed today.',
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),

                  GlassPanel(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _reminder,
                      activeThumbColor: AppColors.pink,
                      onChanged: (value) => setState(() => _reminder = value),
                      title: const Text(
                        'Enable Reminder',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Notify me at the scheduled time',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  CustomButton(
                    text: _isEditing ? 'Update Task' : 'Save Task',
                    icon: _saving ? null : Icons.save_rounded,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),

                  if (_isEditing) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Delete Task',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Text(
          _isEditing ? 'Edit Task' : 'Add Task',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _smartInputCard() {
    return GlassPanel(
      borderColor: AppColors.purple.withValues(alpha: .35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Smart Add',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          const Text(
            'Type it the way you would say it — the date, time, priority and '
            'category get filled in for you.',
            style: TextStyle(
              color: AppColors.grey,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _smartController,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _applySmartInput(),
            decoration: InputDecoration(
              hintText: 'Submit client report tomorrow 5pm urgent',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              filled: true,
              fillColor: Colors.white.withValues(alpha: .06),
              suffixIcon: IconButton(
                onPressed: _applySmartInput,
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.pink,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: .10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.purple,
                  width: 1.5,
                ),
              ),
            ),
          ),

          if (_detections.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _detections.map((detection) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: AppColors.purple.withValues(alpha: .4),
                    ),
                  ),
                  child: Text(
                    detection,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
