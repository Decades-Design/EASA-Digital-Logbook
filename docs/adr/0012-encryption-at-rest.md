# ADR-0012: No app-level encryption at rest, for now

**Status:** Accepted
**Date:** 2026-08-09

## Context

#38: the database holds GDPR personal data — names, credential numbers, dates, and a detailed
movement history (every aerodrome the pilot has flown to or from). This spike asks whether to
encrypt the SQLite file itself, timeboxed to one day.

**Package landscape has moved since ADR-0006 was written.** `sqlcipher_flutter_libs`, the
obvious candidate, does nothing as of 0.7.0 — drift dropped SQLCipher support at 2.32.0 (this
project is pinned to drift 2.34.0, past that point) in favour of SQLite3MultipleCiphers, a
different SQLite fork bundled through the newer Dart build-hooks system
(`hooks.user_defines.sqlite3.source: sqlite3mc` in `pubspec.yaml`), not a plain dependency
add. Key material is supplied via `PRAGMA key` in `NativeDatabase`'s `setup` callback, with a
runtime check for the `cipher` pragma recommended to confirm the encrypted build actually loaded.

**Threat model.** Android has mandated file-based encryption since Android 10; iOS encrypts the
app sandbox by default. Both already protect the case that matters most for a personal device
with no cloud backend and no account system (ADR-0006, CLAUDE.md "deliberately out of scope"):
the device is lost, stolen, or seized while powered off or locked. App-level encryption adds
protection mainly against a narrower set of cases OS encryption doesn't fully close — an
unencrypted local device backup, or a compromised OS reading files while the device is unlocked
— neither of which is this app's primary exposure today.

## Decision

Do not add app-level encryption at rest now. Rely on platform full-disk / file-based encryption.

The determining factor is not "is it needed in principle" — GDPR data always benefits from
defence in depth — but cost against this project's actual state: SQLite3MultipleCiphers needs the
Dart build-hooks system, which is materially newer and less proven than anything else in the
stack, stacked on an already fragile, exact-pinned `drift`/`drift_dev`/`freezed`/`analyzer` chain
(see the extensive version-conflict comments in `pubspec.yaml` and ADR-0006). Taking on that risk
now, before the schema has settled and before there is even a UI to exercise it end to end, is a
bad trade against a threat OS encryption already substantially covers.

**#37's backup file is unaffected as a store of the same information** — it is a `VACUUM INTO`
copy of the same unencrypted database (ADR-0011), so it carries the same exposure as the live
file and the same OS-level protection while at rest on the destination the user chooses.

## Alternatives considered

Implement SQLite3MultipleCiphers now. Rejected for the reasons above — see "Decision."

Encrypt only specific sensitive columns (names, credential numbers) rather than the whole
database. Rejected without deep investigation: it would leave route/movement history — arguably
the more sensitive GDPR data — unprotected, and adds bespoke crypto code to maintain for a
narrower guarantee than whole-file encryption already gives for free at the OS level.

## Consequences

No new dependency, no build-hooks adoption, no key-management or backup-rekey design needed now.

This decision is revisited, not permanent. The condition that would flip it: this app takes on a
threat model OS encryption doesn't cover — cloud sync (explicitly out of scope today, ADR-0006),
shared/managed devices, or a requirement to defend against a compromised-but-unlocked device. If
that happens, this ADR's package research (SQLite3MultipleCiphers via build hooks) is the starting
point, not a decision to redo from scratch.
