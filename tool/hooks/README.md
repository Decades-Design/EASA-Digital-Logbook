# Pre-commit hook (opt-in)

Mirrors the fast checks `.github/workflows/ci.yaml` runs on every PR — formatting, analysis, and
the two domain guards (`check_layering.dart`, `check_domain_types.dart`). Deliberately skips
`flutter test`; that stays CI's job, so the hook stays fast enough to be tolerable.

Nothing breaks if you don't install this. CI runs the same checks either way — this only moves
the failure earlier, from push time to commit time.

## Install

```powershell
git config core.hooksPath tool/hooks
```

## Uninstall

```powershell
git config --unset core.hooksPath
```
