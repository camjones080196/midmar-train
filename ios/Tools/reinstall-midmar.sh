#!/bin/bash
#
# Keeps Midmar Trainer installed on a free Apple ID.
#
# A free account signs apps for 7 days. This rebuilds Midmar Trainer and installs it
# over the copy on your iPhone, over Wi-Fi, a few days before that runs out.
# Installing over the app keeps everything in it — nothing is deleted.
#
# It's run every few hours by the agent install-auto-reinstall.sh sets up, and
# does nothing until the installed copy has less than three days left.
#
#   Tools/reinstall-midmar.sh            renew if it's due
#   Tools/reinstall-midmar.sh --now      renew now, whatever's left
#   Tools/reinstall-midmar.sh --status   when the installed copy runs out
#
# Written for the bash that ships with macOS (3.2).

set -u

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="MidmarTrainer"
BUNDLE_ID="com.camjones.midmartrainer"
TEAM="8AZVURV6A4"

# Set MIDMAR_DEVICE to the iPhone's name if more than one is paired with this Mac.
DEVICE_WANTED="${MIDMAR_DEVICE:-}"

SUPPORT="$HOME/Library/Application Support/Midmar Reinstall"
LOG_DIR="$HOME/Library/Logs/MidmarTrainer"
LOG="$LOG_DIR/reinstall.log"
BUILD_LOG="$LOG_DIR/last-build.log"
DERIVED="$SUPPORT/DerivedData"
STATE="$SUPPORT/installed-until"   # when the copy on the phone stops opening (epoch seconds)
ATTEMPT="$SUPPORT/last-attempt"
SOURCE_STAMP="$SUPPORT/installed-source"   # fingerprint of the code that is on the phone
LOCK="$SUPPORT/lock"

DAY=86400
RENEW_WINDOW=$((3 * DAY))     # renew once less than this is left
RETRY_GAP=$((4 * 3600))       # between builds that didn't get a fresh signature
WARN_WINDOW=$((36 * 3600))    # only notify about trouble once it's this close
FRESH=$((5 * DAY))            # a newly issued free profile has about 7 days

PY=/usr/bin/python3
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"

# ---------------------------------------------------------------- helpers

log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M')  $*"
    echo "$line" >> "$LOG"
    [ -t 1 ] && echo "$line"
    return 0
}

notify() {
    # Messages here are this script's own, without double quotes.
    /usr/bin/osascript -e "display notification \"$1\" with title \"Midmar Trainer\"" >/dev/null 2>&1 || true
}

when() {
    date -r "$1" '+%a %e %b, %H:%M' | tr -s ' '
}

# Runs a command, stopping it after a number of seconds. macOS has no `timeout`.
with_timeout() {
    local secs=$1; shift
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    local watcher=$!
    wait "$pid"
    local status=$?
    kill "$watcher" 2>/dev/null
    wait "$watcher" 2>/dev/null
    return $status
}

installed_until() {
    local value
    value="$(cat "$STATE" 2>/dev/null)"
    case "$value" in ''|*[!0-9]*) echo 0 ;; *) echo "$value" ;; esac
}

# Tells you once it matters: only when the copy on the phone is close to
# running out (or has), and only if this script installed it.
warn_if_close() {
    local installed left
    installed="$(installed_until)"
    [ "$installed" -gt 0 ] || return 0
    left=$((installed - $(date +%s)))
    if [ "$left" -le 0 ]; then
        notify "Midmar Trainer has expired on your iPhone. $1"
    elif [ "$left" -lt "$WARN_WINDOW" ]; then
        notify "Midmar Trainer stops opening $(when "$installed"). $1"
    fi
}

take_lock() {
    if ! mkdir "$LOCK" 2>/dev/null; then
        local pid
        pid="$(cat "$LOCK/pid" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            [ -t 1 ] && echo "Another run is already going."
            exit 0
        fi
        rm -rf "$LOCK"
        mkdir "$LOCK" || exit 1
    fi
    echo $$ > "$LOCK/pid"
    trap 'rm -rf "$LOCK"' EXIT
}

# Paired devices, one per line: platform <tab> identifier <tab> name
paired_devices() {
    local json="$SUPPORT/devices.json"
    rm -f "$json"
    with_timeout 60 xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1
    [ -s "$json" ] || return 1
    "$PY" - "$json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if conn.get("pairingState") != "paired":
        continue
    name = d.get("deviceProperties", {}).get("name", "").replace("\t", " ")
    print("\t".join([hw.get("platform", ""), d.get("identifier", ""), name]))
PY
}

