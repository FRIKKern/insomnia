# Security

## What Insomnia touches

- **Power assertions** via IOKit: process-scoped, gone when the app exits.
- **Optional sudo rule** at `/etc/sudoers.d/insomnia`, written only when you enable *Keep Awake With Lid Closed* and only after macOS's own admin password dialog. It permits exactly two commands: `/usr/bin/pmset -a disablesleep 1` and `/usr/bin/pmset -a disablesleep 0`. No shell, no wildcards. Remove with `sudo rm /etc/sudoers.d/insomnia`.
- **Network**: one HTTPS request to `api.github.com` for the update check, daily by default (toggle *Check Daily* in the *Updates* submenu to turn it off). Nothing is sent except the request itself. Updates run the public `install.sh` from this repository over HTTPS and build from source on your Mac.
- **Preferences** in `~/Library/Preferences/no.guerrilla.insomnia.plist`.

No telemetry, no accounts, no background daemon beyond the app itself.

## Reporting

Open a GitHub issue, or if it is sensitive, email the address on the maintainer's GitHub profile.
