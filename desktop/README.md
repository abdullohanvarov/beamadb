# BeamADB Desktop 2.0 preview

Standalone Flutter application for Linux and Windows. Everyday phone access is the
primary workspace; engineering tools live under Developer Tools. The desktop runtime
does not start the legacy Python HTTP server.

## Build on Linux

Install Flutter's Linux desktop prerequisites and libmpv development headers. On a
supported Ubuntu/Debian system, `../tools/prepare-media-linux.sh` can instead prepare a
local media dependency cache without sudo. The current bundle was built on Ubuntu
26.04 x86-64; older distributions require a build against their own baseline.

From the repository root:

```sh
tools/prepare-media-linux.sh  # optional if libmpv-dev is already installed
FLUTTER_BIN=/path/to/flutter tools/build-desktop-linux.sh
./launch.sh
# Optional Debian package:
tools/package-desktop-linux.sh
```

The complete bundle is `desktop/build/linux/x64/release/bundle/`. Keep its `lib`,
`data`, `bin`, and `licenses` directories beside the executable. Use its `beamadb`
launcher, which sets the local media-library path.

## Windows

A Windows runner and Windows-compatible Flutter dependencies are included. Build on
Windows with the Flutter/Visual Studio desktop toolchain. Put the matching tools from
`bin/scrcpy/windows` under `bin/scrcpy/windows` beside the built executable. Windows is
not yet runtime-verified in this Linux environment.

## Verification

```sh
cd desktop
flutter analyze
flutter test test
# Native tests need libmpv plus a generated raw H.264 sample:
ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30 -t 4 \
  -c:v libx264 -preset ultrafast -tune zerolatency -f h264 \
  /tmp/beamadb-sample.h264 -y
flutter test integration_test/desktop_smoke_test.dart -d linux
```

When using the local dependency cache, export `PKG_CONFIG_PATH` to `.native/pkgconfig`
and `LD_LIBRARY_PATH` to `.native/root/usr/lib/x86_64-linux-gnu` for native tests.

See `../docs/DESKTOP_STATUS.md` for implemented capabilities and verification limits,
and `../docs/DESKTOP_ARCHITECTURE.md` for media transport and process ownership.
