#!/bin/bash
#
# Turns on Midmar Trainer's automatic reinstall: your Mac rebuilds Midmar Trainer and
# installs it over the copy on your iPhone every few days, so a free Apple ID's
# 7-day signature never runs out. New versions of the code are installed too.
#
#   bash "~/Documents/Swimming App/Tools"/install-auto-reinstall.sh          turn it on
#   bash "~/Documents/Swimming App/Tools"/install-auto-reinstall.sh --off    turn it off
#
# Why a small app: the project lives in Documents, which macOS only lets apps
# you've approved read. A background job can't be approved; a tiny app can,
# once. It has no window or Dock icon, and does nothing but run
# reinstall-midmar.sh.

set -euo pipefail

TOOLS="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$TOOLS/reinstall-midmar.sh"
LABEL="com.camjones.midmartrainer.reinstall"
SUPPORT="$HOME/Library/Application Support/Midmar Reinstall"
APPLET="$SUPPORT/Midmar Reinstaller.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/MidmarTrainer"
DOMAIN="gui/$(id -u)"

turn_off() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$AGENT"
}

case "${1:-}" in
    --off|--uninstall)
        turn_off
        echo "Automatic reinstall is off. Midmar Trainer stays on your phone until its signature runs out."
        exit 0 ;;
    "") ;;
    *) echo "Usage: $0 [--off]"; exit 2 ;;
esac

# ---- Checks

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Xcode's command-line tools aren't set up. Run:"
    echo "    sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi
if ! xcrun --find devicectl >/dev/null 2>&1; then
    echo "This needs Xcode 15 or later (for installing over Wi-Fi)."
    exit 1
fi
if [ ! -f "$SCRIPT" ]; then
    echo "Can't find $SCRIPT"
    exit 1
fi

chmod +x "$SCRIPT"
mkdir -p "$SUPPORT" "$LOG_DIR" "$HOME/Library/LaunchAgents"

# ---- The small app that runs the script

source_file="$SUPPORT/reinstaller.applescript"
cat > "$source_file" <<EOF
on run
    try
        do shell script "/bin/bash " & quoted form of "$SCRIPT" & " >> " & quoted form of "$LOG_DIR/reinstall-output.log" & " 2>&1"
    end try
end run
EOF

rm -rf "$APPLET"
osacompile -o "$APPLET" "$source_file"
plist="$APPLET/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIdentifier" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.camjones.midmartrainer.reinstaller" "$plist"
/usr/libexec/PlistBuddy -c "Delete :LSUIElement" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist"
codesign --force --deep --sign - "$APPLET" >/dev/null 2>&1

# ---- The schedule: every 3 hours. The script itself does nothing until
# fewer than 3 days are left, so most runs finish in a moment. Runs missed
# while the Mac sleeps happen when it wakes.

turn_off
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>-j</string>
        <string>-a</string>
        <string>$APPLET</string>
    </array>
    <key>StartInterval</key>
    <integer>10800</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/launchd.log</string>
</dict>
</plist>
EOF
plutil -lint "$AGENT" >/dev/null

# ---- First run, now, while you're here

echo
echo "Running it once now. This builds Midmar Trainer and installs it on your iPhone —"
echo "a few minutes the first time."
echo
echo '  • If macOS asks whether "Midmar Reinstaller" can access your Documents'
echo "    folder, choose Allow. It's asked once."
echo "  • Keep your iPhone unlocked and on the same Wi-Fi as this Mac."
echo

open -W "$APPLET"

launchctl bootstrap "$DOMAIN" "$AGENT"

echo
"$SCRIPT" --status
echo
echo "Full build output: $LOG_DIR/last-build.log"
echo "Renew by hand any time:  $SCRIPT --now"
echo "Turn it off:             bash $TOOLS/install-auto-reinstall.sh --off"
