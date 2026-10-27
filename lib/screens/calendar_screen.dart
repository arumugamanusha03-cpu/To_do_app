import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../database/database_helper.dart';
import '../models/task_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/task_events.dart';
import '../utils/app_colors.dart';
import '../utils/date_helper.dart';
import '../widgets/empty_state.dart';
import '../widgets/task_card.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateHelper.dateOnly(DateTime.now());
  CalendarFormat _format = CalendarFormat.month;

  /// Every task in the focused month, keyed by day — the calendar reads its
  /// markers straight from this instead of hitting the database per cell.
  Map<DateTime, List<TaskModel>> _byDay = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    tasksChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    tasksChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final userId = AuthService.uid;
    if (userId.isEmpty) return;

    final grouped = await DatabaseHelper.instance.getTasksGroupedByDay(
      userId: userId,
      month: _focusedDay,
    );

    if (!mounted) return;
    setState(() {
      _byDay = grouped;
      _loading = false;
    });
  }

  List<TaskModel> _tasksFor(DateTime day) =>
      _byDay[DateHelper.dateOnly(day)] ?? const [];

  Future<void> _toggle(TaskModel task) async {
    final updated = await DatabaseHelper.instance.toggleCompleted(task);

    if (updated.isCompleted) {
      await NotificationService.cancelForTask(updated.id!);
    } else {
      await NotificationService.scheduleForTask(updated);
    }

    notifyTasksChanged();
  }

  Future<void> _addForSelectedDay() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(initialDate: _selectedDay),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedTasks = _tasksFor(_selectedDay);
    final done = selectedTasks.where((t) => t.isCompleted).length;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.pink,
      backgroundColor: const Color(0xFF1E2340),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Calendar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 18),

          _calendarCard(),

          const SizedBox(height: 26),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateHelper.relativeLabel(_selectedDay),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateHelper.prettyDate(_selectedDay),
                      style: const TextStyle(
                        color: AppColors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (selectedTasks.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .12),
                    ),
                  ),
                  child: Text(
                    '$done / ${selectedTasks.length} done',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.pink),
              ),
            )
          else if (selectedTasks.isEmpty)
            EmptyState(
              icon: Icons.event_available_rounded,
              title: 'Nothing scheduled',
              message:
                  'No tasks on ${DateHelper.prettyDate(_selectedDay)}. '
                  'Add one and it will show up on this day.',
              actionLabel: 'Add for this day',
              onAction: _addForSelectedDay,
            )
          else
            ...selectedTasks.map(
              (task) => TaskCard(
                task: task,
                showDate: false,
                onToggle: () => _toggle(task),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditTaskScreen(task: task),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _calendarCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: .12),
            ),
          ),
          child: TableCalendar<TaskModel>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _format,
            startingDayOfWeek: StartingDayOfWeek.monday,
            eventLoader: _tasksFor,

            selectedDayPredicate: (day) =>
                DateHelper.isSameDate(_selectedDay, day),

            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = DateHelper.dateOnly(selected);
                _focusedDay = focused;
              });
            },

            onFormatChanged: (format) => setState(() => _format = format),

            // Markers only exist for the loaded month, so a page change
            // reloads before the new cells are painted.
            onPageChanged: (focused) {
              _focusedDay = focused;
              _load();
            },

            headerStyle: HeaderStyle(
              titleCentered: true,
              formatButtonVisible: true,
              formatButtonShowsNext: false,
              formatButtonDecoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(20),
              ),
              formatButtonTextStyle: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
              ),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
              leftChevronIcon:
                  const Icon(Icons.chevron_left, color: Colors.white),
              rightChevronIcon:
                  const Icon(Icons.chevron_right, color: Colors.white),
            ),

            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(color: Colors.white70, fontSize: 12.5),
              weekendStyle: TextStyle(color: Colors.white38, fontSize: 12.5),
            ),

            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: const TextStyle(color: Colors.white),
              weekendTextStyle: const TextStyle(color: Colors.white70),
              todayDecoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: .35),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              markersMaxCount: 3,
              markerDecoration: const BoxDecoration(
                color: AppColors.pink,
                shape: BoxShape.circle,
              ),
              markerSize: 5,
              markersAlignment: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
    );
  }
}
