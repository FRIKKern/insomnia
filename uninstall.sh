#!/bin/sh
# Removes Insomnia completely: app, preferences, login item, and the optional sudo rule.
#   curl -fsSL https://raw.githubusercontent.com/FRIKKern/insomnia/main/uninstall.sh | sh
set -u
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
if pgrep -x Insomnia >/dev/null 2>&1; then
  say "Stopping Insomnia (this also restores normal lid sleep)"
  open "insomnia://login-off" 2>/dev/null; sleep 1
  open "insomnia://quit" 2>/dev/null || pkill -x Insomnia; sleep 1
fi
rm -rf "$HOME/Applications/Insomnia.app" "/Applications/Insomnia.app" 2>/dev/null
defaults delete no.guerrilla.insomnia >/dev/null 2>&1
if pmset -g | grep -q "SleepDisabled.*1"; then
  say "Lid override still set; clearing it"
  sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || sudo /usr/bin/pmset -a disablesleep 0
fi
if [ -e /etc/sudoers.d/insomnia ] || sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
  say "Removing the sudo rule (admin password)"
  sudo rm -f /etc/sudoers.d/insomnia
fi
say "Insomnia removed."
