import 'package:flutter/material.dart';

import '../utils/constants.dart';

class CategoryDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const CategoryDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Guard against a stored category that is no longer in the list.
    final selected = items.contains(value) ? value : items.first;

    return DropdownButtonFormField<String>(
      initialValue: selected,
      dropdownColor: const Color(0xFF1E2340),
      borderRadius: BorderRadius.circular(18),
      icon: const Icon(Icons.expand_more_rounded, color: Colors.white70),
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .08),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: .10),
          ),
        ),
      ),
      items: items.map((name) {
        final category = AppConstants.categoryOf(name);
        return DropdownMenuItem(
          value: name,
          child: Row(
            children: [
              Icon(category.icon, size: 18, color: category.color),
              const SizedBox(width: 12),
              Text(name, style: const TextStyle(color: Colors.white)),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
