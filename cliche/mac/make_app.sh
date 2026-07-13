#!/bin/bash
# Compile l'app Swift et fabrique le bundle Cliche.app (necessaire pour que
# macOS memorise l'autorisation Enregistrement de l'ecran).
# NB: strings ASCII uniquement, le /bin/bash 3.2 de macOS avale les
# caracteres Unicode colles a une variable.
set -euo pipefail
cd "$(dirname "$0")"

echo "Compilation (release)..."
swift build -c release

APP=build/Cliche.app
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp .build/release/Cliche "${APP}/Contents/MacOS/Cliche"
cp Info.plist "${APP}/Contents/Info.plist"
if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
fi

# Signature ad hoc : suffisante en local, et indispensable pour que les
# autorisations TCC persistent entre deux lancements.
codesign --force --sign - "${APP}"

echo
echo "App creee : $(pwd)/${APP}"
echo "Pour l'installer : cp -r ${APP} /Applications/"
