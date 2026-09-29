# ADR-0014: App identifier and display name

**Status:** Accepted
**Date:** 2026-09-29

## Context

`flutter create`'s scaffold defaults (`com.example.easa_digital_log` as the reverse-DNS
identifier, "A new Flutter project." as the description, no real display name) were still in
place across every platform. #1's own acceptance criteria flag why this can't wait: an Android
`applicationId` or iOS/macOS `PRODUCT_BUNDLE_IDENTIFIER` cannot be changed after a store
submission, so choosing it deliberately, once, before any release work starts, is the only option.

## Decision

**Reverse-DNS identifier: `com.decadesdesign.easalogbook`**, applied identically across Android
(`applicationId`/`namespace`, and the Kotlin source package/path), iOS and macOS
(`PRODUCT_BUNDLE_IDENTIFIER`, including `.RunnerTests` sub-identifiers for both platforms' test
targets), and Linux (`APPLICATION_ID`, GNOME's convention per
`https://wiki.gnome.org/HowDoI/ChooseApplicationID`). Windows has no equivalent reverse-DNS
identifier concept in its native packaging model, so it's out of scope for this field — its
scaffold-default binary/window naming is still replaced below.

**Display name: DigiLog.** Applied as the platform-visible app name everywhere the OS or window
manager shows one: Android's manifest `android:label`, iOS's `CFBundleDisplayName`/`CFBundleName`,
macOS's `PRODUCT_NAME` (which is also its window title per that file's own comment, and drives the
`.app` bundle's actual filename and internal executable name — every literal
`easa_digital_log.app`/`easa_digital_log` reference in the Xcode project and its shared scheme was
updated to match, not just the Xcode build setting, since those are stale otherwise once
`PRODUCT_NAME` changes), and Windows/Linux's window title and binary name (lowercased to
`digilog` for the executable itself, following each platform's own on-disk naming convention —
`easa_digital_log`'s prior lowercase-with-underscore is likewise replaced instead of introducing a
second casing convention).

`lib/main.dart`'s `MaterialApp(title: ...)` (the OS task-switcher label on platforms that show
one) was updated to match, for the same reason: one product, one name, wherever it surfaces.

Company-facing strings that had no real value (Windows' `CompanyName`/`LegalCopyright` resource
fields, macOS's `PRODUCT_COPYRIGHT`, both previously literal `com.example`) now read "Decades
Design", matching the GitHub organization that owns this repository.

**`pubspec.yaml`'s `description:`** field (the scaffold's "A new Flutter project.") now reads
"DigiLog — a multi-jurisdiction pilot logbook and currency tracker."

## Alternatives considered

Changing `pubspec.yaml`'s `name:` field (currently `easa_digital_log`) to match. Rejected: that's
the Dart package name, referenced as `package:easa_digital_log/...` in every import statement
across `lib/` and `test/` — a much larger, purely mechanical refactor with no bearing on any of
#1's acceptance criteria (which name Android's `applicationId`, iOS/macOS's
`PRODUCT_BUNDLE_IDENTIFIER`, and the Kotlin source path specifically — never the Dart package
name). Revisit only if the Dart package name itself becomes user-visible somewhere, which today it
isn't.

Renaming the in-app "Logbook" tab/section labels (`app_shell.dart`, `logbook_screen.dart`) to
match. Rejected: those name a *feature* within the app (the logbook, as distinct from Totals,
Currency, Settings), not the product — the same distinction a pilot's own paper logbook has from
whatever brand of binder holds it. Nothing in #1 asks for this, and conflating "the app" with "the
logbook tab" would read oddly at the point they eventually appear on screen together.

## Consequences

The Android `applicationId` and iOS/macOS `PRODUCT_BUNDLE_IDENTIFIER` are now real and load-bearing
— changing them again after any store submission is the exact irreversible mistake this ADR
exists to avoid making twice. Any future platform-keyed storage this app adopts (an Android
Keystore alias, an iOS/macOS Keychain access group, a GNOME/Linux settings schema keyed by
`APPLICATION_ID`) should be built against `com.decadesdesign.easalogbook` from the start.
