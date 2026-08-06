# ADR-0005: Offline-first, no cloud backend by default

**Status:** Accepted
**Date:** 2026-08-06

## Context

The data this app holds is a pilot's licensing record: personal data under GDPR, and — per the
project's stated purpose — the pilot's legal evidence of flight time. A record that a pilot may
need to produce to a competent authority years after it was created should not depend on the
continued existence of a third-party service.

## Decision

The app is fully functional with no network connection. There is no cloud backend, no account
system and no analytics. Sync, if it is ever added, is an additive layer on top of the
offline-first design and never a dependency of it.

## Alternatives considered

Cloud-first with an offline cache. Rejected on two grounds. First, it makes a legal record
dependent on a service that can be discontinued, changed, or made unavailable, which is the
opposite of what a compliance record needs. Second, it turns what is otherwise a personal file
under the pilot's sole control into a controller/processor relationship under GDPR, which is a
scope and liability decision this project is deliberately not taking on.

## Consequences

Backup and restore of the local database is the user's own responsibility and must be
first-class, not an afterthought — tracked for M2. With no telemetry, bug reports cannot be
diagnosed from server-side logs; the raw facts of the problem must be carried in the report
itself, which issue #9's bug template needs to account for.
