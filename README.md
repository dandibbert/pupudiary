# Pupudiary · 噗噗手帐

A small, calm SwiftUI bowel diary for iPhone. Record a moment with one tap, add details later, and keep useful context on a Home Screen widget.

- iOS 17+, native SwiftUI and WidgetKit
- One-tap logging, optional detail fields, history, and recent-record undo
- Shared local storage for app and interactive widget
- Records stay on the device; no account or analytics service
- Chinese-first interface, designed for comfortable everyday use

This is a personal diary, not a diagnostic tool or medical advice.

## Build

On a Mac with Xcode:

```sh
brew install xcodegen
xcodegen generate
open Pupudiary.xcodeproj
```

Select the shared `Pupudiary` scheme. For Simulator, no Apple Developer signing setup is needed. For a real iPhone, configure your team and App Group for **both** the app and widget; see [Signing and installation](Docs/SIGNING.md).

## Download build artifacts

Open this repository's [Actions runs](https://github.com/dandibbert/pupudiary/actions) and select a completed run:

- `native-iphone-screenshots`: original native iPhone Simulator captures, with actual device/OS/pixel metadata
- `Pupudiary-unsigned-ipa`: unsigned arm64 IPA, checksum, entitlement templates and signing guide
- `xcode-logs-and-tests`: build logs, selected toolchain/device information and XCTest result bundle

Artifacts may require signing into GitHub and expire after the retention period. The unsigned IPA cannot install until it is signed/provisioned. The embedded WidgetKit extension is preserved; its App Group capability must be authorized by both profiles. See [Signing and installation](Docs/SIGNING.md) for an offline signed-IPA validator and app-only fallback limitations.

Native screenshots are captured and uploaded before later test/package stages. Widget-preview captures show the same widget design **inside the app**; they do not establish actual Home Screen widget execution. See [Verification and screenshot provenance](Docs/VERIFICATION.md).

## Layout

- `App/`: SwiftUI app screens and app state
- `Shared/`: data model, local store, widget presentation and App Intent
- `Widget/`: WidgetKit extension
- `Tests/`: core XCTest and native XCUI smoke tests
- `Config/`: bundle metadata, App Group entitlements and privacy manifest
- `scripts/`: native screenshot capture, unsigned packaging and offline IPA checks
- `project.yml`: reproducible XcodeGen project specification

## Privacy and backups

Diary entries may contain sensitive health-related information. Keep exports, device backups, screenshots of real entries, and signing credentials private. CI screenshots use isolated demo records. Exported files are not automatically encrypted by this app; share or store them only where you intend. Removing the app can remove its local records, so preserve an export before reinstalling or changing signing/container identifiers.
