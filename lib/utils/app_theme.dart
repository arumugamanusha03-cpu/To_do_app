import 'package:flutter/material.dart';
import 'app_colors.dart';

/// TaskFlow is a dark, glassmorphic app — there is a single theme and every
/// screen paints its own gradient background on top of it.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.purple,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.pink,
      secondary: AppColors.purple,
      tertiary: AppColors.blue,
      surface: AppColors.background,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF161C3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.grey,
          fontSize: 15,
          height: 1.5,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF121834),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E2340),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),

      // The date/time pickers are the only stock Material surfaces the user
      // sees, so they get explicit colours instead of the seeded defaults.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFF161C3A),
        headerBackgroundColor: AppColors.purple,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: const Color(0xFF161C3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.pink,
      ),

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.pink,
        selectionHandleColor: AppColors.pink,
      ),
    );
  }
}
