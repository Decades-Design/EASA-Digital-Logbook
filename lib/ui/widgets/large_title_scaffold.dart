import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A screen with an iOS-style large title that shrinks into the app bar on
/// scroll, plus optional trailing actions. Every top-level tab screen in the
/// shell (#55) is built on this so the "large title, calm paper" feel is
/// consistent without every screen re-deriving it.
class LargeTitleScaffold extends StatelessWidget {
  const LargeTitleScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            // Material 3's SliverAppBar.large reserves 152dp so the title
            // can bottom-align and shrink into the pinned bar on scroll.
            // The mockups follow iOS's tighter large-title spacing instead
            // — title sits right under the status bar, not a third of the
            // way down the screen — so this trims the expanded height to
            // match while keeping the same collapse-on-scroll behaviour.
            expandedHeight: 96,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 14,
              ),
              title: Text(title, style: theme.textTheme.displaySmall),
              centerTitle: false,
            ),
            actions: actions,
          ),
          ...slivers,
        ],
      ),
    );
  }
}

/// A centered "nothing here yet" state, used by placeholder screens and by
/// genuinely-empty real screens (e.g. a logbook with no flights) alike.
class EmptyStateMessage extends StatelessWidget {
  const EmptyStateMessage({
    super.key,
    required this.icon,
    required this.headline,
    required this.caption,
  });

  final IconData icon;
  final String headline;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 64),
      child: Column(
        children: [
          Icon(icon, size: 40, color: ink.faint),
          const SizedBox(height: 16),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
          ),
        ],
      ),
    );
  }
}
