import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's first real Riverpod state (`ProviderScope` has wrapped
/// `main.dart` since M0, but nothing used it until Settings). Overridden in
/// `main()` with the real instance from `SharedPreferences.getInstance()`
/// before `runApp` — reading this before that override is a programming
/// error, not a recoverable one.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() before runApp',
  );
});

const _themeModeKey = 'settings.theme_mode';

ThemeMode _decodeThemeMode(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

String _encodeThemeMode(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

/// The app's theme override — Light/Dark/System, persisted via
/// `shared_preferences`. `ThemeMode.system` (follow the device) is the
/// default for a pilot who has never opened Settings.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => _decodeThemeMode(
    ref.watch(sharedPreferencesProvider).getString(_themeModeKey),
  );

  void set(ThemeMode mode) {
    state = mode;
    ref
        .read(sharedPreferencesProvider)
        .setString(_themeModeKey, _encodeThemeMode(mode));
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Whether the Settings clock-sample row shows the device's local time
/// alongside Zulu, or Zulu only. Doesn't yet drive any rendering outside
/// Settings itself — no other screen in the app currently displays a flight
/// time in anything but UTC (CLAUDE.md rule 3), so there is nowhere else for
/// this preference to apply yet.
enum TimeDisplayPreference { localWithUtc, utcOnly }

const _timeDisplayKey = 'settings.time_display';

TimeDisplayPreference _decodeTimeDisplay(String? value) => value == 'utcOnly'
    ? TimeDisplayPreference.utcOnly
    : TimeDisplayPreference.localWithUtc;

String _encodeTimeDisplay(TimeDisplayPreference preference) =>
    switch (preference) {
      TimeDisplayPreference.utcOnly => 'utcOnly',
      TimeDisplayPreference.localWithUtc => 'localWithUtc',
    };

class TimeDisplayNotifier extends Notifier<TimeDisplayPreference> {
  @override
  TimeDisplayPreference build() => _decodeTimeDisplay(
    ref.watch(sharedPreferencesProvider).getString(_timeDisplayKey),
  );

  void set(TimeDisplayPreference preference) {
    state = preference;
    ref
        .read(sharedPreferencesProvider)
        .setString(_timeDisplayKey, _encodeTimeDisplay(preference));
  }
}

final timeDisplayProvider =
    NotifierProvider<TimeDisplayNotifier, TimeDisplayPreference>(
      TimeDisplayNotifier.new,
    );
