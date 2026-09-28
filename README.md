# Insomnia

A tiny macOS menu bar app that keeps your laptop awake. One click to toggle.

| Icon | Meaning |
|------|---------|
| moon with a cross above it | Insomnia is **on**. The Mac will not idle-sleep. |
| plain moon | Insomnia is **off**. Normal sleep behaviour. |

- **Left-click** the icon: toggle.
- **Right-click** (or ctrl-click): menu with *Prevent Sleep*, *Keep Awake With Lid Closed*, *Launch at Login*, *Quit*.
- The display may still dim and turn off. That is intended: it saves battery while the system, network and your terminal sessions keep running.
- State is remembered across restarts. Default on first launch is **on**.
- **Scriptable** from any shell, no Accessibility permission needed:

```
open insomnia://on
open insomnia://off
open insomnia://toggle
open insomnia://lid-on     # no confirmation dialog
open insomnia://lid-off
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

## Lid closed

*Keep Awake With Lid Closed* sets `pmset -a disablesleep 1`, which is root-only. The first time you enable it, Insomnia asks for your password once and writes `/etc/sudoers.d/insomnia`, a rule that allows exactly two commands without a password:

```
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
```

After that the toggle is silent. The override is active only while Insomnia is **on** and the lid setting is **on**. Switching Insomnia off, or quitting, clears it, so the laptop sleeps normally on lid close again. A crash or a forced kill does not clear it; run `sudo pmset -a disablesleep 0` by hand in that case. Check with `pmset -g | grep SleepDisabled`.

Running with the lid shut inside a bag makes the machine warm. Remove the rule with `sudo rm /etc/sudoers.d/insomnia`.

## Limits

- An empty battery is not a sleep problem Insomnia can solve. Plug in for long runs.
