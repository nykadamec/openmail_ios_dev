#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project openMail.xcodeproj -scheme openMail -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
APP="build/Build/Products/Release-iphoneos/openMail.app"
[ -d "$APP" ]
rm -rf Payload dist && mkdir -p Payload dist
cp -R "$APP" Payload/
zip -qry dist/openMail-unsigned.ipa Payload
echo "OK: dist/openMail-unsigned.ipa"