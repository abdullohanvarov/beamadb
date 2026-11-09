#!/usr/bin/env bash
# Launch the native desktop app. The legacy browser UI is now opt-in.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/desktop/build/linux/x64/release/bundle/beamadb"
if [[ -x "$APP" ]]; then
  exec "$APP" "$@"
fi
printf 'BeamADB desktop has not been built. Run tools/build-desktop-linux.sh first.\n' >&2
exit 1
