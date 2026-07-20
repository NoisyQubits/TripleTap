# TripleTap

Native macOS proof of concept for triggering Play/Pause with a three-finger
triple tap. The app deliberately loads `MultitouchSupport.framework` at runtime
instead of linking against Apple's private framework.

## Milestone 1

Build and run the loader:

```sh
swift run tripletap
swift run tripletap --symbols
```

`--symbols` asks the system `nm` tool to show exported text symbols. It is a
diagnostic mode only; the application itself resolves APIs with `dlsym`.

> `MultitouchSupport.framework` is a private Apple framework. This proof of
> concept is not suitable for Mac App Store distribution and its APIs can change
> in any macOS release.
