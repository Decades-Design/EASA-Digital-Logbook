import 'package:flutter/material.dart';

/// Raw palette values, kept private so every screen goes through
/// [ColorScheme] / [AppSemanticColors] rather than reaching for a hex code
/// directly.
///
/// "Twilight" palette — replaces the M4 warm-paper theme. Almost every hard
/// problem in this app is a day/night problem (civil twilight, FAA night
/// windows, night landings, night passenger recency), so the brand is
/// twilight: a deep indigo night and a warm ochre day, one hue each, on
/// near-neutral greys. Values are converted from the OKLCH swatches in the
/// "Flight Logbook - App Design" doc (Claude Design project
/// 513e7fc3-e41a-40ea-b3a5-f16f086d15f8, section 1a) via the standard
/// OKLab/sRGB matrices — see memory (twilight-palette-oklch-source) for the
/// swatch list. No dark-mode 1b mock exists; dark values not directly
/// sampled from a swatch (badge/banner surfaces) are relit by hand from the
/// same hue/chroma family rather than guessed from scratch.
class _Palette {
  // Night — indigo. The one accent colour, unchanged across light/dark
  // (the design keeps a single primary hue rather than lightening it for
  // dark mode).
  static const nightPrimary = Color(0xFF325AC2);
  static const nightPressed = Color(0xFF142C6F);

  // Day — ochre. Secondary accent, also constant across modes.
  static const daySecondary = Color(0xFFB86B00);

  // Light neutrals.
  static const paperLight = Color(0xFFEFF0F3);
  static const surfaceLight = Color(0xFFF5F7FA);
  static const inkLight = Color(0xFF1C202A);
  static const inkMediumLight = Color(0xFF424853);
  static const inkMutedLight = Color(0xFF6C7079);
  static const inkFaintLight = Color(0xFF878B92);
  static const borderLight = Color(0xFFDDE0E5);
  static const borderStrongLight = Color(0xFFC7CBD2);

  // Dark neutrals — near-black indigo rather than pure black, so the same
  // hue family carries into dark mode.
  static const paperDark = Color(0xFF0A0C11);
  static const surfaceDark = Color(0xFF14171E);
  static const inkDark = Color(0xFFF0F2F6);
  static const inkMediumDark = Color(0xFFB9BEC7);
  static const inkMutedDark = Color(0xFFA1A5AC);
  static const inkFaintDark = Color(0xFF8F929A);
  static const borderDark = Color(0xFF2A2E36);
  static const borderStrongDark = Color(0xFF3A3F49);

  // Divergence ("MISMATCH" chip) — same ochre family as attention; the new
  // design doesn't give jurisdiction divergence a separate hue from
  // "needs attention".
  static const divergenceLight = Color(0xFF733E00);
  static const divergenceSurfaceLight = Color(0xFFFFE7C7);
  static const divergenceDark = Color(0xFFE3B47D);
  static const divergenceSurfaceDark = Color(0xFF3F2810);

  // Attention/currency warning — DRAFT/UNSIGNED badges and the "N flights
  // need attention" banner. Ochre, same family as divergence above.
  static const currencyLight = Color(0xFF733E00);
  static const currencySurfaceLight = Color(0xFFFFE7C7);
  static const currencyDark = Color(0xFFE3B47D);
  static const currencySurfaceDark = Color(0xFF3F2810);

  // Neutral badge (e.g. "IFR") — flat grey chip, no hue.
  static const neutralBadgeTextLight = Color(0xFF595E66);
  static const neutralBadgeSurfaceLight = Color(0xFFEDF0F6);
  static const neutralBadgeBorderLight = Color(0xFFDBDEE5);
  static const neutralBadgeTextDark = Color(0xFFB4B7BF);
  static const neutralBadgeSurfaceDark = Color(0xFF21242B);
  static const neutralBadgeBorderDark = Color(0xFF343840);

  // Night badge (the "NIGHT" tag on a flight row) — a dark indigo chip that
  // reads the same on a light or dark page background.
  static const nightBadgeText = Color(0xFFE1E8F6);
  static const nightBadgeSurface = Color(0xFF1F2D4C);

  // "OVERRIDDEN" marker — a manually-entered value overriding what the
  // rule engine would otherwise compute. Indigo, distinct from the
  // primary accent so it reads as a marker rather than a link/action.
  static const overriddenTextLight = Color(0xFF264698);
  static const overriddenTextDark = Color(0xFF80A3F0);

