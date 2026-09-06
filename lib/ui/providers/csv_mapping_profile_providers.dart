import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/csv_mapping_profile_repository.dart';
import 'repository_providers.dart';

/// Every saved generic-CSV mapping (#72) — a one-shot fetch, not a stream:
/// the only writer is the mapping screen's own "save for reuse" action,
/// which invalidates this afterward rather than needing a live query for
/// something nothing else writes to concurrently (the same reasoning
/// `flightHistoryProvider` documents).
final savedCsvMappingProfilesProvider =
    FutureProvider<List<CsvMappingProfileRecord>>((ref) {
      return ref.watch(csvMappingProfileRepositoryProvider).listAll();
    });
