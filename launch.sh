#!/usr/bin/env bash
# Wireless ADB Launcher Script
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=5588
URL="http://localhost:${PORT}"

# Add bundled tools & adb to PATH if needed
if [ -d "${DIR}/bin/scrcpy/linux" ]; then
  export PATH="${DIR}/bin/scrcpy/linux:$PATH"
fi
if ! command -v adb >/dev/null 2>&1; then
  if [ -f "$HOME/Android/Sdk/platform-tools/adb" ]; then
    export PATH="$HOME/Android/Sdk/platform-tools:$PATH"
  elif [ -f "$HOME/.local/bin/adb" ]; then
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# Check if server is already running on port 5588
if ! curl -s -m 1 "http://localhost:${PORT}/api/status" >/dev/null 2>&1; then
  echo "Starting Wireless ADB Server on port ${PORT}..."
  setsid python3 -u "${DIR}/server.py" </dev/null >> "${DIR}/server.log" 2>&1 &
  
  # Wait for server to bind
  for i in {1..25}; do
    if curl -s -m 1 "http://localhost:${PORT}/api/status" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done
else
  echo "Wireless ADB Server is already active on port ${PORT}."
fi

echo "Opening Wireless ADB UI: ${URL}"

# Open in browser
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "${URL}" >/dev/null 2>&1 &
elif command -v firefox >/dev/null 2>&1; then
  firefox "${URL}" >/dev/null 2>&1 &
elif command -v google-chrome >/dev/null 2>&1; then
  google-chrome "${URL}" >/dev/null 2>&1 &
else
  echo "Please open ${URL} in your browser."
fi
