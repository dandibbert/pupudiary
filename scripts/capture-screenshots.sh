#!/bin/bash
# Capture actual app pixels from the named native iPhone simulator, before test/IPA work.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SELECTION="${1:-build/simulator-selection.json}"
APP="${2:-build/DerivedData/Build/Products/Debug-iphonesimulator/Pupudiary.app}"
OUTPUT="${3:-build/screenshots}"
mkdir -p "$OUTPUT"
[[ -d "$APP" ]] || { echo "Simulator app not found: $APP" >&2; exit 1; }
python3 - "$SELECTION" <<'PY' > "$OUTPUT/devices.tsv"
import json, sys
seen = set()
for role, device in json.load(open(sys.argv[1])).items():
    if not isinstance(device, dict) or device['udid'] in seen:
        continue
    seen.add(device['udid'])
    print('\t'.join([role, device['udid'], device['name'], device['os']]))
PY
while IFS=$'\t' read -r role udid name os; do
  echo "Capturing $name / iOS $os ($udid)"
  # boot is idempotent at the workflow level; a previously booted device returns nonzero.
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
  xcrun simctl ui "$udid" appearance light
  xcrun simctl install "$udid" "$APP"
  for screen in home record widget-preview; do
    xcrun simctl terminate "$udid" com.dandibbert.pupudiary >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" com.dandibbert.pupudiary --uitesting --screen "$screen"
    # Allow initial SwiftUI layout, sheet presentation and rendering to settle.
    sleep 3
    xcrun simctl io "$udid" screenshot "$OUTPUT/${role}-${screen}.png"
  done
  xcrun simctl terminate "$udid" com.dandibbert.pupudiary >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid"
done < "$OUTPUT/devices.tsv"
python3 - "$SELECTION" "$OUTPUT" <<'PY'
import json, struct, sys
from pathlib import Path
selection = json.load(open(sys.argv[1]))
output = Path(sys.argv[2])
records = []
for path in sorted(output.glob('*.png')):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and len(data) > 8000, f'Invalid/empty screenshot: {path}'
    width, height = struct.unpack('>II', data[16:24])
    role, screen = path.stem.split('-', 1)
    records.append({'file': path.name, 'device': selection[role]['name'], 'iOS': selection[role]['os'],
        'screen': screen, 'width': width, 'height': height,
        'capture': 'Native iOS Simulator screenshot, unresized',
        'note': 'Widget preview inside app; not a SpringBoard widget integration capture.' if screen == 'widget-preview' else 'Native SwiftUI app screen'})
(output / 'manifest.json').write_text(json.dumps(records, indent=2) + '\n')
(output / 'README.txt').write_text(
    'Native iPhone simulator captures. See manifest.json for actual model, OS, and pixel dimensions.\n'
    'widget-preview captures are the app-hosted shared widget design, not the SpringBoard widget.\n'
    'These screenshots do not validate real-device App Group entitlement or interactive widget execution.\n'
    + selection['compact_note'] + '\n')
assert len(records) >= 3, 'Expected at least three native captures'
PY
