import 'package:flutter/material.dart';

import '../models/task_model.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'gradient_background.dart';

/// A single task row. Tapping the circle completes it, tapping the body
/// opens the edit screen.
class TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;

  /// Shows the due-date chip. Off on the calendar, where the date is implied.
  final bool showDate;

  const TaskCard({
    super.key,
    required this.task,
    this.onToggle,
    this.onTap,
    this.showDate = true,
  });

  @override
  Widget build(BuildContext context) {
    final done = task.isCompleted;
    final overdue = task.isOverdue;
    final category = task.categoryInfo;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 4),
      child: GlassPanel(
        onTap: onTap,
        borderColor: overdue
            ? Colors.redAccent.withValues(alpha: .35)
            : Colors.white.withValues(alpha: .12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Complete / re-open toggle.
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 14, top: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? AppColors.pink : Colors.transparent,
                    border: Border.all(
                      color: done ? AppColors.pink : Colors.white54,
                      width: 2,
                    ),
                  ),
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: done ? Colors.white54 : Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      decoration:
                          done ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white38,
                    ),
                  ),

                  if (task.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      task.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Metadata stays monochrome so the eye goes to the title and
                  // the priority badge. Colour on a card is reserved for
                  // status: priority, and overdue.
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Chip(
                        icon: category.icon,
                        label: category.name,
                      ),
                      _Chip(
                        icon: Icons.schedule_rounded,
                        label: showDate
                            ? '${task.displayDate} • ${task.displayTime}'
                            : task.displayTime,
                        color: overdue ? Colors.redAccent : null,
                      ),
                      if (task.reminder && !done)
                        const _Chip(
                          icon: Icons.notifications_none_rounded,
                          label: 'Reminder',
                        ),
                      if (overdue)
                        const _Chip(
                          icon: Icons.error_outline_rounded,
                          label: 'Overdue',
                          color: Colors.redAccent,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: task.priorityColor.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                task.priority,
                style: TextStyle(
                  color: task.priorityColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Null means the default muted white — colour is opt-in, for status only.
  final Color? color;

  const _Chip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Colors.white54;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSpacing.iconChip, color: tone),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: tone,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
