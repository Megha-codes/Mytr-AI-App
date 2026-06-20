#!/bin/bash
set -e

# Build a release APK for sideloading / USB install.
# Usage:
#   ./scripts/build_apk.sh                              # uses debug keystore
#   API_URL=https://api.mytr.ai/api/v1 ./scripts/build_apk.sh

FLUTTER="${FLUTTER_HOME:-$HOME/flutter}/bin/flutter"
API_URL="${API_URL:-https://api.mytr.ai/api/v1}"
FRONTEND_DIR="$(cd "$(dirname "$0")/../frontend" && pwd)"
KEY_PROPERTIES="$FRONTEND_DIR/android/key.properties"

echo "==> API_URL = $API_URL"

# --- Keystore setup (run once) ---
if [ ! -f "$KEY_PROPERTIES" ]; then
  echo ""
  echo "No key.properties found — generating a release keystore."
  echo "Fill in real details for production; press Enter to use defaults."
  echo ""

  KEYSTORE_PATH="$HOME/.android/mytr_release.jks"
  mkdir -p ~/.android

  keytool -genkeypair -v \
    -keystore "$KEYSTORE_PATH" \
    -alias mytr \
    -keyalg RSA -keysize 2048 \
    -validity 10000 \
    -storepass mytrai2024 -keypass mytrai2024 \
    -dname "CN=Mytr.AI, OU=Mobile, O=Mytr, L=City, S=State, C=US"

  cat > "$KEY_PROPERTIES" <<EOF
storePassword=mytrai2024
keyPassword=mytrai2024
keyAlias=mytr
storeFile=$KEYSTORE_PATH
EOF
  echo "==> Created $KEY_PROPERTIES"
fi

# --- Build ---
cd "$FRONTEND_DIR"

echo "==> flutter pub get"
"$FLUTTER" pub get

echo "==> Building release APK..."
"$FLUTTER" build apk --release \
  --dart-define=API_BASE_URL="$API_URL"

APK="$FRONTEND_DIR/build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "==> Done: $APK"
echo ""
echo "To install via USB:"
echo "  adb install -r \"$APK\""
