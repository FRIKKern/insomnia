# For AI agents working in this repo

**Build and verify**

```sh
./build.sh                                      # universal build, installs to ~/Applications, replaces running copy
pmset -g assertions | grep "Insomnia keeps"     # 2 lines while on
./test.sh                                       # full guard matrix; needs the sudo rule for lid tests
```

**Layout**: `Sources/main.m` is the whole app. `install.sh` / `uninstall.sh` are the public installers. `release.sh` cuts a release. `tools/mkicon.m` renders `AppIcon.icns`. The Homebrew formula lives in `FRIKKern/homebrew-tap`, bumped automatically by that repo's workflow after a tag.

**Invariants that must hold after any change**

1. Off, quit, and next launch always clear `pmset disablesleep`. Verify: `pmset -g | grep SleepDisabled` shows 0 after `open insomnia://off`.
2. Guards pause only the lid override, only on battery. Plain idle-sleep assertions are unaffected.
3. The thermal pause is held until lid open or AC. It must not oscillate.
4. Every external signal has a debug hook (`insomnia.debug.power|lid|thermal|net`) so it can be simulated.
5. The app builds with clang alone. No Swift, no packages, no Xcode project.

**Driving the app from a shell**: `open insomnia://on|off|toggle|lid-on|lid-off|login-on|login-off|update|quit`.

**Installing for a user**: `curl -fsSL https://raw.githubusercontent.com/FRIKKern/insomnia/main/install.sh | INSOMNIA_LOGIN=1 sh`. Only `lid-on` / `INSOMNIA_LID=1` prompts for a password; warn the user first.
