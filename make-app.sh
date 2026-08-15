#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$BUILD_DIR/NetToggle.app"

BUNDLE_ID="com.sunnytherabbit.NetToggle"

# Build the release executable.
echo "Building NetToggle..."
swift build -c release

# Bundle it as a macOS app.
echo "Creating $APP_DIR..."
mkdir -p "$APP_DIR/Contents/MacOS"
cp -f "$BUILD_DIR/NetToggle" "$APP_DIR/Contents/MacOS/NetToggle"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>NetToggle</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NetToggle</string>
    <key>CFBundleDisplayName</key>
    <string>NetToggle</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.14</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Ad-hoc sign the bundle so macOS won't refuse to launch it.
if command -v codesign >/dev/null 2>&1; then
    echo "Ad-hoc signing NetToggle.app..."
    codesign --sign - --force --deep "$APP_DIR" || true
fi

echo "Built: $APP_DIR"
echo "Drag it to /Applications, then run ./install.sh once to install the setuid helper."
