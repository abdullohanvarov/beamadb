#!/usr/bin/env bash
# BeamADB Debian (.deb) Package Builder
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_NAME="beamadb"
PKG_VERSION="1.0.0"
PKG_ARCH="all"
BUILD_DIR="${DIR}/dist/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"
DEB_FILE="${DIR}/dist/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"

echo "=== Building Debian package: ${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb ==="

# Clean previous build
rm -rf "${DIR}/dist"
mkdir -p "${BUILD_DIR}/DEBIAN"
mkdir -p "${BUILD_DIR}/usr/bin"
mkdir -p "${BUILD_DIR}/usr/share/beamadb"
mkdir -p "${BUILD_DIR}/usr/share/applications"
mkdir -p "${BUILD_DIR}/usr/share/icons/hicolor/scalable/apps"

# 1. DEBIAN/control
cat << 'EOF' > "${BUILD_DIR}/DEBIAN/control"
Package: beamadb
Version: 1.0.0
Section: devel
Priority: optional
Architecture: all
Maintainer: Abdulloh Anvarov <abdullohanvarov273@gmail.com>
Depends: python3 (>= 3.8)
Suggests: android-tools-adb
Homepage: https://github.com/abdullohanvarov/beamadb
Description: Fast, accessible Android Wireless Debugging and QR Pairing Bridge
 BeamADB allows developers to pair, connect, and debug Android devices
 wirelessly using QR codes, 6-digit codes, or automatic mDNS network discovery.
 Includes both a modern accessible Web GUI and a terminal CLI.
EOF

# 2. DEBIAN/postinst
cat << 'EOF' > "${BUILD_DIR}/DEBIAN/postinst"
#!/bin/sh
set -e
chmod +x /usr/bin/beamadb
chmod +x /usr/share/beamadb/beamadb
chmod +x /usr/share/beamadb/server.py
update-desktop-database /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache /usr/share/icons/hicolor 2>/dev/null || true
exit 0
EOF
chmod 755 "${BUILD_DIR}/DEBIAN/postinst"

# 3. Copy Application files to /usr/share/beamadb
cp "${DIR}/beamadb" "${BUILD_DIR}/usr/share/beamadb/"
cp "${DIR}/server.py" "${BUILD_DIR}/usr/share/beamadb/"
cp -r "${DIR}/static" "${BUILD_DIR}/usr/share/beamadb/"
cp -r "${DIR}/pyqrcode" "${BUILD_DIR}/usr/share/beamadb/"
if [ -d "${DIR}/bin" ]; then
  cp -r "${DIR}/bin" "${BUILD_DIR}/usr/share/beamadb/"
  chmod -R +x "${BUILD_DIR}/usr/share/beamadb/bin" 2>/dev/null || true
fi
rm -rf "${BUILD_DIR}/usr/share/beamadb/pyqrcode/__pycache__"
chmod +x "${BUILD_DIR}/usr/share/beamadb/beamadb"
chmod +x "${BUILD_DIR}/usr/share/beamadb/server.py"

# 4. Create /usr/bin/beamadb launcher wrapper
cat << 'EOF' > "${BUILD_DIR}/usr/bin/beamadb"
#!/bin/sh
exec /usr/share/beamadb/beamadb "$@"
EOF
chmod 755 "${BUILD_DIR}/usr/bin/beamadb"

# Also symlink /usr/bin/beam-adb
ln -sf beamadb "${BUILD_DIR}/usr/bin/beam-adb"

# 5. Desktop Entry
cat << 'EOF' > "${BUILD_DIR}/usr/share/applications/beamadb.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=BeamADB
GenericName=Android Wireless Debugging
Comment=Fast, accessible Android Wireless Debugging and QR Pairing Bridge
Exec=/usr/bin/beamadb
Icon=beamadb
Terminal=false
Categories=Development;Utility;Android;
Keywords=beamadb;adb;android;wireless;debug;qr;wifi;
StartupNotify=true
EOF

# 6. Icon
cp "${DIR}/static/icon.svg" "${BUILD_DIR}/usr/share/icons/hicolor/scalable/apps/beamadb.svg"

# Build .deb with dpkg-deb
dpkg-deb --build --root-owner-group "${BUILD_DIR}" "${DEB_FILE}"

echo "Package created successfully: ${DEB_FILE}"
ls -lh "${DEB_FILE}"
