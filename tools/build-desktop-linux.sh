#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
cd "$ROOT/desktop"
if [[ -f .native/pkgconfig/mpv.pc ]]; then
  export PKG_CONFIG_PATH="$PWD/.native/pkgconfig:${PKG_CONFIG_PATH:-}"
  export LD_LIBRARY_PATH="$PWD/.native/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
fi
if [[ "${1:-}" != "--package-existing" ]]; then
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" analyze
"$FLUTTER_BIN" test test
"$FLUTTER_BIN" build linux --release
fi
BUNDLE="$PWD/build/linux/x64/release/bundle"
mkdir -p "$BUNDLE/bin/scrcpy/linux" "$BUNDLE/licenses"
cp -a "$ROOT/bin/scrcpy/linux/." "$BUNDLE/bin/scrcpy/linux/"
mkdir -p "$BUNDLE/remote"
cp "$ROOT"/remote/{agent.py,relay.py,cellular.py,onboard.py,remove_device.py,install-agent.sh} "$BUNDLE/remote/"
cp "$ROOT/dist/BeamADB-Link.apk" "$BUNDLE/remote/"
cp "$ROOT/LICENSE" "$BUNDLE/licenses/BeamADB-LICENSE"
cp "$ROOT/docs/bundled-tools.json" "$BUNDLE/licenses/bundled-tools.json"
cp "$PWD/assets/fonts/OFL.txt" "$BUNDLE/licenses/Inter-OFL.txt"
if [[ -d .native/root/usr/lib/x86_64-linux-gnu ]]; then
  cp -a .native/root/usr/lib/x86_64-linux-gnu/*.so* "$BUNDLE/lib/"
  mkdir -p "$BUNDLE/licenses/native-packages"
  cp -a .native/root/usr/share/doc/. "$BUNDLE/licenses/native-packages/"
fi
cat > "$BUNDLE/beamadb" <<'LAUNCH'
#!/usr/bin/env bash
set -e
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$APP_DIR/lib:${LD_LIBRARY_PATH:-}"
export BEAMADB_HOME="$APP_DIR"
exec "$APP_DIR/beamadb_desktop" "$@"
LAUNCH
chmod +x "$BUNDLE/beamadb"
printf 'Linux release bundle: %s\n' "$BUNDLE"
