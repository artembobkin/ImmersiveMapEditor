#!/bin/sh
# Builds the editor and wraps it into build/Immersive Map Editor.app, signed
# as a whole with the Apple Development certificate under the identifier the
# editor signs itself with (App/CodeSigning), so the keychain and the folder
# permissions know it. The version is the first argument, else the last tag:
# ./make_app.sh 0.1.0
set -e
cd "$(dirname "$0")"
VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}"
swift build -c release --product ImmersiveMapEditor
APP="build/Immersive Map Editor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ImmersiveMapEditor "$APP/Contents/MacOS/ImmersiveMapEditor"
# The resource bundles of the packages linked (the engine's shaders and its
# overview archive): Bundle.module finds them in Contents/Resources.
for b in .build/release/*.bundle; do [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
# The icon: Icon/AppIcon.png (drawn by Icon/MakeIcon.swift) at every size macOS asks for.
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
<key>CFBundleIdentifier</key><string>com.artembobkin.ImmersiveMapEditor</string>
<key>CFBundleExecutable</key><string>ImmersiveMapEditor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
ID=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
if [ -n "$ID" ]; then
    /usr/bin/codesign --force --sign "$ID" --identifier com.artembobkin.ImmersiveMapEditor "$APP"
else
    echo "make_app.sh: no Apple Development certificate, the app stays ad hoc" >&2
fi
echo "$(pwd)/$APP"
