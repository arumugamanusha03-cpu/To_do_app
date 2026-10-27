/// One spacing and shape scale for the whole app.
///
/// Every gap, padding and corner radius comes from here, so screens stay
/// visually consistent instead of each one inventing its own 18s and 22s.
class AppSpacing {
  AppSpacing._();

  // Gaps between elements.
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 44;

  /// Standard horizontal page padding.
  static const double page = 20;

  /// Bottom padding that clears the floating action button and bottom bar.
  static const double bottomSafe = 140;

  // Corner radii.
  static const double radiusChip = 30;
  static const double radiusField = 16;
  static const double radiusCard = 20;
  static const double radiusSheet = 28;

  // Icon sizes.
  static const double iconChip = 14;
  static const double iconList = 20;
  static const double iconFeature = 22;
}
