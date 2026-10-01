# Changelog

All notable changes to Insomnia. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.3.0] - 2026-10-01

### Added
- *Awake While Agents Work* (default off, remembered): Insomnia holds its assertions whenever any agent session on the Mac is working, and releases them once every session has been idle for a quiet period (5, 10, 20 or 30 minutes; default 10). Agent state comes from `minmacs agents --json`, polled every 15 s while the mode is on; a missing binary, non-zero exit or bad JSON counts as no agents. Without MinMacs the submenu shows *Needs MinMacs: brew install frikkern/tap/minmacs*.
- The manual toggle still wins: agent mode only acts while Insomnia is switched off. The lid setting and all four guards keep applying whenever assertions are held.
- Menu header shows the state while the mode is on, for example "Agents: 2 working · awake" or "Agents idle 4 min · releasing at 10".
- `insomnia://agents-on` and `insomnia://agents-off`.
- Debug hook `insomnia.debug.agents` = *integer* replaces the minmacs call.
- `./test.sh`: agent mode checks (hold, quiet-period release, manual wins, mode off, lid override and guards under an agent hold).

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
