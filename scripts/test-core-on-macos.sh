#!/bin/bash
# Exercise the exact production Foundation/SQLite sources without booting a simulator.
# The AppIntent integration case explicitly skips here; it is still tested by Xcode on iOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PACKAGE="$ROOT/build/CorePackage"
mkdir -p "$PACKAGE/Sources/Pupudiary" "$PACKAGE/Tests/PupudiaryTests" build/logs
cp Shared/LogEntry.swift Shared/DiaryStore.swift "$PACKAGE/Sources/Pupudiary/"
cp Tests/CoreTests.swift "$PACKAGE/Tests/PupudiaryTests/"
cat > "$PACKAGE/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PupudiaryCoreValidation",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "Pupudiary", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "PupudiaryTests", dependencies: ["Pupudiary"])
    ]
)
SWIFT
swift test --package-path "$PACKAGE" 2>&1 | tee build/logs/host-core-tests.log
