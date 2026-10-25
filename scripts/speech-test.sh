#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/build/SpeechTests.app"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -target arm64-apple-macos15.0 -swift-version 5 -parse-as-library \
  LingoWisp/Core/*.swift LingoWisp/App/Preferences.swift \
  LingoWisp/App/TranslationModel.swift LingoWisp/App/BubbleView.swift LingoWisp/App/BubbleBurstEffect.swift \
  LingoWisp/App/SelectableTranslationText.swift LingoWisp/App/SpeechController.swift \
  Tests/VisualHarness.swift Tests/SpeechVerification.swift -o "$app/Contents/MacOS/SpeechTests"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yikessa.LingoWisp.SpeechTests</string>
<key>CFBundleExecutable</key><string>SpeechTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
"$app/Contents/MacOS/SpeechTests" --speech-audio-check --speech-report "$PWD/build/speech-audio-report.json"
open "$app" --args --speech-only --speech-report "$PWD/build/speech-ui-report.json"
