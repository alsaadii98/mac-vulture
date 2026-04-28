# Mac Vulture

> Fast, native, open-source Mac cleaner. Reclaim disk, kill leftovers, watch your system breathe.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Swift](https://img.shields.io/badge/Swift-5.10-orange)

Mac Vulture is a SwiftUI-native cleanup app for macOS. It finds caches, logs, dev artifacts, browser junk, app leftovers, and lets you trash them with a click. No telemetry, no network, all local.

Inspired by [tw93/mole](https://github.com/tw93/mole) — same behavior catalog, native Swift implementation.

## Features (v1.0)

- **Clean** — Categorized scan of caches, logs, trash, browsers, dev tools, Xcode, app caches, Homebrew, orphaned apps. Dry-run by default.
- **Disk Analyzer** — Treemap of where your space is going. Drill in. Trash from the UI.
- **App Uninstaller** — Find apps + their leftovers (containers, prefs, logs, plugins). Trash-first removal.
- **System Status** — Live CPU / Memory / Disk / Network / Battery / Thermal / Top Processes.
- **Menu bar companion** — Free space, quick clean, one-click open.

## Install

```bash
brew tap alsaadii98/tap
brew install --cask mac-vulture
```

(Tap setup pending v1.0 release.)

Repo: https://github.com/alsaadii98/mac-vulture

## Build from source

Requires Xcode 15+ and macOS 13+.

```bash
git clone <repo>
cd mac-vulture
swift build
swift run mac-vulture
```

For a proper signed `.app` bundle, open in Xcode (`xed .`) once the Xcode project lands.

## Safety

- Trash-first — nothing is permanently deleted unless you explicitly opt in per operation.
- Dry-run by default for new users.
- Whitelist at `~/.config/mac-vulture/whitelist` (one path per line, globs supported).
- Operations log at `~/Library/Logs/mac-vulture/operations.log`.
- v1 only touches paths under `$HOME` — no sudo required.
- Path traversal blocked, system-critical paths blocked, running-app deletes blocked.

## Roadmap

| Version | Scope |
|---------|-------|
| v1.0 | Clean, Analyze, Uninstall, Status, Menu bar |
| v1.1 | Privileged helper (`SMAppService`) for system paths, project artifact purge, installer cleanup |
| v1.2 | Optimize tab (DNS flush, LaunchServices rebuild, font cache, etc.) |
| v1.3 | Touch ID for sudo, scheduled background scans |

## Contributing

PRs welcome. Read [CLAUDE.md](CLAUDE.md) for the safety rules — they apply to humans too.

## License

[MIT](LICENSE).
