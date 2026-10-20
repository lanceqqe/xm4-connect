#!/bin/bash
# XM4 Connect — one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/lanceqqe/xm4-connect/main/install.sh | bash
#
# Downloads the latest release, checks its SHA-256 against the checksum published with the
# release, installs "XM4 Connect.app" into /Applications (or ~/Applications if /Applications is
# not writable) and opens it. Nothing else is touched. Read it before running it — it is short.
set -euo pipefail

REPO="lanceqqe/xm4-connect"
ASSET="XM4-Connect-macos.zip"
BASE="https://github.com/$REPO/releases/latest/download"
APP="XM4 Connect.app"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "XM4 Connect runs on macOS only."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || fail "macOS 13 Ventura or newer is required (this Mac runs $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bold "Downloading XM4 Connect…"
curl -fL --progress-bar -o "$tmp/$ASSET" "$BASE/$ASSET" || fail "download failed."
curl -fsSL -o "$tmp/$ASSET.sha256" "$BASE/$ASSET.sha256" || fail "checksum download failed."

bold "Verifying checksum…"
expected=$(awk '{print $1}' "$tmp/$ASSET.sha256")
actual=$(shasum -a 256 "$tmp/$ASSET" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || fail "checksum mismatch — the download is not the published release."
echo "  $actual"

dest="/Applications"
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

bold "Installing to $dest…"
pkill -x XMConnect 2>/dev/null || true
rm -rf "$dest/$APP"
ditto -x -k "$tmp/$ASSET" "$dest"
# Files fetched with curl are not quarantined, so this is normally a no-op. It only clears the
# flag if something else added it, so macOS does not stop the app on first launch.
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

bold "Opening XM4 Connect — look for the headphones icon in the menu bar."
open "$dest/$APP" --args --open

cat <<'EOF'

  • Allow Bluetooth when macOS asks.
  • Make sure your headphones are *connected* to this Mac (System Settings › Bluetooth).
  • Uninstall any time: quit the app and delete "XM4 Connect" from Applications.
EOF
