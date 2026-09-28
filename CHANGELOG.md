# Changelog

All notable changes to Insomnia. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.2.0] - 2026-09-28

### Added
- *Screen Off While Lid Closed* (default on): sleeps the display the moment the lid closes while the override is live, even when an app holds a display assertion. Lid open wakes it.
- Lid open/close now triggers an immediate guard check via the kernel clamshell notification, instead of waiting for the next power event or minute tick.

## [1.1.0] - 2026-09-28

### Added
- In-app update check: *Updates* submenu with *Check for Updates…*, a daily silent check (toggleable), and one-click *Update* that rebuilds from source locally and relaunches.
- `insomnia://update` URL command.
- `./test.sh`: automated guard matrix against the running app using the debug hooks.
- `./release.sh`: one-command release.
- CHANGELOG, CONTRIBUTING, SECURITY, AGENTS.md, Dependabot for Actions.

## [1.0.0] - 2026-09-28

### Added
- Menu bar toggle holding `PreventUserIdleSystemSleep` and `PreventSystemSleep`.
- Keep Awake With Lid Closed via a two-command sudoers rule, coupled to the main toggle, self-healing on launch.
- Guards on battery: charge threshold, unplugged time, offline time (with *Never*), thermal state with lid closed (held until lid open or AC).
- URL scheme: `on`, `off`, `toggle`, `lid-on`, `lid-off`, `login-on`, `login-off`, `quit`.
- Universal binary. `install.sh` one-liner, `uninstall.sh`, Homebrew tap, GitHub release zip.
