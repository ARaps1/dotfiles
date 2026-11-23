#!/bin/bash
# Prints {"dibs":[…sim-dibs files…],"running":[{id,platform,name}]} for the agents-sims mod.
# Dibs come from sim-dibs' state folder; running devices from simctl and adb.
dir="${XDG_STATE_HOME:-$HOME/.local/state}/sim-dibs"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
adb="$sdk/platform-tools/adb"

dibs=$(for f in "$dir"/*.json; do [ -f "$f" ] && jq -c . "$f" 2>/dev/null; done | jq -sc .)

ios=$(xcrun simctl list devices booted -j 2>/dev/null | jq -c '[
  .devices | to_entries[] | select(.key | test("SimRuntime.iOS")) |
  (.key | capture("iOS-(?<a>[0-9]+)-(?<b>[0-9]+)") | "\(.a).\(.b)") as $os |
  .value[] | select(.state == "Booted") | {id: .udid, platform: "ios", name: "\(.name) (iOS \($os))"}]' 2>/dev/null)

android="[]"
if [ -x "$adb" ]; then
  android=$(for s in $("$adb" devices 2>/dev/null | awk '/^emulator-.*device$/ {print $1}'); do
    a=$("$adb" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')
    [ -n "$a" ] && jq -nc --arg a "$a" --arg s "$s" '{id: "avd:\($a)", platform: "android", name: ($a | gsub("_"; " ")), serial: $s}'
  done | jq -sc .)
fi

# The device limit: SIM_DIBS_MAX, else sim-dibs' own default.
max="${SIM_DIBS_MAX:-$(sed -n 's/^MAX="\${SIM_DIBS_MAX:-\([0-9]*\)}"$/\1/p' "$(command -v sim-dibs)" 2>/dev/null)}"

jq -nc --argjson d "${dibs:-[]}" --argjson i "${ios:-[]}" --argjson a "${android:-[]}" --argjson m "${max:-5}" '{dibs: $d, running: ($i + $a), max: $m}'
