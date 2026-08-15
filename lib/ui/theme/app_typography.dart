import 'package:flutter/material.dart';

/// Instrument Sans for running text and UI chrome, IBM Plex Mono for
/// anything that's a number, timestamp, tail number or code — a logbook is
/// a ledger, so figures get a tabular mono cut to line up on any screen,
/// while labels stay in the open, humanist sans (twilight palette design,
/// Claude Design project 513e7fc3-e41a-40ea-b3a5-f16f086d15f8, section 1a).
const _sans = 'Instrument Sans';
const _mono = 'IBM Plex Mono';

TextTheme buildTextTheme(Color ink) {
  TextStyle sans(
    double size,
    FontWeight weight, {
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: _sans,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: ink,
    );
  }

  return TextTheme(
    displayLarge: sans(34, FontWeight.w700, height: 1.15),
    displayMedium: sans(28, FontWeight.w700, height: 1.2),
    displaySmall: sans(24, FontWeight.w600, height: 1.2),
    headlineLarge: sans(22, FontWeight.w600, height: 1.25),
    headlineMedium: sans(20, FontWeight.w600, height: 1.25),
    headlineSmall: sans(18, FontWeight.w600, height: 1.3),
    titleLarge: sans(17, FontWeight.w600, height: 1.3),
    titleMedium: sans(15, FontWeight.w600, height: 1.35),
    titleSmall: sans(13, FontWeight.w600, height: 1.35, letterSpacing: 0.1),
    bodyLarge: sans(16, FontWeight.w400, height: 1.4),
    bodyMedium: sans(14, FontWeight.w400, height: 1.4),
    bodySmall: sans(12.5, FontWeight.w400, height: 1.4),
    labelLarge: sans(14, FontWeight.w500, height: 1.3),
    labelMedium: sans(12, FontWeight.w500, height: 1.3, letterSpacing: 0.2),
    labelSmall: sans(10.5, FontWeight.w500, height: 1.3, letterSpacing: 0.3),
  );
}

/// Mono styles for data — durations, dates, tail numbers, ICAO codes,
/// rule/tag ids. Not part of [TextTheme] because mono is a per-value
/// choice, not a document-structure role.
class AppMonoText {
  const AppMonoText._();

  static TextStyle value(
    Color color, {
    double size = 15,
    FontWeight weight = FontWeight.w500,
  }) {
    return TextStyle(
      fontFamily: _mono,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
  }

  static TextStyle valueLarge(Color color) =>
      value(color, size: 22, weight: FontWeight.w600);

  static TextStyle tag(Color color) =>
      value(color, size: 10.5, weight: FontWeight.w600);
}
