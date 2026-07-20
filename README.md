# TripleTap

Native macOS proof of concept for triggering Play/Pause with a three-finger
triple tap. The app deliberately loads `MultitouchSupport.framework` at runtime
instead of linking against Apple's private framework.

## Milestone 1

Build and run the loader:

```sh
swift run tripletap
swift run tripletap --symbols
swift run tripletap --frames
swift run tripletap --frames --raw
swift run tripletap --layout
swift run tripletap --listen
swift run tripletap --listen --debug-gesture
swift run tripletap --measure-gesture
```

`--symbols` asks the system `nm` tool to show exported text symbols when the
framework is visible as a normal file. It is a diagnostic mode only; the
application itself resolves APIs with `dlsym`. On sealed-system Tahoe installs,
the dynamic loader can expose the framework without making that path available
to command-line file tools, in which case the command reports that limitation.

> `MultitouchSupport.framework` is a private Apple framework. This proof of
> concept is not suitable for Mac App Store distribution and its APIs can change
> in any macOS release.

`--frames` starts each discovered trackpad and prints its raw contacts until the
process is stopped with Control-C. This is the first end-to-end hardware check.
Add `--raw` to print the 96-byte raw record beside its decoded fields. `--layout`
prints the decoder's Swift size, stride, and alignment without starting capture.
`--listen` enables the three-finger-click recognizer without printing every
frame; a recognized click posts the system Play/Pause media key.
Add `--debug-gesture` to trace active-count changes and the recognizer's exact
accept/reject reason without dumping the contact structure.
`--measure-gesture` records completed three-finger press durations without
posting a media event. The default press limit is 260 ms, based on the measured
hard-press samples; the recognizer also rejects movement over 2.5% of the
trackpad's normalized dimensions.

## MTTouch layout

Tahoe's decoder uses the independently documented historical 96-byte layout:
an `Int32` frame, an aligned `Double` timestamp, four `Int32` identity/state
fields, normalized position and velocity, then size and ellipse data. The raw
mode is the authority for validating this assumption on a given macOS build.
