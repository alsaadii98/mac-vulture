# Mole Repo Functionality And Searched Paths

Source reviewed: `https://github.com/tw93/mole` cloned locally at `/private/tmp/tw93-mole`.

This file extracts the behavior of the upstream Mole CLI so it can be used as a blueprint for a macOS app.

## High-Level Product Shape

Mole is a macOS maintenance toolkit. The main executable is `mole`, with `mo` as a lightweight alias. It exposes an interactive terminal menu plus direct commands:

- `mo clean`: deep cleanup of caches, logs, temp files, browser data, app caches, orphaned app leftovers, and developer caches.
- `mo uninstall`: remove installed apps and their related user/system leftovers.
- `mo optimize`: run maintenance tasks such as DNS flush, LaunchServices rebuild, QuickLook/icon cache refresh, database optimization, and broken config cleanup.
- `mo analyze`: Go-based disk usage explorer with TUI and JSON output.
- `mo status`: Go-based live system health dashboard with JSON output.
- `mo purge`: find and remove project build artifacts.
- `mo installer`: find and remove installer files.
- `mo touchid`: configure Touch ID for sudo.
- `mo completion`: install shell completion.
- `mo update` / `mo remove`: self-update and self-uninstall.

## Entry Points

- `mole`: main CLI, command dispatch, interactive menu, version, update, remove.
- `mo`: alias that executes `mole`.
- `bin/clean.sh`: cleanup command.
- `bin/uninstall.sh`: app uninstaller command.
- `bin/optimize.sh`: optimization command.
- `bin/analyze.sh`: builds/runs `cmd/analyze`.
- `bin/status.sh`: builds/runs `cmd/status`.
- `bin/purge.sh`: project artifact purge command.
- `bin/installer.sh`: installer-file cleanup command.
- `bin/touchid.sh`: Touch ID sudo helper.
- `bin/completion.sh`: shell completion installer.

## Safety Model Worth Copying

- Dry-run support for destructive commands.
- Whitelist/protected paths in `~/.config/mole/whitelist`.
- Project purge path config in `~/.config/mole/purge_paths`.
- Operation logs at `~/Library/Logs/mole/operations.log`.
- Conservative system path blocks, path traversal rejection, symlink handling, and deletion validation.
- Trash-first behavior for uninstall by default; permanent deletion is opt-in.
- Sudo only when needed, with keepalive for long operations.
- Running-app checks before cleaning risky app-specific data.
- Special protection for passwords, keychains, credentials, containers, and Apple/system areas.

## Clean Command

Implementation files:

- `bin/clean.sh`
- `lib/clean/user.sh`
- `lib/clean/system.sh`
- `lib/clean/dev.sh`
- `lib/clean/apps.sh`
- `lib/clean/app_caches.sh`
- `lib/clean/caches.sh`
- `lib/clean/brew.sh`
- `lib/clean/hints.sh`
- `lib/core/app_protection.sh`

Main functions:

- Clean user caches/logs/trash/recent items/mail downloads.
- Clean system caches/logs/temp files/crash reports/diagnostics/power logs.
- Clean browser caches and Service Worker caches, while protecting known offline/PWA domains.
- Clean app-specific caches for many popular apps.
- Clean developer ecosystem caches.
- Detect orphaned app data after apps have already been deleted.
- Clean Homebrew cache and orphaned dependencies.
- Suggest project artifact purge when heavy artifacts are detected.

### Clean: Core User Paths

- `~/Library/Caches/*`
- `~/Library/Logs/*`
- `~/.Trash`
- `~/Library/Application Support/com.apple.sharedfilelist/*.sfl*`
- `~/Library/Preferences/com.apple.recentitems.plist`
- `~/Downloads/*.download`
- `~/Downloads/*.crdownload`
- `~/Downloads/*.part`
- `~/Library/Mail Downloads`
- `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`

### Clean: System Paths

- `/Library/Caches`
- `/private/tmp`
- `/private/var/tmp`
- `/Library/Logs/DiagnosticReports`
- `/private/var/log`
- `/Library/Logs/Adobe`
- `/Library/Logs/CreativeCloud`
- `/Library/Logs/adobegc.log`
- `/Library/Updates`
- `/macOS Install Data`
- `/Applications/Install macOS*.app`
- `/private/var/folders/**/X/**/*.code_sign_clone`
- `/private/var/db/diagnostics`
- `/private/var/db/DiagnosticPipeline`
- `/private/var/db/powerlog`
- `/private/var/db/reportmemoryexception/MemoryLimitViolations`
- `/Volumes/*/Backups.backupdb`
- `/Volumes/*/.MobileBackups`

