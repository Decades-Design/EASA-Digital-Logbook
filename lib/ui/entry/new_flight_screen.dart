import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/jurisdiction/jurisdiction_profile.dart';
import '../../domain/jurisdiction/jurisdiction_registry.dart';
import '../../domain/model/aerodrome_directory.dart';
import '../../domain/model/aircraft.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/primitives/default_primitives.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import '../../domain/projection/projection_result.dart';
import 'entry_form_types.dart';
import 'flight_draft_mapper.dart';
import 'sample_fleet_data.dart';
import 'widgets/aircraft_section.dart';
import 'widgets/conditions_section.dart';
import 'widgets/counters_section.dart';
import 'widgets/crew/crew_form_data.dart';
import 'widgets/crew/crew_section.dart';
import 'widgets/crew/crew_selection.dart';
import 'widgets/date_route_section.dart';
import 'widgets/entry_footer.dart';
import 'widgets/entry_top_bar.dart';
import 'widgets/remarks_section.dart';
import 'widgets/times_section.dart';

/// #58/#129, direction 2a from the mockups (Flight Entry Form.dc.html): one
/// literal scroll, sections in the exact order docs/entry-form.md §1 lists
/// them, derivation strip pinned above the save controls. Every UI section
/// through §7 is built; §8 (overrides) and §9 (FSTD, a different form
/// entirely) are not — see the dartdoc on `flight_draft_mapper.dart` and
/// `conditions_section.dart` for exactly which pieces are stubbed and why.
class NewFlightScreen extends StatefulWidget {
  const NewFlightScreen({super.key});

  @override
  State<NewFlightScreen> createState() => _NewFlightScreenState();
}

class _NewFlightScreenState extends State<NewFlightScreen> {
  // ---- §1 Aircraft.
  final _registrationController = TextEditingController();
  final _fleetSearchController = TextEditingController();
  bool _fleetOpen = false;

  // ---- §1.2 Date & route.
  DateTime _date = DateTime.now();
  final List<TextEditingController> _legControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<FocusNode> _legFocusNodes = [FocusNode(), FocusNode()];

  // ---- §2 Times.
  TimeOfDay? _offBlocks;
  TimeOfDay? _onBlocks;
  TimeOfDay? _takeoff;
  TimeOfDay? _landing;
  String? _blockOverride;

  // ---- §4 Crew.
  CrewSelection? _crew;

  // 4A.
  bool _soloEndorsementHeld = true;
  final _endorsingInstructorController = TextEditingController();

  // 4B.
  InstructorArrangement _arrangement =
      InstructorArrangement.receivingInstruction;
  final _instructorNameController = TextEditingController();
  final _instructorLicenceController = TextEditingController();
  DateTime? _instructorCertExpiry;
  String? _purpose;
  final _examinerNoController = TextEditingController();
  String? _result;
  final _ratingAffectedController = TextEditingController();
  bool _instructorSoleManipulator = true;
  final _instructorManipHoursController = TextEditingController();
  final _instructorManipMinutesController = TextEditingController();
  bool _instructorPassengers = false;

  // 4C.
  CommandChoice _command = CommandChoice.me;
  FlyingChoice _flying = FlyingChoice.me;
  final _otherPilotNameController = TextEditingController();
  final _otherPilotLicenceController = TextEditingController();
  bool _multiPilotOperation = false;
  final _otherManipHoursController = TextEditingController();
  final _otherManipMinutesController = TextEditingController();
  OtherPilotRole? _otherPilotRole;
  bool _picusClaimed = false;
  bool _picInterventionNotRequired = false;
  bool _otherPilotPassengers = false;

  // Countersignature (§4B/§4C, shown from the remarks section).
  SignChoice _sign = SignChoice.defer;
  DateTime? _signedAt;

  // ---- §5 Take-offs and landings.
  int _takeoffsDay = 0;
  int _takeoffsNight = 0;
  int _landingsDay = 0;
  int _landingsNight = 0;
  int _fullStop = 0;

  // ---- §6 Conditions.
  final _nightHoursController = TextEditingController();
  final _nightMinutesController = TextEditingController();
  bool _ifrFlightPlanFiled = false;
  final _actualInstHoursController = TextEditingController();
  final _actualInstMinutesController = TextEditingController();
  final _simInstHoursController = TextEditingController();
  final _simInstMinutesController = TextEditingController();
  final List<Approach> _approaches = [];
  final List<TextEditingController> _approachIcaoControllers = [];
  final List<TextEditingController> _approachRunwayControllers = [];
  int _holdingProceduresCount = 0;
  bool _trackingPerformed = false;

