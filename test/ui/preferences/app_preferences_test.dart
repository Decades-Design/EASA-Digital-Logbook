import 'package:easa_digital_log/ui/preferences/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('themeModeProvider', () {
    test('defaults to system when nothing has been saved', () async {
      final container = await _container();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    test('reads back a previously saved value', () async {
      final container = await _container(
        initial: {'settings.theme_mode': 'dark'},
      );
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test(
      'set() updates state and persists through SharedPreferences',
      () async {
        final container = await _container();

        container.read(themeModeProvider.notifier).set(ThemeMode.light);

        expect(container.read(themeModeProvider), ThemeMode.light);
        final prefs = container.read(sharedPreferencesProvider);
        expect(prefs.getString('settings.theme_mode'), 'light');
      },
    );
  });

  group('timeDisplayProvider', () {
    test('defaults to localWithUtc when nothing has been saved', () async {
      final container = await _container();
      expect(
        container.read(timeDisplayProvider),
        TimeDisplayPreference.localWithUtc,
      );
    });

    test('reads back a previously saved value', () async {
      final container = await _container(
        initial: {'settings.time_display': 'utcOnly'},
      );
      expect(
        container.read(timeDisplayProvider),
        TimeDisplayPreference.utcOnly,
      );
    });

    test(
      'set() updates state and persists through SharedPreferences',
      () async {
        final container = await _container();

        container
            .read(timeDisplayProvider.notifier)
            .set(TimeDisplayPreference.utcOnly);

        expect(
          container.read(timeDisplayProvider),
          TimeDisplayPreference.utcOnly,
        );
        final prefs = container.read(sharedPreferencesProvider);
        expect(prefs.getString('settings.time_display'), 'utcOnly');
      },
    );
  });
}
