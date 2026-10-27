import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/task_events.dart';
import '../services/task_intelligence.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/constants.dart';
import '../utils/date_helper.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_background.dart';
import '../widgets/stat_card.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  TaskStats _stats = const TaskStats();
  List<DayProgress> _week = [];
  List<MapEntry<String, int>> _categories = [];
  int _streak = 0;
  int _createdThisMonth = 0;
  int _completedThisMonth = 0;
  List<TaskInsight> _insights = [];
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

    final db = DatabaseHelper.instance;

    final stats = await db.getStats(userId);
    final week = await db.getWeeklyProgress(userId);
    final categories = await db.getCategoryBreakdown(userId);
    final streak = await db.getCurrentStreak(userId);
    final monthly = await db.getMonthlySummary(userId);
    final profile = await TaskIntelligence.learn(userId);

    if (!mounted) return;
    setState(() {
      _stats = stats;
      _week = week;
      _categories = categories;
      _streak = streak;
      _createdThisMonth = monthly.$1;
      _completedThisMonth = monthly.$2;
      _insights = profile.insights();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.pink),
      );
    }

    if (_stats.total == 0) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 40),
          EmptyState(
            icon: Icons.insights_rounded,
            title: 'No data yet',
            message:
                'Add and complete a few tasks — your progress, streak and '
                'category split will show up here.',
          ),
        ],
      );
    }

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
              'Analytics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 20),

          _completionHero(),

          if (_insights.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _insightsSection(),
          ],

          const SizedBox(height: 26),

          _sectionTitle('Task Overview'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.task_alt_rounded,
                  title: 'Total',
                  value: _stats.total.toString(),
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: StatCard(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Done',
                  value: _stats.completed.toString(),
                  color: Colors.greenAccent,
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
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: StatCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Overdue',
                  value: _stats.overdue.toString(),
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          _sectionTitle('Last 7 Days'),
          const SizedBox(height: 6),
          const Text(
            'Share of that day\'s tasks you completed.',
            style: TextStyle(color: AppColors.grey, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          _weeklyChart(),

          const SizedBox(height: 30),

          _sectionTitle('By Category'),
          const SizedBox(height: 18),
          _categoryBreakdown(),

          const SizedBox(height: 30),

          _sectionTitle('This Month'),
          const SizedBox(height: 18),
          _monthlySummary(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 21,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// Patterns the app worked out from this person's own history. Each line
  /// states what was noticed and why it matters — no score, no black box.
  Widget _insightsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: AppSpacing.iconChip + 2,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _sectionTitle('What I noticed'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Worked out on this phone from your own tasks.',
          style: TextStyle(color: AppColors.grey, fontSize: 13.5),
        ),
        const SizedBox(height: AppSpacing.md),
        ..._insights.map(
          (insight) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
            child: GlassPanel(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    insight.icon,
                    size: AppSpacing.iconList,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          insight.detail,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The one number that matters, stated once, with the bar as support.
  Widget _completionHero() {
    final percent = _stats.completionPercent;

    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            '$percent%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 46,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_stats.completed} of ${_stats.total} tasks completed',
            style: const TextStyle(color: AppColors.grey, fontSize: 14.5),
          ),

          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: _stats.completionRate,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: .1),
              valueColor: const AlwaysStoppedAnimation(AppColors.pink),
            ),
          ),

          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Colors.orangeAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _streak == 0
                    ? 'No streak yet — finish a task today'
                    : '$_streak day${_streak == 1 ? '' : 's'} in a row',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A single-series column chart: one hue, height carries the value, and
  /// only the best day is labelled so the axis stays quiet.
  Widget _weeklyChart() {
    final bestIndex = _bestDayIndex();

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      child: SizedBox(
        height: 190,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_week.length, (index) {
            final day = _week[index];
            final isBest = index == bestIndex;
            final isToday = DateHelper.isSameDate(day.day, DateTime.now());

            return Expanded(
              child: Padding(
                // A 2px gap on each side keeps neighbouring bars separate.
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Tooltip(
                  message: day.total == 0
                      ? '${DateHelper.weekdayLabel(day.day)}: no tasks'
                      : '${DateHelper.weekdayLabel(day.day)}: '
                          '${day.completed}/${day.total} done '
                          '(${day.percent}%)',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isBest && day.total > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${day.percent}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final height = day.total == 0
                                ? 3.0
                                : (constraints.maxHeight * day.rate)
                                    .clamp(6.0, constraints.maxHeight);

                            return Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color: day.total == 0
                                      ? Colors.white.withValues(alpha: .12)
                                      : AppColors.pink.withValues(
                                          alpha: isBest ? 1 : .75,
                                        ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        DateHelper.weekdayLabel(day.day).substring(0, 1),
                        style: TextStyle(
                          color: isToday ? Colors.white : Colors.white54,
                          fontSize: 12.5,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  int _bestDayIndex() {
    var bestIndex = -1;
    var bestRate = 0.0;

    for (var i = 0; i < _week.length; i++) {
      if (_week[i].total > 0 && _week[i].rate > bestRate) {
        bestRate = _week[i].rate;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// Horizontal bars, each labelled with its icon, name and count — identity
  /// never rests on colour alone.
  Widget _categoryBreakdown() {
    if (_categories.isEmpty) {
      return const GlassPanel(
        child: Text(
          'No categories to show yet.',
          style: TextStyle(color: AppColors.grey),
        ),
      );
    }

    final max = _categories
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: _categories.map((entry) {
          final category = AppConstants.categoryOf(entry.key);
          final share = max == 0 ? 0.0 : entry.value / max;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(category.icon, size: 17, color: category.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        category.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      entry.value.toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: .08),
                    valueColor: AlwaysStoppedAnimation(category.color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _monthlySummary() {
    Widget row(IconData icon, Color color, String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final pending = _createdThisMonth - _completedThisMonth;

    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Column(
        children: [
          row(
            Icons.calendar_month_rounded,
            AppColors.blue,
            DateHelper.monthYear(DateTime.now()),
            '',
          ),
          const Divider(color: Colors.white12, height: 1),
          row(
            Icons.add_task_rounded,
            AppColors.blue,
            'Tasks created',
            _createdThisMonth.toString(),
          ),
          const Divider(color: Colors.white12, height: 1),
          row(
            Icons.check_circle_outline_rounded,
            Colors.greenAccent,
            'Completed',
            _completedThisMonth.toString(),
          ),
          const Divider(color: Colors.white12, height: 1),
          row(
            Icons.pending_outlined,
            Colors.orangeAccent,
            'Still open',
            (pending < 0 ? 0 : pending).toString(),
          ),
        ],
      ),
    );
  }
}
