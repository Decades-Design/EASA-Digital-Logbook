import 'package:flutter/material.dart';

/// The three-state colour system the Currency screen's own mockup defines
/// (Claude Design project 513e7fc3-e41a-40ea-b3a5-f16f086d15f8, "Currency
/// Totals Settings.dc.html", sections 2a/2a-dark) — red for expired, amber
/// for due soon, green for healthy. Deliberately separate from
/// [AppSemanticColors]'s `currencyWarning`/`error`: those are the app's
/// general-purpose attention/error tones (draft badges, form validation),
/// tuned for a different job, while this screen's mockup specifies its own
/// tighter red/amber/green with several distinct shades per state (a bright
/// "accent" for dots/labels/links, a darker "text" for titles and body
/// copy, and a separate bar-fill shade) — collapsing them into the generic
/// tokens would lose that.
///
/// Every value here is a direct conversion of the mockup's own OKLCH
/// swatches to sRGB via the standard OKLab matrices, not a hand-picked
/// approximation. Dark values come from the mockup's own "2a-dark" variant
/// (independently re-tuned there, not an inverted copy of light — see that
/// section's own note in the design doc).
@immutable
class CurrencyStatusColors {
  const CurrencyStatusColors({
    required this.accent,
    required this.text,
    required this.fill,
    required this.cardBackground,
    required this.cardBorder,
  });

  /// Status dot, the "EXPIRED"/"DUE SOON" label, and the "Which flights
  /// counted" link — the brightest, most saturated shade of the state.
  final Color accent;

  /// Title, numeric line, and footer/context copy inside a hero card or a
  /// flagged list row — darker than [accent] so extended text stays
  /// readable rather than glaring.
  final Color text;

  /// Progress bar fill — its own shade, distinct from both [accent] and
  /// [text] in the source mockup.
  final Color fill;

  final Color cardBackground;
  final Color cardBorder;
}

class CurrencyPalette {
  const CurrencyPalette._();

  static const _expiredLight = CurrencyStatusColors(
    accent: Color(0xFFBE222A),
    text: Color(0xFF861118),
    fill: Color(0xFFC92F33),
    cardBackground: Color(0xFFFFE9E6),
    cardBorder: Color(0xFFFFCCC7),
  );

  static const _expiredDark = CurrencyStatusColors(
    accent: Color(0xFFF97770),
    text: Color(0xFFFFC6C0),
    fill: Color(0xFFF66D67),
    cardBackground: Color(0xFF421C19),
    cardBorder: Color(0xFF6C3531),
  );

  static const _dueSoonLight = CurrencyStatusColors(
    accent: Color(0xFFB86B00),
    text: Color(0xFF5B2D00),
    fill: Color(0xFFCC8730),
    cardBackground: Color(0xFFFFEFD5),
    cardBorder: Color(0xFFEFD3AC),
  );

  static const _dueSoonDark = CurrencyStatusColors(
    accent: Color(0xFFE7A04C),
    text: Color(0xFFF1D2AD),
    fill: Color(0xFFEAA85D),
    cardBackground: Color(0xFF382409),
    cardBorder: Color(0xFF573C1C),
  );

  /// The "DUE SOON" mono label itself uses a third amber shade in the
  /// source mockup — distinct from both [_dueSoonLight]'s accent (the dot)
  /// and text (the title) colours. Nothing else needs this one, so it
  /// isn't a [CurrencyStatusColors] field of its own.
  static const dueSoonLabelLight = Color(0xFF854F15);
  static const dueSoonLabelDark = Color(0xFFDFB585);

  static const _healthyFillLight = Color(0xFF008053);
  static const _healthyFillDark = Color(0xFF57BC8A);

  static CurrencyStatusColors expired(Brightness brightness) =>
      brightness == Brightness.dark ? _expiredDark : _expiredLight;

  static CurrencyStatusColors dueSoon(Brightness brightness) =>
      brightness == Brightness.dark ? _dueSoonDark : _dueSoonLight;

  static Color dueSoonLabel(Brightness brightness) =>
      brightness == Brightness.dark ? dueSoonLabelDark : dueSoonLabelLight;

  static Color healthyFill(Brightness brightness) =>
      brightness == Brightness.dark ? _healthyFillDark : _healthyFillLight;
}
