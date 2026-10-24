#!/bin/sh
# Builds the editor and wraps it into build/Immersive Map Editor.app.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/Immersive Map Editor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ImmersiveMapEditor "$APP/Contents/MacOS/ImmersiveMapEditor"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Immersive Map Editor</string>
<key>CFBundleDisplayName</key><string>Immersive Map Editor</string>
<key>CFBundleIdentifier</key><string>dev.immersivemap.editor</string>
<key>CFBundleExecutable</key><string>ImmersiveMapEditor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "$(pwd)/$APP"
