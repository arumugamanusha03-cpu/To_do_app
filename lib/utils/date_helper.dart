import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Every task is stored with an ISO date (`yyyy-MM-dd`) and a 24h time
/// (`HH:mm`) so that rows sort correctly with a plain SQL `ORDER BY`.
///
/// The first version of the app stored `d/M/yyyy` and `9:00 AM`, so the
/// parsers here accept both formats — the database migration relies on that.
class DateHelper {
  DateHelper._();

  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _storedTime = DateFormat('HH:mm');
  static final DateFormat _prettyDate = DateFormat('EEE, d MMM yyyy');
  static final DateFormat _shortDate = DateFormat('d MMM');
  static final DateFormat _prettyTime = DateFormat('hh:mm a');
  static final DateFormat _weekday = DateFormat('EEE');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy');

  // ===========================
  // STORAGE FORMAT
  // ===========================

  static String toIsoDate(DateTime date) => _isoDate.format(date);

  static String toStoredTime(TimeOfDay time) {
    final asDate = DateTime(2000, 1, 1, time.hour, time.minute);
    return _storedTime.format(asDate);
  }

  /// Same canonical `HH:mm` form, taken straight from a [DateTime].
  static String storedTimeOf(DateTime dateTime) =>
      _storedTime.format(dateTime);

  /// Parses `yyyy-MM-dd` and the legacy `d/M/yyyy`. Returns today when the
  /// value cannot be understood, so a corrupt row never crashes a list.
  static DateTime parseDate(String raw) {
    final value = raw.trim();

    final iso = DateTime.tryParse(value);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final parts = value.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Parses `HH:mm` and the legacy `h:mm a`. Falls back to 09:00.
  static TimeOfDay parseTime(String raw) {
    final value = raw.trim().toUpperCase();

    final isPm = value.contains('PM');
    final isAm = value.contains('AM');
    final digits = value.replaceAll(RegExp(r'[^0-9:]'), '');

    final parts = digits.split(':');
    if (parts.length >= 2) {
      var hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);

      if (hour != null && minute != null) {
        if (isPm && hour < 12) hour += 12;
        if (isAm && hour == 12) hour = 0;
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    }

    return const TimeOfDay(hour: 9, minute: 0);
  }

  /// Normalises any stored date string into the canonical ISO form.
  static String normaliseDate(String raw) => toIsoDate(parseDate(raw));

  /// Normalises any stored time string into the canonical `HH:mm` form.
  static String normaliseTime(String raw) => toStoredTime(parseTime(raw));

  static DateTime combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  // ===========================
  // DISPLAY FORMAT
  // ===========================

  static String prettyDate(DateTime date) => _prettyDate.format(date);

  static String shortDate(DateTime date) => _shortDate.format(date);

  static String prettyTime(TimeOfDay time) {
    return _prettyTime.format(DateTime(2000, 1, 1, time.hour, time.minute));
  }

  static String prettyTimeFromStored(String stored) =>
      prettyTime(parseTime(stored));

  static String weekdayLabel(DateTime date) => _weekday.format(date);

  static String monthYear(DateTime date) => _monthYear.format(date);

  /// "Today", "Tomorrow", "Yesterday" or a short date — used on task cards.
  static String relativeLabel(DateTime date) {
    final today = dateOnly(DateTime.now());
    final target = dateOnly(date);
    final diff = target.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > 1 && diff < 7) return _weekday.format(target);
    return _shortDate.format(target);
  }

  static String greeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // ===========================
  // HELPERS
  // ===========================

  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// The 7 days ending today, oldest first — used by the weekly chart.
  static List<DateTime> lastSevenDays([DateTime? from]) {
    final end = dateOnly(from ?? DateTime.now());
    return List.generate(7, (i) => end.subtract(Duration(days: 6 - i)));
  }
}
