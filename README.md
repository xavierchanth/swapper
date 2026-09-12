# XMT — Xavier's macOS Tweaks

XMT is a personal macOS menu bar app that collects chosen macOS behavior changes into one user-visible app and UI, so there is one product to install, permission, configure, and remember instead of one per tweak. Safety-critical keyboard customization may eventually use isolated built-in helper and system-extension components; it is not a plugin model. This README covers what ships today and how to build, run, and test it; [the documentation tree](docs/README.md) covers product intent, architecture, and roadmap.

## What ships today

The current product focuses on three personal utilities: Window Mover, Hyper Caps, and menu-bar hiding. The SwiftUI Settings window opens when XMT is launched or reopened; closing it leaves XMT running. Only the menu-bar hiding arrow and separator occupy the menu bar, and they disappear when that feature is disabled. There is no separate XMT status icon.

**Hyper Caps** targets the built-in keyboard, maps a Caps tap to Escape and a hold to Control–Option–Shift–Command, and offers an adjustable hold threshold. Enable it explicitly in Settings after quitting Hyperkey. The implementation uses a targeted HID mapping and an event tap, with a separate recovery process; it does not install a DriverKit extension. Physical-keyboard validation and recovery evidence are tracked in the [roadmap](docs/roadmap/README.md).

**Menu-bar hiding** provides a Command-draggable separator and expand/collapse arrow, with automatic collapse after 60 seconds by default. XMT waits while Hidden Bar is running. Quit Hidden Bar, then position XMT's separator once to choose which items to hide. Existing Hidden Bar delay preferences are imported once when available.

Dictation is excluded from the default product. Its source and optional development flag below remain for reference; home-row modifiers are deferred and there is no Rust migration.

Window Mover is available by default. Voice Transcription is disabled at build time unless explicitly enabled.

To enable Voice, use `just features=XMT_VOICE build` (or `test`). With `xcodebuild`, pass `XMT_FEATURES=XMT_VOICE` when building or testing the `XMT` scheme. For example:

```bash
xcodebuild build -project XMT.xcodeproj -scheme XMT -configuration Release -destination 'platform=macOS' -derivedDataPath .build/xcode XMT_FEATURES=XMT_VOICE
```

Ordinary `just build` and `just test` leave Voice off. The flag gates module registration, shortcuts, settings, and Voice/history menu surfaces; shared Voice source, configuration types, and SDK dependencies still compile. Existing Voice preferences, recovery files, and transcripts are preserved. Configuration syntax remains validated, but unavailable Voice shortcuts do not reserve Window Mover bindings. This is a build-time feature gate, not a runtime preference.

**Window Mover** — a global shortcut (default **Option-Space**) that moves the focused window to the next display, wrapping around, preserving relative geometry, and handling native full-screen windows. Specified in [the Window Mover specification](docs/specification/window-mover.md).

**Voice Transcription** — hold **Fn** to dictate, press **Fn-Space** to latch recording on and off, or press **Fn-Escape** to cancel; each action owns an ordered, accessible list of zero or more bindings with add, edit, remove, and reorder controls. Speech is analyzed on device with macOS 26's `SpeechAnalyzer`, the transcript goes to the clipboard and optionally pastes itself into the focused input, and an interrupted recording is kept so it can be retried once. Specified in [the Voice Transcription specification](docs/specification/voice-transcription.md). It is implemented and integrated but **has not yet been validated against real microphone, Speech, or paste behavior**; see [validation gaps](docs/roadmap/README.md#voice-transcription-validation-gaps) before relying on it.

Supporting behavior:

- Lives in the menu bar as an `LSUIElement` app with no Dock icon.
- Rebindable global shortcut powered by [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts).
- Contextual permission status and request actions in Settings; launch does not prompt.
- An optional declarative config file at `~/.config/xmt/config.json`, specified in [the configuration specification](docs/specification/configuration.md).
- Launch at Login through `SMAppService`.

The older home-row/DriverKit feasibility code remains inactive. Menu-bar hiding uses XMT's own status-item spacing, following Hidden Bar's approach; it does not provide an API to individually control other apps' icons.

## Status

Maintained for personal use, with downloadable releases and no support commitment.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- Accessibility permission for Window Mover, the consuming Voice Fn shortcut tap, clipboard-first paste or clipboard-only output, and Paste Latest
- Microphone and Input Monitoring permission for Voice Transcription
- Speech assets for the configured locale, downloadable from the Voice settings tab

