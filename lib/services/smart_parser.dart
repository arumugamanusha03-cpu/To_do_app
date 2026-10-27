import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// What [SmartTaskParser] pulled out of a sentence like
/// "submit the client report tomorrow 5pm urgent".
class ParsedTask {
  /// The sentence with every recognised phrase stripped out, tidied up and
  /// capitalised — "Submit the client report".
  final String title;

  final DateTime? date;
  final TimeOfDay? time;
  final String? priority;
  final String? category;

  /// Human-readable labels for what was recognised, shown as chips under the
  /// input so the user can see (and correct) the guess.
  final List<String> detections;

  const ParsedTask({
    required this.title,
    this.date,
    this.time,
    this.priority,
    this.category,
    this.detections = const [],
  });

  bool get hasAnything =>
      date != null || time != null || priority != null || category != null;
}

/// A small offline natural-language parser for the "smart add" field.
///
/// It is deliberately keyword based: no network call, no API key, works on
/// aeroplane mode, and every guess is shown to the user before saving.
class SmartTaskParser {
  SmartTaskParser._();

  static const List<String> _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// Romanised Tamil weekdays, mapped to `DateTime.weekday` numbers.
  ///
  /// Tanglish has no fixed spelling, so each day lists the ways people
  /// actually type it. Longer spellings come first so "vyazhakizhamai"
  /// matches before the bare "vyazhan".
  static const Map<String, int> _tanglishWeekdays = {
    'thingakizhamai': DateTime.monday,
    'thingatkizhamai': DateTime.monday,
    'thingal': DateTime.monday,
    'sevvaikizhamai': DateTime.tuesday,
    'sevvai': DateTime.tuesday,
    'budhankizhamai': DateTime.wednesday,
    'budhan': DateTime.wednesday,
    'buthan': DateTime.wednesday,
    'vyazhakizhamai': DateTime.thursday,
    'viyazhan': DateTime.thursday,
    'vyazhan': DateTime.thursday,
    'vellikizhamai': DateTime.friday,
    'velli': DateTime.friday,
    'sanikizhamai': DateTime.saturday,
    'sani': DateTime.saturday,
    'gnayiru': DateTime.sunday,
    'nyayiru': DateTime.sunday,
    'njayiru': DateTime.sunday,
  };

  static const Map<String, int> _months = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static const Map<String, List<String>> _categoryKeywords = {
    'Work': [
      'meeting',
      'client',
      'email',
      'report',
      'project',
      'office',
      'deadline',
      'presentation',
      'standup',
      'interview',
      'invoice',
      'manager',
      'demo',
      'review',
      // Tanglish
      'velai',
      'vela',
      'aluvalagam',
    ],
    'Study': [
      'study',
      'exam',
      'assignment',
      'homework',
      'class',
      'lecture',
      'revision',
      'notes',
      'test',
      'semester',
      'college',
      'syllabus',
      'chapter',
      'tutorial',
      // Tanglish
      'padi',
      'padikka',
      'padipp',
      'thervu',
    ],
    'Shopping': [
      'buy',
      'purchase',
      'groceries',
      'grocery',
      'shopping',
      'order',
      'milk',
      'vegetables',
      'recharge',
      'cart',
      // Tanglish
      'vaangu',
      'vaanga',
      'vanga',
      'kadai',
      'saman',
    ],
    'Health': [
      'gym',
      'workout',
      'doctor',
      'medicine',
      'tablet',
      'yoga',
      'walk',
      'run',
      'dentist',
      'hospital',
      'exercise',
      'checkup',
      'meditation',
      // Tanglish
      'marundhu',
      'marunthu',
      'nadakka',
      'nadaka',
      'udambu',
    ],
    'Personal': [
      'call',
      'birthday',
      'family',
      'friend',
      'mom',
      'dad',
      'home',
      'clean',
      'laundry',
      'bill',
      'rent',
      'bank',
      // Tanglish
      'amma',
      'appa',
      'veedu',
      'veettu',
      'thambi',
      'akka',
    ],
  };

