#!/bin/bash
# Compile l'app Swift et fabrique le bundle Regie.app.
# NB: strings ASCII uniquement, le /bin/bash 3.2 de macOS avale les
# caracteres Unicode colles a une variable.
set -euo pipefail
cd "$(dirname "$0")"

echo "Compilation (release)..."
swift build -c release

APP=build/Regie.app
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp .build/release/Regie "${APP}/Contents/MacOS/Regie"
cp Info.plist "${APP}/Contents/Info.plist"
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
fi

# Signature ad hoc : suffisante en local, et indispensable pour que
# l'autorisation Automation (System Events) persiste.
codesign --force --sign - "${APP}"

echo
echo "App creee : $(pwd)/${APP}"
echo "Pour l'installer : cp -r ${APP} /Applications/"
