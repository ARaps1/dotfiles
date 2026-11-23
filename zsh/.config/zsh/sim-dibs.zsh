# sim-dibs shims (adb, xcrun simctl, emulator, maestro, agent-device) go first on PATH,
# so every agent or shell drives only the simulator its Herdr terminal leases.
# Only where the opt-in herdr-mobile package is installed; a no-op everywhere else.
if [ -d "$HOME/.config/sim-dibs/shims" ]; then
  export PATH="$HOME/.config/sim-dibs/shims:$PATH"
fi
