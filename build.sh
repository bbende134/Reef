#!/bin/bash
#
# Builds Reef.app using only the Xcode Command Line Tools.
#
# SwiftPM produces a bare executable and has no concept of an application bundle, so
# this compiles the package and then assembles Contents/ by hand.
#
# Usage:
#   ./build.sh                      # ad-hoc signature (see the signing note below)
#   ./build.sh "Apple Development: you@example.com (XXXXXXXXXX)"
#   ./build.sh "Reef Local Signing" # a self-signed Keychain certificate
#
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${1:--}"
APP=".build/Reef.app"
BUNDLE_ID="xandergouws.Reef"
SHORT_VERSION="1.1.0-fork"
BUILD_VERSION="9000"

echo "==> Compiling"
xcrun swift build -c release --arch arm64

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Reef "$APP/Contents/MacOS/Reef"

# SwiftPM emits the vendored dependency's localisations as a side-by-side bundle.
if [ -d .build/release/Reef_KeyboardShortcuts.bundle ]; then
  cp -R .build/release/Reef_KeyboardShortcuts.bundle "$APP/Contents/Resources/"
fi

# The asset catalog needs actool (Xcode-only), so the one image Reef uses is copied in
# directly. ReefApp.menuBarIcon loads it by name from Resources.
cp Reef/Assets.xcassets/menu_placeholder.imageset/ReefMenuIcon44.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>            <string>Reef</string>
	<key>CFBundleIdentifier</key>            <string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>                  <string>Reef</string>
	<key>CFBundleDisplayName</key>           <string>Reef</string>
	<key>CFBundlePackageType</key>           <string>APPL</string>
	<key>CFBundleShortVersionString</key>    <string>${SHORT_VERSION}</string>
	<key>CFBundleVersion</key>               <string>${BUILD_VERSION}</string>
	<key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
	<key>LSMinimumSystemVersion</key>        <string>14.6</string>
	<key>LSApplicationCategoryType</key>     <string>public.app-category.utilities</string>
	<!-- Menu bar agent: no Dock icon, no menu bar of its own. -->
	<key>LSUIElement</key>                   <true/>
	<key>NSHighResolutionCapable</key>       <true/>
	<key>NSPrincipalClass</key>              <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Signing (identity: ${IDENTITY})"
if [ "$IDENTITY" = "-" ]; then
  # An ad-hoc signature's designated requirement is a bare cdhash, which changes on
  # every rebuild and therefore invalidates the Accessibility grant each time. Pinning
  # the requirement to the bundle identifier keeps one grant valid across rebuilds.
  codesign --force --sign - \
    --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"${BUNDLE_ID}\"" \
    "$APP"
else
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --options runtime "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"
echo "==> Designated requirement:"
codesign -d -r- "$APP" 2>&1 | tail -1
echo "==> Built $APP"
