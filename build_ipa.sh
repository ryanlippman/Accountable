#!/bin/bash
# Builds an unsigned Accountable.ipa. Sideloadly or AltStore signs it with your Apple ID when you install it.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build Accountable.ipa
xcodebuild -project Accountable.xcodeproj -target Accountable -configuration Release -sdk iphoneos \
  SYMROOT="$PWD/build" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  > build.log 2>&1 || { grep -E "error:|warning: unre" build.log | head -60; echo "BUILD FAILED (full log: build.log)"; exit 1; }
mkdir -p build/ipa/Payload
cp -R build/Release-iphoneos/Accountable.app build/ipa/Payload/
(cd build/ipa && zip -qry ../../Accountable.ipa Payload)
echo "Built $(pwd)/Accountable.ipa ($(du -h Accountable.ipa | cut -f1))"
