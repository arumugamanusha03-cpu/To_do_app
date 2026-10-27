import 'package:flutter/material.dart';

class PriorityChip extends StatelessWidget {
  final String text;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const PriorityChip({
    super.key,
    required this.text,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(text),
      selected: selected,
      selectedColor: color,
      backgroundColor: Colors.white10,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white70,
      ),
      onSelected: (_) => onTap(),
    );
  }
}