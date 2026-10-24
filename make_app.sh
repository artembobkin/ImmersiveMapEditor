#!/bin/sh
# Builds the editor and wraps it into build/Immersive Map Editor.app.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="build/Immersive Map Editor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ImmersiveMapEditor "$APP/Contents/MacOS/ImmersiveMapEditor"
# The icon: Icon/AppIcon.png (drawn by Icon/make_icon.swift) at every size macOS asks for.
SET=build/AppIcon.iconset
rm -rf "$SET" && mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s Icon/AppIcon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Icon/AppIcon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Immersive Map Editor</string>
<key>CFBundleDisplayName</key><string>Immersive Map Editor</string>
<key>CFBundleIdentifier</key><string>dev.immersivemap.editor</string>
<key>CFBundleExecutable</key><string>ImmersiveMapEditor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "$(pwd)/$APP"
