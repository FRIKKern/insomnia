#!/bin/sh
# Insomnia installer: builds from source with clang (no Gatekeeper quarantine),
# installs to ~/Applications, launches, and verifies.
#
#   curl -fsSL https://raw.githubusercontent.com/FRIKKern/insomnia/main/install.sh | sh
#
# Options (env vars, so they work through a pipe):
#   INSOMNIA_REF=v1.0.0     git ref to install (default: main)
#   INSOMNIA_NO_LAUNCH=1    build and install only
#   INSOMNIA_LOGIN=1        also register Launch at Login
#   INSOMNIA_LID=1          also enable Keep Awake With Lid Closed (one admin password prompt)
set -eu

REPO="https://github.com/FRIKKern/insomnia"
REF="${INSOMNIA_REF:-main}"
DEST="$HOME/Applications/Insomnia.app"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Insomnia is a macOS app."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 13 ] || die "macOS 13 or newer required (found $(sw_vers -productVersion))."

if ! xcode-select -p >/dev/null 2>&1 || ! command -v clang >/dev/null 2>&1; then
  say "Command Line Tools are missing. Opening Apple's installer; re-run this script when it finishes."
  xcode-select --install 2>/dev/null || true
  die "Command Line Tools not installed yet."
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
say "Fetching $REPO@$REF"
curl -fsSL "$REPO/archive/$REF.tar.gz" | tar -xz -C "$TMP" --strip-components=1

say "Building (clang, universal)"
(cd "$TMP" && sh build.sh --no-install >/dev/null)

if pgrep -x Insomnia >/dev/null 2>&1; then
  say "Stopping running Insomnia"
  open "insomnia://quit" 2>/dev/null || pkill -x Insomnia || true
  sleep 1
fi

say "Installing to $DEST"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$TMP/build/Insomnia.app" "$DEST"

[ "${INSOMNIA_NO_LAUNCH:-0}" = "1" ] && { say "Installed. Launch with: open $DEST"; exit 0; }

say "Launching"
open "$DEST"
sleep 2
[ "${INSOMNIA_LOGIN:-0}" = "1" ] && { open "insomnia://login-on"; say "Registered Launch at Login (macOS may ask you to approve it once)."; }
[ "${INSOMNIA_LID:-0}" = "1" ]   && { open "insomnia://lid-on";   say "Enabling Keep Awake With Lid Closed (admin password prompt on screen)."; }

sleep 1
if pmset -g assertions | grep -q "Insomnia keeps"; then
  say "Verified: Insomnia is running and holding sleep assertions. Look for the moon in your menu bar."
else
  say "Installed and launched. Verify with: pmset -g assertions | grep Insomnia"
fi
