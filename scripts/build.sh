#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project LingoWisp.xcodeproj -scheme LingoWisp -configuration Release -derivedDataPath build build
mkdir -p build/Distribution
ditto build/Build/Products/Release/LingoWisp.app build/Distribution/LingoWisp.app
codesign --verify --deep --strict build/Distribution/LingoWisp.app
printf '%s\n' "Built: $PWD/build/Distribution/LingoWisp.app"
