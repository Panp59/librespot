#!/bin/bash
# Compile l'app Swift et fabrique le bundle Clap.app (nécessaire pour que
# macOS mémorise les autorisations écran / micro / accessibilité).
set -euo pipefail
cd "$(dirname "$0")"

echo "Compilation (release)…"
swift build -c release

APP=build/Clap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Clap "$APP/Contents/MacOS/Clap"
cp Info.plist "$APP/Contents/Info.plist"

# Signature ad hoc : suffisante en local, et indispensable pour que les
# autorisations TCC persistent entre deux lancements.
codesign --force --sign - "$APP"

echo
echo "✅ App créée : $(pwd)/$APP"
echo "   Pour l'installer : cp -r $APP /Applications/"
