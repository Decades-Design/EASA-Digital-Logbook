import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';

/// §1 of docs/entry-form.md: aircraft first, registration only — it
/// determines the shape of everything below. Real resolution (type, ICAO
/// designator, class, SP/MP, category, FAA complex/high-performance/
/// tailwheel flags) comes from the aircraft repository once #56/#61 wire
/// it up; for now this just captures the registration.
class AircraftSection extends StatelessWidget {
  const AircraftSection({
    super.key,
    required this.controller,
    required this.resolvedType,
  });

  final TextEditingController controller;

  /// Null until a registration is typed — stands in for real aircraft-record
  /// resolution. Once #56 lands this becomes a real lookup against
  /// [AircraftRepository] instead of a guess made here in the UI.
  final String? resolvedType;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    return EntrySection(
      label: 'Aircraft',
      child: EntryCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontWeight: FontWeight.w600,
                fontSize: 19,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                hintText: 'Registration, e.g. G-EZTK',
              ),
            ),
            if (resolvedType != null) ...[
              const SizedBox(height: 4),
              Text(
                resolvedType!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: ink.muted),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}
