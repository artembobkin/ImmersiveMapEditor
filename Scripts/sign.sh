#!/bin/sh
# Signs the editor's binary with the Apple Development certificate of the
# user's keychain, under one stable identifier, so the keychain knows it as
# the same app from build to build (the proxy, the tokens: allowed once with
# "Always Allow", never asked again). An ad hoc signature, what a plain
# build leaves, changes with every build and is asked about every time.
# The editor does this to itself at launch (CodeSigning); this script is
# for a binary that is not going to be run first, such as one to copy:
# Scripts/sign.sh .build/release/ImmersiveMapEditor
set -e
BIN="${1:?usage: sign.sh BINARY}"
ID=$(security find-identity -v -p codesigning | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
if [ -z "$ID" ]; then
    echo "sign.sh: no Apple Development certificate in the keychain, $BIN stays ad hoc" >&2
    exit 0
fi
/usr/bin/codesign --force --sign "$ID" --identifier com.artembobkin.ImmersiveMapEditor "$BIN"
echo "signed $BIN as com.artembobkin.ImmersiveMapEditor ($ID)"
