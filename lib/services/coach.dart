import '../database/database_helper.dart';
import '../utils/constants.dart';

/// What tapping the coach line should do, if anything.
enum CoachAction { none, showOverdue, showToday, addTask }

/// The line the home screen greets you with.
class CoachMessage {
  /// The main sentence, emoji included.
  final String text;

  /// An optional quieter second line.
  final String? sub;

  final String? actionLabel;
  final CoachAction action;

  const CoachMessage({
    required this.text,
    this.sub,
    this.actionLabel,
    this.action = CoachAction.none,
  });
}

/// Writes the greeting on the home screen.
///
/// It is the app's voice: it uses the person's name, reacts to what is
/// actually in their list today, and can speak English or Tanglish. Nothing
/// here is generated — these are written lines picked by simple rules, which
/// is why they never say anything the data does not support.
class Coach {
  Coach._();

  static CoachMessage build({
    required String name,
    required TaskStats stats,
    int streak = 0,
    bool tanglish = false,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final first = _firstName(name);
    final message = _pick(first, stats, tanglish, reference);

    // A streak is the strongest thing the app can say, so it is appended to
    // whatever the day needs rather than replacing it — and it must still
    // show on the days the streak was actually earned, which is exactly when
    // the message already has a second line.
    if (streak >= 3) {
      final streakLine = tanglish
          ? '$streak naal thodarndhu 🔥'
          : '$streak day streak 🔥';

      return CoachMessage(
        text: message.text,
        sub: message.sub == null
            ? streakLine
            : '${message.sub} · $streakLine',
        actionLabel: message.actionLabel,
        action: message.action,
      );
    }

    return message;
  }

  static CoachMessage _pick(
    String name,
    TaskStats stats,
    bool tanglish,
    DateTime now,
  ) {
    // 1. Nothing at all yet.
    if (stats.total == 0) {
      return CoachMessage(
        text: tanglish
            ? 'Hi $name 👋 Innum onnum illa inga.'
            : 'Hi $name 👋 Nothing here yet.',
        sub: tanglish
            ? 'Mudhal task-ah add pannu — naan un pazhakkathai kathukka '
                'aarambikkiren.'
            : 'Add your first task and I\'ll start learning how you work.',
        actionLabel: tanglish ? 'Task add pannu' : 'Add a task',
        action: CoachAction.addTask,
      );
    }

    // 2. Something has slipped — that matters more than anything else.
    if (stats.overdue > 0) {
      final n = stats.overdue;
      return CoachMessage(
        text: tanglish
            ? 'Hi $name 👀 $n task time thaandi poiduchu.'
            : 'Hi $name 👀 $n task${n == 1 ? '' : 's'} slipped past '
                '${n == 1 ? 'its' : 'their'} time.',
        sub: tanglish
            ? 'Onnu sari pannalaama? Adhu thaan mudhal vela 💪'
            : 'Want to clear them first? 💪',
        actionLabel: tanglish ? 'Overdue paaru' : 'See overdue',
        action: CoachAction.showOverdue,
      );
    }

    // 3. Today has work and none of it is done — the nudge.
    if (stats.dueToday > 0 && stats.completedToday == 0) {
      final n = stats.dueToday;
      return CoachMessage(
        text: tanglish
            ? 'Hi $name 👋 Innaikku $n task irukku, innum onnu kooda '
                'complete panla.'
            : 'Hi $name 👋 $n task${n == 1 ? '' : 's'} for today, none '
                'ticked off yet.',
        sub: tanglish
            ? 'Onnu start pannu, adhuve poadhum 💪'
            : 'Start with one — that\'s usually enough 💪',
        actionLabel: tanglish ? 'Innaiku task' : "Today's tasks",
        action: CoachAction.showToday,
      );
    }

    // 4. Today is half done.
    if (stats.pendingToday > 0) {
      return CoachMessage(
        text: tanglish
            ? 'Nalla poidhu $name 🔥 Innaikku ${stats.dueToday}-la '
                '${stats.completedToday} mudinjudhu.'
            : 'Nice going, $name 🔥 ${stats.completedToday} of '
                '${stats.dueToday} done today.',
        sub: tanglish
            ? 'Innum ${stats.pendingToday} baaki.'
            : '${stats.pendingToday} to go.',
        actionLabel: tanglish ? 'Innaiku task' : "Today's tasks",
        action: CoachAction.showToday,
      );
    }

    // 5. Today is finished.
    if (stats.dueToday > 0) {
      return CoachMessage(
        text: tanglish
            ? 'Innaikku ella task-um mudinjudhu $name 🎉'
            : "Today's list is clear, $name 🎉",
        sub: tanglish
            ? 'Ella onnum complete. Nalla naal!'
            : 'Every task done — that\'s a good day.',
      );
    }

    // 6. Nothing pending anywhere.
    if (stats.pending == 0) {
      return CoachMessage(
        text: tanglish
            ? 'Onnum pending illa $name ✨'
            : 'Nothing pending, $name ✨',
        sub: tanglish
            ? 'List clear-a irukku. Relax pannu.'
            : 'Enjoy the clear list.',
      );
    }

    // 7. Work exists, just not today.
    final greeting = _greeting(now, tanglish);
    return CoachMessage(
      text: tanglish
          ? '$greeting $name 👋 Innaikku onnum illa, aana '
              '${stats.pending} task varaappogudhu.'
          : '$greeting, $name 👋 Nothing due today, but ${stats.pending} '
              'task${stats.pending == 1 ? '' : 's'} coming up.',
      sub: tanglish
          ? 'Munnadiye onnu mudichaa, appuram nimmadhi.'
          : 'Getting one done early always helps.',
    );
  }

  static String _greeting(DateTime now, bool tanglish) {
    if (now.hour < 12) return tanglish ? 'Good morning' : 'Good morning';
    if (now.hour < 17) return tanglish ? 'Good afternoon' : 'Good afternoon';
    return tanglish ? 'Good evening' : 'Good evening';
  }

  /// Greetings use the first name only — "Hi Anusha Devi 👋" reads like a
  /// form letter.
  static String _firstName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'there';

    final first = trimmed.split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'there' : first;
  }

  /// The filter the home screen should switch to when the line is tapped.
  static TaskFilter? filterFor(CoachAction action) {
    switch (action) {
      case CoachAction.showOverdue:
        return TaskFilter.overdue;
      case CoachAction.showToday:
        return TaskFilter.today;
      case CoachAction.none:
      case CoachAction.addTask:
        return null;
    }
  }
}