  // ---- §7 Remarks.
  final _remarksController = TextEditingController();

  // ---- Held licences. Stubbed until a real pilot-profile/held-ratings
  // source is read by this screen — see #56/#61, and the equivalent notes
  // already on `aircraft_section.dart` and `crew_with_instructor.dart`
  // before this pass. Both true by default (docs' "EASA and FAA" default).
  final bool _hasEasaLicence = true;
  final bool _hasFaaLicence = true;
  final bool _isStudent = false;

  // ---- Jurisdiction projection, loaded once from assets/jurisdictions/.
  JurisdictionProjection? _easaProjection;
  JurisdictionProjection? _faaProjection;

  @override
  void initState() {
    super.initState();
    // Every text field below feeds either the draft `Flight` (the
    // derivation strip, `flight_draft_mapper.dart`) or a conditionally-
    // rendered field elsewhere on the screen (aircraft resolution, the
    // safety-pilot toggle gated on simulated instrument time, the remarks-
    // required note). All of those are read via getters at *build* time —
    // a `TextEditingController` changing does not, on its own, rebuild the
    // ancestor `State` that reads it, so every one of these needs a
    // listener that requests a rebuild. Leg and approach-field controllers
    // are the exception: their callers already `setState` explicitly
    // (`_addStop`/`_removeStop`, the `onApproach*Changed` callbacks), so
    // adding a listener there would only double the rebuild, not fix
    // anything.
    for (final c in [
      _registrationController,
      _fleetSearchController,
      _endorsingInstructorController,
      _instructorNameController,
      _instructorLicenceController,
      _examinerNoController,
      _ratingAffectedController,
      _instructorManipHoursController,
      _instructorManipMinutesController,
      _otherPilotNameController,
      _otherPilotLicenceController,
      _otherManipHoursController,
      _otherManipMinutesController,
      _nightHoursController,
      _nightMinutesController,
      _actualInstHoursController,
      _actualInstMinutesController,
      _simInstHoursController,
      _simInstMinutesController,
      _remarksController,
    ]) {
      c.addListener(_rebuild);
    }
    _loadJurisdictions();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadJurisdictions() async {
    // `cache: false` — `rootBundle` is a process-wide singleton whose
    // default cache keys a `Future<String>` by asset path. In a widget-test
    // run that opens this screen more than once, a `Future` first created
    // in one test's zone never resolves once that test tears down its
    // message channel, and every later test that asks for the same asset
    // gets hits that permanently-pending cached `Future` back instead of a
    // fresh load. Loading is cheap and happens once per screen open either
    // way, so skipping the cache costs nothing in the real app.
    final easaYaml = await rootBundle.loadString(
      'assets/jurisdictions/eu.easa.part-fcl.yaml',
      cache: false,
    );
    final faaYaml = await rootBundle.loadString(
      'assets/jurisdictions/us.faa.part61.yaml',
      cache: false,
    );
    final registry = JurisdictionRegistry([
      parseJurisdictionProfileYaml(easaYaml),
      parseJurisdictionProfileYaml(faaYaml),
    ]);
    // No aerodrome data source wired into this screen yet — night/cross-
    // country quantities will read back as "could not be resolved" rather
    // than a real figure, which is fine: the derivation strip only shows
    // pilot-function-time quantities (pic/dual/spic/... and
    // actingPic/loggedPic/...), none of which touch aerodromes.
    final aerodromes = AerodromeDirectory(const []);
    if (!mounted) return;
    setState(() {
      _easaProjection = JurisdictionProjection(
        registry: registry,
        primitives: defaultPrimitives,
        aerodromes: aerodromes,
        jurisdictionId: 'eu.easa.part-fcl',
      );
      _faaProjection = JurisdictionProjection(
        registry: registry,
        primitives: defaultPrimitives,
        aerodromes: aerodromes,
        jurisdictionId: 'us.faa.part61',
      );
    });
  }

  @override
  void dispose() {
    _registrationController.dispose();
    _fleetSearchController.dispose();
    for (final c in _legControllers) {
      c.dispose();
    }
    for (final f in _legFocusNodes) {
      f.dispose();
    }
    _endorsingInstructorController.dispose();
    _instructorNameController.dispose();
    _instructorLicenceController.dispose();
    _examinerNoController.dispose();
    _ratingAffectedController.dispose();
    _instructorManipHoursController.dispose();
    _instructorManipMinutesController.dispose();
    _otherPilotNameController.dispose();
    _otherPilotLicenceController.dispose();
    _otherManipHoursController.dispose();
    _otherManipMinutesController.dispose();
    _nightHoursController.dispose();
    _nightMinutesController.dispose();
    _actualInstHoursController.dispose();
    _actualInstMinutesController.dispose();
    _simInstHoursController.dispose();
    _simInstMinutesController.dispose();
    for (final c in _approachIcaoControllers) {
      c.dispose();
    }
    for (final c in _approachRunwayControllers) {
      c.dispose();
    }
    _remarksController.dispose();
    super.dispose();
  }

  // ---- Derived helpers.

  SampleFleetAircraft? get _resolvedAircraft =>
      findFleetAircraft(_registrationController.text);

  /// Used for the derivation strip when no registration has resolved yet.
  /// A generic single-pilot, non-multi-crew aeroplane — the common case,
  /// and safe because [DraftFlightInputs] only reads
  /// `Aircraft.requiresMultiCrew` (the 4B/4C multi-pilot pre-fill), which
  /// this deliberately leaves off rather than on. Requiring a resolved
  /// registration before showing *any* breakdown was too strict: crew and
  /// times alone are enough to project PIC/dual/SPIC for the "Just me" and
  /// "With passengers" paths, which never read the aircraft at all (see
  /// `flight_draft_mapper.dart`'s `_buildCapacity`).
  static const _fallbackAircraft = Aircraft(
    registration: '',
    manufacturer: '',
    model: '',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
  );

  Aircraft get _effectiveAircraft =>
      _resolvedAircraft?.aircraft ?? _fallbackAircraft;

  Duration? get _blockTime {
    final off = _offBlocks;
    final on = _onBlocks;
    if (off == null || on == null) return null;
    final offMinutes = off.hour * 60 + off.minute;
    var onMinutes = on.hour * 60 + on.minute;
    if (onMinutes < offMinutes) onMinutes += 24 * 60; // past midnight
    return Duration(minutes: onMinutes - offMinutes);
  }

  String get _blockTimeText {
    if (_blockOverride?.isNotEmpty == true) return _blockOverride!;
    final block = _blockTime;
    if (block == null) return '—:—';
    return '${block.inHours}:${block.inMinutes.remainder(60).abs().toString().padLeft(2, '0')}';
  }

  String get _startLabel => switch (_resolvedAircraft?.aircraft.category) {
    AircraftCategory.helicopter => 'Rotors start',
    AircraftCategory.airship => 'Released from mast',
    _ => 'Off blocks',
  };

  String get _endLabel => switch (_resolvedAircraft?.aircraft.category) {
    AircraftCategory.helicopter => 'Rotors stop',
    AircraftCategory.airship => 'Secured on mast',
    _ => 'On blocks',
  };

  List<String> get _route => [
    for (final c in _legControllers) c.text.trim().toUpperCase(),
  ].where((s) => s.isNotEmpty).toList();

  UtcInstant? _utcOf(TimeOfDay? t) {
    if (t == null) return null;
    return UtcInstant.utc(_date.year, _date.month, _date.day, t.hour, t.minute);
  }

  FlightDuration _durationOf(
    TextEditingController hours,
    TextEditingController minutes,
  ) {
    final h = int.tryParse(hours.text) ?? 0;
    final m = int.tryParse(minutes.text) ?? 0;
    return FlightDuration(h * 60 + m);
  }

  Flight? get _draftFlight {
    final off = _utcOf(_offBlocks);
    final on = _utcOf(_onBlocks);
    final crew = _crew;
    if (off == null || on == null || crew == null) {
      return null;
    }
    return buildDraftFlight(
      DraftFlightInputs(
        aircraft: _effectiveAircraft,
        route: _route,
        offBlocks: off,
        onBlocks: on,
        takeoff: _utcOf(_takeoff),
        landing: _utcOf(_landing),
        crew: crew,
        isStudent: _isStudent,
        soloEndorsementHeld: _soloEndorsementHeld,
        endorsingInstructorName: _endorsingInstructorController.text,
        arrangement: _arrangement,
        instructorName: _instructorNameController.text,
        instructorLicence: _instructorLicenceController.text,
        instructorCredentialExpiry: _instructorCertExpiry == null
            ? null
            : (
                _instructorCertExpiry!.year,
                _instructorCertExpiry!.month,
                _instructorCertExpiry!.day,
              ),
        purpose: _purpose,
        instructorSoleManipulator: _instructorSoleManipulator,
        instructorManipulationTime: _durationOf(
          _instructorManipHoursController,
          _instructorManipMinutesController,
        ),
        instructorPassengers: _instructorPassengers,
        command: _command,
        flying: _flying,
        otherPilotName: _otherPilotNameController.text,
        otherPilotLicence: _otherPilotLicenceController.text,
        multiPilotOperation: _multiPilotOperation,
        otherPilotRole: _otherPilotRole,
        picusClaimed: _picusClaimed,
        picInterventionNotRequired: _picInterventionNotRequired,
        otherManipulationTime: _durationOf(
          _otherManipHoursController,
          _otherManipMinutesController,
        ),
        otherPilotPassengers: _otherPilotPassengers,
        sign: _sign,
        signedAt: _signedAt == null
            ? null
            : UtcInstant.fromDateTime(_signedAt!.toUtc()),
        ifrFlightPlanFiled: _ifrFlightPlanFiled,
        actualInstrumentTime: _durationOf(
          _actualInstHoursController,
          _actualInstMinutesController,
        ),
        simulatedInstrumentTime: _durationOf(
          _simInstHoursController,
          _simInstMinutesController,
        ),
        approaches: List.of(_approaches),
        holdingProceduresCount: _holdingProceduresCount,
        trackingPerformed: _trackingPerformed,
        takeoffs: CircuitCounts(
          dayFullStop: _takeoffsDay,
          nightFullStop: _takeoffsNight,
        ),
        landings: CircuitCounts(
          dayFullStop: _landingsDay,
          nightFullStop: _landingsNight,
        ),
        remarks: _remarksController.text,
      ),
    );
  }

  ProjectionResult? get _easaResult {
    final flight = _draftFlight;
    if (flight == null || _easaProjection == null) return null;
    return _easaProjection!.project(flight, _effectiveAircraft);
  }

  ProjectionResult? get _faaResult {
    final flight = _draftFlight;
    if (flight == null || _faaProjection == null) return null;
    return _faaProjection!.project(flight, _effectiveAircraft);
  }

  bool get _simulatedInstrumentPresent =>
      _durationOf(
        _simInstHoursController,
        _simInstMinutesController,
      ).inMinutes >
      0;

  // ---- Callbacks.

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 10),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(
    ValueChanged<TimeOfDay> onPicked,
    TimeOfDay? initial, {
    required String helpText,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      helpText: helpText,
      // Entry is Zulu, not local (see times_section.dart's dartdoc) — a
      // 12-hour AM/PM picker would invite exactly the local/UTC confusion
      // this screen exists to avoid, and aviation time is conventionally
      // written 24-hour regardless.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  Future<void> _pickInstructorCertExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _instructorCertExpiry ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 20),
    );
    if (picked != null) setState(() => _instructorCertExpiry = picked);
  }

