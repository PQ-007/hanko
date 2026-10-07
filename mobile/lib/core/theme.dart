import 'package:flutter/material.dart';

/// Brand constants that are the same in light and dark: the blue accent
/// (web/src/app/globals.css --color-seal) and the battle arena's own stage.
/// Everything that changes with the theme lives in [HankoPalette].
class HankoColors {
  const HankoColors._();

  static const seal = Color(0xFF256ABF);
  static const sealDark = Color(0xFF184F95);

  /// The battle arena's dark stage (globals.css `.hk-arena`).
  static const arena = Color(0xFF202832);
  static const parchment = Color(0xFFF6EFE1);
}

/// Every colour that differs between light and dark mode. Read it with
/// `context.hk` so widgets follow the active theme instead of hard-coding the
/// light palette.
@immutable
class HankoPalette extends ThemeExtension<HankoPalette> {
  const HankoPalette({
    required this.paper,
    required this.card,
    required this.paperDim,
    required this.paperDeep,
    required this.line,
    required this.lineSoft,
    required this.ink,
    required this.inkSoft,
    required this.inkMute,
    required this.sealTint,
    required this.heatmapEmpty,
    required this.gradeNew,
    required this.gradeF,
    required this.gradeD,
    required this.gradeC,
    required this.gradeB,
    required this.gradeA,
    required this.again,
    required this.hard,
    required this.easy,
    required this.warnBg,
    required this.warnFg,
    this.seal = HankoColors.seal,
    this.sealDark = HankoColors.sealDark,
    this.sealTextOverride,
  });

  /// The accent (primary buttons, links, selected states). Blue everywhere
  /// except Цайвар, which takes the vermilion of the hanko seal itself.
  final Color seal;
  final Color sealDark;

  /// The accent as text or an icon on the page. Same as [seal] except on
  /// Цэнхэр, where navy on a blue page is unreadable (web: the
  /// html[data-scheme="blue"] .text-seal override).
  Color get sealText => sealTextOverride ?? seal;
  final Color? sealTextOverride;

  /// Page background.
  final Color paper;

  /// Cards, sheets, the navigation bar.
  final Color card;
  final Color paperDim;
  final Color paperDeep;
  final Color line;
  final Color lineSoft;
  final Color ink;
  final Color inkSoft;
  final Color inkMute;

  /// Unfilled ring track, selected chips, the nav indicator.
  final Color sealTint;
  final Color heatmapEmpty;

  /// Grade ramp. Light mode is the web's (light → dark = weak → strong). On a
  /// deep-blue background the darkest steps would vanish, so dark mode runs
  /// the same order the other way — dim → bright = weak → strong — keeping
  /// "more mastered" as "more visible" in both.
  final Color gradeNew;
  final Color gradeF;
  final Color gradeD;
  final Color gradeC;
  final Color gradeB;
  final Color gradeA;

  /// Rating colours. "Again" stays red: that's the semantic wrong-answer
  /// colour, not the brand. Good uses the primary in both themes.
  final Color again;
  final Color hard;
  final Color easy;

  /// Offline banner.
  final Color warnBg;
  final Color warnFg;

  static const light = HankoPalette(
    paper: Color(0xFFFAF7F0),
    card: Colors.white,
    paperDim: Color(0xFFF0EBDD),
    paperDeep: Color(0xFFE6E0CF),
    line: Color(0xFFD8D0BE),
    lineSoft: Color(0xFFE8E2D4),
    ink: Color(0xFF1F2933),
    inkSoft: Color(0xFF666053),
    inkMute: Color(0xFF787161),
    sealTint: Color(0xFFDBE7F7),
    heatmapEmpty: Color(0xFFEBEDF0),
    gradeNew: Color(0xFF898781),
    gradeF: Color(0xFF86B6EF),
    gradeD: Color(0xFF3987E5),
    gradeC: Color(0xFF256ABF),
    gradeB: Color(0xFF184F95),
    gradeA: Color(0xFF0D366B),
    again: Color(0xFFB91C1C),
    hard: Color(0xFF92400E),
    easy: Color(0xFF047857),
    warnBg: Color(0xFFFFF8E1),
    warnFg: Color(0xFF8A5A00),
  );

  /// Deep blue. Primary (#256ABF) is unchanged; surfaces step up in lightness
  /// so cards still read as raised above the page.
  static const dark = HankoPalette(
    paper: Color(0xFF0A1A33),
    card: Color(0xFF10264A),
    paperDim: Color(0xFF15305A),
    paperDeep: Color(0xFF1F3B66),
    line: Color(0xFF2C4A78),
    lineSoft: Color(0xFF1C365E),
    ink: Color(0xFFEAF1FB),
    inkSoft: Color(0xFFB4C4DD),
    inkMute: Color(0xFF8FA3C2),
    sealTint: Color(0xFF1D3D6B),
    heatmapEmpty: Color(0xFF18315A),
    gradeNew: Color(0xFF6B7488),
    gradeF: Color(0xFF2B5C99),
    gradeD: Color(0xFF3F7FCF),
    gradeC: Color(0xFF5E9BE4),
    gradeB: Color(0xFF8DBBF0),
    gradeA: Color(0xFFC3DCFA),
    again: Color(0xFFF87171),
    hard: Color(0xFFFBBF24),
    easy: Color(0xFF34D399),
    warnBg: Color(0xFF3A2E10),
    warnFg: Color(0xFFFCD679),
  );

