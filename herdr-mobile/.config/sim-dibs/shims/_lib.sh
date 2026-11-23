# Shared by the sim-dibs shims. Each shim takes the calling Herdr terminal's lease
# (sim-dibs device ...) and points the real tool at the leased device, so any agent
# or shell drives only its own simulator. SIM_DIBS_BYPASS=1 runs the real tool
# untouched (sim-dibs sets it for itself and everything it starts).
SHIMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"

# real_tool <name> [fallback path]: the first <name> on PATH that isn't a shim.
real_tool() {
  local p IFS=:
  for p in $PATH; do
    [ "$p" = "$SHIMS" ] && continue
    [ -x "$p/$1" ] && [ ! -d "$p/$1" ] && { echo "$p/$1"; return; }
  done
  [ -n "${2:-}" ] && [ -x "$2" ] && echo "$2"
}

# lease <ios|android|udid|avd:name>: print the device's address, or explain and exit 3.
lease() {
  local addr
  addr=$(sim-dibs device "$1") || { echo "sim-dibs: no $1 device for this terminal (see above)." >&2; exit 3; }
  echo "$addr"
}

is_udid() { [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; }

# The one device this terminal holds, if exactly one: "<platform> <address>".
only_device() {
  local ids; ids=$(sim-dibs mine)
  [ "$(printf '%s\n' "$ids" | grep -c .)" = 1 ] || return 1
  case "$ids" in
    avd:*) local a; a=$(lease "$ids") || return 3; echo "android $a" ;;
    *) echo "ios $ids" ;;
  esac
}

# check_target <udid|emulator-NNNN|other>: an explicit device must be ours (claims it if free).
check_target() {
  local avd
  if is_udid "$1"; then lease "$1" >/dev/null
  elif [[ "$1" == emulator-* ]]; then
    avd=$(SIM_DIBS_BYPASS=1 "$SDK/platform-tools/adb" -s "$1" emu avd name 2>/dev/null | head -1 | tr -d '\r')
    [ -z "$avd" ] || lease "avd:$avd" >/dev/null
  fi
}

# target_for <platform flag value or empty>: "<platform> <address>" for this terminal,
# from the platform given, else the one device it holds. Returns 1 when there's
# nothing to pick (let the tool choose), 3 when the lease was refused (stop).
target_for() {
  local a
  case "$1" in
    ios|android) a=$(lease "$1") || return 3; echo "$1 $a" ;;
    *) only_device ;;
  esac
}
