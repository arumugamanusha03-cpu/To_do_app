import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/database/database_helper.dart';
import 'package:todo_app/models/task_model.dart';
import 'package:todo_app/services/coach.dart';
import 'package:todo_app/services/password_hasher.dart';
import 'package:todo_app/services/smart_parser.dart';
import 'package:todo_app/services/task_breakdown.dart';
import 'package:todo_app/services/task_intelligence.dart';
import 'package:todo_app/utils/constants.dart';
import 'package:todo_app/utils/date_helper.dart';

/// Builds a task without repeating every required field in each test.
TaskModel _task({
  required String title,
  String category = 'Work',
  String priority = AppConstants.priorityMedium,
  String date = '2026-09-10',
  String time = '09:00',
  bool completed = false,
  String? completedAt,
  String? createdAt,
}) {
  return TaskModel(
    userId: '1',
    title: title,
    description: '',
    category: category,
    priority: priority,
    date: date,
    time: time,
    reminder: true,
    isCompleted: completed,
    completedAt: completedAt,
    createdAt: createdAt ?? '2026-09-01T09:00:00.000',
  );
}

void main() {
  // PasswordHasher hashes on a background isolate via `compute`.
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fixed "now" so the relative-date cases are deterministic.
  // 2026-09-10 is a Thursday.
  final now = DateTime(2026, 9, 10, 10, 0);

  group('DateHelper', () {
    test('parses the legacy d/M/yyyy format written by v1 of the app', () {
      expect(DateHelper.parseDate('5/3/2026'), DateTime(2026, 3, 5));
    });

    test('parses the ISO format', () {
      expect(DateHelper.parseDate('2026-03-05'), DateTime(2026, 3, 5));
    });

    test('parses legacy 12-hour times', () {
      expect(DateHelper.parseTime('9:00 AM'), const TimeOfDay(hour: 9, minute: 0));
      expect(DateHelper.parseTime('3:30 PM'), const TimeOfDay(hour: 15, minute: 30));
      expect(DateHelper.parseTime('12:00 AM'), const TimeOfDay(hour: 0, minute: 0));
      expect(DateHelper.parseTime('12:15 PM'), const TimeOfDay(hour: 12, minute: 15));
    });

    test('falls back instead of throwing on unreadable values', () {
      expect(DateHelper.parseTime('rubbish'), const TimeOfDay(hour: 9, minute: 0));
    });

    test('normalises to the sortable storage format', () {
      expect(DateHelper.normaliseDate('5/3/2026'), '2026-03-05');
      expect(DateHelper.normaliseTime('3:30 PM'), '15:30');
    });

    test('lastSevenDays ends on the given day', () {
      final days = DateHelper.lastSevenDays(now);
      expect(days.length, 7);
      expect(days.first, DateTime(2026, 9, 4));
      expect(days.last, DateTime(2026, 9, 10));
    });
  });

  group('SmartTaskParser', () {
    test('pulls the date, time and priority out of a sentence', () {
      final parsed = SmartTaskParser.parse(
        'Submit client report tomorrow 5pm urgent',
        now: now,
      );

      expect(parsed.title, 'Submit client report');
      expect(parsed.date, DateTime(2026, 9, 11));
      expect(parsed.time, const TimeOfDay(hour: 17, minute: 0));
      expect(parsed.priority, AppConstants.priorityHigh);
      expect(parsed.category, 'Work');
    });

    test('reads "day after tomorrow" before "tomorrow"', () {
      final parsed = SmartTaskParser.parse(
        'Dentist day after tomorrow 11:30 am',
        now: now,
      );

      expect(parsed.date, DateTime(2026, 9, 12));
      expect(parsed.time, const TimeOfDay(hour: 11, minute: 30));
      expect(parsed.category, 'Health');
    });

    test('resolves a weekday to its next occurrence', () {
      // Thursday 10 Sep -> next Monday is 14 Sep.
      final parsed = SmartTaskParser.parse('Team standup monday', now: now);
      expect(parsed.date, DateTime(2026, 9, 14));
    });

    test('a bare time with no date lands today when it is still ahead', () {
      final parsed = SmartTaskParser.parse('Call mom at 8pm', now: now);
      expect(parsed.date, DateTime(2026, 9, 10));
      expect(parsed.time, const TimeOfDay(hour: 20, minute: 0));
      expect(parsed.category, 'Personal');
    });

    test('a bare time that already passed rolls to tomorrow', () {
      final parsed = SmartTaskParser.parse('Yoga at 7am', now: now);
      expect(parsed.date, DateTime(2026, 9, 11));
      expect(parsed.time, const TimeOfDay(hour: 7, minute: 0));
    });

    test('understands "in 3 days"', () {
      final parsed = SmartTaskParser.parse('Renew rent in 3 days', now: now);
      expect(parsed.date, DateTime(2026, 9, 13));
    });

    test('strips filler openings', () {
      final parsed = SmartTaskParser.parse(
        'remind me to buy groceries tomorrow',
        now: now,
      );

      expect(parsed.title, 'Buy groceries');
      expect(parsed.category, 'Shopping');
    });

    test('low-priority wording is recognised', () {
      final parsed =
          SmartTaskParser.parse('Clean the desk whenever', now: now);
      expect(parsed.priority, AppConstants.priorityLow);
      expect(parsed.title, 'Clean the desk');
    });

    test('plain text keeps its title and detects nothing', () {
      final parsed = SmartTaskParser.parse('Read a book', now: now);
      expect(parsed.title, 'Read a book');
      expect(parsed.date, isNull);
      expect(parsed.time, isNull);
      expect(parsed.priority, isNull);
      expect(parsed.hasAnything, isFalse);
    });

    test('an empty input produces an empty title', () {
      expect(SmartTaskParser.parse('   ', now: now).title, '');
    });
  });

  group('PasswordHasher', () {
    test('the correct password verifies', () async {
      final hashed = await PasswordHasher.hash('correct horse battery');

      expect(
        await PasswordHasher.verify(
          password: 'correct horse battery',
          expectedHash: hashed.hash,
          salt: hashed.salt,
          iterations: hashed.iterations,
        ),
        isTrue,
      );
    });

    test('a wrong password does not verify', () async {
      final hashed = await PasswordHasher.hash('correct horse battery');

      expect(
        await PasswordHasher.verify(
          password: 'wrong horse battery',
          expectedHash: hashed.hash,
          salt: hashed.salt,
          iterations: hashed.iterations,
        ),
        isFalse,
      );
    });

    test('the same password hashes differently each time (unique salt)',
        () async {
      final first = await PasswordHasher.hash('same password');
      final second = await PasswordHasher.hash('same password');

      expect(first.salt, isNot(second.salt));
      expect(first.hash, isNot(second.hash));
    });

    test('a missing salt fails closed instead of matching', () async {
      expect(
        await PasswordHasher.verify(
          password: 'anything',
          expectedHash: 'whatever',
          salt: '',
          iterations: 0,
        ),
        isFalse,
      );
    });
  });

  group('SmartTaskParser — Tanglish', () {
    test('naalaiku kaalai becomes tomorrow at 9am', () {
      final parsed = SmartTaskParser.parse('gym naalaiku kaalai', now: now);

      expect(parsed.date, DateTime(2026, 9, 11));
      expect(parsed.time, const TimeOfDay(hour: 9, minute: 0));
      expect(parsed.category, 'Health');
    });

    test('innaiku raathiri becomes today at 8pm', () {
      final parsed =
          SmartTaskParser.parse('amma kitta pesanum innaiku raathiri', now: now);

      expect(parsed.date, DateTime(2026, 9, 10));
      expect(parsed.time, const TimeOfDay(hour: 20, minute: 0));
      expect(parsed.category, 'Personal');
    });

    test('a Tamil weekday resolves to its next occurrence', () {
      // 10 Sep 2026 is a Thursday, so velli (Friday) is the 11th.
      final parsed = SmartTaskParser.parse('report submit velli', now: now);
      expect(parsed.date, DateTime(2026, 9, 11));
      expect(parsed.category, 'Work');
    });

    test('avasaram is read as high priority', () {
      final parsed = SmartTaskParser.parse('bill kattanum avasaram', now: now);
      expect(parsed.priority, AppConstants.priorityHigh);
    });

    test('"N naal kazhichu" counts days forward', () {
      final parsed =
          SmartTaskParser.parse('saman vaanganum 2 naal kazhichu', now: now);
      expect(parsed.date, DateTime(2026, 9, 12));
      expect(parsed.category, 'Shopping');
    });

    test('trailing Tamil verb helpers are stripped from the title', () {
      final parsed = SmartTaskParser.parse('report submit pannanum', now: now);
      expect(parsed.title, 'Report submit');
    });

    test('English still parses exactly as before', () {
      final parsed =
          SmartTaskParser.parse('Gym tomorrow 6am urgent', now: now);

      expect(parsed.date, DateTime(2026, 9, 11));
      expect(parsed.time, const TimeOfDay(hour: 6, minute: 0));
      expect(parsed.priority, AppConstants.priorityHigh);
    });
  });

  group('Coach', () {
    const name = 'Anusha Devi';

    test('greets a brand new list and offers the first step', () {
      final message = Coach.build(
        name: name,
        stats: const TaskStats(),
      );

      expect(message.text, contains('Anusha'));
      // First name only.
      expect(message.text, isNot(contains('Devi')));
      expect(message.action, CoachAction.addTask);
    });

    test('overdue work outranks everything else', () {
      final message = Coach.build(
        name: name,
        stats: const TaskStats(
          total: 5,
          pending: 5,
          dueToday: 3,
          overdue: 2,
        ),
      );

      expect(message.action, CoachAction.showOverdue);
      expect(message.text, contains('2'));
    });

    test('says when today has work and nothing is ticked off', () {
      final message = Coach.build(
        name: name,
        stats: const TaskStats(
          total: 4,
          pending: 4,
          dueToday: 4,
        ),
      );

      expect(message.action, CoachAction.showToday);
      expect(message.text, contains('4'));
    });

    test('celebrates a finished day', () {
      final message = Coach.build(
        name: name,
        stats: const TaskStats(
          total: 3,
          completed: 3,
          dueToday: 3,
          completedToday: 3,
        ),
      );

      expect(message.action, CoachAction.none);
      expect(message.text, contains('🎉'));
    });

    test('Tanglish mode speaks Tanglish', () {
      final message = Coach.build(
        name: name,
        stats: const TaskStats(total: 4, pending: 4, dueToday: 4),
        tanglish: true,
      );

      expect(message.text, contains('Innaikku'));
      expect(message.text, contains('Anusha'));
    });

    test('a streak is mentioned underneath, not instead', () {
      final message = Coach.build(
        name: name,
        stats: const TaskStats(
          total: 6,
          completed: 6,
          dueToday: 2,
          completedToday: 2,
        ),
        streak: 5,
      );

      expect(message.text, contains('🎉'));
      expect(message.sub, contains('5'));
    });

    test('pendingToday never goes negative', () {
      const stats = TaskStats(dueToday: 2, completedToday: 5);
      expect(stats.pendingToday, 0);
    });
  });

  group('TaskIntelligence', () {
    test('learns the median scheduled time for a category', () {
      final profile = TaskIntelligence.profileFrom([
        _task(title: 'Standup', category: 'Work', time: '09:00'),
        _task(title: 'Email', category: 'Work', time: '10:00'),
        _task(title: 'Report', category: 'Work', time: '11:00'),
      ]);

      expect(
        profile.timeByCategory['Work'],
        const TimeOfDay(hour: 10, minute: 0),
      );
    });

    test('one odd hour does not drag the learned time (median, not mean)', () {
      final profile = TaskIntelligence.profileFrom([
        _task(title: 'A', time: '09:00'),
        _task(title: 'B', time: '09:30'),
        _task(title: 'C', time: '10:00'),
        _task(title: 'D', time: '10:00'),
        _task(title: 'E', time: '03:00'),
      ]);

      expect(profile.timeByCategory['Work']!.hour, 9);
    });

    test('does not claim a habit from too few samples', () {
      final profile = TaskIntelligence.profileFrom([
        _task(title: 'Only one', time: '17:00'),
      ]);

      expect(profile.timeByCategory, isEmpty);
      expect(profile.hasLearnedEnough, isFalse);
    });

    test('learns a dominant priority but ignores a split one', () {
      final dominant = TaskIntelligence.profileFrom([
        _task(title: 'A', priority: AppConstants.priorityHigh),
        _task(title: 'B', priority: AppConstants.priorityHigh),
        _task(title: 'C', priority: AppConstants.priorityHigh),
        _task(title: 'D', priority: AppConstants.priorityLow),
      ]);
      expect(
        dominant.priorityByCategory['Work'],
        AppConstants.priorityHigh,
      );

      final split = TaskIntelligence.profileFrom([
        _task(title: 'A', priority: AppConstants.priorityHigh),
        _task(title: 'B', priority: AppConstants.priorityLow),
        _task(title: 'C', priority: AppConstants.priorityMedium),
      ]);
      expect(split.priorityByCategory['Work'], isNull);
    });

    test('spots a repeated task and the weekday it lands on', () {
      // 7, 14, 21 September 2026 are all Mondays.
      final profile = TaskIntelligence.profileFrom([
        _task(title: 'Gym', category: 'Health', date: '2026-09-07'),
        _task(title: 'gym', category: 'Health', date: '2026-09-14'),
        _task(title: 'Gym!', category: 'Health', date: '2026-09-21'),
      ]);

      final frequent = profile.frequentTasks.single;
      expect(frequent.count, 3);
      expect(frequent.isRecurring, isTrue);
      expect(frequent.weekday, DateTime.monday);
    });

    test('ranks productive hours from when tasks were actually completed', () {
      final profile = TaskIntelligence.profileFrom([
        _task(
          title: 'A',
          completed: true,
          completedAt: '2026-09-10T09:15:00.000',
        ),
        _task(
          title: 'B',
          completed: true,
          completedAt: '2026-09-11T09:40:00.000',
        ),
        _task(
          title: 'C',
          completed: true,
          completedAt: '2026-09-12T20:00:00.000',
        ),
      ]);

      expect(profile.productiveHours.first, 9);
    });

    test('suggests a time with the reason behind it', () {
      final profile = TaskIntelligence.profileFrom([
        _task(title: 'A', category: 'Health', time: '06:00'),
        _task(title: 'B', category: 'Health', time: '06:00'),
        _task(title: 'C', category: 'Health', time: '06:30'),
      ]);

      final suggestion = profile.suggestTime('Health');
      expect(suggestion, isNotNull);
      expect(suggestion!.value.hour, 6);
      expect(suggestion.reason, contains('Health'));
    });

    test('planDay puts overdue work first, then high priority', () {
      final profile = TaskIntelligence.profileFrom(const []);

      final slots = profile.planDay(
        [
          _task(
            title: 'Low today',
            priority: AppConstants.priorityLow,
            date: '2026-09-21',
          ),
          _task(
            title: 'High today',
            priority: AppConstants.priorityHigh,
            date: '2026-09-21',
          ),
          _task(
            title: 'Overdue',
            priority: AppConstants.priorityLow,
            date: '2020-01-01',
          ),
        ],
        now: DateTime(2026, 9, 21, 8, 5),
      );

      expect(slots.map((s) => s.task.title).toList(), [
        'Overdue',
        'High today',
        'Low today',
      ]);
      // First slot starts at the next quarter hour.
      expect(slots.first.start, const TimeOfDay(hour: 8, minute: 15));
    });

    test('planDay stops rather than scheduling into the night', () {
      final profile = TaskIntelligence.profileFrom(const []);

      final slots = profile.planDay(
        List.generate(20, (i) => _task(title: 'Task $i')),
        now: DateTime(2026, 9, 21, 20, 0),
      );

      expect(slots.length, lessThan(20));
      expect(slots.every((s) => s.start.hour < 22), isTrue);
    });

    test('normalises titles so spelling variants group together', () {
      expect(TaskIntelligence.normaliseTitle('  Gym!!  '), 'gym');
      expect(TaskIntelligence.normaliseTitle('Buy   Milk'), 'buy milk');
    });
  });

  group('TaskBreakdown', () {
    test('matches a known kind of task', () {
      final breakdown = TaskBreakdown.suggest('Study for the maths exam');
      expect(breakdown.matched, isTrue);
      expect(breakdown.steps, isNotEmpty);
      expect(breakdown.basis, contains('studying'));
    });

    test('falls back to a generic split and says so', () {
      final breakdown = TaskBreakdown.suggest('Zzzz qqqq');
      expect(breakdown.matched, isFalse);
      expect(breakdown.steps.length, 3);
      expect(breakdown.basis, contains('general'));
    });

    test('never returns an empty list', () {
      expect(TaskBreakdown.suggest('').steps, isNotEmpty);
    });
  });

  group('AppConstants', () {
    test('unknown categories fall back to Other rather than throwing', () {
      expect(AppConstants.categoryOf('Nonexistent').name, 'Other');
    });

    test('priority sorting weight is highest for High', () {
      expect(
        AppConstants.priorityWeight(AppConstants.priorityHigh),
        greaterThan(AppConstants.priorityWeight(AppConstants.priorityMedium)),
      );
    });
  });
}