# The earliest expiry of every profile inside the app — the phone app's, the
# watch app's and the complication's each run out on their own.
signed_until() {
    "$PY" - "$1" <<'PY'
import calendar, os, plistlib, subprocess, sys
earliest = None
for root, _, files in os.walk(sys.argv[1]):
    if "embedded.mobileprovision" not in files:
        continue
    raw = subprocess.run(["security", "cms", "-D", "-i", os.path.join(root, "embedded.mobileprovision")],
                         capture_output=True).stdout
    try:
        expires = calendar.timegm(plistlib.loads(raw)["ExpirationDate"].utctimetuple())
    except Exception:
        continue
    earliest = expires if earliest is None else min(earliest, expires)
print(earliest or 0)
PY
}

# Moves Xcode's cached profiles for Midmar Trainer aside (not deleted), so the next
# build has to ask Apple for new ones rather than reusing one that's half spent.
set_aside_profiles() {
    "$PY" - "$TEAM" "$BUNDLE_ID" "$SUPPORT/old-profiles" <<'PY'
import os, plistlib, shutil, subprocess, sys, time
team, bundle, dest = sys.argv[1:4]
os.makedirs(dest, exist_ok=True)
home = os.path.expanduser("~")
moved = 0
for folder in ("Library/MobileDevice/Provisioning Profiles",
               "Library/Developer/Xcode/UserData/Provisioning Profiles"):
    folder = os.path.join(home, folder)
    if not os.path.isdir(folder):
        continue
    for name in os.listdir(folder):
        if not name.endswith(".mobileprovision"):
            continue
        path = os.path.join(folder, name)
        raw = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True).stdout
        try:
            profile = plistlib.loads(raw)
        except Exception:
            continue
        app_id = profile.get("Entitlements", {}).get("application-identifier", "")
        if team not in profile.get("TeamIdentifier", []):
            continue
        if app_id == f"{team}.{bundle}" or app_id.startswith(f"{team}.{bundle}."):
            shutil.move(path, os.path.join(dest, f"{int(time.time())}-{name}"))
            moved += 1
print(moved)
PY
}

APP=""
build() {
    log "Building Midmar Trainer…"
    if with_timeout 1800 xcodebuild \
            -project "$PROJECT_DIR/MidmarTrainer.xcodeproj" \
            -scheme "$SCHEME" \
            -configuration Debug \
            -destination 'generic/platform=iOS' \
            -derivedDataPath "$DERIVED" \
            -allowProvisioningUpdates \
            -allowProvisioningDeviceRegistration \
            DEVELOPMENT_TEAM="$TEAM" \
            build > "$BUILD_LOG" 2>&1; then
        APP="$DERIVED/Build/Products/Debug-iphoneos/MidmarTrainer.app"
        if [ -d "$APP" ]; then return 0; fi
        log "The build finished but MidmarTrainer.app isn't where it should be."
        return 1
    fi

    log "The build failed. From $BUILD_LOG:"
    grep -E "error:|Signing|No Account|session has expired" "$BUILD_LOG" | sort -u | tail -n 8 | while IFS= read -r line; do
        log "    $line"
    done
    if grep -qiE "No Account|session has expired|log in|sign in" "$BUILD_LOG"; then
        warn_if_close "Open Xcode, Settings, Accounts and sign in again."
    else
        warn_if_close "The automatic rebuild failed; see Logs/MidmarTrainer/reinstall.log."
    fi
    return 1
}

install_on() {   # device-id, app
    with_timeout 900 xcrun devicectl device install app --device "$1" "$2" >> "$BUILD_LOG" 2>&1
}

status() {
    local installed
    installed="$(installed_until)"
    if [ "$installed" -gt 0 ]; then
        echo "The copy on your iPhone is signed until $(when "$installed")."
        echo "It's renewed once less than $((RENEW_WINDOW / DAY)) days are left."
    else
        echo "Nothing installed by this script yet."
    fi
    if launchctl print "gui/$(id -u)/com.camjones.midmartrainer.reinstall" >/dev/null 2>&1; then
        echo "Automatic reinstall: on."
    else
        echo "Automatic reinstall: off. Turn it on with Tools/install-auto-reinstall.sh"
    fi
    if [ -f "$LOG" ]; then
        echo
        echo "Latest from $LOG:"
        tail -n 8 "$LOG"
    fi
}

# A fingerprint of the app's code, so new versions are installed without waiting.
source_print() {
    (cd "$PROJECT_DIR" && find MidmarTrainer MidmarTrainer.xcodeproj -type f ! -name '.DS_Store' ! -path '*/xcuserdata/*' -print0 \
        | sort -z | xargs -0 shasum 2>/dev/null | shasum | cut -d' ' -f1)
}

# ---------------------------------------------------------------- the run

