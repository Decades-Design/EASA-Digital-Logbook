import 'package:flutter/material.dart';

import '../widgets/large_title_scaffold.dart';

/// Placeholder for the Settings tab. Aircraft management (#61) and crew
/// records live here as sections rather than as their own tab — decided
/// 2026-08-10 to keep the phone nav to four destinations. Licence/profile
/// settings (the mockups' "Onboarding · licences" screen) belong here too.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LargeTitleScaffold(
      title: 'Settings',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateMessage(
            icon: Icons.settings_outlined,
            headline: 'Settings land next',
            caption:
                'Aircraft, crew, held licences and app preferences will live here.',
          ),
        ),
      ],
    );
  }
}
