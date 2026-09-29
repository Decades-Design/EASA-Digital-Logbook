import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_database_bootstrap.dart';
import 'data/crash_recovery_snapshot.dart';
import 'data/seed_sample_data.dart';
import 'ui/preferences/app_preferences.dart';
import 'ui/providers/database_provider.dart';
import 'ui/recovery/database_recovery_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const RootApp(),
    ),
  );
}

/// #90 AC5: owns the one decision that has to happen before the rest of the
/// app can exist at all — did the database open healthy? A plain
/// `runApp(App())` can't express "actually, show a recovery screen instead"
/// once it's already committed to a widget tree, so this stays a
/// `StatefulWidget` at the root and re-bootstraps in place after a restore,
/// rather than main() picking one branch once and being stuck with it.
class RootApp extends StatefulWidget {
  const RootApp({super.key});

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  DatabaseBootstrapResult? _result;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final result = await bootstrapRealAppDatabase();
    if (result is DatabaseBootstrapReady) {
      // First-run only — see seed_sample_data.dart's own dartdoc for why.
      await seedSampleDataIfEmpty(result.db);
      await takeCrashRecoverySnapshot(result.db, result.appSupportDirectory);
    }
    if (mounted) {
      setState(() => _result = result);
    }
  }

  /// Passed to `DatabaseRecoveryScreen` as `onRestored` — re-runs bootstrap
  /// against whatever file restoration just put in place. A database that's
  /// healthy this time swaps this screen for the real app; one that isn't
  /// (a bad backup file) keeps the pilot on the recovery screen with the
  /// new failure reason, rather than looping silently.
  Future<void> _retryAfterRestore() => _bootstrap();

  @override
  Widget build(BuildContext context) {
    final result = _result;

    if (result == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (result is DatabaseBootstrapCorrupt) {
      return MaterialApp(
        title: 'Logbook',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: DatabaseRecoveryScreen(
          dbFile: result.dbFile,
          appSupportDirectory: result.appSupportDirectory,
          detail: result.detail,
          onRestored: _retryAfterRestore,
        ),
      );
    }

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(
          (result as DatabaseBootstrapReady).db,
        ),
      ],
      child: const MainApp(),
    );
  }
}

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Logbook',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: const AppShell(),
    );
  }
}
