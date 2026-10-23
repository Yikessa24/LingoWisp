#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
xcrun swiftc -parse-as-library HoldTranslate/Core/BubbleBurstRenderer.swift Tests/BurstPreview.swift -o build/BurstPreview
build/BurstPreview
