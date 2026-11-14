#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
sdk="${ANDROID_HOME:-$HOME/Android/Sdk}"
bt="$sdk/build-tools/35.0.0"
jar="$sdk/platforms/android-35/android.jar"
out="$(pwd)/build"
mkdir -p "$out/classes" "$out/dex"
javac --release 8 -classpath "$jar" -d "$out/classes" src/dev/beamadb/link/*.java
"$bt/d8" --lib "$jar" --min-api 30 --output "$out/dex" "$out"/classes/dev/beamadb/link/*.class
"$bt/aapt" package -f -M AndroidManifest.xml -I "$jar" -F "$out/base.apk"
(cd "$out/dex" && zip -q "$out/base.apk" classes.dex)
"$bt/zipalign" -f 4 "$out/base.apk" "$out/aligned.apk"
mkdir -p ../../dist
"$bt/apksigner" sign --ks "${BEAMADB_DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}" --ks-pass pass:android --out ../../dist/BeamADB-Link.apk "$out/aligned.apk"
"$bt/apksigner" verify ../../dist/BeamADB-Link.apk
