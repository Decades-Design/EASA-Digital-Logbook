import 'package:flutter/material.dart';

import '../../entry_form_types.dart';
import '../duration_field.dart';
import '../entry_segmented_choice.dart';
import '../entry_toggle_row.dart';
import 'crew_form_data.dart';

/// §4B. Both arrangements share the same field set; only the arrangement
/// choice itself changes what gets derived (Dual vs SPIC under EASA — see
/// `flight_draft_mapper.dart`). The countersignature block itself lives in
/// the remarks section (§7), not here — docs/entry-form.md places it
/// alongside §4C's PICUS countersignature under one "always present, never
/// required to save" block, gated on `crew == instructor || picus`.
class CrewWithInstructor extends StatelessWidget {
  const CrewWithInstructor({super.key, required this.data});

  final CrewFormData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receiving =
        data.arrangement == InstructorArrangement.receivingInstruction;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What was the arrangement?', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          EntrySegmentedChoice<InstructorArrangement>(
            options: [
              (
                InstructorArrangement.receivingInstruction,
                InstructorArrangement.receivingInstruction.label,
              ),
              if (data.spicOffered)
                (
                  InstructorArrangement.inCommandObserving,
                  InstructorArrangement.inCommandObserving.label,
                ),
            ],
            selected: data.arrangement,
            onChanged: data.onArrangementChanged,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: data.instructorNameController,
            decoration: const InputDecoration(labelText: 'Instructor name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: data.instructorLicenceController,
            decoration: const InputDecoration(
              labelText: 'Instructor licence / certificate number',
            ),
          ),
          if (data.hasFaaLicence) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: data.onPickInstructorCertExpiry,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Certificate expiry',
                ),
                child: Text(
                  data.instructorCertExpiry != null
                      ? _formatDate(data.instructorCertExpiry!)
                      : '—',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: data.purpose,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Purpose of flight'),
            items: [
              for (final p in flightPurposes)
                DropdownMenuItem(
                  value: p,
                  child: Text(p, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: data.onPurposeChanged,
          ),
          if (flightPurposeNotes[data.purpose] != null) ...[
            const SizedBox(height: 6),
            Text(
              flightPurposeNotes[data.purpose]!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
          if (purposeHasExaminer(data.purpose)) ...[
            const SizedBox(height: 12),
            TextField(
              controller: data.examinerNoController,
              decoration: const InputDecoration(
                labelText: 'Examiner no.',
                hintText: 'e.g. UK.FE.1284',
              ),
            ),
            const SizedBox(height: 12),
            Text('Result', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            EntrySegmentedChoice<String>(
              options: const [
                ('Pass', 'Pass'),
                ('Partial', 'Partial'),
                ('Fail', 'Fail'),
              ],
              selected: data.result,
              onChanged: data.onResultChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: data.ratingAffectedController,
              decoration: const InputDecoration(
                labelText: 'Rating affected',
                hintText: 'e.g. SEP (land)',
              ),
            ),
          ],
          EntryToggleRow(
            label: 'I was sole manipulator',
            value: data.instructorSoleManipulator,
            onChanged: (_) => data.onToggleInstructorSoleManipulator(),
          ),
          if (!data.instructorSoleManipulator && receiving) ...[
            const SizedBox(height: 6),
            DurationField(
              label: 'My manipulation time',
              hoursController: data.instructorManipHoursController,
              minutesController: data.instructorManipMinutesController,
            ),
          ],
          EntryToggleRow(
            label: 'Passengers on board',
            value: data.instructorPassengers,
            onChanged: (_) => data.onToggleInstructorPassengers(),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
