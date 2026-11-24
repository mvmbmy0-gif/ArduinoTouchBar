#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building ArduinoTouchBar..."
mkdir -p ArduinoTouchBar.app/Contents/MacOS

clang -fobjc-arc -O2 \
    -framework Cocoa \
    -framework Carbon \
    -framework ApplicationServices \
    -F /System/Library/PrivateFrameworks \
    -framework DFRFoundation \
    main.m -o ArduinoTouchBar.app/Contents/MacOS/ArduinoTouchBar

echo "Build complete: ArduinoTouchBar.app"