## Installing

The [release workflow](.github/workflows/release.yml) tests both feature configurations and builds an ad-hoc-signed universal app on Xcode 26.5. Version tags matching `flake.nix` publish ZIP and tar.gz archives plus SHA-256 checksums. Manual workflow runs upload test artifacts without publishing a release. No Developer ID certificate or notarization credentials are required. See the [release-note template](assets/release-notes.md) for the signing limitation.

The repository's [Nix flake](flake.nix) packages the prebuilt tar.gz release without rebuilding or modifying its code signature. Consumers can add `inputs.xmt.url = "github:xavierchanth/xmt"` and include `inputs.xmt.packages.${pkgs.stdenv.hostPlatform.system}.xmt` in their Darwin packages. Keep XMT's stable Nixpkgs input to support both Apple silicon and Intel; the unstable branch no longer supports Intel macOS. Commit the consumer lockfile to pin the source and binary content. Installation through Nix does not grant Accessibility access or bypass Gatekeeper.

After publishing, Actions downloads and checks both archives, generates the binary input's lockfile hash, compares it with the verified archive's unpacked content hash, and evaluates both Darwin package definitions. It uploads the lockfile as a workflow artifact and opens a pin-update PR. Enable **Allow GitHub Actions to create and approve pull requests** in repository Actions settings for PR creation; the workflow never approves or merges its own PR. The initial pin must be merged before consuming it from the default branch. Updating a separate dotfiles repository remains a separate authorized operation; XMT's repository token is not given cross-repository access.

With [`just`](https://github.com/casey/just) installed, build a Release app and copy it to `/Applications`:

```bash
just install
```

That recipe quits a running copy, replaces `/Applications/XMT.app`, and launches the result. Existing preferences remain in place across replacement; the Voice settings action **Restore Default Bindings** can restore Fn, Fn-Space, and Fn-Escape together after confirmation. Open `Settings...` from the menu bar icon to configure each module and grant its permissions contextually.

To build and launch without installing:

```bash
just run
```

Both build into `.build/xcode`; `just clean` removes that directory.

Alternatively, open `XMT.xcodeproj` in Xcode and run the `XMT` target.

Launching or reopening XMT presents Settings; login-item launch is intended to start quietly. The default tabs are General, Window Mover, Hyper, and Menu Bar. General includes Quit; closing the window keeps the features running. The optional Voice development build additionally exposes its archived settings.

## Testing

`XMTTests` contains unit tests for window geometry, trigger arbitration and binding ownership, multi-binding routing and list editing, pure recorder chord decoding, the voice session reducer, input-device selection and the bounded audio queue, recovery reconciliation, transcript commit ordering, and configuration decoding, migration, precedence, and reload. Run them through the shared `XMT` scheme with `just test`; `just check` runs both tests and documentation checks. Audio capture, speech analysis, the live event tap, and the SwiftUI surfaces are not covered.

## Documentation checks

```bash
just docs-check
```

This validates heading structure, opening paragraphs, relative links, heading fragments, and reachability from `docs/README.md`. It needs Node and nothing else — no package manager, lockfile, or dependency install. Without `just`, run `node assets/check-docs.mjs`, which scans the same files by default.

`just check` runs the unit tests and documentation validation.

## Repository layout

- `XMT/App` — app entry point and app delegate
- `XMT/WindowManagement` — window discovery, geometry, movement, coordinate conversion, and the Window Mover lifecycle
- `XMT/VoiceTranscription` — the voice module coordinator plus its `Audio`, `Session`, and `Output` layers
- `XMT/Triggers` — the Fn event tap and the pure trigger arbitrator
- `XMT/Configuration` — config file decoding, settings resolution, and the reloader
- `XMT/HotKeys` — global shortcut names and defaults
- `XMT/Services` — Accessibility permission and reminder handling
- `XMT/Settings` — settings window and its tabs
- `XMT/MenuBar` — menu bar menu
- `XMT/Resources` — `Info.plist`, entitlements, and asset catalog
- `XMTTests` — unit tests
- `docs/` — [product, architecture, specification, and roadmap](docs/README.md)
- `assets/` — repository tooling, currently the documentation checker

Swift package dependency: `KeyboardShortcuts`, up to the next major version from `2.0.0`.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
