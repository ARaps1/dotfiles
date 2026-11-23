#!/bin/bash
# Local patch: boot a device picked in the herdr-sim pane through sim-dibs, so slimming
# (simslim.json / avdslim.json) and the device limit (SIM_DIBS_MAX) live in one place.
#   pane-claim.sh <udid|avd:name> [folder...]
# Runs from the first folder whose git root has a slim profile, so sim-dibs finds it.
# The pane holds the device as "wt:herdr-sim-pane": sim-dibs frees it after 30 minutes
# unused, and an agent that needs it gets it then (or asks: sim-dibs status shows it).
id="$1"; shift
dir=""
for d in "$@"; do
  root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || continue
  if [ -f "$root/simslim.json" ] || [ -f "$root/avdslim.json" ]; then dir="$root"; break; fi
  [ -n "$dir" ] || dir="$root"
done
cd "${dir:-$HOME}" || exit 1
HC_TERMINAL_ID="wt:herdr-sim-pane" exec sim-dibs claim "$id"
