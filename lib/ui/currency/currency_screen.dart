import 'package:flutter/material.dart';

import '../widgets/large_title_scaffold.dart';

/// Placeholder for #62 (currency dashboard with explanations).
class CurrencyScreen extends StatelessWidget {
  const CurrencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LargeTitleScaffold(
      title: 'Currency',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateMessage(
            icon: Icons.verified_outlined,
            headline: 'Currency rules land next',
            caption:
                'Every held licence, grouped, with a reason for each pill.',
          ),
        ),
      ],
    );
  }
}