  static const errorLight = Color(0xFFBD3838);
  static const errorDark = Color(0xFFF07F77);
}

/// Colour roles that Material's [ColorScheme] doesn't have a slot for —
/// the jurisdiction-divergence and currency-warning treatments used across
/// the logbook, entry form and currency dashboard.
///
/// Read through `Theme.of(context).extension<AppSemanticColors>()!`, or the
/// `context.semanticColors` shortcut below.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.divergence,
    required this.divergenceSurface,
    required this.currencyWarning,
    required this.currencyWarningSurface,
    required this.neutralBadgeText,
    required this.neutralBadgeSurface,
    required this.neutralBadgeBorder,
    required this.nightBadgeText,
    required this.nightBadgeSurface,
    required this.overriddenText,
  });

  /// Text/icon colour for jurisdiction-divergence badges (the "MISMATCH"
  /// chip).
  final Color divergence;

  /// Background tint behind a divergence badge.
  final Color divergenceSurface;

  /// Text/icon colour for a currency-lapse, approaching-lapse, or
  /// needs-attention warning (draft/unsigned flights, the "N flights need
  /// attention" banner).
  final Color currencyWarning;

  /// Background tint behind a currency/attention warning.
  final Color currencyWarningSurface;

  /// Text colour for a flat, hueless badge (e.g. "IFR").
  final Color neutralBadgeText;

  /// Background tint behind a neutral badge.
  final Color neutralBadgeSurface;

  /// Border colour for a neutral badge.
  final Color neutralBadgeBorder;

  /// Text colour for the "NIGHT" tag.
  final Color nightBadgeText;

  /// Background for the "NIGHT" tag — a dark indigo chip that reads the
  /// same regardless of page background, so it isn't themed per mode.
  final Color nightBadgeSurface;

  /// Text/marker colour for a manually-overridden derived value.
  final Color overriddenText;

  static const light = AppSemanticColors(
    divergence: _Palette.divergenceLight,
    divergenceSurface: _Palette.divergenceSurfaceLight,
    currencyWarning: _Palette.currencyLight,
    currencyWarningSurface: _Palette.currencySurfaceLight,
    neutralBadgeText: _Palette.neutralBadgeTextLight,
    neutralBadgeSurface: _Palette.neutralBadgeSurfaceLight,
    neutralBadgeBorder: _Palette.neutralBadgeBorderLight,
    nightBadgeText: _Palette.nightBadgeText,
    nightBadgeSurface: _Palette.nightBadgeSurface,
    overriddenText: _Palette.overriddenTextLight,
  );

  static const dark = AppSemanticColors(
    divergence: _Palette.divergenceDark,
    divergenceSurface: _Palette.divergenceSurfaceDark,
    currencyWarning: _Palette.currencyDark,
    currencyWarningSurface: _Palette.currencySurfaceDark,
    neutralBadgeText: _Palette.neutralBadgeTextDark,
    neutralBadgeSurface: _Palette.neutralBadgeSurfaceDark,
    neutralBadgeBorder: _Palette.neutralBadgeBorderDark,
    nightBadgeText: _Palette.nightBadgeText,
    nightBadgeSurface: _Palette.nightBadgeSurface,
    overriddenText: _Palette.overriddenTextDark,
  );

  @override
  AppSemanticColors copyWith({
    Color? divergence,
    Color? divergenceSurface,
    Color? currencyWarning,
    Color? currencyWarningSurface,
    Color? neutralBadgeText,
    Color? neutralBadgeSurface,
    Color? neutralBadgeBorder,
    Color? nightBadgeText,
    Color? nightBadgeSurface,
    Color? overriddenText,
  }) {
    return AppSemanticColors(
      divergence: divergence ?? this.divergence,
      divergenceSurface: divergenceSurface ?? this.divergenceSurface,
      currencyWarning: currencyWarning ?? this.currencyWarning,
      currencyWarningSurface:
          currencyWarningSurface ?? this.currencyWarningSurface,
      neutralBadgeText: neutralBadgeText ?? this.neutralBadgeText,
      neutralBadgeSurface: neutralBadgeSurface ?? this.neutralBadgeSurface,
      neutralBadgeBorder: neutralBadgeBorder ?? this.neutralBadgeBorder,
      nightBadgeText: nightBadgeText ?? this.nightBadgeText,
      nightBadgeSurface: nightBadgeSurface ?? this.nightBadgeSurface,
      overriddenText: overriddenText ?? this.overriddenText,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      divergence: Color.lerp(divergence, other.divergence, t)!,
      divergenceSurface: Color.lerp(
        divergenceSurface,
        other.divergenceSurface,
        t,
      )!,
      currencyWarning: Color.lerp(currencyWarning, other.currencyWarning, t)!,
      currencyWarningSurface: Color.lerp(
        currencyWarningSurface,
        other.currencyWarningSurface,
        t,
      )!,
      neutralBadgeText: Color.lerp(
        neutralBadgeText,
        other.neutralBadgeText,
        t,
      )!,
      neutralBadgeSurface: Color.lerp(
        neutralBadgeSurface,
        other.neutralBadgeSurface,
        t,
      )!,
      neutralBadgeBorder: Color.lerp(
        neutralBadgeBorder,
        other.neutralBadgeBorder,
        t,
      )!,
      nightBadgeText: Color.lerp(nightBadgeText, other.nightBadgeText, t)!,
      nightBadgeSurface: Color.lerp(
        nightBadgeSurface,
        other.nightBadgeSurface,
        t,
      )!,
      overriddenText: Color.lerp(overriddenText, other.overriddenText, t)!,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}

ColorScheme buildLightColorScheme() => const ColorScheme.light(
  primary: _Palette.nightPrimary,
  onPrimary: Colors.white,
  primaryContainer: _Palette.nightPrimary,
  onPrimaryContainer: Colors.white,
  secondary: _Palette.daySecondary,
  onSecondary: Colors.white,
  surface: _Palette.surfaceLight,
  onSurface: _Palette.inkLight,
  surfaceContainerLowest: _Palette.paperLight,
  surfaceContainerLow: _Palette.paperLight,
  surfaceContainer: _Palette.surfaceLight,
  surfaceContainerHigh: _Palette.surfaceLight,
  onSurfaceVariant: _Palette.inkMutedLight,
  outline: _Palette.borderStrongLight,
  outlineVariant: _Palette.borderLight,
  error: _Palette.errorLight,
  onError: Colors.white,
  inversePrimary: _Palette.nightPressed,
);

ColorScheme buildDarkColorScheme() => const ColorScheme.dark(
  primary: _Palette.nightPrimary,
  onPrimary: Colors.white,
  primaryContainer: _Palette.nightPrimary,
  onPrimaryContainer: Colors.white,
  secondary: _Palette.daySecondary,
  onSecondary: Colors.white,
  surface: _Palette.surfaceDark,
  onSurface: _Palette.inkDark,
  surfaceContainerLowest: _Palette.paperDark,
  surfaceContainerLow: _Palette.paperDark,
  surfaceContainer: _Palette.surfaceDark,
  surfaceContainerHigh: _Palette.surfaceDark,
  onSurfaceVariant: _Palette.inkMutedDark,
  outline: _Palette.borderStrongDark,
  outlineVariant: _Palette.borderDark,
  error: _Palette.errorDark,
  onError: _Palette.paperDark,
  inversePrimary: _Palette.nightPrimary,
);

/// The muted/faint ink tiers sit outside [ColorScheme]'s roles too — expose
/// them the same way as the semantic colours rather than hard-coding hex in
/// screens. Kept in this file, next to the palette they're drawn from.
@immutable
class AppInkTiers extends ThemeExtension<AppInkTiers> {
  const AppInkTiers({
    required this.medium,
    required this.muted,
    required this.faint,
  });

  final Color medium;
  final Color muted;
  final Color faint;

  static const light = AppInkTiers(
    medium: _Palette.inkMediumLight,
    muted: _Palette.inkMutedLight,
    faint: _Palette.inkFaintLight,
  );

  static const dark = AppInkTiers(
    medium: _Palette.inkMediumDark,
    muted: _Palette.inkMutedDark,
    faint: _Palette.inkFaintDark,
  );

  @override
  AppInkTiers copyWith({Color? medium, Color? muted, Color? faint}) {
    return AppInkTiers(
      medium: medium ?? this.medium,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
    );
  }

  @override
  AppInkTiers lerp(ThemeExtension<AppInkTiers>? other, double t) {
    if (other is! AppInkTiers) return this;
    return AppInkTiers(
      medium: Color.lerp(medium, other.medium, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
    );
  }
}

extension AppInkTiersContext on BuildContext {
  AppInkTiers get inkTiers => Theme.of(this).extension<AppInkTiers>()!;
}
