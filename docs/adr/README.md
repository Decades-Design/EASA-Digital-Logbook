# Architecture decision records

| # | Title | Status | Summary |
|---|---|---|---|
| [0001](0001-raw-facts-only.md) | Store raw facts only, never a derived quantity | Accepted | A flight row stores raw facts; PIC/night/cross-country/etc. are computed per jurisdiction at read time, never stored as columns. |
| [0002](0002-utc-only.md) | All stored times are UTC | Accepted | Every persisted instant is UTC; local time is a display-only concern at the UI boundary. |
| [0003](0003-draft-until-exported.md) | Entries are mutable drafts until first exported, then immutable | Accepted | An entry is freely editable until first included in a PDF export, at which point it commits and every later change appends a retained revision. |
| [0004](0004-rules-as-data.md) | Currency rules are versioned data, not Dart logic | Accepted | Currency thresholds and windows live in versioned YAML evaluated by a generic engine, referencing named Dart primitives rather than embedding logic. |
| [0005](0005-offline-first.md) | Offline-first, no cloud backend by default | Accepted | The app is fully functional offline with no account system or analytics; sync, if ever added, is additive and never a dependency. |
| [0006](0006-dependency-stack.md) | Settle the dependency stack now, add packages per milestone | Accepted | The full package list is decided up front, but each dependency is only added to `pubspec.yaml` in the milestone that first imports it. |
| [0007](0007-duration-representation.md) | Represent logbook durations as integer minutes | Accepted | `FlightDuration` stores whole minutes for exact arithmetic; `HH:MM` and decimal hours (tenths, half away from zero) are display-only formats, and rounding never happens before a total is summed. |
| [0008](0008-night-time-position-interpolation.md) | Approximate in-flight position as a straight great-circle line between two waypoints | Accepted | Night-time primitives interpolate position linearly, by elapsed time, along the great circle between the first and last resolvable route waypoints — not every intermediate stop, since `Flight` records no per-waypoint timestamp to split time against. |
| [0009](0009-date-boundary-policy.md) | A flight's logbook date is the UTC calendar date of departure | Accepted | `Flight.logbookDate` is the UTC calendar date of `offBlocks`, never of `onBlocks` and never a local date — the one place list ordering, PDF pagination and currency windows must read it from. |
| [0010](0010-migration-safety.md) | Two-layer migration safety, backup scoped to migration only | Accepted | A schema migration is protected by SQL transactional rollback and a separate file-level backup; the backup is internal-only, not a first cut of #37's backup/restore feature. |

New ADRs are numbered sequentially and are never renumbered. A decision that is later reversed
is superseded by a new ADR, not edited in place — the old record stays as evidence of what was
decided and why, with its status changed to `Superseded by ADR-NNNN`.
