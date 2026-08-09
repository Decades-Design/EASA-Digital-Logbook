---
name: Feature request
about: Suggest something the app should do
title: ""
labels: type:feat
---

## What and why

What the app should do, and the problem it solves — not just "add X," but why X matters for
logging or tracking currency.

## Milestone

Which milestone (see the repo's milestones) this most naturally belongs to, if you have a guess.
Not required — just helps triage.

## Non-goals check

`CLAUDE.md`'s "Deliberately out of scope" section lists things intentionally not being built yet
(background flight recording, cloud sync, an account system, analytics, instructor
countersignature *workflow*). If this request is adjacent to one of those, say which one and why
this is different — it may already be a deliberate exclusion rather than an oversight.

## Domain-rule check, if relevant

If this touches `lib/domain/` — a new field on `Flight`, a new derived quantity, a new
jurisdiction — skim CLAUDE.md's five non-negotiable domain rules first. A request that implies
storing a derived quantity, or a field that only covers one authority's discriminators, needs
reshaping before it can be built as described.
