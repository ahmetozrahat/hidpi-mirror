#!/bin/zsh
# Builds a release binary and wraps it in HiDPI Mirror.app.
# Usage: ./build.sh [--install]   (--install copies the app to ~/Applications and relaunches it)
#
# Signs with SIGN_IDENTITY, else the first "Developer ID Application" identity, else ad-hoc.
# A stable identity matters: Accessibility permission (brightness keys) is tied to the signature,
# and an ad-hoc signature changes on every build.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP="build/HiDPI Mirror.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/HiDPIMirror "$APP/Contents/MacOS/"
# SwiftPM stamps the binary with the deployment target as its SDK version, and AppKit then runs
# it in compatibility mode: no Liquid Glass. Record the SDK it was really built against.
vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/HiDPIMirror" "$APP/Contents/MacOS/HiDPIMirror"
cp Resources/Info.plist "$APP/Contents/"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application/ { print $2; exit }')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x HiDPIMirror && while pgrep -x HiDPIMirror >/dev/null; do sleep 0.2; done || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/"HiDPI Mirror.app"
    cp -R "$APP" ~/Applications/
    open ~/Applications/"HiDPI Mirror.app"
    echo "Installed and launched ~/Applications/HiDPI Mirror.app"
fi
