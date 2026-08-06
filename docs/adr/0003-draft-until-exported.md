# ADR-0003: Entries are mutable drafts until first exported, then immutable

**Status:** Accepted
**Date:** 2026-08-06

## Context

EASA's May 2023 guidelines on electronic documents, records and signatures reference eIDAS (EU
910/2014) and expect audit trails, user authentication and correction tracking for electronic
logbook records (`docs/jurisdiction-matrix.md` §8). That guidance is a working summary here, not
a verified citation, and should be confirmed against the current instrument before it becomes
load-bearing — but the underlying expectation, that a *record* carries provenance and cannot be
silently rewritten, is not in doubt and is the reason this project treats data integrity as a
hard requirement in the first place.

The question this ADR answers is not whether that expectation applies, but *when it starts
applying*. A logbook entry being typed is not yet a record of anything. `docs/entry-form.md` §3
requires that a flight can always be saved incomplete, that validation runs on blur and never
blocks the save button, and that drafts are excluded from all totals, currency evaluation and
exports. §8 of the same document requires that any derived value be overridable, that overrides
be recorded with a reason and land in revision history, and that the pilot — not the app — is
the legally responsible record-keeper. Both of those requirements presuppose a state before an
entry is asserted as fact: a pilot who is three fields into logging a flight, unsure yet whether
the last landing was full-stop or touch-and-go, has not yet made a legal claim about that
flight. Treating every keystroke as a revision-worthy event conflates the *drafting* of a record
with the record itself.

At the same time, once a flight has been printed, signed and included in an export handed to a
competent authority, the pilot has asserted it as fact. From that point the paper-logbook analogy
is instructive: a crossed-out ink entry in a physical logbook remains legible underneath the
correction. The tradition this app is digitising already expects a visible trail from the moment
an entry is asserted, not from the moment it is first typed.

## Decision

An entry is freely mutable in place until it is first included in a generated PDF export; at
that point it is committed, and every subsequent change appends a delta revision retaining the
prior state. Committed entries are never `UPDATE`d or `DELETE`d in place. Revision history is
device-local and backup-scoped, and is not part of any future sync payload — sync, if it is ever
added, is an additive layer per ADR-0005, and revision history recording who corrected what
locally is not data that should leave the device as part of a routine sync operation.

This is CLAUDE.md rule 4, and it is a deliberate rewrite of an earlier, stricter statement of the
same rule that made every entry append-only unconditionally from creation.

## Alternatives considered

Unconditional append-only from first keystroke. Rejected for two reasons. First, it produces a
revision per typo — a pilot correcting a mistyped registration or an autocomplete misfire while
still drafting the entry generates the same kind of history entry as a genuine post-export
correction, making the audit trail noise rather than evidence: the record shows a hundred
edits and the one that matters is indistinguishable from the ninety-nine that don't. Second, and
more fundamentally, export is the moment the record is asserted to an authority; before that
there is nothing to be reliable *about*. An audit trail's purpose is to show that a record was
not tampered with after the fact — it has nothing to protect against tampering with a draft
that was never a record to begin with.

## Consequences

The schema needs a draft/committed state machine, tracked for M2. Export becomes a state
transition with side effects — it commits every draft entry included in the export — rather than
a pure read of already-final data, which the `export/` layer must account for. The
paper-logbook analogy argues *for* retaining history rather than against it: once an entry is
committed, correcting it must behave like crossing out and re-entering in ink, not like erasing,
which is exactly what rule 4's delta-revision behaviour after commit implements.
