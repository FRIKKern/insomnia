# Insomnia

A tiny macOS menu bar app that keeps your laptop awake. One click to toggle.

| Icon | Meaning |
|------|---------|
| moon with a cross above it | Insomnia is **on**. The Mac will not idle-sleep. |
| plain moon | Insomnia is **off**. Normal sleep behaviour. |

- **Left-click** the icon: toggle.
- **Right-click** (or ctrl-click): menu with *Prevent Sleep*, *Launch at Login*, *Quit*.
- The display may still dim and turn off. That is intended: it saves battery while the system, network and your terminal sessions keep running.
- State is remembered across restarts. Default on first launch is **on**.
- **Scriptable** from any shell, no Accessibility permission needed:

```
open insomnia://on
open insomnia://off
open insomnia://toggle
```

Under the hood it holds the same two IOKit power assertions as `caffeinate -i -s`:
`PreventUserIdleSystemSleep` always, and `PreventSystemSleep` (effective on AC only). Verify with:

```
pmset -g assertions | grep Insomnia
```

## Build

Needs only Xcode Command Line Tools. Written in Objective-C so it compiles with clang alone.

```
./build.sh        # builds build/Insomnia.app and installs to ~/Applications
open ~/Applications/Insomnia.app
```

Regenerate the app icon (only needed if you change `tools/mkicon.m`):

```
clang -fobjc-arc -framework Cocoa tools/mkicon.m -o build/mkicon && ./build/mkicon
iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
```

## Limits

- Closing the lid still sleeps a MacBook. To override that too: `sudo pmset -a disablesleep 1` (revert with `0`). The machine will run warm in a bag.
- An empty battery is not a sleep problem Insomnia can solve. Plug in for long runs.
