import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/gradient_background.dart';
import 'add_task_screen.dart';
import 'ai_assist_sheet.dart';
import 'analytics_screen.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Holds the four tabs in an `IndexedStack` so switching tabs keeps each
/// one's scroll position and loaded data.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _goToTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  /// The + opens the assistant, which is where adding a task now starts.
  /// Long-pressing skips straight to the full form for anyone who would
  /// rather fill the fields in themselves.
  Future<void> _openAssistant() => AiAssistSheet.show(context);

  Future<void> _openFullForm() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddTaskScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,

      floatingActionButton: GestureDetector(
        onLongPress: _openFullForm,
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.pink.withValues(alpha: .45),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            // Just a plus. The assistant announces itself by talking to you
            // on the home screen, which reads better than a badge on a
            // button nobody stops to decode.
            child: InkWell(
              onTap: _openAssistant,
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: BottomNav(
        currentIndex: _index,
        onTap: _goToTab,
      ),

      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              HomeTab(onOpenTab: _goToTab),
              const CalendarTab(),
              const AnalyticsTab(),
              const SettingsTab(),
            ],
          ),
        ),
      ),
    );
  }
}
