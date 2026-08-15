import 'package:flutter/material.dart';

import 'widgets/aircraft_section.dart';
import 'widgets/crew/crew_section.dart';
import 'widgets/date_route_section.dart';
import 'widgets/entry_footer.dart';
import 'widgets/entry_top_bar.dart';
import 'widgets/times_section.dart';

/// #58, direction 2a from the mockups: one literal scroll, sections in the
/// exact order docs/entry-form.md §1 lists them, derivation strip pinned
/// above the save controls. This pass covers §1 Aircraft, §1.2 Date &
/// route, §2 Times and §4 Crew — take-offs/landings (§5), conditions (§6)
/// and remarks (§7 onward) land in a later pass.
class NewFlightScreen extends StatefulWidget {
  const NewFlightScreen({super.key});

  @override
  State<NewFlightScreen> createState() => _NewFlightScreenState();
}

class _NewFlightScreenState extends State<NewFlightScreen> {
  final _registrationController = TextEditingController();
  DateTime _date = DateTime.now();
  final List<TextEditingController> _legControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  TimeOfDay? _offBlocks;
  TimeOfDay? _onBlocks;
  TimeOfDay? _takeoff;
  TimeOfDay? _landing;

  @override
  void dispose() {
    _registrationController.dispose();
    for (final c in _legControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Duration? get _blockTime {
    final off = _offBlocks;
    final on = _onBlocks;
    if (off == null || on == null) return null;
    final offMinutes = off.hour * 60 + off.minute;
    var onMinutes = on.hour * 60 + on.minute;
    if (onMinutes < offMinutes) onMinutes += 24 * 60; // past midnight
    return Duration(minutes: onMinutes - offMinutes);
  }

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
    TimeOfDay? initial,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => onPicked(picked));
  }

  void _addStop() {
    setState(() {
      _legControllers.insert(
        _legControllers.length - 1,
        TextEditingController(),
      );
    });
  }

  void _removeStop(int index) {
    setState(() {
      _legControllers.removeAt(index).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          EntryTopBar(title: 'New flight', onSaveDraft: () {}),
          Expanded(
            child: ListView(
              children: [
                AircraftSection(
                  controller: _registrationController,
                  resolvedType: null,
                ),
                DateRouteSection(
                  date: _date,
                  onTapDate: _pickDate,
                  legControllers: _legControllers,
                  onAddStop: _addStop,
                  onRemoveStop: _removeStop,
                ),
                TimesSection(
                  offBlocks: _offBlocks,
                  onBlocks: _onBlocks,
                  onTapOffBlocks: () =>
                      _pickTime((t) => _offBlocks = t, _offBlocks),
                  onTapOnBlocks: () =>
                      _pickTime((t) => _onBlocks = t, _onBlocks),
                  blockTime: _blockTime,
                  takeoff: _takeoff,
                  landing: _landing,
                  onTapTakeoff: () => _pickTime((t) => _takeoff = t, _takeoff),
                  onTapLanding: () => _pickTime((t) => _landing = t, _landing),
                ),
                const CrewSection(),
                // Landings, conditions and remarks land in the next pass —
                // see the class dartdoc.
                const SizedBox(height: 24),
              ],
            ),
          ),
          EntryFooter(blockTime: _blockTime, onSaveDraft: () {}, onSave: () {}),
        ],
      ),
    );
  }
}
