# Verification and screenshot provenance

## Automated checks

The GitHub Actions workflow `.github/workflows/ios.yml` runs on push, pull request, and manual dispatch. It uses the `macos-15` runner and an explicit installed Xcode 26.3 path. The workflow records the actual Xcode/macOS versions, SDKs, available runtimes and device inventory as artifacts. If GitHub removes that Xcode version, update the workflow after inspecting the current runner inventory; do not silently claim an untested toolchain.

Order matters:

1. Generate the project from `project.yml` with XcodeGen
2. Build the app and embedded widget for iOS Simulator
3. Select the newest installed Pro iPhone; also select an installed iPhone SE for compact coverage, with a clearly named fallback only if SE is absent
4. Boot the real simulators, install the compiled app, launch each screen, and capture native PNG screenshots
5. **Upload screenshots before** tests or device builds
6. Run XCTest core tests and XCUI smoke tests, preserving the `.xcresult` bundle
7. Independently build Release for `generic/platform=iOS`, package the full app including widget, validate the unsigned IPA and calculate SHA-256
8. Upload all available logs/results even when a later stage fails

An IPA can be produced even when a test stage fails. Check the full run conclusion and individual stage outcomes, not just artifact existence. An unavailable or failed check is not a pass.

## Screenshot origin

`scripts/capture-screenshots.sh` uses `xcrun simctl io <actual-device-UDID> screenshot` and does not resize the output or render a web mockup. `manifest.json` records the actual device name, iOS version, native pixel size and screen. No unavailable model is relabeled as iPhone 18 Pro or any other requested model.

The app supports simulator-only deterministic demo launches:

```sh
xcrun simctl launch <UDID> com.dandibbert.pupudiary --uitesting --screen home
xcrun simctl launch <UDID> com.dandibbert.pupudiary --uitesting --screen record
xcrun simctl launch <UDID> com.dandibbert.pupudiary --uitesting --screen widget-preview
```

The widget-preview screen is an **app-hosted preview of the shared SwiftUI widget design**, not a SpringBoard widget screenshot. It demonstrates layout only. CI does not use undocumented/private SpringBoard automation to add widgets. Actual Home Screen installation, App Intent execution and signed shared-container access need the physical-device checklist in `SIGNING.md`. Do not present preview screenshots as proof those checks passed.

UI smoke tests cover quick save/undo, rapid repeated quick saves, cancel/reopen without saving, a detailed record with optional fields empty, and background/foreground retention. They identify elements with stable accessibility IDs rather than screen coordinates. Core tests cover persistence/business logic separately. UI test launches use an isolated temporary diary, so automated tests do not erase a real diary.

## Local reproduction on macOS

```sh
brew install xcodegen
xcodegen generate
mkdir -p build/logs
xcrun simctl list devices available --json > build/logs/simulators.json
python3 scripts/select-simulators.py build/logs/simulators.json build/simulator-selection.json
xcodebuild -project Pupudiary.xcodeproj -scheme Pupudiary -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
scripts/capture-screenshots.sh
# Substitute the real primary UDID from build/simulator-selection.json
xcodebuild -project Pupudiary.xcodeproj -scheme Pupudiary \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath build/DerivedData -resultBundlePath build/Pupudiary.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
scripts/build-unsigned-ipa.sh
```

Open `build/Pupudiary.xcresult` with Xcode to inspect test cases, failures, and attached screenshots. Inspect native screenshots at their original resolution for clipping, small-screen overflow, contrast and accessibility. The automated PNG validation verifies valid/nonempty dimensions; it is not a visual-quality judgment.

## Source references

- [GitHub's macOS 15 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [XcodeGen project specification](https://yonaskolb.github.io/XcodeGen/Docs/ProjectSpec.html)
