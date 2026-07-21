# TripleTap

TripleTap is a native Swift command-line utility for macOS that sends the
Play/Pause media key when you perform a stationary three-finger click on the
built-in trackpad.

It loads Apple's private `MultitouchSupport.framework` at runtime, recognises a
short three-finger press, rejects swipes, then posts `NX_KEYTYPE_PLAY` through
Quartz Event Services.

## Requirements

- macOS 26 Tahoe on Apple Silicon
- Xcode 26 / Swift 6
- Accessibility permission, if macOS requires it to post the media event

This is a personal proof of concept. `MultitouchSupport.framework` is private
and may change in a future macOS release; the project is not App Store suitable.

## Run

```sh
swift run tripletap --listen
```

The process prints `Three-finger click detected` and sends Play/Pause whenever
it accepts a gesture. Stop it with Control-C. Running the binary with no
arguments behaves the same as `--listen`, which is what the background service
below uses.

## Install with Homebrew

Install from the [NoisyQubits tap](https://github.com/NoisyQubits/homebrew-noisyqubits):

```sh
brew tap noisyqubits/noisyqubits
brew trust noisyqubits/noisyqubits   # required once for third-party taps
brew install tripletap               # add --HEAD to build the latest main
```

## Run in the background

TripleTap runs as a per-user `launchd` LaunchAgent: it starts at login,
restarts if it exits, and lives inside your GUI session so it can post media
keys and hold Accessibility permission.

With Homebrew (uses the formula's `service` block):

```sh
brew services start tripletap    # start now + at login
brew services stop tripletap     # stop + disable
brew services info tripletap     # status; logs at $(brew --prefix)/var/log/tripletap.log
```

Without Homebrew, use the bundled plist:

```sh
swift build -c release
sudo cp .build/release/tripletap /usr/local/bin/tripletap
cp dist/com.noisyqubits.tripletap.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.noisyqubits.tripletap.plist    # start + enable
launchctl unload ~/Library/LaunchAgents/com.noisyqubits.tripletap.plist  # stop + disable
```

Logs go to `/tmp/tripletap.log`. If Play/Pause does not fire, grant the binary
Accessibility permission under System Settings → Privacy & Security.

## Gesture rules

A click is accepted only when it has exactly three fingers, releases within the
configured time limit, does not move beyond the configured distance, and is
outside the cooldown period. Fingers may lift on separate frames.

Default limits:

| Setting | Default |
| --- | --- |
| Press duration | 260 ms |
| Per-finger movement | 0.025 normalized units |
| Cooldown | 250 ms |

Override the two calibration limits when launching:

```sh
swift run tripletap --listen --max-duration-ms 300 --max-movement 0.05
```

## Calibration and diagnostics

Measure real presses without sending a media event:

```sh
swift run tripletap --measure-gesture
```

Trace only gesture transitions and rejection reasons:

```sh
swift run tripletap --listen --debug-gesture
```

Raw touch diagnostics remain available for framework troubleshooting:

```sh
swift run tripletap --frames
swift run tripletap --frames --raw
swift run tripletap --layout
```

## Verify

```sh
swift test
```

The detector tests cover normal and staggered releases, swipes, long presses,
too many fingers, and cooldown handling.
