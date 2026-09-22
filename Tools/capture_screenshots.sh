#!/usr/bin/env bash
#
# Captures screenshots of the real ParkLife app running in an iOS simulator.
#
# Requires macOS with Xcode. Run from the repository root:
#   ./Tools/capture_screenshots.sh [output-directory]
#
# Each shot boots a simulator, installs the app, launches it with arguments that put it into a
# known state (a warmed-up park, a chosen panel, a selection) and captures the screen. The park in
# the resulting images is a simulation that really ran — that is the whole point of doing it this
# way rather than drawing a mockup.
set -uo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-docs/screenshots}"
BUNDLE_ID="com.parklife.game"
DERIVED="$(pwd)/.build/screenshots-dd"
mkdir -p "$OUT"

log() { printf '\033[1m▸ %s\033[0m\n' "$*"; }

pick_device() {
    # Newest available runtime for the requested device name.
    xcrun simctl list devices available -j \
    | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)['devices']
best = None
for runtime, devices in data.items():
    if 'iOS' not in runtime:
        continue
    for device in devices:
        if device['name'] == name and device['isAvailable']:
            if best is None or runtime > best[0]:
                best = (runtime, device['udid'])
print(best[1] if best else '')
" "$1"
}

resolve_device() {
    for candidate in "$@"; do
        local udid
        udid="$(pick_device "$candidate")"
        if [ -n "$udid" ]; then
            echo "$udid $candidate"
            return 0
        fi
    done
    return 1
}

log "Building ParkLife for the simulator"
xcodebuild build \
    -project App/ParkLife.xcodeproj \
    -scheme ParkLife \
    -configuration Debug \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    | tail -20
build_status="${PIPESTATUS[0]}"
if [ "$build_status" -ne 0 ]; then
    echo "build failed" >&2
    exit "$build_status"
fi

APP="$DERIVED/Build/Products/Debug-iphonesimulator/ParkLife.app"
[ -d "$APP" ] || { echo "app not found at $APP" >&2; exit 1; }

# shot <file> <device-name...> -- <launch args...>
shot() {
    local file="$1"; shift
    local devices=()
    while [ "$1" != "--" ]; do devices+=("$1"); shift; done
    shift
    local args=("$@")

    local resolved udid name
    if ! resolved="$(resolve_device "${devices[@]}")"; then
        echo "  no simulator available among: ${devices[*]}" >&2
        return 1
    fi
    udid="${resolved%% *}"
    name="${resolved#* }"

    log "$file  ($name)"
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" >/dev/null 2>&1
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
    xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1
    xcrun simctl install "$udid" "$APP" >/dev/null
    xcrun simctl launch --console-pty "$udid" "$BUNDLE_ID" "${args[@]}" >/tmp/launch.log 2>&1 &
    local launch_pid=$!

    # The warm-up runs thousands of simulated minutes before the first frame.
    sleep 45
    xcrun simctl io "$udid" screenshot "$OUT/$file" >/dev/null 2>&1 \
        && echo "  captured $OUT/$file" \
        || echo "  FAILED to capture $file" >&2
    kill "$launch_pid" >/dev/null 2>&1
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1
    tail -5 /tmp/launch.log 2>/dev/null | sed 's/^/    app: /'
}

IPAD=("iPad Pro 13-inch (M4)" "iPad Pro (12.9-inch) (6th generation)" "iPad Air 13-inch (M2)" "iPad (10th generation)")
IPHONE=("iPhone 16 Pro" "iPhone 16" "iPhone 15 Pro" "iPhone 15")

shot "01-ipad-park-and-bookings.png" "${IPAD[@]}" -- \
    -parklife-screenshot -parklife-warmup-days 40 -parklife-panel reservations \
    -parklife-select cottage -parklife-zoom 0.55

shot "02-ipad-overlay-and-objectives.png" "${IPAD[@]}" -- \
    -parklife-screenshot -parklife-warmup-days 40 -parklife-panel park \
    -parklife-overlay congestion -parklife-zoom 0.5

shot "03-iphone-build-mode.png" "${IPHONE[@]}" -- \
    -parklife-screenshot -parklife-warmup-days 25 -parklife-build cottage_comfort_4 \
    -parklife-zoom 0.7

shot "04-iphone-finances.png" "${IPHONE[@]}" -- \
    -parklife-screenshot -parklife-warmup-days 40 -parklife-panel finances -parklife-zoom 0.6

shot "05-iphone-guest-inspector.png" "${IPHONE[@]}" -- \
    -parklife-screenshot -parklife-warmup-days 30 -parklife-select guest \
    -parklife-overlay scenery -parklife-zoom 0.8

log "Done"
ls -la "$OUT"/*.png 2>/dev/null || true
