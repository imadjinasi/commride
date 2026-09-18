import 'package:flutter/material.dart';

abstract final class CommRideColors {
  static const Color commBlack = Color(0xFF161616);
  static const Color roadWhite = Color(0xFFF4F2EC);
  static const Color signalOrange = Color(0xFFFF6A1A);
  static const Color roadGrey = Color(0xFF767676);
  static const Color criticalRed = Color(0xFFB42318);
}

abstract final class CommRideTheme {
  static ThemeData light() {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: CommRideColors.signalOrange,
      onPrimary: Colors.white,
      secondary: CommRideColors.commBlack,
      onSecondary: Colors.white,
      surface: CommRideColors.roadWhite,
      onSurface: CommRideColors.commBlack,
      error: CommRideColors.criticalRed,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CommRideColors.roadWhite,
      dividerColor: CommRideColors.roadGrey.withValues(alpha: 0.28),
      appBarTheme: const AppBarTheme(
        backgroundColor: CommRideColors.roadWhite,
        foregroundColor: CommRideColors.commBlack,
        centerTitle: false,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CommRideColors.roadWhite,
        indicatorColor: CommRideColors.signalOrange.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) {
            final FontWeight weight = states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500;
            return TextStyle(
              color: CommRideColors.commBlack,
              fontWeight: weight,
            );
          },
        ),
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
        bodyLarge: TextStyle(
          color: CommRideColors.commBlack,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: CommRideColors.roadGrey,
          fontWeight: FontWeight.w400,
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    );
  }
}
