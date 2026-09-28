#!/bin/sh
# Cuts a release: ./release.sh 1.2.0
# Bumps Info.plist, requires a CHANGELOG entry, commits, tags v1.2.0, pushes.
# GitHub Actions then builds and attaches the zip; the tap workflow picks up the tag.
set -eu
cd "$(dirname "$0")"
V="${1:-}"; case "$V" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "usage: ./release.sh X.Y.Z" >&2; exit 2;; esac
[ "$(git branch --show-current)" = "main" ] || { echo "release from main only" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }
git pull -q --ff-only
grep -q "^## \[$V\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$V]' section" >&2; exit 1; }
BUILD=$(echo "$V" | awk -F. '{printf "%d%02d%02d", $1, $2, $3}')
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" -c "Set :CFBundleVersion $BUILD" Info.plist
sh build.sh --no-install >/dev/null
git add Info.plist && git commit -q -m "Release $V"
git tag -a "v$V" -m "Insomnia $V"
git push -q origin main "v$V"
echo "Released v$V. Watch: gh run watch --repo FRIKKern/insomnia"
echo "Tap bump runs on schedule, or now: gh workflow run bump-insomnia.yml --repo FRIKKern/homebrew-tap"