### Clean: Browser And Web Cache Paths

The repo includes browser-specific cache logic in `lib/clean/caches.sh`, plus Service Worker protection for offline web apps.

Protected Service Worker domains include:

- `capcut.com`, `photopea.com`, `pixlr.com`
- `docs.google.com`, `sheets.google.com`, `slides.google.com`, `drive.google.com`, `mail.google.com`
- `github.com`, `gitlab.com`, `codepen.io`, `codesandbox.io`, `replit.com`, `stackblitz.com`
- `notion.so`, `figma.com`, `linear.app`, `excalidraw.com`

### Clean: Developer Cache Paths

- npm: `~/.npm`, `_cacache`, `_npx`, `_logs`, `_prebuilds`
- pnpm: `~/Library/pnpm/store`
- bun: `~/.bun/install/cache`
- tnpm: `~/.tnpm/_cacache`, `~/.tnpm/_logs`
- yarn: `~/.yarn/cache`, `~/Library/Caches/Yarn`
- pip: `~/Library/Caches/pip`
- Python tools: `~/.pyenv/cache`, `~/.cache/poetry`, `~/.cache/uv`, `~/.cache/ruff`, `~/.cache/mypy`, `~/.pytest_cache`, `~/.jupyter/runtime`, `~/.cache/huggingface`, `~/.cache/torch`, `~/.cache/tensorflow`, `~/.conda/pkgs`, `~/anaconda3/pkgs`, `~/.cache/wandb`
- Go: `go env GOCACHE`, `go env GOMODCACHE`
- mise: `$MISE_CACHE_DIR` or `~/Library/Caches/mise`
- Rust: `~/.cargo/registry/cache`, `~/.cargo/git`, `~/.rustup/downloads`
- Docker: `~/.docker/buildx/cache`
- Nix: `/nix/store` via `nix-collect-garbage --delete-older-than 30d`
- Cloud CLIs: `~/.kube/cache`, `~/.local/share/containers/storage/tmp`, `~/.aws/cli/cache`, `~/.config/gcloud/logs`, `~/.azure/logs`
- Frontend: `~/.cache/typescript`, `~/.cache/electron`, `~/.cache/node-gyp`, `~/.node-gyp`, `~/.turbo/cache`, `~/.vite/cache`, `~/.cache/vite`, `~/.cache/webpack`, `~/.parcel-cache`, `~/.cache/eslint`, `~/.cache/prettier`
- Android NDK check: `~/Library/Android/sdk/ndk`

### Clean: Xcode And Apple Developer Paths