  static const List<String> _highPriorityWords = [
    'urgent',
    'asap',
    'important',
    'critical',
    'high priority',
    'top priority',
    'immediately',
    // Tanglish
    'avasaram',
    'avasram',
    'mukkiyam',
    'mukkiam',
    'seekiram',
    'seekkiram',
    'udane',
  ];

  static const List<String> _lowPriorityWords = [
    'low priority',
    'whenever',
    'someday',
    'sometime',
    'no rush',
    'optional',
    'if possible',
    // Tanglish
    'eppo venaalum',
    'eppavachum',
    'nidhaanama',
    'appuram',
  ];

  /// Filler phrases that add nothing to a task title.
  static final List<RegExp> _fillerPhrases = [
    RegExp(r'^\s*(please\s+)?remind me to\s+', caseSensitive: false),
    RegExp(r'^\s*(i\s+)?(need|have|has|got)\s+to\s+', caseSensitive: false),
    RegExp(r"^\s*don'?t forget to\s+", caseSensitive: false),
    RegExp(r'^\s*remember to\s+', caseSensitive: false),
    RegExp(r'^\s*(add|create|make)\s+(a\s+)?task\s+(to\s+)?', caseSensitive: false),
    // Tanglish openers
    RegExp(r'^\s*(enakku|enaku)\s+', caseSensitive: false),
    RegExp(r'^\s*naan\s+', caseSensitive: false),
    RegExp(
      r'^\s*(nyabagam|nyaabagam|gnabagam)\s*(paduthu|paduthunga)?\s+',
      caseSensitive: false,
    ),
  ];

  /// Tamil verb endings that carry no meaning in a task title —
  /// "report submit pannanum" is a better title as "Report submit".
  static final RegExp _tanglishVerbTail = RegExp(
    r'\s+(pannanum|pannum|panna|pannu|seiyanum|seyyanum|seyya|'
    r'mudikkanum|mudikka|poganum|poga|varanum)\s*$',
    caseSensitive: false,
  );

  /// Parses [input] against [now] (injectable so the behaviour is testable).
  static ParsedTask parse(String input, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final original = input.trim();

    if (original.isEmpty) {
      return const ParsedTask(title: '');
    }

    final lower = original.toLowerCase();

    // Index ranges that were consumed by a recogniser and must not end up in
    // the title.
    final consumed = <_Span>[];
    final detections = <String>[];

    final date = _extractDate(lower, reference, consumed, detections);
    final time = _extractTime(lower, consumed, detections);
    final priority = _extractPriority(lower, consumed, detections);

    var title = _stripSpans(original, consumed);
    title = _cleanTitle(title);

    // The category is guessed from the words that survived, so a date like
    // "march" never turns into a category.
    final category = _guessCategory(title.toLowerCase());
    if (category != null) {
      detections.add('Category: $category');
    }

    final resolved = _resolveDateTime(date, time, reference);

    return ParsedTask(
      title: title.isEmpty ? original : title,
      date: resolved.$1,
      time: resolved.$2,
      priority: priority,
      category: category,
      detections: detections,
    );
  }

  // ===========================
  // DATE
  // ===========================

