# XMT release

XMT brings Caps Override, Window Mover, and menu-bar hiding into one personal macOS app. Requires macOS 26 or later; the universal app supports Apple silicon and Intel. Dictation is disabled in this build.

## A note on macOS signing

Despite having previously signed and released applications for Apple platforms, Apple has been gatekeeping me from obtaining a personal developer account and leaving me in the dark. XMT therefore ships without Developer ID signing or notarization.

SHA-256 checksums are included if you'd like to verify your downloads manually. Download `XMT-macos.zip`, `XMT-macos.tar.gz`, and `SHA256SUMS` from this release into the same directory, then run:

```sh
shasum -a 256 -c SHA256SUMS
```

Both archives should report `OK`. If either fails, do not install it. These checks confirm that the files match the published checksums; they do not prove publisher identity or that the software is safe.

The app has an ad-hoc signature for executable integrity, not a verified publisher identity. Gatekeeper may require manual approval. This release does not disable Gatekeeper or remove quarantine automatically.

## Downloads and Nix

Use `XMT-macos.zip` for a manual installation. `XMT-macos.tar.gz` is the equivalent bundle for the repository's Nix flake.

The flake exposes `packages.aarch64-darwin.xmt` and `packages.x86_64-darwin.xmt`. Pin both the source and binary inputs in your consumer's `flake.lock`; no Xcode installation is needed to install the prebuilt package. Nix automatically verifies fetched, unpacked release content against the binary input's locked `narHash` and rejects mismatches. This is a content hash, distinct from the archive checksums above. Review the initial download and intentional lockfile updates: creating a new lock establishes a new trusted hash rather than authenticating the publisher.

Quit Hyperkey and Hidden Bar before enabling their replacements. Caps interception is unavailable during Secure Input; use physical Escape in password fields. Accessibility and login-item approval remain under your control.
