# sim-dibs

Leases on iOS simulators and Android emulators for Herdr terminals, at most 5 running at once (`SIM_DIBS_MAX`).

- **Lease:** held by a Herdr terminal (`$HC_TERMINAL_ID`). It lasts while that terminal runs a program (any agent: Claude Code, Codex, Cursor, pi, or a command a person runs) and ends when the terminal goes away. When the terminal is back at a bare shell, or the holder is outside Herdr, it ends after 30 minutes without simulator commands (`SIM_DIBS_STALE_MIN`).
- **Shims** (`shims/`, first on `PATH` via `zsh/sim-dibs.zsh`): `adb`, `xcrun simctl`, `emulator`, `maestro` and `agent-device` lease a device for the calling terminal and point the real tool at it. They refuse a device another terminal holds (exit 3) and refuse `simctl shutdown|erase|delete all`. Listing and server commands pass through. `SIM_DIBS_BYPASS=1` skips them.
- **Reaper:** `sim-dibs reap`, run every minute by launchd (`local.sim-dibs.reap`, installed by `setup.sh herdr-mobile`). It ends leases whose terminal is gone and shuts down a device nobody has held for 10 minutes (`SIM_DIBS_IDLE_MIN`, 0 = never). Shutdowns are logged to `~/.local/state/sim-dibs/reap.log`.
- **Herdr:** the agents-sims sidebar shows `sim-dibs leases --json`, including when a free device will shut down. The herdr-sim pane boots through `sim-dibs claim`, and closing the pane releases the pane's own lease.

## Slim profiles

`sim-dibs` slims every simulator it boots. A repo can ship its own `simslim.json` or `avdslim.json` at its git root, and that one wins (fitness-app ships a generated `simslim.json`). Otherwise `sim-dibs` uses the defaults here. `SIM_DIBS_SLIM=0` boots stock.

## simslim.json (iOS, [simslim](https://github.com/mobai-app/simslim))

The format is simslim's own `--profile` file: `except` keeps whole categories, `keep` keeps single daemons. `simslim profiles` lists them.

- `com.apple.apsd`: push notifications (Expo push tokens, remote pushes).
- `com.apple.akd` and `com.apple.appleaccountd`: Sign in with Apple.

## avdslim.json (Android, [avdslim](https://github.com/kdbhalala/avdslim))

avdslim has no profile file, so `sim-dibs` turns these fields into `avdslim start <avd> --headless` flags. `enable` entries first run `avdslim enable <feature> <avd>`, which writes the AVD's `config.ini`.

- `ram: 2048`: a dev build with Hermes, Metro and a camera preview runs out of room at avdslim's 1536 MB default. 2048 MB still saves 1–2 GB against stock AVDs.
- `enable: camera`: avdslim turns the emulated cameras off by default. Apps that record need them.
- `skip: bglimit`: avdslim caps background processes at 4, which can kill the app while Settings, a Custom Tab or the Google account picker is in front.
- Audio stays off, as before. Run `avdslim enable audio <avd>` to test sound.
- Google Play services (sign-in, FCM), WebView and Chrome are never disabled. The profile doesn't pass `--aggressive`.

Use Google APIs images, not Google Play or 16 KB page size (`ps16k`) images, which ignore the RAM limit.
