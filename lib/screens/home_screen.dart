import 'dart:ui';

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/task_model.dart';
import '../services/auth_service.dart';
import '../services/coach.dart';
import '../services/notification_service.dart';
import '../services/shared_pref_service.dart';
import '../services/task_events.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/constants.dart';
import '../widgets/coach_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_icon.dart';
import '../widgets/sort_sheet.dart';
import '../widgets/stat_card.dart';
import '../widgets/task_card.dart';
import 'ai_assist_sheet.dart';
import 'edit_task_screen.dart';

class HomeTab extends StatefulWidget {
  /// Lets the "See calendar" shortcut switch the shell's tab.
  final ValueChanged<int> onOpenTab;

  const HomeTab({super.key, required this.onOpenTab});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _searchController = TextEditingController();

  List<TaskModel> _tasks = [];
  TaskStats _stats = const TaskStats();
  CoachMessage? _coach;
  TaskFilter _filter = TaskFilter.all;
  TaskSort _sort = TaskSort.dueDate;
  String? _category;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    tasksChanged.addListener(_load);
    _restoreSortThenLoad();
  }

  @override
  void dispose() {
    tasksChanged.removeListener(_load);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreSortThenLoad() async {
    _sort = await SharedPrefService.getSort();
    await _load();
  }

  Future<void> _load() async {
    final userId = AuthService.uid;
    if (userId.isEmpty) return;

    final db = DatabaseHelper.instance;

    final tasks = await db.getTasks(
      userId: userId,
      search: _searchController.text,
      category: _category,
      filter: _filter,
      sort: _sort,
    );
    final stats = await db.getStats(userId);
    final streak = await db.getCurrentStreak(userId);
    final tanglish = await SharedPrefService.getTanglish();

    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _stats = stats;
      _coach = Coach.build(
        name: AuthService.displayName,
        stats: stats,
        streak: streak,
        tanglish: tanglish,
      );
      _loading = false;
    });
  }

  void _onCoachAction(CoachAction action) {
    if (action == CoachAction.addTask) {
      _addTask();
      return;
    }

    final filter = Coach.filterFor(action);
    if (filter == null) return;

    setState(() => _filter = filter);
    _load();
  }

  // ===========================
  // ACTIONS
  // ===========================

  Future<void> _toggle(TaskModel task) async {
    final updated = await DatabaseHelper.instance.toggleCompleted(task);

    // A completed task should stop nagging; re-opening one restores it.
    if (updated.isCompleted) {
      await NotificationService.cancelForTask(updated.id!);
    } else {
      await NotificationService.scheduleForTask(updated);
    }

    notifyTasksChanged();
  }

  Future<void> _delete(TaskModel task) async {
    if (task.id == null) return;

    await NotificationService.cancelForTask(task.id!);
    await DatabaseHelper.instance.deleteTask(task.id!);
    notifyTasksChanged();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${task.title}"'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.pink,
            onPressed: () async {
              // Re-inserting assigns a new row id, so the reminder is
              // rescheduled against the restored task.
              final restored = task.copyWith();
              restored.id = await DatabaseHelper.instance
                  .insertTask(restored..id = null);
              await NotificationService.scheduleForTask(restored);
              notifyTasksChanged();
            },
          ),
        ),
      );
  }

  Future<void> _openTask(TaskModel task) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditTaskScreen(task: task)),
    );
  }

  /// Adding starts in the assistant, same as the + button, so there is one
  /// way in rather than two that behave differently.
  Future<void> _addTask() => AiAssistSheet.show(context);

  Future<void> _pickSort() async {
    final picked = await showSortSheet(context, _sort);
    if (picked == null || !mounted) return;
    await SharedPrefService.setSort(picked);
    setState(() => _sort = picked);
    await _load();
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filter by category',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.clear_all_rounded,
                  color: Colors.white70),
              title: const Text(
                'All categories',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            ...AppConstants.categories.map(
              (category) => ListTile(
                leading: Icon(category.icon, color: category.color),
                title: Text(
                  category.name,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: _category == category.name
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.pink)
                    : null,
                onTap: () => Navigator.pop(sheetContext, category.name),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (picked == null) return;
    setState(() => _category = picked.isEmpty ? null : picked);
    await _load();
  }

  // ===========================
  // UI
  // ===========================

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.pink,
      backgroundColor: const Color(0xFF1E2340),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _header(),
          const SizedBox(height: AppSpacing.lg),
          if (_coach != null)
            CoachCard(message: _coach!, onAction: _onCoachAction),
          const SizedBox(height: AppSpacing.lg),
          _searchField(),
          const SizedBox(height: 20),
          _filterRow(),
          const SizedBox(height: 28),
          _overview(),
          const SizedBox(height: 30),
          _listHeader(),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 50),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.pink),
              ),
            )
          else if (_tasks.isEmpty)
            _emptyState()
          else
            ..._tasks.map(_dismissibleCard),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        GlassIcon(
          icon: Icons.tune_rounded,
          onTap: _pickCategory,
        ),
        const Spacer(),
        GlassIcon(
          icon: _sort == TaskSort.dueDate
              ? Icons.sort_rounded
              : Icons.filter_list_rounded,
          onTap: _pickSort,
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => widget.onOpenTab(3),
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient,
            ),
            child: Center(
              child: Text(
                AuthService.initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: .12),
            ),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => _load(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              hintText: 'Search tasks...',
              hintStyle: const TextStyle(color: Colors.white54),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54),
                      onPressed: () {
                        _searchController.clear();
                        _load();
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterRow() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...TaskFilter.values.map((filter) {
            final selected = _filter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () {
                  setState(() => _filter = filter);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: selected ? AppColors.primaryGradient : null,
                    color: selected
                        ? null
                        : Colors.white.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : Colors.white.withValues(alpha: .12),
                    ),
                  ),
                  child: Text(
                    filter.label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            );
          }),
          if (_category != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () {
                  setState(() => _category = null);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.categoryOf(_category!)
                        .color
                        .withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: AppConstants.categoryOf(_category!).color,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _category!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.task_alt_rounded,
                title: 'Total',
                value: _stats.total.toString(),
                color: AppColors.pink,
                onTap: () {
                  setState(() => _filter = TaskFilter.all);
                  _load();
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: StatCard(
                icon: Icons.check_circle_outline_rounded,
                title: 'Completed',
                value: _stats.completed.toString(),
                color: Colors.greenAccent,
                onTap: () {
                  setState(() => _filter = TaskFilter.completed);
                  _load();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.pending_actions_rounded,
                title: 'Pending',
                value: _stats.pending.toString(),
                color: Colors.orangeAccent,
                onTap: () {
                  setState(() => _filter = TaskFilter.pending);
                  _load();
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: StatCard(
                icon: Icons.priority_high_rounded,
                title: 'High priority',
                value: _stats.highPriority.toString(),
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _listHeader() {
    final label = switch (_filter) {
      TaskFilter.all => 'All Tasks',
      TaskFilter.pending => 'Pending Tasks',
      TaskFilter.completed => 'Completed Tasks',
      TaskFilter.today => "Today's Tasks",
      TaskFilter.overdue => 'Overdue Tasks',
    };

    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 10),
        if (!_loading)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _tasks.length.toString(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => widget.onOpenTab(1),
          child: const Text(
            'Calendar',
            style: TextStyle(
              color: AppColors.blue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dismissibleCard(TaskModel task) {
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
        ),
      ),
      onDismissed: (_) => _delete(task),
      child: TaskCard(
        task: task,
        onToggle: () => _toggle(task),
        onTap: () => _openTask(task),
      ),
    );
  }

  Widget _emptyState() {
    final searching = _searchController.text.trim().isNotEmpty;

    if (searching) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message:
            'Nothing matches "${_searchController.text.trim()}". Try a '
            'different word or clear the search.',
      );
    }

    final message = switch (_filter) {
      TaskFilter.completed =>
        'Complete a task and it will show up here.',
      TaskFilter.today => 'Nothing is scheduled for today.',
      TaskFilter.overdue => 'Nothing is overdue. Well done!',
      TaskFilter.pending => 'No pending tasks — everything is done.',
      TaskFilter.all => 'Add your first task and it will appear here.',
    };

    return EmptyState(
      icon: Icons.checklist_rtl_rounded,
      title: 'Nothing here yet',
      message: message,
      actionLabel: 'Add a task',
      onAction: _addTask,
    );
  }
}
