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
# The engine's shaders compiled into the default.metallib of its bundle:
# Xcode compiles a package's .metal resources, `swift build` only copies
# them, flattened, so the engine found no library and stopped as its map
# opened (the user, 2026-11-05: the release crashed in the Engine view).
# They are compiled from the engine's source tree, where their relative
# includes resolve, from the folders its Package.swift processes.
ENGINE=$(swift package show-dependencies --format json | grep -o '"path" *: *"[^"]*ImmersiveMap"' | head -1 | sed 's/.*: *"//; s/"$//')
SHADERS="$ENGINE/Sources/ImmersiveMap"
AIR=build/air
rm -rf "$AIR" && mkdir -p "$AIR"
n=0
for f in $(find "$SHADERS/Avatars/Shaders" "$SHADERS/Globe/Shaders" "$SHADERS/Horizon/Shaders" "$SHADERS/Labels/Shaders" \
             "$SHADERS/Layers/Shaders" "$SHADERS/Render/Debug/Shaders" "$SHADERS/Render/PostProcessing/Shaders" \
             "$SHADERS/SceneModels/Shaders" "$SHADERS/Shadows/Shaders" "$SHADERS/Starfield/Shaders" "$SHADERS/Text/Shaders" \
             "$SHADERS/Tile/Shaders" -name '*.metal' 2>/dev/null) "$SHADERS/Render/Shaders/Shared/GeoMath.metal"; do
    n=$((n + 1))
    xcrun -sdk macosx metal -O3 -c -o "$AIR/$n.air" "$f"
done
xcrun -sdk macosx metallib -o "$APP/Contents/Resources/ImmersiveMap_ImmersiveMap.bundle/default.metallib" "$AIR"/*.air
# And as the app's own default library: SwiftPM's Bundle.module looks for the
# engine's bundle beside the .app, not in Contents/Resources (where signing
# allows it), then falls back to the build folder's path compiled in, whose
# bundle has no library; the engine then takes the main bundle's library
# (RendererSetup.makeLibrary), which is this one (the user, 2026-11-05: the
# library in the engine's bundle alone was never read, the crash stayed).
cp "$APP/Contents/Resources/ImmersiveMap_ImmersiveMap.bundle/default.metallib" "$APP/Contents/Resources/default.metallib"
rm -rf "$AIR"
echo "the engine's $n shaders compiled into its default.metallib"
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
