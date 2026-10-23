#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/build/VisualTests.app"
mkdir -p "$app/Contents/MacOS" docs/screenshots
xcrun swiftc -target arm64-apple-macos15.0 -swift-version 5 -parse-as-library \
  HoldTranslate/Core/*.swift HoldTranslate/App/Preferences.swift \
  HoldTranslate/App/TranslationModel.swift HoldTranslate/App/BubbleView.swift HoldTranslate/App/BubbleBurstEffect.swift Tests/VisualHarness.swift \
  -o "$app/Contents/MacOS/VisualTests"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yikessa.HoldTranslate.VisualTests</string>
<key>CFBundleExecutable</key><string>VisualTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
"$app/Contents/MacOS/VisualTests" --output "$PWD/docs/screenshots/translation-light.png"
"$app/Contents/MacOS/VisualTests" --dark --output "$PWD/docs/screenshots/translation-dark.png"
"$app/Contents/MacOS/VisualTests" --chinese --output "$PWD/docs/screenshots/chinese-to-english.png"
"$app/Contents/MacOS/VisualTests" --word --output "$PWD/docs/screenshots/word.png"
"$app/Contents/MacOS/VisualTests" --long --output "$PWD/docs/screenshots/long-translation.png"
if [[ "${1:-}" == "--traditional" ]]; then
  "$app/Contents/MacOS/VisualTests" --traditional --output "$PWD/docs/screenshots/traditional-to-english.png"
fi
