# Insomnia

A tiny macOS menu bar app that keeps your laptop awake. One click to toggle.

| Icon | Meaning |
|------|---------|
| moon with a cross above it | Insomnia is **on**. The Mac will not idle-sleep. |
| moon, cross, and a dot | On, and the lid override is live right now. |
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

After that the toggle is silent. The override is active only while Insomnia is **on**, the lid setting is **on**, and the battery guard is not pausing it. Switching Insomnia off, or quitting, clears it, so the laptop sleeps normally on lid close again. On every launch Insomnia compares the OS setting with its own preferences and repairs it, so a crash or forced kill is healed at the next start. Check with `pmset -g | grep SleepDisabled`.

### Battery guard

Unplugging does not pause the override straight away, so moving rooms or working an hour on battery keeps working. The override pauses when either limit is hit, and re-arms when the charger returns:

| Limit | Default | Menu options |
|-------|---------|--------------|
| battery at or below | 20% | 10, 20, 30, 40, 50 |
| unplugged longer than | 2 hours | 30 min, 1 h, 2 h, 4 h, never |

The unplugged clock is persisted, so a relaunch on battery does not reset it. The submenu *Lid Override on Battery* shows the current state, for example "Unplugged 42 min · battery 63%". Plain idle-sleep prevention is not affected by the guard.

Test hook for simulating power states without unplugging:

```
defaults write no.guerrilla.insomnia insomnia.debug.power battery:15   # or: ac
defaults delete no.guerrilla.insomnia insomnia.debug.power            # back to real readings
```

Running with the lid shut inside a bag makes the machine warm. Remove the rule with `sudo rm /etc/sudoers.d/insomnia`.

## Limits

- An empty battery is not a sleep problem Insomnia can solve. Plug in for long runs.
