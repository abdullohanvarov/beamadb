#!/usr/bin/env bash
# Optional Ubuntu/Debian local dependency preparation. No sudo/system changes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE="$ROOT/desktop/.native"
mkdir -p "$NATIVE/packages" "$NATIVE/root" "$NATIVE/pkgconfig"
cd "$NATIVE/packages"
apt-get download libmpv-dev libmpv2 liblua5.2-0 libmujs3 libsixel1 libxpresent1 libsndio7.0
for package in ./*.deb; do dpkg-deb -x "$package" "$NATIVE/root"; done
# Shared linking needs only public mpv headers. Preserve the original package's
# private dependency metadata in root; use this separate local descriptor.
cat > "$NATIVE/pkgconfig/mpv.pc" <<PC
prefix=$NATIVE/root/usr
includedir=\${prefix}/include
libdir=\${prefix}/lib/x86_64-linux-gnu
Name: mpv
Description: Local libmpv shared client
Version: 2.5.0
Libs: -L\${libdir} -lmpv
Cflags: -I\${includedir}
PC
LD_LIBRARY_PATH="$NATIVE/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}" ldd "$NATIVE/root/usr/lib/x86_64-linux-gnu/libmpv.so.2"
