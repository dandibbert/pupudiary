# Pupudiary · 噗噗手帐

A native SwiftUI bowel diary for iPhone. See the time since the last logged bowel movement, seven-day frequency, stool shape and effort at a glance. Record a timestamp with one tap, then add optional details using original flat illustrations.

- iOS 17+, native SwiftUI and WidgetKit
- One-tap logging, visual Bristol selection, optional details, history, and recent-record undo
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

- `native-redesign-preview`: short native home/form capture from the preview workflow
- `intel-native-xctest-screenshots-*`: original native Simulator XCTest attachments from full validation, with actual device/OS/pixel metadata
- `Pupudiary-unsigned-ipa`: unsigned arm64 IPA, checksum, entitlement templates and signing guide
- `native-redesign-preview-results` / `intel-xctest-results-and-logs-*`: full XCTest bundles and logs
- `host-core-test-logs` / `device-build-logs`: independent core and packaging evidence

Artifacts may require signing into GitHub and expire after the retention period. The unsigned IPA cannot install until it is signed/provisioned. The embedded WidgetKit extension is preserved; its App Group capability must be authorized by both profiles. See [Signing and installation](Docs/SIGNING.md) for an offline signed-IPA validator and app-only fallback limitations.

The short preview workflow finalizes its native screenshots independently of the full validation matrix. Device packaging and core checks also run independently. Widget-preview captures show the same widget design **inside the app**; they do not establish actual Home Screen widget execution. See [Verification and screenshot provenance](Docs/VERIFICATION.md).

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

## Recording model

The app assumes bowel movements are logged: days without an entry count as no bowel movement. The interval is calculated from the latest saved event; backfilled and edited records automatically recalculate it. Before the first event, no missing-day baseline is invented. No daily confirmation step is required.

Descriptive “constipation-related signs” use actual logged hard/lumpy stool, effort, pain or incomplete-emptying details. The elapsed interval is not a diagnosis of constipation duration. References: [NIDDK](https://www.niddk.nih.gov/health-information/digestive-diseases/constipation/definition-facts), [NHS](https://www.nhs.uk/conditions/constipation/).
