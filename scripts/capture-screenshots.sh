#!/bin/bash
# Capture actual app pixels from the named native iPhone simulator, before test/IPA work.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SELECTION="${1:-build/simulator-selection.json}"
APP="${2:-build/DerivedData/Build/Products/Debug-iphonesimulator/Pupudiary.app}"
OUTPUT="${3:-build/screenshots}"
FILTER="${4:-all}"
mkdir -p "$OUTPUT"
[[ -d "$APP" ]] || { echo "Simulator app not found: $APP" >&2; exit 1; }
# Keep runner stalls bounded and identify the exact command in retained logs.
run_simctl() {
  local limit="$1"; shift
  python3 - "$limit" "${udid:-}" "$@" <<'PY'
import datetime, os, pathlib, signal, subprocess, sys, time
limit, device = int(sys.argv[1]), sys.argv[2]
args = ['xcrun', 'simctl'] + sys.argv[3:]
label = ' '.join(args)
def stamp(message):
    print(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'), message, flush=True)
def invoke(command, seconds, capture=False):
    process = subprocess.Popen(command, start_new_session=True,
        stdout=subprocess.PIPE if capture else None, stderr=subprocess.STDOUT if capture else None)
    try:
        output, _ = process.communicate(timeout=seconds)
        return process.returncode, output or b''
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        return 124, output or b''
stamp(f'BEGIN timeout={limit}s {label}')
started = time.monotonic()
code, _ = invoke(args, limit)
stamp(f'END exit={code} elapsed={time.monotonic()-started:.1f}s {label}')
# Terminating an app that is not running is benign; a timeout never is.
if code and not (sys.argv[3] == 'terminate' and code != 124):
    stamp('SIMULATOR FAILURE: collecting bounded diagnostics; existing captures are retained')
    checks = [['xcrun', 'simctl', 'list', 'devices']]
    if device:
        checks.append(['xcrun', 'simctl', 'spawn', device, 'log', 'show', '--last', '2m', '--style', 'compact',
            '--predicate', 'process == "SpringBoard" OR process == "Pupudiary" OR process == "installd"'])
    for check in checks:
        stamp('DIAGNOSTIC ' + ' '.join(check))
        diagnostic_code, output = invoke(check, 8, capture=True)
        print('\n'.join(output.decode(errors='replace').splitlines()[-100:]), flush=True)
        stamp(f'DIAGNOSTIC exit={diagnostic_code}')
    log = pathlib.Path.home() / 'Library/Logs/CoreSimulator' / device / 'system.log'
    if log.is_file():
        print('\n'.join(log.read_text(errors='replace').splitlines()[-100:]), flush=True)
    stamp(f'EXPLICIT FAILURE exit={code}: {label}')
sys.exit(code)
PY
}
terminate_app() {
  local code=0
  run_simctl 30 terminate "$udid" com.dandibbert.pupudiary || code=$?
  # Nonzero for an already stopped app is expected. Do not hide a stalled command.
  [[ "$code" != 124 ]] || exit "$code"
}
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
  [[ "$FILTER" == "all" || "$FILTER" == "$role" ]] || continue
  echo "Capturing $name / iOS $os ($udid)"
  # Start the official Simulator application through LaunchServices as well as the device service.
  python3 - <<'PYOPEN'
import os, subprocess
try:
    subprocess.run(['open', '-a', os.environ['DEVELOPER_DIR'] + '/Applications/Simulator.app'], timeout=20, check=False)
except subprocess.TimeoutExpired:
    print('Simulator UI launch timed out; continuing with the bounded device service check', flush=True)
PYOPEN
  # bootstatus -b starts an unbooted simulator and also waits for readiness.
  run_simctl 180 bootstatus "$udid" -b
  run_simctl 15 status_bar "$udid" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100 || echo "Cosmetic status-bar override failed; keeping the actual system status bar"
  run_simctl 30 ui "$udid" appearance light
  run_simctl 60 install "$udid" "$APP"
  for screen in home record widget-preview history trends; do
    terminate_app
    run_simctl 60 launch "$udid" com.dandibbert.pupudiary --uitesting --screen "$screen"
    # Allow initial SwiftUI layout, sheet presentation and rendering to settle.
    sleep 3
    run_simctl 30 io "$udid" screenshot "$OUTPUT/${role}-${screen}.png"
  done
  if [[ "$role" == "primary" ]]; then
    run_simctl 30 ui "$udid" appearance dark
    terminate_app
    run_simctl 60 launch "$udid" com.dandibbert.pupudiary --uitesting --screen home
    sleep 3
    run_simctl 30 io "$udid" screenshot "$OUTPUT/${role}-home-dark.png"
    run_simctl 30 ui "$udid" appearance light
    for screen in home record; do
      terminate_app
      run_simctl 60 launch "$udid" com.dandibbert.pupudiary --uitesting --screen "$screen" --large-type
      sleep 3
      run_simctl 30 io "$udid" screenshot "$OUTPUT/${role}-${screen}-large-type.png"
    done
  fi
  terminate_app
  run_simctl 30 shutdown "$udid"
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
