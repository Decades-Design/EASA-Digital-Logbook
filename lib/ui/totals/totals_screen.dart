import 'package:flutter/material.dart';

import '../widgets/large_title_scaffold.dart';

/// Placeholder for #85 (totals and summary view, M7).
class TotalsScreen extends StatelessWidget {
  const TotalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LargeTitleScaffold(
      title: 'Totals',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateMessage(
            icon: Icons.query_stats_outlined,
            headline: 'Totals land in a later milestone',
            caption:
                'Reserved here so the shell\'s navigation is complete now.',
          ),
        ),
      ],
    );
  }
}
