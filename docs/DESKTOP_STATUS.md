# Desktop rebuild status

## Implemented in the Linux preview

- Native Flutter desktop workspace with light/dark/system themes, bundled Inter font,
  keyboard focus, reduced-motion setting, and responsive 900×620 minimum layout.
- USB device selection, discovery, secure QR session generation/expiry, manual pairing,
  direct connection, and USB-to-wireless migration with a connection-readiness check.
- Embedded H.264 screen/camera playback, native texture decoding, aspect-ratio updates,
  screen touch/key/scroll controls, explicit clipboard paste, resolution/FPS/bitrate
  preferences, stay-awake preference, phone display power, fullscreen, and screenshots.
- Independent raw PCM phone playback/microphone sessions with explicit start and mute.
- Stream recording via native remuxing, separate session windows (restart on move),
  retained main-window sessions across device selection and resource cleanup.
- File browsing, editable path/history/shortcuts/filtering, multiple selection,
  uploads/downloads, recursive folder transfer, collision choices, rename, copy, move,
  protected deletion, and bounded image/text previews.
- APK/split-APK installation, package search, user/system separation, launch, force stop,
  data clearing, uninstall, package details and APK export.
- Bounded live Logcat, severity/text filtering, pause-display and export.
- Cancellable shell commands/history; diagnostics, bug reports, performance trace
  capture, port forward/reverse inspection and management, permissions, deep links,
  instrumentation tests and reviewed sequential shell workflows.
- Operation history, persistent failure banners, cancellation, timeouts, bounded command
  output, Android semantic-failure detection, custom ADB path and diagnostic summary.
- Linux build/package scripts, bundled platform tools, Windows runner and dependency
  groundwork. No HTTP control server in the desktop runtime.

## Verification

Passed on the available Linux environment:

- Flutter analyzer: no issues found in the final release build.
- 10 unit/widget tests: device and service parsing, address validation, quoting,
  protected paths, command failures/timeouts, semantic Android errors and layouts.
- 4 native integration tests: navigation/screenshot, H.264 texture decoding, simulated
  scrcpy handshake/video/control/recording/cleanup, and PCM decoding/mute/cleanup.

Synthetic media verifies the native desktop path but does not replace phone testing.
The final release launcher was also opened successfully for a ten-second startup check.
The Linux amd64 Debian preview package was generated without system installation.

No Android phone was present in the ADB device list during implementation. Pairing,
camera hardware, real-phone audio restrictions, physical input/rotation and file/app
operations still require real-device verification. No user device data was modified.
Windows has not been built or tested here.

## Remaining work from the broader product plan

This is a functional preview foundation, not completion of every planned enhancement.

- Validate Linux device workflows on actual phones and multiple Android versions.
- Build/test Windows; validate separate-window behavior on both platforms.
- Smooth detach/reattach without restarting, window geometry persistence and a
  multi-stream grid workspace.
- Camera capability enumeration/custom sensor modes and an audio level meter.
- Integrated audio/video recording synchronization and richer capture library.
- Exact byte-based transfer speed/ETA, bounded queued scheduling, durable retry history,
  grid file view/thumbnails and additional sorting controls.
- Friendly application labels/icons and richer package/permission summaries.
- Stable device aliases and complete per-device settings persistence.
- PTY-style interactive shell, app/process Logcat selectors, regex filters and richer
  crash grouping. The current shell is a command runner, not a full terminal emulator.
- Typed APK/test workflow steps, reusable variables, workflow editing and controlled
  multi-device workflow concurrency. Current workflows are reviewed shell sequences.
- Cross-distribution packaging/performance benchmarks and broad Wayland/X11/GPU testing.

Virtual webcam output is outside this preview; camera preview does not create a system
webcam device. Android's permission/private-data limits remain in force.
