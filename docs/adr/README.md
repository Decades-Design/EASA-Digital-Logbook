# Architecture decision records

| # | Title | Status | Summary |
|---|---|---|---|
| [0001](0001-raw-facts-only.md) | Store raw facts only, never a derived quantity | Accepted | A flight row stores raw facts; PIC/night/cross-country/etc. are computed per jurisdiction at read time, never stored as columns. |
| [0002](0002-utc-only.md) | All stored times are UTC | Accepted | Every persisted instant is UTC; local time is a display-only concern at the UI boundary. |
| [0003](0003-draft-until-exported.md) | Entries are mutable drafts until first exported, then immutable | Accepted | An entry is freely editable until first included in a PDF export, at which point it commits and every later change appends a retained revision. |
| [0004](0004-rules-as-data.md) | Currency rules are versioned data, not Dart logic | Accepted | Currency thresholds and windows live in versioned YAML evaluated by a generic engine, referencing named Dart primitives rather than embedding logic. |
| [0005](0005-offline-first.md) | Offline-first, no cloud backend by default | Accepted | The app is fully functional offline with no account system or analytics; sync, if ever added, is additive and never a dependency. |
| [0006](0006-dependency-stack.md) | Settle the dependency stack now, add packages per milestone | Accepted | The full package list is decided up front, but each dependency is only added to `pubspec.yaml` in the milestone that first imports it. |

New ADRs are numbered sequentially and are never renumbered. A decision that is later reversed
is superseded by a new ADR, not edited in place — the old record stays as evidence of what was
decided and why, with its status changed to `Superseded by ADR-NNNN`.
