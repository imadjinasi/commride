import 'package:flutter/material.dart';

abstract final class CommRideColors {
  static const Color commBlack = Color(0xFF161616);
  static const Color roadWhite = Color(0xFFF4F2EC);
  static const Color signalOrange = Color(0xFFFF6A1A);
  static const Color roadGrey = Color(0xFF767676);
  static const Color textSecondary = Color(0xFF4A4A4A);
  static const Color surfaceMuted = Color(0xFFE7E3DB);
  static const Color disabled = Color(0xFF8A867F);
  static const Color criticalRed = Color(0xFFB42318);
}

abstract final class CommRideSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class CommRideRadii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
}

abstract final class CommRideTargets {
  static const double minimum = 56;
  static const double activeRide = 64;
  static const double sos = 72;
}

abstract final class CommRideDurations {
  static const Duration sosHold = Duration(seconds: 3);
}

abstract final class CommRideTheme {
  static ThemeData light() {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: CommRideColors.signalOrange,
      onPrimary: CommRideColors.commBlack,
      secondary: CommRideColors.commBlack,
      onSecondary: Colors.white,
      surface: CommRideColors.roadWhite,
      onSurface: CommRideColors.commBlack,
      error: CommRideColors.criticalRed,
      onError: Colors.white,
    );

    const RoundedRectangleBorder controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(CommRideRadii.md)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CommRideColors.roadWhite,
      disabledColor: CommRideColors.disabled,
      dividerColor: CommRideColors.roadGrey.withValues(alpha: 0.28),
      appBarTheme: const AppBarTheme(
        backgroundColor: CommRideColors.roadWhite,
        foregroundColor: CommRideColors.commBlack,
        centerTitle: false,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CommRideColors.roadWhite,
        indicatorColor: CommRideColors.signalOrange.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
          Set<WidgetState> states,
        ) {
          final FontWeight weight = states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500;
          return TextStyle(color: CommRideColors.commBlack, fontWeight: weight);
        }),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: CommRideColors.commBlack,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(
          color: CommRideColors.commBlack,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: CommRideColors.commBlack,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: CommRideColors.commBlack,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: CommRideColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: CommRideColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(CommRideRadii.md)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, CommRideTargets.minimum),
          padding: const EdgeInsets.symmetric(
            horizontal: CommRideSpacing.md,
            vertical: CommRideSpacing.sm,
          ),
          shape: controlShape,
          disabledBackgroundColor: CommRideColors.surfaceMuted,
          disabledForegroundColor: CommRideColors.disabled,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, CommRideTargets.minimum),
          padding: const EdgeInsets.symmetric(
            horizontal: CommRideSpacing.md,
            vertical: CommRideSpacing.sm,
          ),
          shape: controlShape,
          foregroundColor: CommRideColors.commBlack,
          disabledForegroundColor: CommRideColors.disabled,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, CommRideTargets.minimum),
          padding: const EdgeInsets.symmetric(
            horizontal: CommRideSpacing.sm,
            vertical: CommRideSpacing.xs,
          ),
          shape: controlShape,
          foregroundColor: CommRideColors.commBlack,
          disabledForegroundColor: CommRideColors.disabled,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(CommRideRadii.md)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(CommRideRadii.md)),
          borderSide: BorderSide(color: CommRideColors.roadGrey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(CommRideRadii.md)),
          borderSide: BorderSide(color: CommRideColors.commBlack, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(CommRideRadii.md)),
          borderSide: BorderSide(color: CommRideColors.surfaceMuted),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CommRideColors.signalOrange,
        linearTrackColor: CommRideColors.surfaceMuted,
      ),
    );
  }
}
