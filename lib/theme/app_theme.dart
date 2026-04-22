import 'package:flutter/material.dart';

/// 全局种子色：偏影院感的深靛蓝。
const Color kAppSeedIndigo = Color(0xFF1E2A5A);

/// 播放器控制层与对话框的视觉 tokens，避免在页面内散落魔法数。
@immutable
class PlayerChrome extends ThemeExtension<PlayerChrome> {
  final Color accent;
  final Color bottomGradientStart;
  final Color topGradientStart;
  final Color pillBackground;
  final double pillRadius;
  final double chipRadius;
  final double indicatorRadius;
  final Color chipBackground;
  final Color chipBorder;
  final Color dialogBackground;
  final Color osdOnScrim;
  final Color osdOnScrimMuted;
  final Color volumeRailBackground;
  final Color playPauseBackground;
  final Color playPauseBorder;
  final Color indicatorBackground;
  final Color selectionHighlight;

  const PlayerChrome({
    required this.accent,
    required this.bottomGradientStart,
    required this.topGradientStart,
    required this.pillBackground,
    required this.pillRadius,
    required this.chipRadius,
    required this.indicatorRadius,
    required this.chipBackground,
    required this.chipBorder,
    required this.dialogBackground,
    required this.osdOnScrim,
    required this.osdOnScrimMuted,
    required this.volumeRailBackground,
    required this.playPauseBackground,
    required this.playPauseBorder,
    required this.indicatorBackground,
    required this.selectionHighlight,
  });

  factory PlayerChrome.fromScheme(ColorScheme scheme) {
    final accent = scheme.primary;
    return PlayerChrome(
      accent: accent,
      bottomGradientStart: const Color(0x8A000000),
      topGradientStart: const Color(0xDE000000),
      pillBackground: const Color(0x61000000),
      pillRadius: 12,
      chipRadius: 10,
      indicatorRadius: 8,
      chipBackground: const Color(0x78000000),
      chipBorder: const Color(0x3DFFFFFF),
      dialogBackground: const Color(0xDE000000),
      osdOnScrim: Colors.white,
      osdOnScrimMuted: const Color(0xB3FFFFFF),
      volumeRailBackground: const Color(0x66000000),
      playPauseBackground: const Color(0x4C000000),
      playPauseBorder: const Color(0x80FFFFFF),
      indicatorBackground: const Color(0x8A000000),
      selectionHighlight: accent.withAlpha(77),
    );
  }

  LinearGradient get bottomBarGradient => LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [bottomGradientStart, Colors.transparent],
      );

  LinearGradient get topBarGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topGradientStart, Colors.transparent],
      );

  BoxDecoration get pillDecoration => BoxDecoration(
        color: pillBackground,
        borderRadius: BorderRadius.circular(pillRadius),
      );

  BoxDecoration get indicatorDecoration => BoxDecoration(
        color: indicatorBackground,
        borderRadius: BorderRadius.all(Radius.circular(indicatorRadius)),
      );

  @override
  PlayerChrome copyWith({
    Color? accent,
    Color? bottomGradientStart,
    Color? topGradientStart,
    Color? pillBackground,
    double? pillRadius,
    double? chipRadius,
    double? indicatorRadius,
    Color? chipBackground,
    Color? chipBorder,
    Color? dialogBackground,
    Color? osdOnScrim,
    Color? osdOnScrimMuted,
    Color? volumeRailBackground,
    Color? playPauseBackground,
    Color? playPauseBorder,
    Color? indicatorBackground,
    Color? selectionHighlight,
  }) {
    return PlayerChrome(
      accent: accent ?? this.accent,
      bottomGradientStart: bottomGradientStart ?? this.bottomGradientStart,
      topGradientStart: topGradientStart ?? this.topGradientStart,
      pillBackground: pillBackground ?? this.pillBackground,
      pillRadius: pillRadius ?? this.pillRadius,
      chipRadius: chipRadius ?? this.chipRadius,
      indicatorRadius: indicatorRadius ?? this.indicatorRadius,
      chipBackground: chipBackground ?? this.chipBackground,
      chipBorder: chipBorder ?? this.chipBorder,
      dialogBackground: dialogBackground ?? this.dialogBackground,
      osdOnScrim: osdOnScrim ?? this.osdOnScrim,
      osdOnScrimMuted: osdOnScrimMuted ?? this.osdOnScrimMuted,
      volumeRailBackground: volumeRailBackground ?? this.volumeRailBackground,
      playPauseBackground: playPauseBackground ?? this.playPauseBackground,
      playPauseBorder: playPauseBorder ?? this.playPauseBorder,
      indicatorBackground: indicatorBackground ?? this.indicatorBackground,
      selectionHighlight: selectionHighlight ?? this.selectionHighlight,
    );
  }

  @override
  PlayerChrome lerp(ThemeExtension<PlayerChrome>? other, double t) {
    if (other is! PlayerChrome) return this;
    return PlayerChrome(
      accent: Color.lerp(accent, other.accent, t)!,
      bottomGradientStart:
          Color.lerp(bottomGradientStart, other.bottomGradientStart, t)!,
      topGradientStart: Color.lerp(topGradientStart, other.topGradientStart, t)!,
      pillBackground: Color.lerp(pillBackground, other.pillBackground, t)!,
      pillRadius: pillRadius + (other.pillRadius - pillRadius) * t,
      chipRadius: chipRadius + (other.chipRadius - chipRadius) * t,
      indicatorRadius:
          indicatorRadius + (other.indicatorRadius - indicatorRadius) * t,
      chipBackground: Color.lerp(chipBackground, other.chipBackground, t)!,
      chipBorder: Color.lerp(chipBorder, other.chipBorder, t)!,
      dialogBackground:
          Color.lerp(dialogBackground, other.dialogBackground, t)!,
      osdOnScrim: Color.lerp(osdOnScrim, other.osdOnScrim, t)!,
      osdOnScrimMuted: Color.lerp(osdOnScrimMuted, other.osdOnScrimMuted, t)!,
      volumeRailBackground:
          Color.lerp(volumeRailBackground, other.volumeRailBackground, t)!,
      playPauseBackground:
          Color.lerp(playPauseBackground, other.playPauseBackground, t)!,
      playPauseBorder: Color.lerp(playPauseBorder, other.playPauseBorder, t)!,
      indicatorBackground:
          Color.lerp(indicatorBackground, other.indicatorBackground, t)!,
      selectionHighlight:
          Color.lerp(selectionHighlight, other.selectionHighlight, t)!,
    );
  }
}

ThemeData buildAppTheme({
  required Brightness brightness,
  required PageTransitionsTheme pageTransitionsTheme,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kAppSeedIndigo,
    brightness: brightness,
  );

  final base = ThemeData(
    colorScheme: colorScheme,
    brightness: brightness,
    useMaterial3: true,
  );

  final playerChrome = PlayerChrome.fromScheme(colorScheme);

  return base.copyWith(
    pageTransitionsTheme: pageTransitionsTheme,
    cardTheme: CardThemeData(
      elevation: 2,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
    ),
    extensions: <ThemeExtension<dynamic>>[
      playerChrome,
    ],
  );
}
