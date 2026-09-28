#!/bin/sh
# Guard matrix against the RUNNING Insomnia, using the debug hooks.
# Needs: app installed and launched; the sudo rule for lid tests (else they are skipped).
# Leaves the app with real readings and the state it had before.
set -u
D=no.guerrilla.insomnia
pass=0; fail=0; skip=0
lid()  { pmset -g | grep -q "SleepDisabled.*1" && echo live || echo paused; }
asrt() { pmset -g assertions | grep -c "Insomnia keeps"; }
sync() { open "insomnia://on"; sleep 1.5; }
dbg()  { for kv in "$@"; do defaults write $D "insomnia.debug.${kv%%=*}" "${kv#*=}"; done; sync; }
ago()  { date -u -v-"$1"M +%Y-%m-%dT%H:%M:%SZ; }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-52s %s\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL  %-52s got %s, want %s\n' "$1" "$3" "$2"; fi
}

pgrep -x Insomnia >/dev/null || { echo "Insomnia is not running"; exit 1; }
orig_awake=$(defaults read $D insomnia.awake 2>/dev/null || echo 1)
orig_lid=$(defaults read $D insomnia.lid 2>/dev/null || echo 0)
cleanup() {
  for k in power lid thermal net; do defaults delete $D insomnia.debug.$k >/dev/null 2>&1; done
  for k in lid.minBattery lid.graceMinutes lid.offlineMinutes lid.thermalGuard lid.screenOff unpluggedAt offlineAt; do defaults delete $D insomnia.$k >/dev/null 2>&1; done
  [ "$orig_lid" = "1" ] && defaults write $D insomnia.lid -bool true || defaults write $D insomnia.lid -bool false
  [ "$orig_awake" = "1" ] && open insomnia://on || open insomnia://off
}
trap cleanup EXIT

echo "== toggle"
open insomnia://off; sleep 1.5; check "off releases assertions" 0 "$(asrt)"
open insomnia://on;  sleep 1.5; check "on holds two assertions"  2 "$(asrt)"

if sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
  defaults write $D insomnia.lid -bool true
  echo "== lid coupling"
  dbg power=ac lid=open thermal=nominal net=online; check "AC: override live" live "$(lid)"
  open insomnia://off; sleep 1.5;                      check "off clears override" paused "$(lid)"
  sync;                                                check "on restores override" live "$(lid)"
  echo "== battery guard"
  dbg power=battery:60;                                check "battery 60%, just unplugged" live "$(lid)"
  dbg power=battery:20;                                check "battery 20% (threshold)" paused "$(lid)"
  dbg power=battery:21;                                check "battery 21%" live "$(lid)"
  defaults write $D insomnia.unpluggedAt -date "$(ago 119)"; sync; check "unplugged 1h59 (grace 2h)" live "$(lid)"
  defaults write $D insomnia.unpluggedAt -date "$(ago 121)"; sync; check "unplugged 2h01" paused "$(lid)"
  defaults write $D insomnia.lid.graceMinutes -int 0; sync;        check "grace Never" live "$(lid)"
  dbg power=ac;                                        check "charger back: clock reset" none "$(defaults read $D insomnia.unpluggedAt 2>/dev/null || echo none)"
  echo "== network guard"
  dbg power=battery:70 net=offline;                    check "just offline" live "$(lid)"
  defaults write $D insomnia.offlineAt -date "$(ago 16)"; sync;    check "offline 16 min (grace 15)" paused "$(lid)"
  defaults write $D insomnia.lid.offlineMinutes -int 0; sync;      check "offline Never" live "$(lid)"
  dbg net=online;                                      check "back online" live "$(lid)"
  echo "== bag guard"
  dbg lid=open thermal=serious;                        check "hot, lid open" live "$(lid)"
  dbg lid=closed;                                      check "hot, lid closed" paused "$(lid)"
  dbg thermal=nominal;                                 check "cooled, still closed (hold)" paused "$(lid)"
  dbg lid=open;                                        check "lid opened clears hold" live "$(lid)"
  dbg lid=closed thermal=critical;                     check "critical, closed" paused "$(lid)"
  dbg power=ac;                                        check "AC clears hold" live "$(lid)"
  dbg power=battery:70 lid=closed thermal=serious; defaults write $D insomnia.lid.thermalGuard -bool false; sync
                                                       check "thermal guard disabled" live "$(lid)"
  echo "== screen off while lid closed (screen goes dark for a few seconds)"
  offs() { pmset -g log | grep -cE "Display is turned off"; }
  dbg power=ac lid=open thermal=nominal net=online; caffeinate -u -t 2; sleep 2   # wake display first
  b=$(offs); dbg lid=closed; sleep 2;                  check "lid closed + override live sleeps display" yes "$( [ $(offs) -gt $b ] && echo yes || echo no)"
  dbg lid=open; caffeinate -u -t 2; sleep 1
  defaults write $D insomnia.lid.screenOff -bool false; b=$(offs); dbg lid=closed; sleep 2
                                                       check "option off leaves display alone" yes "$( [ $(offs) -eq $b ] && echo yes || echo no)"
  defaults delete $D insomnia.lid.screenOff; dbg lid=open; caffeinate -u -t 1
  echo "== self-heal"
  defaults write $D insomnia.lid -bool false; sudo -n /usr/bin/pmset -a disablesleep 1
  open insomnia://quit; sleep 1.5; open ~/Applications/Insomnia.app; sleep 2.5
  check "stale override healed on launch" paused "$(lid)"
else
  skip=1; echo "== lid tests skipped (sudo rule not installed; enable Keep Awake With Lid Closed once)"
fi

echo; echo "passed $pass, failed $fail$( [ $skip = 1 ] && echo ', lid tests skipped')"
[ $fail = 0 ]
