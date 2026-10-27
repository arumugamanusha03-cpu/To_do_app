import 'package:flutter/material.dart';

import '../services/coach.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import 'gradient_background.dart';

/// The line the app greets you with on the home screen.
///
/// This is where the assistant is visible day to day — no badge on a button,
/// just the app noticing what your list looks like and saying so.
class CoachCard extends StatelessWidget {
  final CoachMessage message;

  /// Called when the action is tapped, with the action to perform.
  final void Function(CoachAction action)? onAction;

  const CoachCard({
    super.key,
    required this.message,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final hasAction =
        message.actionLabel != null && message.action != CoachAction.none;

    return GlassPanel(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      borderColor: AppColors.purple.withValues(alpha: .22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),

          if (message.sub != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              message.sub!,
              style: const TextStyle(
                color: AppColors.grey,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],

          if (hasAction) ...[
            const SizedBox(height: AppSpacing.sm + 2),
            GestureDetector(
              onTap: () => onAction?.call(message.action),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.actionLabel!,
                    style: const TextStyle(
                      color: AppColors.pink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: AppSpacing.iconChip + 2,
                    color: AppColors.pink,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
