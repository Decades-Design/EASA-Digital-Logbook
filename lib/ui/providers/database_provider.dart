import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';

/// Provider conventions (#56) live here, next to the first provider that
/// needed one:
///
/// - A provider that opens a real resource (the on-device database, an
///   asset-backed registry/directory) lives in `lib/ui/providers/`, one file
///   per resource, exposed as a plain `Provider`/`FutureProvider`.
/// - A provider composes domain and data; it never contains business logic
///   itself. Read/derive with domain functions from inside a screen via
///   `ref.watch`, not from inside the provider body.
/// - Something that can't be constructed synchronously from other providers
///   alone (this one — opening the database needs a platform path lookup
///   first) has no default implementation: it throws until `main()`
///   overrides it with the already-constructed value via
///   `overrideWithValue`, the same pattern `sharedPreferencesProvider`
///   already used before this file existed. A missing override in a test is
///   then a loud, immediate failure rather than a silently-null repository.
///
/// **Why hand-written, not `riverpod_generator`/`@riverpod`**: tried and
/// reverted. No released `riverpod_generator` resolves against this
/// project's analyzer pin -- `freezed` 3.2.5 and `json_serializable`
/// ^6.14.1 hold `analyzer` at 10.2.0 (see pubspec.yaml's own comments on
/// that chain), and every `riverpod_generator` release wants either
/// `analyzer <10` or `>=12`. Revisit once a stable freezed 4 lets the whole
/// stack move to `analyzer >=12` together.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider has no default — main() must override it with the '
    'already-opened AppDatabase (see openRealAppDatabase in '
    'lib/data/app_database_bootstrap.dart), and a test must override it '
    'with an in-memory one.',
  );
});
