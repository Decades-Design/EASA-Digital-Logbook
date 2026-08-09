## Summary

<!-- What changed and why. Link the issue(s) this closes. -->

## Checklist

- [ ] Tests added or updated for the change, and mutation-tested where the logic is non-trivial
      (a key branch was confirmed red before green, not just green)
- [ ] `dart format --set-exit-if-changed .`, `flutter analyze --fatal-infos`, and
      `flutter test` all pass locally
- [ ] `dart run tool/check_layering.dart` and `dart run tool/check_domain_types.dart` pass, if
      `lib/domain/` was touched
- [ ] A regulatory citation (`FCL.010`, `§61.51(e)(1)(i)`, `AMC1 FCL.050` column N, ...) is
      included in a code comment where a line of logic depends on it
- [ ] No derived quantity was added as a stored column or field — `lib/domain/model/Flight`
      stores raw facts only (CLAUDE.md rule 1); a new number is a projection, not a field
- [ ] Every jurisdiction-dependent number rendered in the UI is labelled with its jurisdiction
      (CLAUDE.md rule 5)
