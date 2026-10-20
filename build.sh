#!/bin/zsh
# Builds a release binary and wraps it in HiDPI Mirror.app (ad-hoc signed).
# Usage: ./build.sh [--install]   (--install copies the app to ~/Applications)
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP="build/HiDPI Mirror.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/HiDPIMirror "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x HiDPIMirror && sleep 1 || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"HiDPI Mirror.app"
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/HiDPI Mirror.app"
fi
