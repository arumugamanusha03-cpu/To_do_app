/// Suggested steps for a task, and where they came from.
class Breakdown {
  final List<String> steps;

  /// What the suggestion is based on, shown to the user so they know this is
  /// a pattern match rather than something that read their mind.
  final String basis;

  /// False when nothing matched and the generic scaffold was used.
  final bool matched;

  const Breakdown({
    required this.steps,
    required this.basis,
    required this.matched,
  });
}

/// Splits a task into steps using a library of patterns for the kinds of work
/// people actually put in a to-do app.
///
/// This runs on the phone with no model behind it, so it is honest about what
/// it is: a good scaffold you edit, not a plan someone wrote for you. Every
/// suggested step is editable and removable before anything is saved.
class TaskBreakdown {
  TaskBreakdown._();

  /// Ordered — the first pattern whose keyword appears in the title wins, so
  /// more specific patterns are listed before general ones.
  static const List<_Pattern> _patterns = [
    _Pattern(
      keywords: ['bug', 'fix', 'crash', 'issue', 'error', 'debug'],
      label: 'fixing something broken',
      steps: [
        'Reproduce the problem',
        'Find what is causing it',
        'Write the fix',
        'Test that it works',
        'Check nothing else broke',
      ],
    ),
    _Pattern(
      keywords: ['exam', 'test', 'study', 'revision', 'syllabus', 'semester'],
      label: 'studying for something',
      steps: [
        'Collect the syllabus and notes',
        'Plan which topics to cover when',
        'Study the weak topics first',
        'Practice past questions',
        'Final revision the day before',
      ],
    ),
    _Pattern(
      keywords: ['presentation', 'slides', 'deck', 'demo', 'pitch'],
      label: 'preparing a presentation',
      steps: [
        'Decide the one message it has to land',
        'Draft the outline',
        'Build the slides',
        'Add the visuals and data',
        'Rehearse it out loud once',
      ],
    ),
    _Pattern(
      keywords: ['report', 'essay', 'assignment', 'document', 'write', 'blog'],
      label: 'writing something',
      steps: [
        'Outline the structure',
        'Gather the sources and data',
        'Write the first draft',
        'Edit and cut',
        'Final read, then submit',
      ],
    ),
    _Pattern(
      keywords: ['interview', 'meeting', 'call', 'standup', 'review'],
      label: 'a meeting or call',
      steps: [
        'Set the agenda',
        'Gather what you need to bring',
        'Confirm the time with everyone',
        'Take notes during it',
        'Send the follow-up',
      ],
    ),
    _Pattern(
      keywords: ['trip', 'travel', 'flight', 'train', 'vacation', 'holiday'],
      label: 'planning a trip',
      steps: [
        'Book the travel',
        'Book the stay',
        'Make a packing list',
        'Check documents and bookings',
        'Pack the night before',
      ],
    ),
    _Pattern(
      keywords: ['shopping', 'groceries', 'grocery', 'buy', 'purchase'],
      label: 'a shopping run',
      steps: [
        'Write the list',
        'Check what you already have',
        'Set a budget',
        'Buy everything on the list',
        'Put it all away',
      ],
    ),
    _Pattern(
      keywords: ['clean', 'tidy', 'organise', 'organize', 'declutter'],
      label: 'cleaning or tidying',
      steps: [
        'Clear the surfaces',
        'Sort into keep, move, throw',
        'Clean properly',
        'Put everything back in its place',
      ],
    ),
    _Pattern(
      keywords: ['app', 'project', 'build', 'develop', 'feature', 'design'],
      label: 'building something',
      steps: [
        'Write down what it has to do',
        'Decide the approach',
        'Build the first working version',
        'Test it properly',
        'Ship it',
      ],
    ),
    _Pattern(
      keywords: ['gym', 'workout', 'run', 'exercise', 'yoga', 'walk'],
      label: 'a workout',
      steps: [
        'Warm up',
        'Main set',
        'Cool down and stretch',
        'Log what you did',
      ],
    ),
    _Pattern(
      keywords: ['bill', 'rent', 'payment', 'tax', 'invoice', 'recharge'],
      label: 'paying something',
      steps: [
        'Check the amount and due date',
        'Make sure the money is there',
        'Pay it',
        'Save the receipt',
      ],
    ),
    _Pattern(
      keywords: ['doctor', 'dentist', 'appointment', 'checkup', 'hospital'],
      label: 'a health appointment',
      steps: [
        'Book the slot',
        'Collect past reports and prescriptions',
        'Write down what to ask',
        'Go to the appointment',
        'Book the follow-up if needed',
      ],
    ),
  ];

  /// The fallback when nothing matches: a plain three-step scaffold. It is
  /// labelled as generic so it never pretends to be a tailored plan.
  static const List<String> _generic = [
    'Work out what "done" looks like',
    'Do the main part',
    'Check it and wrap up',
  ];

  /// Suggests steps for [title]. Never returns an empty list.
  static Breakdown suggest(String title) {
    final text = title.toLowerCase();

    for (final pattern in _patterns) {
      final hit = pattern.keywords.where((k) => text.contains(k)).firstOrNull;
      if (hit == null) continue;

      return Breakdown(
        steps: pattern.steps,
        basis: 'Common steps for ${pattern.label}',
        matched: true,
      );
    }

    return const Breakdown(
      steps: _generic,
      basis: 'A general three-step split — edit these to fit',
      matched: false,
    );
  }
}

class _Pattern {
  final List<String> keywords;
  final String label;
  final List<String> steps;

  const _Pattern({
    required this.keywords,
    required this.label,
    required this.steps,
  });
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
