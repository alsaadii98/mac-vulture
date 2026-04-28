# Mac Vulture — v1.0 Plan

## Context

Greenfield macOS app. Project dir holds only `Functionality_Paths.md` (blueprint extracted from `tw93/mole`) and `icon.svg`. Goal: ship a fast, clean, open-source Mac cleaner — `Mac Vulture` — installable via `brew install --cask mac-vulture`. Reuses behavior catalog from upstream Mole but reimplements logic natively in Swift for speed and a polished UX. v1 covers: Clean, Disk Analyzer, App Uninstaller, System Status. Sudo-required system paths deferred to v1.1.

## Decisions (locked)

| Area | Choice |
|------|--------|
| UI | SwiftUI native, Swift 5.10+, Swift Concurrency |
| Engine | Native Swift port of Mole logic (FileManager, NSWorkspace, IOKit, sysctl) |
| Min macOS | 13.0 Ventura |
| Distribution | Homebrew cask, Developer ID signed + notarized |
| Window shape | Main window + menu bar companion |
| Privilege | $HOME + Trash only in v1. SMAppService helper in v1.1 |
| License | MIT |

## Repo Layout

```
mac-vulture/
├── MacVulture.xcodeproj            (or Package.swift if SPM-only)
├── App/
│   ├── MacVultureApp.swift         @main, WindowGroup + MenuBarExtra
│   ├── AppState.swift              ObservableObject root
│   └── Assets.xcassets/            AppIcon (from icon.svg) + accent colors
├── Features/
│   ├── Dashboard/                  reclaimable estimate, health, last scan
│   ├── Clean/                      categorized scan + preview + delete
│   ├── Analyze/                    disk explorer, treemap or list, drill-in
│   ├── Uninstall/                  app list, leftovers, trash-first
│   ├── Status/                     live CPU/mem/disk/net/battery cards
│   └── Settings/                   whitelist, dry-run default, logs
├── Core/
│   ├── Scanner/                    async scanners per category, AsyncSequence
│   ├── Deleter/                    centralized, path-validated, Trash-first
│   ├── Paths/                      typed PathCatalog from Functionality_Paths.md
│   ├── Sizing/                     fast directory size with caching, parallel
│   ├── Metrics/                    CPU, memory, disk I/O, battery via syscalls
│   ├── BundleResolver/             app name ↔ bundle id ↔ leftover patterns
│   ├── Whitelist/                  ~/.config/mac-vulture/whitelist
│   └── Log/                        ~/Library/Logs/mac-vulture/operations.log
├── Resources/
│   └── path_catalog.json           machine-readable from blueprint
├── Tests/
├── packaging/
│   ├── Info.plist
│   ├── entitlements.plist
│   ├── notarize.sh
│   └── Casks/mac-vulture.rb
├── .github/workflows/{ci,release}.yml
├── icon.svg
├── CLAUDE.md
├── plan.md (this file)
├── README.md
└── LICENSE (MIT)
```

## Architecture

### Concurrency
- `Scanner` returns `AsyncStream<ScanItem>` for incremental UI updates.
- Scans run in cancellable `Task`s; check `Task.isCancelled` in inner loops.
- `TaskGroup` parallelizes independent categories.
- Directory sizing: bounded-depth walker + skip-list (Analyze Folded Directories), cached on `(path, mtime)`.

### Deletion safety
Every delete passes `Core/Deleter`:
1. Resolve symlinks, reject `..`, reject paths outside allow-listed roots.
2. Block system-critical paths.
3. Honor `~/.config/mac-vulture/whitelist`.
4. `NSWorkspace.shared.recycle` (Trash) by default.
5. Append to `operations.log`.

Dry-run default for new users.

### Path catalog
`Resources/path_catalog.json` — single source of truth for scanners, UI categories, and tests. Schema:
```json
{"categories": [{"id":"user_caches","title":"User Caches","scope":"user","globs":["~/Library/Caches/*"],"risk":"low","running_app_check":false}]}
```

### App Uninstaller
- `BundleResolver` reads `Info.plist` for bundle id/version.
- Generates leftover candidates from blueprint patterns; existence + size scan in parallel.
- `NSRunningApplication` blocks unsafe deletes.
- Trash-first; user confirms with file list visible.