  /// Цэнхэр — the story image's seal blue (storyCard.ts "seal"), same
  /// tokens as the web's html[data-scheme="blue"]: a blue page, lighter blue
  /// cards, white type, deep-navy buttons; the grade ramp runs dim → bright.
  static const blue = HankoPalette(
    paper: Color(0xFF2563B8),
    card: Color(0xFF2F6EC4),
    paperDim: Color(0xFF1F57A6),
    paperDeep: Color(0xFF1B4F96),
    line: Color(0xFF5B8FD6),
    lineSoft: Color(0xFF3F78C8),
    ink: Color(0xFFFFFFFF),
    inkSoft: Color(0xFFDBE8FB),
    inkMute: Color(0xFFB3CBEE),
    sealTint: Color(0xFF3A74C4),
    heatmapEmpty: Color(0xFF1B4F96),
    gradeNew: Color(0xFF9AAECB),
    gradeF: Color(0xFF7FB0EE),
    gradeD: Color(0xFFA6C9F5),
    gradeC: Color(0xFFC9DFFB),
    gradeB: Color(0xFFE4EFFD),
    gradeA: Color(0xFFFFFFFF),
    again: Color(0xFFFCA5A5),
    hard: Color(0xFFFCD34D),
    easy: Color(0xFF6EE7B7),
    warnBg: Color(0xFF4A3A12),
    warnFg: Color(0xFFFCD679),
    seal: Color(0xFF0F3A78),
    sealDark: Color(0xFF0B2D5E),
    sealTextOverride: Color(0xFFD6E8FF),
  );

  /// Цайвар — the story image's washi paper (storyCard.ts "paper"), the
  /// default: warm amber cream, white cards, the hanko's vermilion as the
  /// accent. Same tokens as the web's html[data-scheme="paper"].
  static const paperTheme = HankoPalette(
    paper: Color(0xFFF7EEDD),
    card: Color(0xFFFFFFFF),
    paperDim: Color(0xFFEFE0C4),
    paperDeep: Color(0xFFE6D3B1),
    line: Color(0xFFDCC7A2),
    lineSoft: Color(0xFFECDFC6),
    ink: Color(0xFF1C232B),
    inkSoft: Color(0xFF5F5546),
    inkMute: Color(0xFF75685A),
    sealTint: Color(0xFFF6DDD6),
    heatmapEmpty: Color(0xFFEFE0C4),
    gradeNew: Color(0xFF8C7F6C),
    gradeF: Color(0xFFEFA898),
    gradeD: Color(0xFFE07A63),
    gradeC: Color(0xFFC8442F),
    gradeB: Color(0xFF9E3322),
    gradeA: Color(0xFF6E2116),
    again: Color(0xFFB91C1C),
    hard: Color(0xFF92400E),
    easy: Color(0xFF047857),
    warnBg: Color(0xFFFFF4D6),
    warnFg: Color(0xFF8A5A00),
    seal: Color(0xFFC8442F),
    sealDark: Color(0xFFA83623),
  );

  Color rating(String rating) => switch (rating) {
        'again' => again,
        'hard' => hard,
        'easy' => easy,
        _ => seal,
      };

  @override
  HankoPalette copyWith() => this;

  @override
  HankoPalette lerp(HankoPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return HankoPalette(
      paper: l(paper, other.paper),
      card: l(card, other.card),
      paperDim: l(paperDim, other.paperDim),
      paperDeep: l(paperDeep, other.paperDeep),
      line: l(line, other.line),
      lineSoft: l(lineSoft, other.lineSoft),
      ink: l(ink, other.ink),
      inkSoft: l(inkSoft, other.inkSoft),
      inkMute: l(inkMute, other.inkMute),
      sealTint: l(sealTint, other.sealTint),
      heatmapEmpty: l(heatmapEmpty, other.heatmapEmpty),
      gradeNew: l(gradeNew, other.gradeNew),
      gradeF: l(gradeF, other.gradeF),
      gradeD: l(gradeD, other.gradeD),
      gradeC: l(gradeC, other.gradeC),
      gradeB: l(gradeB, other.gradeB),
      gradeA: l(gradeA, other.gradeA),
      again: l(again, other.again),
      hard: l(hard, other.hard),
      easy: l(easy, other.easy),
      warnBg: l(warnBg, other.warnBg),
      warnFg: l(warnFg, other.warnFg),
      seal: l(seal, other.seal),
      sealDark: l(sealDark, other.sealDark),
      sealTextOverride: l(sealText, other.sealText),
    );
  }
}

extension HankoThemeContext on BuildContext {
  HankoPalette get hk => Theme.of(this).extension<HankoPalette>() ?? HankoPalette.light;
}

ThemeData buildHankoTheme(Brightness brightness, [HankoPalette? palette]) {
  final p = palette ?? (brightness == Brightness.dark ? HankoPalette.dark : HankoPalette.light);
  final scheme = ColorScheme.fromSeed(
    seedColor: p.seal,
    brightness: brightness,
    primary: p.seal,
    onPrimary: Colors.white,
    surface: p.paper,
    onSurface: p.ink,
    surfaceContainerLowest: p.card,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.paperDim,
    surfaceContainerHighest: p.paperDeep,
    onSurfaceVariant: p.inkSoft,
    outline: p.line,
    outlineVariant: p.lineSoft,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.paper,
    canvasColor: p.paper,
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.lineSoft),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      indicatorColor: p.sealTint,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? p.ink : p.inkSoft,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: p.card,
    ),
    dividerTheme: DividerThemeData(color: p.lineSoft),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.sealTint,
      side: BorderSide(color: p.lineSoft),
    ),
  );
}
