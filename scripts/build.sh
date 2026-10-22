#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project HoldTranslate.xcodeproj -scheme HoldTranslate -configuration Release -derivedDataPath build build
mkdir -p build/Distribution
ditto build/Build/Products/Release/HoldTranslate.app build/Distribution/HoldTranslate.app
codesign --verify --deep --strict build/Distribution/HoldTranslate.app
printf '%s\n' "Built: $PWD/build/Distribution/HoldTranslate.app"
