#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/desktop/build/linux/x64/release/bundle"
[[ -x "$BUNDLE/beamadb" ]] || { printf 'Run tools/build-desktop-linux.sh first.\n' >&2; exit 1; }
ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == amd64 ]] || { printf 'The bundled ADB tools currently require amd64.\n' >&2; exit 1; }
VERSION=2.0.0~preview1
STAGE="$ROOT/dist/beamadb-desktop_${VERSION}_${ARCH}"
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/lib/beamadb" "$STAGE/usr/bin" "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/scalable/apps"
cp -a "$BUNDLE/." "$STAGE/usr/lib/beamadb/"
cp "$ROOT/beamadb.desktop" "$STAGE/usr/share/applications/beamadb.desktop"
cp "$ROOT/static/icon.svg" "$STAGE/usr/share/icons/hicolor/scalable/apps/beamadb.svg"
cat > "$STAGE/usr/bin/beamadb-desktop" <<'LAUNCH'
#!/bin/sh
exec /usr/lib/beamadb/beamadb "$@"
LAUNCH
chmod +x "$STAGE/usr/bin/beamadb-desktop"
# Derive runtime package requirements from the actual build host. This avoids
# declaring a platform-specific Flutter/media build architecture-independent.
DEPENDENCIES="$(python3 "$ROOT/tools/runtime-dependencies.py" "$BUNDLE")"
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: beamadb-desktop
Version: $VERSION
Architecture: $ARCH
Section: utils
Priority: optional
Maintainer: BeamADB contributors
Depends: $DEPENDENCIES
Description: Native Android companion and developer workspace (preview)
 Flutter desktop application for Android device access, embedded media,
 file transfers, application management and developer tools.
 This package targets the Linux distribution used to build it.
CONTROL
dpkg-deb --build --root-owner-group "$STAGE" "$ROOT/dist/beamadb-desktop_${VERSION}_${ARCH}.deb"
printf 'Package: %s\n' "$ROOT/dist/beamadb-desktop_${VERSION}_${ARCH}.deb"
