#!/bin/sh
# Builds Insomnia.app into ./build and installs it to ~/Applications.
set -e
cd "$(dirname "$0")"
APP=build/Insomnia.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
clang -fobjc-arc -O2 -Wall -mmacosx-version-min=13.0 \
  -framework Cocoa -framework IOKit -framework ServiceManagement \
  Sources/main.m -o "$APP/Contents/MacOS/Insomnia"
cp Info.plist "$APP/Contents/"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
mkdir -p ~/Applications
rm -rf ~/Applications/Insomnia.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/Insomnia.app"
