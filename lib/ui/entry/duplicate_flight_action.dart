import 'package:flutter/material.dart';

import '../../domain/repository/flight_read_repository.dart';
import 'new_flight_screen.dart';

/// #65: "reachable in one or two taps from the flight detail and from the
/// list" — the single entry point both call. Opens straight into
/// [NewFlightScreen.duplicate] when reversing the route wouldn't produce
/// anything different — a single-aerodrome route, or a round trip already
/// shaped `[A, B, A]`, whose reverse is the identical sequence; offers a
/// same-route/return-leg choice only when reversing genuinely names a
/// different route (e.g. a one-way `[A, B]`).
Future<void> showDuplicateFlightMenu(
  BuildContext context,
  FlightRecord record,
) async {
  final route = record.flight.route;
  final reversedRoute = route.reversed.toList();
  final reversedDiffers = !_sameRoute(route, reversedRoute);
  if (!reversedDiffers) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NewFlightScreen.duplicate(record: record),
      ),
    );
    return;
  }

  final reversed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Duplicate'),
            subtitle: Text(record.flight.route.join(' → ')),
            onTap: () => Navigator.of(context).pop(false),
          ),
          ListTile(
            title: const Text('Duplicate return leg'),
            subtitle: Text(reversedRoute.join(' → ')),
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ),
  );
  if (reversed == null || !context.mounted) return;

  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NewFlightScreen.duplicate(
        record: record,
        reverseRouteOnDuplicate: reversed,
      ),
    ),
  );
}

bool _sameRoute(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
