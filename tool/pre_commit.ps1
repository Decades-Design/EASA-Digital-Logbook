# Opt-in pre-commit check logic (#10). Mirrors the fast checks
# .github/workflows/ci.yaml runs on every PR -- format, analyze, and the two
# domain guards -- deliberately skipping `flutter test`, which stays CI's
# job: "fast enough to be tolerable" is the whole point of a local hook.
#
# Invoked through PowerShell on purpose, not run directly by git's hook
# shell: `flutter`/`dart` here are puro shims that only resolve under
# PowerShell (CLAUDE.md), so tool/hooks/pre-commit shells out to this file
# rather than calling them itself.

$ErrorActionPreference = "Stop"
$repoRoot = git rev-parse --show-toplevel
Set-Location $repoRoot

Write-Host "pre-commit: checking formatting..."
dart format --set-exit-if-changed .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "pre-commit: analyzing..."
flutter analyze --fatal-infos
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "pre-commit: checking domain layering..."
dart run tool/check_layering.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "pre-commit: checking domain types..."
dart run tool/check_domain_types.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "pre-commit: all checks passed."
exit 0