  void _addStop() {
    setState(() {
      final insertAt = _legControllers.length - 1;
      _legControllers.insert(insertAt, TextEditingController());
      _legFocusNodes.insert(insertAt, FocusNode());
    });
  }

  void _removeStop(int index) {
    setState(() {
      _legControllers.removeAt(index).dispose();
      _legFocusNodes.removeAt(index).dispose();
    });
  }

  void _pickAircraft(SampleFleetAircraft entry) {
    setState(() {
      _registrationController.text = entry.registration;
      _fleetOpen = false;
      _fleetSearchController.clear();
      // The multi-pilot toggle pre-fills from the aircraft record and stays
      // independently overridable — docs/entry-form.md §4C.
      _multiPilotOperation = entry.aircraft.requiresMultiCrew;
    });
  }

  void _addApproach() {
    setState(() {
      final prefillIcao = _route.isNotEmpty ? _route.last : '';
      _approaches.add(
        Approach(
          type: ApproachType.rnav,
          aerodromeIcao: prefillIcao,
          runway: '',
          count: 1,
        ),
      );
      _approachIcaoControllers.add(TextEditingController(text: prefillIcao));
      _approachRunwayControllers.add(TextEditingController());
    });
  }

  void _removeApproach(int index) {
    setState(() {
      _approaches.removeAt(index);
      _approachIcaoControllers.removeAt(index).dispose();
      _approachRunwayControllers.removeAt(index).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final crewData = CrewFormData(
      crew: _crew,
      onSelectCrew: (v) => setState(() => _crew = v),
      isStudent: _isStudent,
      soloEndorsementHeld: _soloEndorsementHeld,
      onToggleSoloEndorsement: () =>
          setState(() => _soloEndorsementHeld = !_soloEndorsementHeld),
      endorsingInstructorController: _endorsingInstructorController,
      arrangement: _arrangement,
      onArrangementChanged: (v) => setState(() => _arrangement = v),
      spicOffered: true,
      instructorNameController: _instructorNameController,
      instructorLicenceController: _instructorLicenceController,
      hasFaaLicence: _hasFaaLicence,
      instructorCertExpiry: _instructorCertExpiry,
      onPickInstructorCertExpiry: _pickInstructorCertExpiry,
      purpose: _purpose,
      onPurposeChanged: (v) => setState(() => _purpose = v),
      examinerNoController: _examinerNoController,
      result: _result,
      onResultChanged: (v) => setState(() => _result = v),
      ratingAffectedController: _ratingAffectedController,
      instructorSoleManipulator: _instructorSoleManipulator,
      onToggleInstructorSoleManipulator: () => setState(
        () => _instructorSoleManipulator = !_instructorSoleManipulator,
      ),
      instructorManipHoursController: _instructorManipHoursController,
      instructorManipMinutesController: _instructorManipMinutesController,
      instructorPassengers: _instructorPassengers,
      onToggleInstructorPassengers: () =>
          setState(() => _instructorPassengers = !_instructorPassengers),
      command: _command,
      onCommandChanged: (v) => setState(() => _command = v),
      flying: _flying,
      onFlyingChanged: (v) => setState(() => _flying = v),
      otherPilotNameController: _otherPilotNameController,
      otherPilotLicenceController: _otherPilotLicenceController,
      multiPilotOperation: _multiPilotOperation,
      aircraftRequiresMultiCrew:
          _resolvedAircraft?.aircraft.requiresMultiCrew ?? false,
      onToggleMultiPilot: () =>
          setState(() => _multiPilotOperation = !_multiPilotOperation),
      otherManipHoursController: _otherManipHoursController,
      otherManipMinutesController: _otherManipMinutesController,
      otherPilotRole: _otherPilotRole,
      onOtherPilotRoleChanged: (v) => setState(() => _otherPilotRole = v),
      picusClaimed: _picusClaimed,
      onTogglePicus: () => setState(() => _picusClaimed = !_picusClaimed),
      picInterventionNotRequired: _picInterventionNotRequired,
      onTogglePicInterventionNotRequired: () => setState(
        () => _picInterventionNotRequired = !_picInterventionNotRequired,
      ),
      simulatedInstrumentPresent: _simulatedInstrumentPresent,
      otherPilotPassengers: _otherPilotPassengers,
      onToggleOtherPilotPassengers: () =>
          setState(() => _otherPilotPassengers = !_otherPilotPassengers),
    );

    final showCountersignature =
        _crew == CrewSelection.withInstructor ||
        (_crew == CrewSelection.withOtherPilot && _picusClaimed);
    final signatoryName = _crew == CrewSelection.withInstructor
        ? _instructorNameController.text
        : _otherPilotNameController.text;
    final needsRemarks =
        _crew == CrewSelection.withInstructor &&
        (flightPurposeNotes[_purpose] != null);

    return Scaffold(
      body: Column(
        children: [
          EntryTopBar(title: 'New flight', onSaveDraft: () {}),
          Expanded(
            // `padding: zero` — a primary vertical `ListView` otherwise
            // insets itself by the ambient `MediaQuery.padding` (status bar
            // height) automatically, on top of what `EntryTopBar`'s own
            // `SafeArea` already consumed above it. The two together
            // produced the large blank gap between the top bar and
            // "Aircraft" reported after the first real-device run.
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                AircraftSection(
                  controller: _registrationController,
                  resolved: _resolvedAircraft,
                  fleetOpen: _fleetOpen,
                  onToggleFleet: () => setState(() {
                    _fleetOpen = !_fleetOpen;
                    if (!_fleetOpen) _fleetSearchController.clear();
                  }),
                  onFocusRegistration: () => setState(() => _fleetOpen = true),
                  onPickAircraft: _pickAircraft,
                  searchController: _fleetSearchController,
                ),
                DateRouteSection(
                  date: _date,
                  onTapDate: _pickDate,
                  legControllers: _legControllers,
                  legFocusNodes: _legFocusNodes,
                  onAddStop: _addStop,
                  onRemoveStop: _removeStop,
                ),
                TimesSection(
                  offBlocks: _offBlocks,
                  onBlocks: _onBlocks,
                  onTapOffBlocks: () => _pickTime(
                    (t) => _offBlocks = t,
                    _offBlocks,
                    helpText: '${_startLabel.toUpperCase()} (ZULU)',
                  ),
                  onTapOnBlocks: () => _pickTime(
                    (t) => _onBlocks = t,
                    _onBlocks,
                    helpText: '${_endLabel.toUpperCase()} (ZULU)',
                  ),
                  blockTime: _blockTime,
                  blockOverrideText: _blockOverride,
                  onBlockOverrideChanged: (v) =>
                      setState(() => _blockOverride = v),
                  startLabel: _startLabel,
                  endLabel: _endLabel,
                  takeoff: _takeoff,
                  landing: _landing,
                  onTapTakeoff: () => _pickTime(
                    (t) => _takeoff = t,
                    _takeoff,
                    helpText: 'TAKE-OFF (ZULU)',
                  ),
                  onTapLanding: () => _pickTime(
                    (t) => _landing = t,
                    _landing,
                    helpText: 'LANDING (ZULU)',
                  ),
                ),
                CrewSection(data: crewData),
                CountersSection(
                  takeoffsDay: _takeoffsDay,
                  takeoffsNight: _takeoffsNight,
                  landingsDay: _landingsDay,
                  landingsNight: _landingsNight,
                  onChangeTakeoffsDay: (v) => setState(() => _takeoffsDay = v),
                  onChangeTakeoffsNight: (v) =>
                      setState(() => _takeoffsNight = v),
                  onChangeLandingsDay: (v) => setState(() => _landingsDay = v),
                  onChangeLandingsNight: (v) =>
                      setState(() => _landingsNight = v),
                  showFullStop: _hasFaaLicence && _landingsNight > 0,
                  fullStop: _fullStop,
                  onChangeFullStop: (v) => setState(() => _fullStop = v),
                ),
                ConditionsSection(
                  blockTime: _blockTime,
                  nightHoursController: _nightHoursController,
                  nightMinutesController: _nightMinutesController,
                  hasEasaLicence: _hasEasaLicence,
                  ifrFlightPlanFiled: _ifrFlightPlanFiled,
                  onToggleIfrFlightPlanFiled: () => setState(
                    () => _ifrFlightPlanFiled = !_ifrFlightPlanFiled,
                  ),
                  hasFaaLicence: _hasFaaLicence,
                  actualInstHoursController: _actualInstHoursController,
                  actualInstMinutesController: _actualInstMinutesController,
                  simInstHoursController: _simInstHoursController,
                  simInstMinutesController: _simInstMinutesController,
                  approaches: _approaches,
                  approachIcaoControllers: _approachIcaoControllers,
                  approachRunwayControllers: _approachRunwayControllers,
                  onApproachTypeChanged: (i, t) => setState(
                    () => _approaches[i] = _approaches[i].copyWith(type: t),
                  ),
                  onApproachIcaoChanged: (i, v) => setState(
                    () => _approaches[i] = _approaches[i].copyWith(
                      aerodromeIcao: v,
                    ),
                  ),
                  onApproachRunwayChanged: (i, v) => setState(
                    () => _approaches[i] = _approaches[i].copyWith(runway: v),
                  ),
                  onApproachCountChanged: (i, c) => setState(
                    () => _approaches[i] = _approaches[i].copyWith(count: c),
                  ),
                  onApproachRemoved: _removeApproach,
                  onApproachAdded: _addApproach,
                  holdingProceduresCount: _holdingProceduresCount,
                  onHoldingProceduresChanged: (v) =>
                      setState(() => _holdingProceduresCount = v),
                  trackingPerformed: _trackingPerformed,
                  onToggleTracking: () =>
                      setState(() => _trackingPerformed = !_trackingPerformed),
                ),
                RemarksSection(
                  controller: _remarksController,
                  remarksRequiredNote: needsRemarks
                      ? flightPurposeNotes[_purpose]
                      : null,
                  showCountersignature: showCountersignature,
                  sign: _sign,
                  onSignChanged: (v) => setState(() {
                    _sign = v;
                    if (v == SignChoice.now) _signedAt = DateTime.now();
                  }),
                  signedAt: _signedAt,
                  signatoryName: signatoryName,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          EntryFooter(
            blockTimeText: _blockTimeText,
            easaResult: _easaResult,
            faaResult: _faaResult,
            hasFaaLicence: _hasFaaLicence,
            onSaveDraft: () {},
            onSave: () {},
          ),
        ],
      ),
    );
  }
}
