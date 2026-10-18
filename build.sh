#!/bin/zsh
set -eu
ROOT="${0:A:h}"
DEST="${1:-$ROOT/dist}"
APP="$DEST/Twin.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/module-cache"
swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 \
  -module-cache-path "$ROOT/.build/module-cache" \
  -framework AppKit -framework SwiftUI \
  "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/Twin"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Twin</string>
<key>CFBundleIdentifier</key><string>local.twin.launcher</string>
<key>CFBundleName</key><string>Twin</string>
<key>CFBundleDisplayName</key><string>Twin</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "Built $APP"