- `~/Library/Developer/CoreSimulator/Caches/*`
- `~/Library/Developer/CoreSimulator/Devices/*/data/tmp/*`
- `~/Library/Logs/CoreSimulator/*`
- unavailable simulators via `xcrun simctl delete unavailable`
- `~/Library/Caches/com.apple.dt.Xcode/*`
- `~/Library/Developer/Xcode/iOS Device Logs/*`
- `~/Library/Developer/Xcode/watchOS Device Logs/*`
- `~/Library/Developer/Xcode/Products/*`
- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/Xcode/Archives/*`
- `~/Library/Developer/Xcode/DocumentationCache/*`
- `~/Library/Developer/Xcode/DocumentationIndex/*`
- `/Library/Developer/Xcode/DocumentationCache`
- `/Library/Developer/CoreSimulator/Volumes`
- `/Library/Developer/CoreSimulator/Cryptex`

### Clean: App-Specific Cache Families

Representative app paths from `lib/clean/app_caches.sh`:

- Code editors: VS Code, Sublime Text, Zed.
- Communication: Discord, Legcord, Slack, Zoom, WeChat, Telegram, Teams, WhatsApp, Skype, Tencent Meeting, WeCom, Feishu.
- AI apps: ChatGPT, Claude Desktop, Codex.
- Design/video/3D: Sketch, Adobe, Figma, ScreenFlow, Final Cut Pro, DaVinci Resolve, Premiere Pro, Blender, Cinema 4D, Autodesk, SketchUp.
- Productivity/media: MiaoYan, Klee, Ora, Filo, Flomo, Quark, NetNewsWire, MindNode, Spotify, Music, Podcasts, TV, Plex, NetEase Music, QQ Music.
- Video/download/gaming: IINA, VLC, MPV, iQIYI, Tencent Video, Bilibili, Stremio, Aria2, Transmission, qBittorrent, Downie, Folx, Steam, Epic Games, Battle.net, EA, GOG, Riot, Minecraft, Lunar Client, PCSX2, RPCS3.
- Utilities: shell history/caches, Warp, Ghostty, WakaTime, WeType, mihomo-party, Stash, Notion, Obsidian, Logseq, Bear, Evernote, Alfred, Raycast, TeamViewer, AnyDesk, ToDesk, Sunlogin.

## Uninstall Command

Implementation files:

- `bin/uninstall.sh`
- `lib/uninstall/batch.sh`
- `lib/uninstall/brew.sh`
- `lib/ui/app_selector.sh`
- `lib/core/app_protection.sh`
- `lib/core/bundle_resolver.sh`

Main functions:

- Find installed apps.
- Show selectable app list.
- Resolve app bundle id and related files.
- Stop launch services and remove login items.
- Remove app bundle and leftovers.
- Optionally use Homebrew cask uninstall.
- Rebuild LaunchServices after uninstall.
- Warn about macOS Local Network permission leftovers.

### Uninstall: App Search Locations

- `/Applications`
- `/System/Applications`
- `~/Applications`
- `/opt/homebrew/Caskroom`
- `/usr/local/Caskroom`
- `~/Library/Application Support/Setapp/Applications`

### Uninstall: User Leftover Paths

Patterns are built from `$app_name`, `$bundle_id`, and naming variants.

- `~/Library/Application Support/$app_name`
- `~/Library/Application Support/$bundle_id`
- `~/Library/Caches/$bundle_id`
- `~/Library/Caches/$app_name`
- `~/Library/Logs/$app_name`
- `~/Library/Logs/$bundle_id`
- `~/Library/Application Support/CrashReporter/$app_name`
- `~/Library/Saved Application State/$bundle_id.savedState`
- `~/Library/Containers/$bundle_id`
- `~/Library/WebKit/$bundle_id`
- `~/Library/WebKit/com.apple.WebKit.WebContent/$bundle_id`
- `~/Library/HTTPStorages/$bundle_id`
- `~/Library/HTTPStorages/$bundle_id.binarycookies`
- `~/Library/Cookies/$bundle_id.binarycookies`
- `~/Library/Application Scripts/$bundle_id`
- `~/Library/Services/$app_name.workflow`
- `~/Library/QuickLook/$app_name.qlgenerator`
- `~/Library/Internet Plug-Ins/$app_name.plugin`
- `~/Library/Audio/Plug-Ins/Components/$app_name.component`
- `~/Library/Audio/Plug-Ins/VST/$app_name.vst`
- `~/Library/Audio/Plug-Ins/VST3/$app_name.vst3`
- `~/Library/Audio/Plug-Ins/Digidesign/$app_name.dpm`
- `~/Library/PreferencePanes/$app_name.prefPane`
- `~/Library/Input Methods/$app_name.app`
- `~/Library/Input Methods/$bundle_id.app`
- `~/Library/Screen Savers/$app_name.saver`
- `~/Library/Frameworks/$app_name.framework`
- `~/Library/Autosave Information/$bundle_id`
- `~/Library/Contextual Menu Items/$app_name.plugin`
- `~/Library/Spotlight/$app_name.mdimporter`
- `~/Library/ColorPickers/$app_name.colorPicker`
- `~/Library/Workflows/$app_name.workflow`
- `~/.config/$app_name`
- `~/.local/share/$app_name`
- `~/.$app_name`
- `~/.$app_namerc`
- `~/Library/SyncedPreferences/$bundle_id.plist`
- `~/Library/Address Book Plug-Ins/$app_name.bundle`
- `~/Library/Accessibility/$app_name.bundle`
- `~/Library/Mail/Bundles/$app_name.mailbundle`
- `~/Library/Preferences/$bundle_id.plist`
- `~/Library/Preferences/$bundle_id`
- `~/Library/Preferences/ByHost/$bundle_id*.plist`
- `~/Library/LaunchAgents/$bundle_id.plist`
- `~/Library/LaunchAgents/$bundle_id.*.plist`
- `~/Library/Caches/com.apple.nsurlsessiond/Downloads/$bundle_id`
- `~/Library/Group Containers/*$bundle_id*`
- `~/Library/Application Support/com.apple.sharedfilelist/**/$bundle_id.sfl4`

### Uninstall: System Leftover Paths

- `/Library/Application Support/$app_name`
- `/Library/Application Support/$bundle_id`
- `/Library/LaunchAgents/$bundle_id.plist`
- `/Library/LaunchDaemons/$bundle_id.plist`
- `/Library/Preferences/$bundle_id.plist`
- `/Library/Receipts/$bundle_id.bom`
- `/Library/Receipts/$bundle_id.plist`
- `/Library/Frameworks/$app_name.framework`
- `/Library/Internet Plug-Ins/$app_name.plugin`
- `/Library/Input Methods/$app_name.app`
- `/Library/Input Methods/$bundle_id.app`
- `/Library/Audio/Plug-Ins/Components/$app_name.component`
- `/Library/Audio/Plug-Ins/VST/$app_name.vst`
- `/Library/Audio/Plug-Ins/VST3/$app_name.vst3`
- `/Library/Audio/Plug-Ins/Digidesign/$app_name.dpm`
- `/Library/QuickLook/$app_name.qlgenerator`
- `/Library/PreferencePanes/$app_name.prefPane`
- `/Library/Screen Savers/$app_name.saver`
- `/Library/Caches/$bundle_id`
- `/Library/Caches/$app_name`
- `/Library/Extensions/$app_name.kext`
- `/Library/StartupItems/$app_name`
- `/Library/Logs/$app_name`
- `/Library/Logs/$bundle_id`
- `/Library/LaunchAgents/$bundle_id.*.plist`
- `/Library/LaunchDaemons/$bundle_id.*.plist`
- `/Library/PrivilegedHelperTools/$bundle_id*`
- `/private/var/db/receipts/*$bundle_id*`

## Purge Command

Implementation files:

- `bin/purge.sh`
- `lib/clean/project.sh`
- `lib/clean/purge_shared.sh`
- `lib/manage/purge_paths.sh`

Main function: scan configured project roots and remove heavyweight build/dependency artifacts.

### Purge Search Roots

Default roots:

- `~/www`
- `~/dev`
- `~/Projects`
- `~/GitHub`
- `~/Code`
- `~/Workspace`
- `~/Repos`
- `~/Development`

Custom roots:

- `~/.config/mole/purge_paths`

Auto-discovery also scans direct children of `$HOME`, skipping hidden/system/media folders such as `Library`, `Applications`, `Movies`, `Music`, `Pictures`, and `Public`.

### Purge Targets

- `node_modules`
- `target`
- `build`
- `dist`
- `venv`
- `.venv`
- `.pytest_cache`
- `.mypy_cache`
- `.tox`
- `.nox`
- `.ruff_cache`
- `.gradle`
- `__pycache__`
- `.next`
- `.nuxt`
- `.output`
- `vendor`
- `bin`
- `obj`
- `.turbo`
- `.parcel-cache`
- `.dart_tool`
- `.zig-cache`
- `zig-out`
- `.angular`
- `.svelte-kit`
- `.astro`
- `coverage`
- `DerivedData`
- `Pods`
- `.cxx`
- `.expo`
- `.build`

Project indicators:

- `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `pom.xml`, `build.gradle`, `Gemfile`, `composer.json`, `pubspec.yaml`, `Package.swift`, `Makefile`, `build.zig`, `build.zig.zon`, `.git`

Monorepo indicators:

- `lerna.json`, `pnpm-workspace.yaml`, `nx.json`, `rush.json`

## Installer Command

Implementation file:

- `bin/installer.sh`

Main function: find `.dmg`, `.pkg`, `.mpkg`, `.iso`, `.xip`, and installer-like `.zip` files.

### Installer Search Paths

- `~/Downloads`
- `~/Desktop`
- `~/Documents`
- `~/Public`
- `~/Library/Downloads`
- `/Users/Shared`
- `/Users/Shared/Downloads`
- `~/Library/Caches/Homebrew`
- `~/Library/Mobile Documents/com~apple~CloudDocs/Downloads`
- `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`
- `~/Library/Application Support/Telegram Desktop`
- `~/Downloads/Telegram Desktop`

Default max depth is `2`. If `fd` exists, Mole uses it; otherwise it falls back to `find`.

## Optimize Command

Implementation files:

- `bin/optimize.sh`
- `lib/optimize/tasks.sh`
- `lib/optimize/maintenance.sh`

Main functions:

- Flush DNS cache with `dscacheutil -flushcache` and `killall -HUP mDNSResponder`.
- Verify or rebuild Spotlight index.
- Refresh QuickLook thumbnails and icon services.
- Remove old `.savedState` folders.
- Repair corrupted preferences.
- Clear quarantine history.
- VACUUM selected SQLite databases.
- Rebuild LaunchServices.
- Rebuild font cache.
- Release inactive memory when pressure is high.
- Refresh route/ARP cache if network checks fail.
- Repair user directory permissions if broken.
- Restart Bluetooth daemon only when safe.
- Refresh Dock.
- Prevent `.DS_Store` on network/USB volumes.
- Clean broken LaunchAgents.
- Run periodic maintenance.
- Repair shared file lists.
- Clean oversized Notification Center database.
- Clean oversized CoreDuet Knowledge database.
- Audit broken login items.

### Optimize Paths

- `~/Library/Caches/com.apple.QuickLook.thumbnailcache`
- `~/Library/Caches/com.apple.iconservices.store`
- `~/Library/Caches/com.apple.iconservices`
- `~/Library/Saved Application State/*.savedState`
- `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2`
- `~/Library/Mail/V*/MailData/Envelope Index*`
- `~/Library/Messages/chat.db`
- `~/Library/Safari/History.db`
- `~/Library/Safari/TopSites.db`
- `~/Library/Application Support/Dock/*.db`
- `~/Library/Preferences/com.apple.dock.plist`
- `~/Library/LaunchAgents/*.plist`
- `/var/log/daily.out`
- `~/Library/Application Support/com.apple.sharedfilelist/*.sfl2`
- `~/Library/Application Support/com.apple.sharedfilelist/*.sfl3`
- `$DARWIN_USER_DIR/com.apple.notificationcenter/db2/db`
- `~/Library/Application Support/Knowledge/knowledgeC.db`
- `~/Library/Application Support/Knowledge/knowledgeC.db-wal`
- `~/Library/Application Support/Knowledge/knowledgeC.db-shm`

## Analyze Command

Implementation files:

- `cmd/analyze/main.go`
- `cmd/analyze/scanner.go`
- `cmd/analyze/constants.go`
- `cmd/analyze/insights.go`
- `cmd/analyze/cache.go`
- `cmd/analyze/delete.go`
- `cmd/analyze/json.go`

Main functions:

- TUI disk explorer.
- JSON disk report with entries, large files, total size, total files.
- Overview mode when no path is passed.
- Path-specific mode when a path is passed.
- Large file list.
- Delete by moving to Trash through Finder.
- Cached scan results.

### Analyze Overview Paths

- `$HOME`
- `$HOME/Library`
- `/Applications`
- `/Library`
- `$HOME/Library/Application Support/MobileSync/Backup`
- `$HOME/Downloads` as "Old Downloads (90d+)"
- `$HOME/Library/Logs`
- `$HOME/Library/Caches/Homebrew`
- `$HOME/Library/Developer/Xcode/DerivedData`
- `$HOME/Library/Developer/CoreSimulator/Devices`
- `$HOME/Library/Developer/Xcode/Archives`
- `$HOME/Library/Application Support/Spotify/PersistentCache`
- `$HOME/Library/Caches/JetBrains`
- `$HOME/Library/Containers/com.docker.docker/Data`
- `$HOME/Library/Caches/pip`
- `$HOME/.gradle/caches`
- `$HOME/Library/Caches/CocoaPods`

### Analyze Folded Directories

These are treated as heavy/known directories and measured without deeply expanding every child in the display:

- VCS: `.git`, `.svn`, `.hg`
- JS/Node: `node_modules`, `.npm`, `.yarn`, `.pnpm-store`, `.next`, `.nuxt`, `.vite`, `.turbo`, `.parcel-cache`, `.nx`, `.rush`, `.bun`, `.deno`, `bower_components`
- Python: `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `venv`, `.venv`, `virtualenv`, `.tox`, `site-packages`, `.pyenv`, `.poetry`, `.pip`, `.pipx`
- Build/cache: `target`, `.gradle`, `.m2`, `.ivy2`, `build`, `dist`, `.output`, `coverage`, `.cache`
- IDE/tools: `.idea`, `.vscode`, `.vs`, `.fleet`
- macOS/mobile: `Application Scripts`, `Saved Application State`, `Pods`, `DerivedData`, `.build`, `Carthage`, `.dart_tool`
- Other: `.docker`, `.containerd`, `.terraform`, `.vagrant`, `tmp`, `temp`

Root-level skip directories include:

- `/System`, `/dev`, `/tmp`, `/private`, `/cores`, `/net`, `/home`, `/sbin`, `/bin`, `/etc`, `/var`, `/Volumes`, `/Network`, `/.vol`, `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.TemporaryItems`, `.MobileBackups`

## Status Command

Implementation files:

- `cmd/status/main.go`
- `cmd/status/metrics.go`
- `cmd/status/metrics_cpu.go`
- `cmd/status/metrics_memory.go`
- `cmd/status/metrics_disk.go`
- `cmd/status/metrics_network.go`
- `cmd/status/metrics_battery.go`
- `cmd/status/metrics_gpu.go`
- `cmd/status/metrics_bluetooth.go`
- `cmd/status/metrics_health.go`
- `cmd/status/metrics_process.go`
- `cmd/status/process_watch.go`
- `cmd/status/view.go`

Main functions:

- Live TUI refreshed every second.
- JSON output via `--json` or when output is piped.
- Health score from CPU, memory, disk, temperature, battery, and I/O.
- Hardware summary.
- CPU, GPU, memory, disk, disk I/O, network, proxy, battery, thermal, Bluetooth, and top process metrics.
- Persistent high-CPU process alerts.
- Preference stored at `~/.config/mole/status_prefs`.

System data sources include:

- gopsutil for CPU, memory, disk, network, host, and process stats.
- `vm_stat`
- `sysctl`
- `diskutil info`
- `diskutil info -plist`
- `pmset -g batt`
- `system_profiler SPHardwareDataType`
- `system_profiler SPDisplaysDataType`
- `system_profiler SPPowerDataType`
- `system_profiler SPBluetoothDataType`
- `ioreg -rn AppleSmartBattery`
- `powermetrics --samplers gpu_power`

## Config And State Files

- `~/.config/mole/whitelist`
- `~/.config/mole/purge_paths`
- `~/.config/mole/clean-list.txt`
- `~/.config/mole/install_channel`
- `~/.config/mole/status_prefs`
- `~/.cache/mole/update_message`
- `~/.cache/mole/permissions_granted`
- `~/.cache/mole/installed_apps_cache`
- `~/.cache/mole/brew_last_cleanup`
- `~/Library/Logs/mole/operations.log`

## Suggested Mac App Screens

- Dashboard: disk free, estimated reclaimable space, health score, last scan date.
- Clean: category list with dry-run preview, whitelist management, and detailed file review.
- Uninstaller: installed apps, bundle id, size, leftovers, running state, safety warnings.
- Disk Analyzer: overview folders, large files, drill-down tree, trash action.
- Project Purge: configured roots, discovered projects, artifact categories.
- Installer Cleanup: installer files grouped by source.
- Optimize: maintenance tasks as toggles with risk labels and dry-run preview.
- Status Monitor: live CPU/memory/disk/network/battery/process cards.
- Settings: whitelist, purge paths, logs, delete mode, sudo/Touch ID status.

## Important Implementation Notes For A GUI App

- Do scanning first and deletion second. Always show exact paths before deleting.
- Keep deletion APIs path-validated and centralized.
- Prefer Trash for user-visible deletion.
- Separate user-level operations from sudo-required operations.
- Treat app containers and Group Containers as high-risk.
- Avoid deleting LaunchAgents/LaunchDaemons generically; only remove validated app-specific or broken entries.
- Avoid scanning the entire home directory without pruning. Mole uses default project roots, depth limits, skip lists, and timeouts.
- Add progress/cancellation for every scan because Library, Xcode, Docker, and browser caches can be huge.