  static DateTime? _extractDate(
    String lower,
    DateTime now,
    List<_Span> consumed,
    List<String> detections,
  ) {
    final today = DateTime(now.year, now.month, now.day);

    DateTime? found;

    void record(RegExpMatch match, DateTime value, String label) {
      if (found != null) return;
      found = value;
      consumed.add(_Span(match.start, match.end));
      detections.add('Date: $label');
    }

    // "day after tomorrow" — checked before "tomorrow".
    final dayAfter = RegExp(
      r'\b(day after tomorrow|marunaal|maru naal)\b',
    ).firstMatch(lower);
    if (dayAfter != null) {
      record(dayAfter, today.add(const Duration(days: 2)), 'day after tomorrow');
    }

    if (found == null) {
      final tomorrow = RegExp(
        r'\b(tomorrow|tmrw|tmr|naalaikku|naalaiku|nalaikku|nalaiku|'
        r'naalikki|naaliki|nalaiki)\b',
      ).firstMatch(lower);
      if (tomorrow != null) {
        record(tomorrow, today.add(const Duration(days: 1)), 'tomorrow');
      }
    }

    if (found == null) {
      final todayMatch = RegExp(
        r'\b(today|innaiku|innaikku|inniku|innikku|indhanaal|indha naal)\b',
      ).firstMatch(lower);
      if (todayMatch != null) record(todayMatch, today, 'today');
    }

    // "tonight" sets the date here; the time recogniser reads it separately.
    if (found == null) {
      final tonight = RegExp(r'\btonight\b').firstMatch(lower);
      if (tonight != null) {
        found = today;
        detections.add('Date: today');
      }
    }

    // "in 3 days" / "in 2 weeks"
    if (found == null) {
      final relative =
          RegExp(r'\bin (\d{1,3}) (day|days|week|weeks)\b').firstMatch(lower);
      if (relative != null) {
        final amount = int.parse(relative.group(1)!);
        final unit = relative.group(2)!;
        final days = unit.startsWith('week') ? amount * 7 : amount;
        record(
          relative,
          today.add(Duration(days: days)),
          'in $amount $unit',
        );
      }
    }

    // Tanglish puts the number first: "3 naal kazhichu", "2 vaaram la".
    if (found == null) {
      final relativeTamil = RegExp(
        r'\b(\d{1,3})\s*(naal|naalla|naalaila|vaaram|vaarathula)\b'
        r'(?:\s*(kazhichu|kazhitthu|la|kku))?',
      ).firstMatch(lower);

      if (relativeTamil != null) {
        final amount = int.parse(relativeTamil.group(1)!);
        final unit = relativeTamil.group(2)!;
        final days = unit.startsWith('vaaram') ? amount * 7 : amount;
        record(
          relativeTamil,
          today.add(Duration(days: days)),
          'in $amount ${unit.startsWith('vaaram') ? 'weeks' : 'days'}',
        );
      }
    }

    if (found == null) {
      final nextWeek = RegExp(
        r'\b(next week|adutha vaaram|aduttha vaaram)\b',
      ).firstMatch(lower);
      if (nextWeek != null) {
        record(nextWeek, today.add(const Duration(days: 7)), 'next week');
      }
    }

    // Weekday names in English or romanised Tamil, with or without a
    // "next"/"this"/"on"/"adutha" prefix. Always the next occurrence after
    // today.
    if (found == null) {
      // Longest first, so "vellikizhamai" is not cut short by "velli".
      final names = [..._weekdays, ..._tanglishWeekdays.keys]
        ..sort((a, b) => b.length.compareTo(a.length));

      final weekday = RegExp(
        r'\b(?:on\s+|next\s+|this\s+|adutha\s+)?(' + names.join('|') + r')\b',
      ).firstMatch(lower);

      if (weekday != null) {
        final name = weekday.group(1)!;
        final target = _tanglishWeekdays[name] ?? (_weekdays.indexOf(name) + 1);

        var delta = (target - today.weekday) % 7;
        if (delta == 0) delta = 7;
        record(weekday, today.add(Duration(days: delta)), name);
      }
    }

    // "12/5", "12-05-2026"
    if (found == null) {
      final numeric = RegExp(
        r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b',
      ).firstMatch(lower);

      if (numeric != null) {
        final day = int.parse(numeric.group(1)!);
        final month = int.parse(numeric.group(2)!);
        var year = int.tryParse(numeric.group(3) ?? '') ?? today.year;
        if (year < 100) year += 2000;

        if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
          var value = DateTime(year, month, day);
          // A bare "5/3" that already passed means next year.
          if (numeric.group(3) == null && value.isBefore(today)) {
            value = DateTime(year + 1, month, day);
          }
          record(numeric, value, '$day/$month/${value.year}');
        }
      }
    }