FORCE=0
case "${1:-}" in
    --now) FORCE=1 ;;
    --status) status; exit 0 ;;
    "") ;;
    *) echo "Usage: $0 [--now | --status]"; exit 2 ;;
esac

mkdir -p "$SUPPORT" "$LOG_DIR"
if [ -f "$LOG" ] && [ "$(stat -f %z "$LOG")" -gt 524288 ]; then
    mv -f "$LOG" "$LOG.1"
fi

take_lock

now="$(date +%s)"
installed="$(installed_until)"
left=$((installed - now))

current_source="$(source_print)"
if [ "$FORCE" -eq 0 ] && [ "$left" -gt "$RENEW_WINDOW" ] && [ -n "$current_source" ] \
        && [ "$current_source" != "$(cat "$SOURCE_STAMP" 2>/dev/null)" ] && [ "$installed" -gt 0 ]; then
    log "The app's code has changed since it was installed; installing the new version."
    FORCE=1
fi
if [ "$FORCE" -eq 0 ]; then
    if [ "$left" -gt "$RENEW_WINDOW" ]; then
        [ -t 1 ] && echo "Signed until $(when "$installed") — not due yet. Use --now to renew anyway."
        exit 0
    fi
    last="$(cat "$ATTEMPT" 2>/dev/null)"
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    if [ $((now - last)) -lt "$RETRY_GAP" ] && [ "$left" -gt $((12 * 3600)) ]; then
        exit 0
    fi
fi

# Find the iPhone first, so nothing is built while it's out of reach.
devices="$(paired_devices)" || devices=""
phone=""; phone_name=""; watch=""
while IFS="$(printf '\t')" read -r platform ident name; do
    [ -n "$ident" ] || continue
    case "$platform" in
        iOS)
            if [ -z "$phone" ]; then
                if [ -z "$DEVICE_WANTED" ] || [ "$name" = "$DEVICE_WANTED" ] || [ "$ident" = "$DEVICE_WANTED" ]; then
                    phone="$ident"; phone_name="$name"
                fi
            fi ;;
        watchOS)
            [ -z "$watch" ] && watch="$ident" ;;
    esac
done <<EOF
$devices
EOF

if [ -z "$phone" ]; then
    log "No paired iPhone found. Plug it in once and open Xcode, Window, Devices and Simulators."
    warn_if_close "Your Mac can't see your iPhone."
    exit 1
fi

if ! with_timeout 60 xcrun devicectl device info details --device "$phone" >/dev/null 2>&1; then
    log "$phone_name isn't reachable right now (off Wi-Fi, or asleep). Will try again later."
    warn_if_close "Your Mac can't reach your iPhone — keep both on the same Wi-Fi."
    exit 1
fi

echo "$now" > "$ATTEMPT"

build || exit 1
until_signed="$(signed_until "$APP")"

# Xcode tends to reuse a profile until it runs out, which would install a copy
# that expires just as soon. Ask for new ones instead.
if [ $((until_signed - now)) -lt "$FRESH" ]; then
    if [ "$until_signed" -gt 0 ]; then
        log "Xcode reused a signature that runs out $(when "$until_signed"); asking Apple for a fresh one."
    fi
    moved="$(set_aside_profiles)"
    log "Set aside ${moved:-0} cached profile(s) in $SUPPORT/old-profiles."
    build || exit 1
    until_signed="$(signed_until "$APP")"
fi

if [ "$until_signed" -le $((now + 3600)) ]; then
    log "The new build's signature has already run out — not installing it."
    warn_if_close "Xcode couldn't get a fresh signature; open Xcode and press Run once."
    exit 1
fi

log "Installing on $phone_name (signed until $(when "$until_signed"))…"
if ! install_on "$phone" "$APP"; then
    sleep 20
    if ! install_on "$phone" "$APP"; then
        log "Installing failed. The end of $BUILD_LOG says:"
        tail -n 6 "$BUILD_LOG" | while IFS= read -r line; do log "    $line"; done
        warn_if_close "Installing failed — unlock your iPhone and it will try again."
        exit 1
    fi
fi

if [ "$until_signed" -gt $((installed + 3600)) ] || [ $((installed - now)) -gt "$RENEW_WINDOW" ]; then
    [ "$until_signed" -gt "$installed" ] || until_signed="$installed"
    echo "$until_signed" > "$STATE"
    echo "$current_source" > "$SOURCE_STAMP"
    rm -f "$ATTEMPT"
    log "Done. Midmar Trainer is good until $(when "$until_signed")."
else
    echo "$current_source" > "$SOURCE_STAMP"
    log "Installed, but Apple sent back the same signature, so it still runs out $(when "$installed"). Will try again."
    warn_if_close "The automatic renewal didn't extend it; press Run in Xcode once."
fi

exit 0
