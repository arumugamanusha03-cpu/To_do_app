import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/constants.dart';

/// Bottom sheet used by both Home and Settings to choose the task order.
/// Returns null when dismissed without choosing.
Future<TaskSort?> showSortSheet(BuildContext context, TaskSort current) {
  return showModalBottomSheet<TaskSort>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sort tasks by',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ...TaskSort.values.map((sort) {
            final selected = sort == current;
            return ListTile(
              onTap: () => Navigator.pop(sheetContext, sort),
              leading: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.pink : Colors.white38,
              ),
              title: Text(
                sort.label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
        ],
      ),
    ),
  );
}
