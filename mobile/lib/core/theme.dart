import 'package:flutter/material.dart';

/// The web app's design tokens (web/src/app/globals.css), so the two clients
/// read as one product: washi paper ground, ink text, one blue accent.
class HankoColors {
  const HankoColors._();

  static const seal = Color(0xFF256ABF);
  static const sealDark = Color(0xFF184F95);
  static const sealTint = Color(0xFFDBE7F7);

  static const paper = Color(0xFFFAF7F0);
  static const paperDim = Color(0xFFF0EBDD);
  static const paperDeep = Color(0xFFE6E0CF);
  static const line = Color(0xFFD8D0BE);
  static const lineSoft = Color(0xFFE8E2D4);

  static const ink = Color(0xFF1F2933);
  static const inkSoft = Color(0xFF666053);
  static const inkMute = Color(0xFF787161);

  /// The battle arena's dark stage (globals.css `.hk-arena`).
  static const arena = Color(0xFF202832);
  static const parchment = Color(0xFFF6EFE1);

  /// Grade ramp (web/src/app/decks/_lib/gradeColors.ts): one hue, light to
  /// dark = weak to strong, with "new" as a neutral outside the ramp.
  static const gradeNew = Color(0xFF898781);
  static const gradeF = Color(0xFF86B6EF);
  static const gradeD = Color(0xFF3987E5);
  static const gradeC = Color(0xFF256ABF);
  static const gradeB = Color(0xFF184F95);
  static const gradeA = Color(0xFF0D366B);

  static const heatmapEmpty = Color(0xFFEBEDF0);
}

/// One rating palette for every screen that grades a card. Review, leech
/// rescue and the speed round each used to pick their own reds and greens.
/// Tone is carried by tint plus the label text, never by color alone, and
/// "again" stays red: that's the semantic wrong-answer color, not the brand.
class RatingColors {
  const RatingColors._();

  static const again = Color(0xFFB91C1C);
  static const hard = Color(0xFF92400E);
  static const good = HankoColors.seal;
  static const easy = Color(0xFF047857);

  static Color of(String rating) => switch (rating) {
        'again' => again,
        'hard' => hard,
        'easy' => easy,
        _ => good,
      };
}

ThemeData buildHankoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HankoColors.seal,
    primary: HankoColors.seal,
    onPrimary: Colors.white,
    surface: HankoColors.paper,
    onSurface: HankoColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: HankoColors.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: HankoColors.paper,
      foregroundColor: HankoColors.ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: HankoColors.lineSoft),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: HankoColors.sealTint,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? HankoColors.ink
              : HankoColors.inkSoft,
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
    dividerTheme: const DividerThemeData(color: HankoColors.lineSoft),
  );
}
