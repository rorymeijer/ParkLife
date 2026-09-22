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
#
# The script fails loudly. A shot that cannot be taken exits non-zero, because a capture job that
# reports success while producing nothing is worse than one that reports failure.
set -uo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-docs/screenshots}"
BUNDLE_ID="com.parklife.game"
DERIVED="$(pwd)/.build/screenshots-dd"
LOGS="$(pwd)/.build/screenshot-logs"
# How long to wait for the app to finish its simulated warm-up and print its ready marker.
READY_TIMEOUT="${PARKLIFE_READY_TIMEOUT:-240}"
# A rendered park compresses to roughly 0.18-0.39 bytes per pixel; the blank launch screen the
# first working run captured came out at 0.022. Judging density rather than absolute size keeps
# the check honest across devices and resolutions.
MIN_BYTES_PER_PIXEL=0.05
# How many times to re-capture when the frame still looks blank.
CAPTURE_ATTEMPTS=4

mkdir -p "$OUT" "$LOGS"

log() { printf '\033[1m▸ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }

FAILURES=0

# Newest-runtime device whose name starts with one of the given prefixes, in preference order.
#
# Matching is by prefix so that "iPad Pro 13-inch" finds "iPad Pro 13-inch (M5)" — the runners get
# new hardware generations every few months and an exact-name list goes stale silently. That is
# precisely how the first version of this script captured nothing while passing.
resolve_device() {
    xcrun simctl list devices available -j \
    | python3 -c '
import json, re, sys

prefixes = sys.argv[1:]
data = json.load(sys.stdin)["devices"]


def runtime_key(runtime):
    numbers = re.findall(r"\d+", runtime)
    return tuple(int(n) for n in numbers) if numbers else (0,)


def shape_score(name, prefix):
    # Prefer a mainstream model over a small or cut-down one when falling back to a bare
    # "iPad" / "iPhone" prefix.
    score = 0
    if "mini" in name:
        score -= 3
    if re.search(r"\bSE\b", name):
        score -= 3
    if re.search(r"^iPhone \d+e\b", name):
        score -= 2
    if "Pro" in name:
        score += 2
    # The plain model beats its Max sibling: "iPhone 17 Pro" should not silently become a
    # "iPhone 17 Pro Max" just because the name sorts later.
    rest = name[len(prefix):].strip()
    if rest == "" or rest.startswith("("):
        score += 4
    return score


best = None
for index, prefix in enumerate(prefixes):
    for runtime, devices in data.items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            name = device.get("name", "")
            if not device.get("isAvailable"):
                continue
            if not name.startswith(prefix):
                continue
            key = (-index, runtime_key(runtime), shape_score(name, prefix), name)
            if best is None or key > best[0]:
                best = (key, device["udid"], name, runtime)
    if best is not None:
        # An earlier prefix wins outright; do not let a later one override it.
        break

if best is None:
    sys.exit(1)
print(best[1], best[3], best[2])
' "$@"
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
    fail "build failed"
    exit "$build_status"
fi

APP="$DERIVED/Build/Products/Debug-iphonesimulator/ParkLife.app"
[ -d "$APP" ] || { fail "app not found at $APP"; exit 1; }

# Waits for the app to print its ready marker. Returns non-zero if it never does.
wait_for_ready() {
    local logfile="$1"
    local waited=0
    while [ "$waited" -lt "$READY_TIMEOUT" ]; do
        if grep -q "PARKLIFE_SCENE_DRAWN" "$logfile" 2>/dev/null; then
            echo "  ready after ${waited}s"
            # One more beat so SpriteKit has drawn the frame behind the marker.
            sleep 3
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

# Succeeds when the PNG carries enough detail per pixel to be a real frame.
frame_has_content() {
    python3 -c '
import struct, sys

path, floor = sys.argv[1], float(sys.argv[2])
with open(path, "rb") as handle:
    data = handle.read()
if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
    print("not a PNG")
    raise SystemExit(1)
width, height = struct.unpack(">II", data[16:24])
if width == 0 or height == 0:
    print("zero-sized image")
    raise SystemExit(1)
density = len(data) / (width * height)
print("%dx%d, %.4f bytes/pixel" % (width, height, density))
raise SystemExit(0 if density >= floor else 1)
' "$1" "$MIN_BYTES_PER_PIXEL"
}

# shot <file> <device-prefix...> -- <launch args...>
shot() {
    local file="$1"; shift
    local prefixes=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do prefixes+=("$1"); shift; done
    shift || true
    local args=("$@")

    local resolved udid runtime name
    if ! resolved="$(resolve_device "${prefixes[@]}")"; then
        fail "$file: no simulator matches any of: ${prefixes[*]}"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
    read -r udid runtime name <<<"$resolved"

    log "$file  ($name, $runtime)"
    local logfile="$LOGS/${file%.png}.log"
    rm -f "$logfile" "$OUT/$file"

    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
    if ! xcrun simctl install "$udid" "$APP"; then
        fail "$file: install failed"
        FAILURES=$((FAILURES + 1))
        return 1
    fi

    xcrun simctl launch --console-pty "$udid" "$BUNDLE_ID" "${args[@]}" >"$logfile" 2>&1 &
    local launch_pid=$!

    local status=1
    if ! wait_for_ready "$logfile"; then
        fail "$file: app never reported ready within ${READY_TIMEOUT}s"
    else
        local attempt=1
        while [ "$attempt" -le "$CAPTURE_ATTEMPTS" ]; do
            if ! xcrun simctl io "$udid" screenshot "$OUT/$file" >/dev/null 2>&1; then
                fail "$file: simctl io screenshot failed (attempt $attempt)"
            else
                local detail
                if detail="$(frame_has_content "$OUT/$file")"; then
                    echo "  captured $OUT/$file ($detail)"
                    status=0
                    break
                fi
                echo "  attempt $attempt looks blank ($detail), waiting for the frame" >&2
            fi
            attempt=$((attempt + 1))
            sleep 5
        done
        if [ "$status" -ne 0 ]; then
            fail "$file: still blank after ${CAPTURE_ATTEMPTS} attempts — the app never drew"
        fi
    fi

    kill "$launch_pid" >/dev/null 2>&1
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1
    xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1

    if [ "$status" -ne 0 ]; then
        echo "--- app log tail ---" >&2
        tail -30 "$logfile" 2>/dev/null | sed 's/^/    app: /' >&2
        FAILURES=$((FAILURES + 1))
    fi
    return "$status"
}

IPAD=("iPad Pro 13-inch" "iPad Pro (12.9-inch)" "iPad Air 13-inch" "iPad Pro 11-inch" "iPad Air 11-inch" "iPad Pro" "iPad Air" "iPad")
IPHONE=("iPhone 17 Pro" "iPhone 16 Pro" "iPhone 15 Pro" "iPhone")

shot "01-ipad-park-and-bookings.png" "${IPAD[@]}" -- \
    -parklife-screenshot -parklife-warmup-days 40 -parklife-panel reservations \
    -parklife-select cottage -parklife-zoom 0.55

shot "02-ipad-park-panel.png" "${IPAD[@]}" -- \
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

ls -la "$OUT"/*.png 2>/dev/null || true

if [ "$FAILURES" -ne 0 ]; then
    fail "$FAILURES screenshot(s) could not be captured"
    exit 1
fi
log "Done — all screenshots captured"
