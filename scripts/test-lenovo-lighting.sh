#!/usr/bin/env bash
# Build the app first so the checks use the same production frameworks as the CLI.
set -euo pipefail
cd "$(dirname "$0")/.."
products="$PWD/.build/xcode/Build/Products/Release"
sources=Apps/OpenDisplay/Sources
common=(-swift-version 6 -parse-as-library -F "$products" -Xlinker -rpath -Xlinker "$products"
        "$sources"/{LenovoLightingController,LenovoStripEffects,LenovoAudioMeter}.swift)
swiftc "${common[@]}" Tests/HardwareLab/LenovoLighting/main.swift -o .build/lenovo-lighting-check
.build/lenovo-lighting-check
swiftc "${common[@]}" "$sources"/{LenovoStripControls,LenovoPaletteEditor,LenovoStripColorPicker}.swift \
    Tests/HardwareLab/LenovoLighting/QuickRow.swift -o .build/lenovo-quick-row-check
.build/lenovo-quick-row-check
