#!/usr/bin/env bash
#
# ParkLife — local verification.
#
# One command to check the project before committing. Runs everything that can run on the
# machine it is invoked from and clearly says what it skipped, so a pass never overstates
# what was actually checked.
#
#   ./Tools/verify.sh            structure + content + core build + core tests
#   ./Tools/verify.sh --app      also builds the iOS app (needs Xcode)
#   ./Tools/verify.sh --quick    structure + content only (no compiler needed)
#
set -uo pipefail

cd "$(dirname "$0")/.."

BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[[ -t 1 ]] || { BOLD=""; RED=""; GREEN=""; YELLOW=""; DIM=""; OFF=""; }

WITH_APP=0
QUICK=0
for argument in "$@"; do
    case "$argument" in
        --app) WITH_APP=1 ;;
        --quick) QUICK=1 ;;
        -h|--help) sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $argument" >&2; exit 2 ;;
    esac
done

FAILED=()
SKIPPED=()
PASSED=()

step() {
    local name="$1"; shift
    printf '%s▸ %s%s\n' "$BOLD" "$name" "$OFF"
    if "$@"; then
        PASSED+=("$name")
        printf '  %s✓ %s%s\n\n' "$GREEN" "$name" "$OFF"
    else
        FAILED+=("$name")
        printf '  %s✗ %s%s\n\n' "$RED" "$name" "$OFF"
    fi
}

skip() {
    SKIPPED+=("$1 — $2")
    printf '%s▸ %s%s\n  %s· skipped: %s%s\n\n' "$BOLD" "$1" "$OFF" "$YELLOW" "$2" "$OFF"
}

# ---------------------------------------------------------------- structure

check_sources() {
    python3 Tools/check_sources.py
}

check_catalog() {
    python3 - <<'PY'
import json, pathlib, sys
failed = False
for path in sorted(pathlib.Path("Sources/ParkLifeCore/Resources/Catalog").glob("*.json")):
    try:
        json.load(open(path))
        print(f"  ok   {path.name}")
    except Exception as error:
        print(f"  FAIL {path.name}: {error}")
        failed = True
sys.exit(1 if failed else 0)
PY
}

if command -v python3 >/dev/null 2>&1; then
    step "Swift source structure" check_sources
    step "Content catalog JSON" check_catalog
else
    skip "Swift source structure" "python3 not found"
    skip "Content catalog JSON" "python3 not found"
fi

# ---------------------------------------------------------------- simulation core

# Keeps the test output so the summary can repeat the failing assertions at the very end.
#
# A CI log is read from the tail. With 225 tests over eleven minutes, a failure two hundred lines
# up is effectively invisible, and working out which test failed cost a whole extra run once.
CORE_TEST_LOG="${TMPDIR:-/tmp}/parklife-core-tests.$$.log"
trap 'rm -f "$CORE_TEST_LOG"' EXIT

run_core_tests() {
    swift test 2>&1 | tee "$CORE_TEST_LOG"
    return "${PIPESTATUS[0]}"
}

# Prints just the failing assertions, if any were recorded.
report_test_failures() {
    [[ -f "$CORE_TEST_LOG" ]] || return 0
    local failures
    failures="$(grep -E ": error: |' failed \(" "$CORE_TEST_LOG" 2>/dev/null || true)"
    [[ -n "$failures" ]] || return 0
    printf '\n%sFailing tests%s\n' "$BOLD" "$OFF"
    printf '%s\n' "$failures" | sed 's/^/  /'
}


if [[ $QUICK -eq 1 ]]; then
    skip "ParkLifeCore build" "--quick"
    skip "ParkLifeCore tests" "--quick"
elif command -v swift >/dev/null 2>&1; then
    printf '%s  using %s%s\n' "$DIM" "$(swift --version 2>&1 | head -1)" "$OFF"
    step "ParkLifeCore build" swift build
    step "ParkLifeCore tests" run_core_tests
else
    skip "ParkLifeCore build" "no swift toolchain on PATH"
    skip "ParkLifeCore tests" "no swift toolchain on PATH"
fi

# ---------------------------------------------------------------- iOS app

build_app() {
    xcodebuild build \
        -project App/ParkLife.xcodeproj \
        -scheme ParkLife \
        -configuration Debug \
        -destination 'generic/platform=iOS Simulator' \
        CODE_SIGNING_ALLOWED=NO \
        | tail -40
    return "${PIPESTATUS[0]}"
}

if [[ $WITH_APP -eq 1 ]]; then
    if command -v xcodebuild >/dev/null 2>&1; then
        step "iOS app build" build_app
    else
        skip "iOS app build" "xcodebuild not found (needs macOS with Xcode)"
    fi
else
    skip "iOS app build" "pass --app to include it"
fi

# ---------------------------------------------------------------- summary

printf '%s────────────────────────────────────────%s\n' "$BOLD" "$OFF"
for name in "${PASSED[@]:-}"; do [[ -n "$name" ]] && printf '%s  ✓ %s%s\n' "$GREEN" "$name" "$OFF"; done
for name in "${SKIPPED[@]:-}"; do [[ -n "$name" ]] && printf '%s  · %s%s\n' "$YELLOW" "$name" "$OFF"; done
for name in "${FAILED[@]:-}";  do [[ -n "$name" ]] && printf '%s  ✗ %s%s\n' "$RED" "$name" "$OFF"; done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    report_test_failures
    printf '\n%s%d check(s) failed.%s\n' "$RED" "${#FAILED[@]}" "$OFF"
    exit 1
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    printf '\n%sAll checks that could run passed. %d were skipped — a pass here does not mean the project compiles.%s\n' \
        "$YELLOW" "${#SKIPPED[@]}" "$OFF"
    exit 0
fi
printf '\n%sEverything passed.%s\n' "$GREEN" "$OFF"
