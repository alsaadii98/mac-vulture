# CLAUDE.md — Mac Vulture

Guidance for AI agents (Claude Code, etc.) working in this repo.

## What this project is

`Mac Vulture` is an open-source macOS cleaner inspired by [tw93/mole](https://github.com/tw93/mole). Native SwiftUI app. Min macOS 13. Distributed as a Homebrew cask. Logic ported natively to Swift — **do not** shell out to mole or rebuild it as a wrapper.

The behavior catalog (every path Mole touches) is in [Functionality_Paths.md](Functionality_Paths.md) and the machine-readable copy is `Resources/path_catalog.json`. Treat these as the spec.

Reference upstream code (read-only, for cross-checking edge cases): `/private/tmp/tw93-mole`.

## Non-negotiable safety rules

When touching scan/delete code, follow these without exception:

1. **Trash first.** All deletes go through `Core/Deleter` which calls `NSWorkspace.shared.recycle`. Permanent delete is opt-in per operation, never the default.
2. **Dry-run is default** for first-time users. Every destructive UI flow must show the full list of paths + sizes before any delete.
3. **Whitelist is sacred.** Read `~/.config/mac-vulture/whitelist` (one path per line, supports globs). Anything matched is excluded from results — not just from delete, from the *scan results*.
4. **Path validation.** Reject `..`, resolve symlinks before validating, reject paths outside the allow-listed roots in `path_catalog.json`. Block hardcoded list of system-critical paths (`/System`, keychains, login items, Time Machine).
5. **Running-app check.** Before deleting anything from a `.app`'s container/cache/leftovers, check `NSRunningApplication.runningApplications(withBundleIdentifier:)`. If running, refuse and surface a warning.
6. **Never scan `/`** or `$HOME` recursively without depth limits and the skip-list from `path_catalog.json`. Mole's `Analyze Folded Directories` list is the source.
7. **No sudo in v1.** v1 only touches user-owned paths. System paths (`/Library/...`, `/private/var/...`) are scoped to v1.1 with `SMAppService` privileged helper.
8. **Log every operation** to `~/Library/Logs/mac-vulture/operations.log` with timestamp, action, path, size, result.
9. **Don't hardcode paths in scanner code.** Read from `path_catalog.json`. One source of truth.

## Architecture quick map

```
App/        @main, AppState, MenuBarExtra
Features/   one folder per tab: Dashboard, Clean, Analyze, Uninstall, Status, Settings
Core/
  Scanner/         AsyncStream<ScanItem>, cooperative cancellation
  Deleter/         centralized safe delete, see rules above
  Paths/           PathCatalog loader (path_catalog.json)
  Sizing/          parallel directory size with (path, mtime) cache
  Metrics/         IOKit/sysctl metrics behind MetricsProvider protocol
  BundleResolver/  app ↔ bundle id ↔ leftover patterns
  Whitelist/       reads ~/.config/mac-vulture/whitelist
  Log/             ~/Library/Logs/mac-vulture/operations.log
Resources/path_catalog.json
Tests/
packaging/  Info.plist, entitlements, notarize.sh, Casks/mac-vulture.rb
```

## Concurrency conventions

- Scanners return `AsyncStream<ScanItem>` so the UI can render incrementally — don't block on full-scan completion before showing results.
- Each scan runs in a `Task`, cancellable from the UI. Always check `Task.isCancelled` in the inner loop.
- Parallelize independent categories with `TaskGroup`. Don't oversubscribe — disk I/O caps the win.
- All UI-bound state is `@MainActor`. Scanners run off-main and post via `MainActor.run` or `@Observable` views.

## Common commands

```bash
# Build + test
swift build
swift test

# Open in Xcode
xed .

# Convert icon (run once after icon changes)
./packaging/scripts/make-appicon.sh icon.svg App/Assets.xcassets/AppIcon.appiconset

# Local release dry-run (signs ad-hoc, no notarize)
./packaging/notarize.sh --dry-run

# Release (CI only — needs Developer ID secrets)
git tag v1.0.0 && git push --tags
```

## When adding a new clean category

1. Add entry to `Resources/path_catalog.json` with `id`, `title`, `scope`, `globs`, `risk`, `running_app_check`.
2. Cross-check the path list against `Functionality_Paths.md`. If missing, add to the .md too — they must stay in sync.
3. Add a fixture-based test in `Tests/ScannerTests` that builds a tmp tree and asserts only the expected files are returned.
4. UI category list reads from the catalog automatically — no UI code changes needed unless adding a new section.

## When adding a new metric to Status

- Implement against `MetricsProvider` protocol in `Core/Metrics`.
- Provide a stub in `Tests/MetricsTests` so UI tests don't depend on host hardware.
- Throttle: refresh only while the Status view is visible (`onAppear`/`onDisappear`).

## What NOT to do

- Don't add Electron, web views, or JavaScript runtimes. Native only.
- Don't bundle the upstream mole shell scripts.
- Don't enable App Sandbox in v1 — we need broad disk read access. Hardened Runtime is on.
- Don't use `system()` or `Process` to shell out for cleanup. Use Foundation + IOKit.
- Don't write to `/Library`, `/System`, or anything outside `$HOME` in v1.
- Don't auto-delete on launch, on schedule, or anywhere without explicit user click.
- Don't add telemetry/analytics. This is a privacy tool — keep it offline.

## License

MIT. Upstream attribution to `tw93/mole` lives in `README.md` and `LICENSE` notice.
