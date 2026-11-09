# BeamADB desktop architecture

The Flutter application in `desktop/` is independent of the legacy Python HTTP server.
The original CLI and web sources remain for migration reference. `launch.sh` launches
only the native release. No HTTP device-control endpoint is started.

## Layers

- `core/adb.dart`: argument-based subprocesses, bounded output, timeouts, cancellation,
  Android semantic-error detection, device/service parsers and protected remote paths.
- `core/store.dart`: device selection, metadata, operation history, preferences,
  active sessions and shutdown ownership.
- `core/media_session.dart`: version-matched bundled scrcpy server, unique Android
  server file/socket, ADB port forward, handshake, raw H.264/PCM transport, native
  libmpv decoding through media_kit textures, control messages and recording.
- `features/`: desktop screens, file/app actions, pairing and developer workspaces.

## Media

The private player accepts only an application-generated loopback TCP URL. The relay
binds IPv4 loopback on an ephemeral port and accepts one consumer. It is not a remote
control server. A scrcpy dummy-byte handshake validates Android readiness before
opening the control connection. Streams are decoded natively; frame pixels do not
pass through Dart. The Dart transport strips only the handshake and forwards bytes.
Video and audio use independent sessions. Screen input uses scrcpy control messages.

The capture server version is read from its bundled companion client. Both artifacts
must be upgraded together, with transport tests and real-phone tests. Current Linux
bundle reports scrcpy 5.0.1. Do not silently replace only the server.

Separate windows currently use independent native application processes and restart
the selected stream. They do not reparent X11 windows. Sessions in the main workspace
are retained across device selection. Each process owns and cleans up its own sessions;
it never kills the shared ADB daemon on exit.

## Runtime dependencies

Flutter, media_kit, file_selector, window_manager and preferences support Linux and
Windows. Linux uses libmpv and GTK. `tools/prepare-media-linux.sh` can extract Ubuntu
packages into a git-ignored local cache without system installation. The bundle copies
these runtime libraries plus their Debian copyright files. Build on the oldest Linux
release you intend to support; a build made on Ubuntu 26.04 is not claimed compatible
with older Ubuntu releases.

Original BeamADB source licensing remains in LICENSE. Inter uses the included OFL.
Native media packages retain their own licenses and corresponding upstream/source
package references; Debian's libmpv package includes GPL components. Public release
packaging must preserve the applicable source and redistribution requirements.

## Verification boundary

Native synthetic-stream tests verify decoder, texture, transport and control framing.
They do not prove Android camera/audio permissions, OEM encoder support, physical input
behavior or discovery on a real network. Windows runners are present but unverified
until built and exercised on Windows.
