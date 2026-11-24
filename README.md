# ArduinoTouchBar

Native macOS Touch Bar integration for Arduino IDE on MacBook Pro (2016-2020).

## Features
- **Verify / Compile** (`Cmd + R`)
- **Upload** (`Cmd + U`)
- **Serial Monitor** (`Cmd + Shift + M`)
- **Sketchbook** (`Cmd + Shift + B`)
- **Include Library** (`Cmd + Shift + I`)
- **Sketch Switcher**: Quick window switcher on the Touch Bar when multiple sketches are open
- **Control Strip Button**: Custom CPU icon in the Control Strip for one-tap access

## Installation
1. Download the latest `ArduinoTouchBar-v1.0.0.zip` from [Releases](https://github.com/mvmbmy0-gif/ArduinoTouchBar/releases).
2. Unzip and move `ArduinoTouchBar.app` to `/Applications` or your preferred directory.
3. Grant Accessibility permissions under **System Settings → Privacy & Security → Accessibility**.
4. Open the app — it runs quietly in the menu bar and activates whenever Arduino IDE is in focus.

## Building from source
```bash
./build.sh
```
Requires Xcode Command Line Tools (`clang`).
