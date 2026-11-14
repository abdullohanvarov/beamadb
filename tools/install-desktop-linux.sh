#!/usr/bin/env bash
# Install for the current user, replacing any older personal launcher.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$ROOT/tools/build-desktop-linux.sh" "$@"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_DIR/beamadb"
mkdir -p "$APP_DIR" "$DATA_DIR/applications" "$DATA_DIR/icons/hicolor/scalable/apps"
cp -a --remove-destination "$ROOT/desktop/build/linux/x64/release/bundle/." "$APP_DIR/"
install -m 644 "$ROOT/static/icon.svg" "$DATA_DIR/icons/hicolor/scalable/apps/beamadb.svg"
python3 - "$ROOT/beamadb.desktop" "$DATA_DIR/applications/beamadb.desktop" "$APP_DIR/beamadb" <<'PY'
import pathlib
import sys
source, destination, executable = sys.argv[1:]
# Desktop Exec quoting is separate from shell quoting; escape reserved characters.
escaped = executable.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
content = pathlib.Path(source).read_text()
content = content.replace('Exec=beamadb-desktop', f'Exec="{escaped}"')
pathlib.Path(destination).write_text(content)
PY
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$DATA_DIR/applications"
fi
if command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache -f -t "$DATA_DIR/icons/hicolor"
fi
printf 'BeamADB installed. Close existing BeamADB windows and reopen it from Applications.\n'