    // "5 dec" / "dec 5" / "15th march"
    if (found == null) {
      final monthNames = _months.keys.join('|');

      final dayFirst = RegExp(
        r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(' + monthNames + r')\b',
      ).firstMatch(lower);

      final monthFirst = RegExp(
        r'\b(' + monthNames + r')\s+(\d{1,2})(?:st|nd|rd|th)?\b',
      ).firstMatch(lower);

      final match = dayFirst ?? monthFirst;
      if (match != null) {
        final day = int.parse(
          (dayFirst != null ? match.group(1) : match.group(2))!,
        );
        final month =
            _months[(dayFirst != null ? match.group(2) : match.group(1))!]!;

        if (day >= 1 && day <= 31) {
          var value = DateTime(today.year, month, day);
          if (value.isBefore(today)) {
            value = DateTime(today.year + 1, month, day);
          }
          record(match, value, '$day/${value.month}/${value.year}');
        }
      }
    }

    return found;
  }

  // ===========================
  // TIME
  // ===========================

  static TimeOfDay? _extractTime(
    String lower,
    List<_Span> consumed,
    List<String> detections,
  ) {
    TimeOfDay? found;

    void record(RegExpMatch match, TimeOfDay value, {bool consume = true}) {
      if (found != null) return;
      found = value;
      if (consume) consumed.add(_Span(match.start, match.end));
      detections.add('Time: ${_formatTime(value)}');
    }

    // "5:30pm", "17:30", "5.30 pm"
    final withMinutes = RegExp(
      r'\b(?:at\s+)?(\d{1,2})[:.](\d{2})\s*(am|pm)?\b',
    ).firstMatch(lower);

    if (withMinutes != null) {
      var hour = int.parse(withMinutes.group(1)!);
      final minute = int.parse(withMinutes.group(2)!);
      final meridiem = withMinutes.group(3);

      if (meridiem == 'pm' && hour < 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;

      if (hour < 24 && minute < 60) {
        record(withMinutes, TimeOfDay(hour: hour, minute: minute));
      }
    }

    // "5pm", "9 am"
    if (found == null) {
      final hourOnly =
          RegExp(r'\b(?:at\s+)?(\d{1,2})\s*(am|pm)\b').firstMatch(lower);

      if (hourOnly != null) {
        var hour = int.parse(hourOnly.group(1)!);
        final meridiem = hourOnly.group(2)!;

        if (meridiem == 'pm' && hour < 12) hour += 12;
        if (meridiem == 'am' && hour == 12) hour = 0;

        if (hour < 24) {
          record(hourOnly, TimeOfDay(hour: hour, minute: 0));
        }
      }
    }

    // Named times.
    if (found == null) {
      // Insertion order matters: the first pattern that matches wins, so the
      // more specific words are listed first.
      const named = {
        r'\b(noon|nanpakal|nandpakal)\b': TimeOfDay(hour: 12, minute: 0),
        r'\bmidnight\b': TimeOfDay(hour: 0, minute: 0),
        r'\b(morning|kaalai|kalai|kaalaila|kaalayila)\b':
            TimeOfDay(hour: 9, minute: 0),
        r'\b(afternoon|madhiyam|mathiyam|madhyanam|madhiyana)\b':
            TimeOfDay(hour: 14, minute: 0),
        r'\b(evening|saayangaalam|sayangalam|saayangalam|maalai)\b':
            TimeOfDay(hour: 18, minute: 0),
        r'\btonight\b': TimeOfDay(hour: 20, minute: 0),
        r'\b(night|raathiri|rathiri|raatri|iravu|iravula)\b':
            TimeOfDay(hour: 20, minute: 0),
      };

      for (final entry in named.entries) {
        final match = RegExp(entry.key).firstMatch(lower);
        if (match != null) {
          record(match, entry.value);
          break;
        }
      }
    }

    // Bare "at 5" — read as 5 PM for 1..7, otherwise as given.
    if (found == null) {
      final bare = RegExp(r'\bat (\d{1,2})\b').firstMatch(lower);
      if (bare != null) {
        var hour = int.parse(bare.group(1)!);
        if (hour >= 1 && hour <= 7) hour += 12;
        if (hour < 24) {
          record(bare, TimeOfDay(hour: hour, minute: 0));
        }
      }
    }

    return found;
  }

  // ===========================
  // PRIORITY
  // ===========================

  static String? _extractPriority(
    String lower,
    List<_Span> consumed,
    List<String> detections,
  ) {
    for (final word in _highPriorityWords) {
      final match = RegExp('\\b${RegExp.escape(word)}\\b').firstMatch(lower);
      if (match != null) {
        consumed.add(_Span(match.start, match.end));
        detections.add('Priority: High');
        return AppConstants.priorityHigh;
      }
    }

    for (final word in _lowPriorityWords) {
      final match = RegExp('\\b${RegExp.escape(word)}\\b').firstMatch(lower);
      if (match != null) {
        consumed.add(_Span(match.start, match.end));
        detections.add('Priority: Low');
        return AppConstants.priorityLow;
      }
    }

    return null;
  }

  // ===========================
  // CATEGORY
  // ===========================

  static String? _guessCategory(String text) {
    var best = <String, int>{};

    for (final entry in _categoryKeywords.entries) {
      var hits = 0;
      for (final keyword in entry.value) {
        if (RegExp('\\b${RegExp.escape(keyword)}').hasMatch(text)) hits++;
      }
      if (hits > 0) best[entry.key] = hits;
    }

    if (best.isEmpty) return null;

    final sorted = best.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  // ===========================
  // HELPERS
  // ===========================

  /// Combines the recognised date and time into the values the form should
  /// show. A time with no date lands today, or tomorrow if it already passed.
  static (DateTime?, TimeOfDay?) _resolveDateTime(
    DateTime? date,
    TimeOfDay? time,
    DateTime now,
  ) {
    if (date == null && time == null) return (null, null);

    if (date == null) {
      final today = DateTime(now.year, now.month, now.day);
      final candidate = DateTime(
        today.year,
        today.month,
        today.day,
        time!.hour,
        time.minute,
      );
      return (
        candidate.isAfter(now) ? today : today.add(const Duration(days: 1)),
        time,
      );
    }

    return (date, time);
  }

  static String _stripSpans(String original, List<_Span> spans) {
    if (spans.isEmpty) return original;

    final keep = List<bool>.filled(original.length, true);
    for (final span in spans) {
      for (var i = span.start; i < span.end && i < original.length; i++) {
        keep[i] = false;
      }
    }

    final buffer = StringBuffer();
    for (var i = 0; i < original.length; i++) {
      if (keep[i]) buffer.write(original[i]);
    }
    return buffer.toString();
  }

  static String _cleanTitle(String raw) {
    var text = raw;

    for (final filler in _fillerPhrases) {
      text = text.replaceAll(filler, '');
    }

    // Strip repeatedly: "gym poga pannanum" sheds both tails.
    var previous = '';
    while (previous != text) {
      previous = text;
      text = text.replaceAll(_tanglishVerbTail, '');
    }

    text = text
        // Prepositions left dangling by a removed date/time.
        .replaceAll(
          RegExp(r'\b(on|at|by|before|due)\s*$', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+([,.!?])'), r'$1')
        .trim()
        .replaceAll(RegExp(r'^[\s,\-–—:]+'), '')
        .replaceAll(RegExp(r'[\s,\-–—:]+$'), '')
        .trim();

    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  static String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

class _Span {
  final int start;
  final int end;

  const _Span(this.start, this.end);
}