### Status dashboard
- 1Hz `Timer.publish`, only while view is visible.
- CPU: `host_processor_info`. Memory: `host_statistics64`. Disk I/O: `IOServiceGetMatchingServices` on `IOBlockStorageDriver`. Battery: `IOPSCopyPowerSourcesInfo`. Top procs: `proc_listpids`. Temp: SMC keys.
- Behind `MetricsProvider` protocol for testability.

### Menu bar companion
`MenuBarExtra`: free space, % reclaimable, "Quick Clean" (user caches + trash), "Open Mac Vulture". Light background scan every 6h on idle.

## v1 Feature Detail

**Dashboard** — Disk Free / Reclaimable / Health 0–100 / Last Scan; "Run Full Scan" CTA.

**Clean** — Left: category checkboxes (User Caches, Logs, Trash, Browsers, Dev Tools, Xcode, App Caches, Homebrew, Orphaned Apps). Right: results table (size, path, age, app). Bottom: "Move to Trash (X items, Y GB)" + dry-run toggle + whitelist context menu.

**Analyze** — Treemap; Overview = Mole's overview folders. Drill-in. Reveal in Finder, Move to Trash.

**Uninstall** — App grid (icon, name, version, install size, bundle id). Detail pane: leftovers + total reclaimable + running-status warning. Single-confirm trash flow.

**Status** — 2×4 grid: CPU, Memory, Disk Usage, Disk I/O, Network, Battery, Thermal, Top Processes.

**Settings** — Default delete mode, dry-run default, whitelist editor, view operations log, open data folder, check for updates.

## Testing

- Unit `Deleter`: traversal blocks, whitelist, symlink targets, system path blocks.
- Unit `BundleResolver`: real Calculator.app + synthetic tmp bundles.
- Integration: full Clean scan against tmp `$HOME` overlay (`HOME` env per test), verify allow-listed paths only.
- UI snapshot per tab.
- Manual smoke: real-machine dry-run before every release.

## Distribution

GitHub Actions `release.yml` on tag `v*`:
1. `xcodebuild archive`
2. Export with Developer ID (`BUILD_CERT`, `BUILD_CERT_PASSWORD`)
3. `xcrun notarytool submit --wait` (`APPLE_ID`, `APPLE_TEAM_ID`, `APP_PASSWORD`)
4. Staple, package as DMG (`create-dmg`)
5. SHA256 + attach DMG to release
6. PR to tap repo updating `Casks/mac-vulture.rb`

User: `brew tap <user>/tap && brew install --cask mac-vulture`.

## Reference files

- `Functionality_Paths.md` — source of truth.
- `/private/tmp/tw93-mole/lib/clean/*.sh` — clean edge cases.
- `/private/tmp/tw93-mole/cmd/analyze/scanner.go` — fold/skip rules.
- `/private/tmp/tw93-mole/cmd/status/metrics_*.go` — IOKit/sysctl reference.
- `icon.svg` — convert to AppIcon set.

## Milestones

1. **M0 — Scaffold** (1d): repo init, license, CLAUDE.md, plan.md, Xcode project, AppIcon, empty tab shell, CI.
2. **M1 — Catalog + Deleter + Scanner core** (2–3d).
3. **M2 — Clean tab UI** (2d).
4. **M3 — Analyze tab** (3d).
5. **M4 — Uninstall tab** (2–3d).
6. **M5 — Status tab** (2d).
7. **M6 — Menu bar + Dashboard polish** (1d).
8. **M7 — Sign + notarize + DMG + cask + release workflow** (1–2d).

## Verification

- `swift test` green on CI.
- Manual: clean Ventura/Sonoma/Sequoia VM; dry-run scan in each tab; no paths outside `$HOME`; whitelist blocks; Trash receives items.
- `brew install --cask <tap>/mac-vulture` on clean Mac → Gatekeeper passes.
- Perf budget: cold launch <500 ms, full Clean scan of typical $HOME <5 s, Status tab <2% CPU steady state.
