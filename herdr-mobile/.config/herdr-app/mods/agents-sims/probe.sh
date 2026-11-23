#!/bin/bash
# Prints sim-dibs' own view for the agents-sims mod: valid leases only (sim-dibs judges
# them), running devices with when each went unheld, the device limit, and the idle
# time before an unheld device shuts down.
exec "$HOME/.local/bin/sim-dibs" leases --json
