# Verification and screenshot provenance

## Native preview and full validation

The short `native-preview.yml` workflow captures the redesigned home and record form in one XCTest session. It runs on an Intel `macos-15-intel` runner with Xcode 26.3 and a real iPhone 16 Pro / iOS 18.6 Simulator. It asserts that the seven illustrated shape choices and effort controls are visible, exports the original PNG attachments and retains the full result bundle. This is a native SwiftUI app launch, not a rendered web mockup.

The full `.github/workflows/ios.yml` workflow independently runs:

- Native screenshot, quick logging, record form, core/model, compact-phone and appearance shards
- Production Foundation/SQLite tests on macOS without Simulator boot
- Release device build, complete embedded WidgetKit extension, unsigned arm64 IPA validation and SHA-256 calculation

The workflow records actual Xcode/macOS versions, SDKs, runtime and device inventory. It uses installed iPhone 16 Pro and iPhone SE (3rd generation) Simulators on iOS 18.6. No unavailable model is renamed as iPhone 18 Pro.

Each native test step has a 20-minute limit. One retry is allowed only for a runner killed before any test case began; assertion failures are never automatically retried. Both attempts remain in the artifacts. Native attachments and test results are uploaded even when a later stage fails.

An IPA can be produced while a test job fails or is still running. Artifact existence is not a test pass. Check the exact source SHA, full run conclusion, individual test summaries and skipped tests before treating a build as verified.

## What the screenshots demonstrate

Screenshots come from native `XCUIScreen.main.screenshot()` / `XCUIApplication.screenshot()` attachments. `xcresulttool` exports their unchanged PNG bytes. The artifact includes device/OS metadata, an attachment manifest and PNG dimensions. Screenshots use isolated demo data, never the user's diary.

The widget-preview screen is an **app-hosted view of the shared SwiftUI widget design**, not a SpringBoard screenshot. It demonstrates appearance only. Actual Home Screen installation, interactive AppIntent execution and entitled cross-process App Group access require the physical-device checklist in [SIGNING.md](SIGNING.md). Do not claim that a preview proves those checks passed.

PNG validation checks basic file structure/dimensions; it is not a visual-quality judgment. Inspect actual pixels for clipped text, overflow, contrast and small-screen/dynamic-type behavior.

## Functional coverage

Core tests exercise transaction safety, cross-connection duplicate protection, edits/undo/recovery, CSV escaping/formula neutralization, strict JSON validation, additive nonoverwriting restore, timezone/DST boundaries, supported backup limits and failure rollback.


UI tests cover quick save/undo, repeated taps, foreground retention, supplementing the same entry, cancelling a form, leaving optional fields empty, scrolling with the keyboard, note persistence and an empty first-use view without an invented elapsed interval. They use accessibility identifiers rather than screen coordinates.

The real `QuickLogIntent.perform()` persistence-before-return path can run against an isolated Simulator-only test container. A separate real shared-App-Group integration test explicitly skips when the signing entitlement is unavailable; a skip is not a pass. Device/release builds do not include the testing-container override.

## Reproduce on a Mac

```sh
brew install xcodegen
xcodegen generate
mkdir -p build/logs
xcodebuild -version
xcrun simctl list devices available
# Use a real available device name and runtime from this machine.
xcodebuild test -project Pupudiary.xcodeproj -scheme Pupudiary \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' \
  -derivedDataPath build/DerivedData -resultBundlePath build/Pupudiary.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
scripts/test-core-on-macos.sh
scripts/build-unsigned-ipa.sh
```

For a short home/form run, append:

```sh
-only-testing:PupudiaryUITests/PupudiaryUITests/testCaptureRedesignedHomeAndRecord
```

Open the `.xcresult` bundle in Xcode, or export attachments with the current Xcode's `xcresulttool`. CI verifies that tool's help before using it. `scripts/capture-screenshots.sh` remains an optional direct-simctl route, but CI uses XCTest to manage Simulator lifecycle because that route was more reliable on the tested hosted runners.

## Source references

- [GitHub runner images](https://github.com/actions/runner-images)
- [XcodeGen project specification](https://yonaskolb.github.io/XcodeGen/Docs/ProjectSpec.html)
