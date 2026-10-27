import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/task_events.dart';
import '../services/task_intelligence.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';
import '../widgets/empty_state.dart';

/// Lays out everything still open for today and proposes a time for each.
///
/// Overdue work comes first, then priority, starting from the next quarter
/// hour and favouring the hours this person actually finishes things in.
/// Nothing is written until "Apply plan" is pressed.
class PlanDaySheet extends StatefulWidget {
  const PlanDaySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PlanDaySheet(),
    );
  }

  @override
  State<PlanDaySheet> createState() => _PlanDaySheetState();
}

class _PlanDaySheetState extends State<PlanDaySheet> {
  TaskProfile _profile = const TaskProfile();
  List<PlannedSlot> _slots = [];
  bool _loading = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final userId = AuthService.uid;
    if (userId.isEmpty) return;

    final profile = await TaskIntelligence.learn(userId);

    final pending = await DatabaseHelper.instance.getTasks(
      userId: userId,
      filter: TaskFilter.pending,
    );

    // Today's work plus anything that has already slipped.
    final today = DateHelper.dateOnly(DateTime.now());
    final relevant = pending
        .where((t) =>
            DateHelper.isSameDate(t.dueDate, today) ||
            t.dueDate.isBefore(today))
        .toList();

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _slots = profile.planDay(relevant);
      _loading = false;
    });
  }

  Future<void> _apply() async {
    setState(() => _applying = true);

    final today = DateHelper.toIsoDate(DateTime.now());
    var moved = 0;

    try {
      for (final slot in _slots) {
        if (!slot.moved && slot.task.date == today) continue;

        final updated = slot.task.copyWith(
          date: today,
          time: DateHelper.toStoredTime(slot.start),
        );

        await DatabaseHelper.instance.updateTask(updated);
        await NotificationService.scheduleForTask(updated);
        moved++;
      }

      notifyTasksChanged();

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              moved == 0
                  ? 'Your day was already in good shape'
                  : '$moved task${moved == 1 ? '' : 's'} rescheduled',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not apply the plan: $error')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF10162F),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusSheet),
            ),
            border: Border.all(
              color: AppColors.blue.withValues(alpha: .3),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _header(),
              const Divider(color: Colors.white12, height: AppSpacing.lg),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.pink,
                        ),
                      )
                    : _slots.isEmpty
                        ? _empty()
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.page,
                              0,
                              AppSpacing.page,
                              AppSpacing.md,
                            ),
                            itemCount: _slots.length,
                            itemBuilder: (context, index) =>
                                _slotTile(_slots[index], index),
                          ),
              ),
              if (!_loading && _slots.isNotEmpty) _applyBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event_note_rounded,
              color: AppColors.blue,
              size: AppSpacing.iconFeature,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plan my day',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _profile.productiveHours.isEmpty
                      ? 'Ordered by what is overdue, then priority'
                      : 'Built around the hours you actually finish things',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return const SingleChildScrollView(
      child: EmptyState(
        icon: Icons.beach_access_rounded,
        title: 'Nothing left for today',
        message:
            'No open tasks due today and nothing overdue. There is nothing '
            'to plan — enjoy it.',
      ),
    );
  }

  Widget _slotTile(PlannedSlot slot, int index) {
    final task = slot.task;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateHelper.prettyTime(slot.start),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (slot.moved)
                  Text(
                    'was ${task.displayTime}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),

          // Timeline rail.
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: task.isOverdue
                      ? Colors.redAccent
                      : task.priorityColor,
                ),
              ),
              if (index != _slots.length - 1)
                Container(
                  width: 2,
                  height: 46,
                  color: Colors.white12,
                ),
            ],
          ),

          const SizedBox(width: AppSpacing.sm + 2),

          Expanded(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(AppSpacing.radiusField),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        '${task.category} • ${task.priority}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12.5,
                        ),
                      ),
                      if (task.isOverdue) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'Overdue',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _applyBar() {
    final moving = _slots.where((s) => s.moved).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        children: [
          Text(
            moving == 0
                ? 'Everything is already at a sensible time'
                : '$moving task${moving == 1 ? '' : 's'} would move',
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _applying ? null : _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                disabledBackgroundColor: AppColors.blue.withValues(alpha: .5),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusField),
                ),
              ),
              icon: _applying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check_rounded, color: Colors.white),
              label: const Text(
                'Apply plan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
