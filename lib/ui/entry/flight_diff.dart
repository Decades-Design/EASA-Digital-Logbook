/// A human-readable diff between two versions of a [Flight] — #59's "shows
/// a diff of what will change before saving" requirement for editing a
/// committed entry. Compares every field the entry wizard can actually
/// change; fields it has no question for are identical between [before]
/// and [after] by construction (`preserveWizardBlindSpots`), so diffing all
/// of them rather than a curated subset can't produce a false entry.
library;

import '../../domain/model/countersignature.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_times.dart';

class FlightFieldChange {
  const FlightFieldChange(this.label, this.before, this.after);
  final String label;
  final String before;
  final String after;
}

List<FlightFieldChange> diffFlightsForDisplay(Flight before, Flight after) {
  final changes = <FlightFieldChange>[];

  void add(String label, String beforeValue, String afterValue) {
    if (beforeValue != afterValue) {
      changes.add(FlightFieldChange(label, beforeValue, afterValue));
    }
  }

  add('Route', before.route.join(' → '), after.route.join(' → '));
  add(
    'Off-blocks',
    _utc(before.offBlocks.toIso8601String()),
    _utc(after.offBlocks.toIso8601String()),
  );
  add(
    'On-blocks',
    _utc(before.onBlocks.toIso8601String()),
    _utc(after.onBlocks.toIso8601String()),
  );
  add(
    'Block time',
    before.blockTime.toHoursMinutes(),
    after.blockTime.toHoursMinutes(),
  );
  add(
    'Command authority',
    _yesNo(before.capacity.commandAuthority),
    _yesNo(after.capacity.commandAuthority),
  );
  add(
    'Sole manipulator',
    _yesNo(before.capacity.soleManipulator),
    _yesNo(after.capacity.soleManipulator),
  );
  add(
    'Sole occupant',
    _yesNo(before.capacity.soleOccupant),
    _yesNo(after.capacity.soleOccupant),
  );
  add(
    'Multi-pilot operation',
    _yesNo(before.capacity.multiPilotOperation),
    _yesNo(after.capacity.multiPilotOperation),
  );
  add(
    'PICUS claimed',
    _yesNo(before.capacity.picusClaimed),
    _yesNo(after.capacity.picusClaimed),
  );
  add(
    'Instructor aboard',
    before.capacity.instructor?.name ?? '—',
    after.capacity.instructor?.name ?? '—',
  );
  add(
    'Countersignature',
    _countersignature(before.capacity.countersignature),
    _countersignature(after.capacity.countersignature),
  );
  add('Other pilot', before.otherPilotName ?? '—', after.otherPilotName ?? '—');
  add(
    'Carrying passengers',
    _yesNo(before.carryingPassengers),
    _yesNo(after.carryingPassengers),
  );
  add(
    'Take-offs (day/night)',
    '${before.takeoffs.dayFullStop + before.takeoffs.dayTouchAndGo}/'
        '${before.takeoffs.nightFullStop + before.takeoffs.nightTouchAndGo}',
    '${after.takeoffs.dayFullStop + after.takeoffs.dayTouchAndGo}/'
        '${after.takeoffs.nightFullStop + after.takeoffs.nightTouchAndGo}',
  );
  add(
    'Landings (day/night)',
    '${before.landings.dayFullStop + before.landings.dayTouchAndGo}/'
        '${before.landings.nightFullStop + before.landings.nightTouchAndGo}',
    '${after.landings.dayFullStop + after.landings.dayTouchAndGo}/'
        '${after.landings.nightFullStop + after.landings.nightTouchAndGo}',
  );
  add(
    'IFR flight plan filed',
    _yesNo(before.ifrFlightPlanFiled),
    _yesNo(after.ifrFlightPlanFiled),
  );
  add(
    'Actual instrument',
    before.actualInstrumentTime.toHoursMinutes(),
    after.actualInstrumentTime.toHoursMinutes(),
  );
  add(
    'Simulated instrument',
    before.simulatedInstrumentTime.toHoursMinutes(),
    after.simulatedInstrumentTime.toHoursMinutes(),
  );
  add(
    'Holding procedures',
    '${before.holdingProceduresCount}',
    '${after.holdingProceduresCount}',
  );
  add(
    'Tracking performed',
    _yesNo(before.trackingPerformed),
    _yesNo(after.trackingPerformed),
  );
  add(
    'Remarks',
    before.remarks.isEmpty ? '—' : before.remarks,
    after.remarks.isEmpty ? '—' : after.remarks,
  );

  return changes;
}

String _yesNo(bool value) => value ? 'Yes' : 'No';

String _utc(String iso) {
  // "2026-03-01T09:00:00.000Z" -> "2026-03-01 09:00Z" -- readable, not raw.
  final datePart = iso.substring(0, 10);
  final timePart = iso.substring(11, 16);
  return '$datePart $timePart'
      'Z';
}

String _countersignature(Countersignature? c) => switch (c?.status) {
  null => '—',
  CountersignatureStatus.pending => 'Pending',
  CountersignatureStatus.signed => 'Signed',
  CountersignatureStatus.refused => 'Refused',
};
