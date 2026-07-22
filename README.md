# AutoTyper (`typer`)

**AutoTyper** is a lightweight, native macOS menu bar utility designed to bypass remote screen-sharing clipboard limitations. When controlling a remote participant's screen in applications like Zoom, Microsoft Teams, or Webex, direct clipboard sharing is often disabled or unsupported. 

AutoTyper acts as a virtual human keyboard, taking your local clipboard contents and simulating throttled hardware keystrokes line-by-line directly into the remote session or active target application.

---

## Key Features

* **Menu Bar Status Item:** Lives unobtrusively in your macOS status bar (`MenuBarExtra`).
* **Global Hotkey Support:** Trigger typing instantly with **`Control` + `Option` + `V`** (`⌃ ⌥ V`).
* **Focus Safety Switch:** Automatically cancels typing the exact millisecond you switch windows or click away, preventing text leakage into unrelated applications.
* **Native Keycode Injection:** Correctly handles line breaks (`\n` -> Return keycode `36`) and tabs (`\t` -> Tab keycode `48`) rather than dropping raw characters.
* **Throttled Delivery:** Automatically throttles keystrokes (20ms delay) to ensure remote desktop connection protocols do not drop characters due to latency.
* **Smart App Targeting:** Automatically detects and filters active remote desktop/meeting apps (Zoom, Teams, Webex, VS Code).

---

## Requirements

* **macOS:** 14.0 (Sonoma) or newer.
* **Xcode:** Version 15.0 or newer (for building from source).
* **Permissions:** **Accessibility** privileges enabled in System Settings.

---

## Build & Setup Instructions

### 1. Clone & Open Project
1. Clone or download this repository.
2. Open `typer.xcodeproj` in Xcode.

### 2. Configure App Agent Mode (Hide Dock Icon)
To ensure the app only runs in the menu bar without appearing in the Dock:
1. Open the project configuration in Xcode.
2. Go to the **Info** tab.
3. Verify or add the key: `Application is agent (UIElement)` set to `YES`.

### 3. Build & Run
1. Select your target (My Mac) and press **`Cmd + R`** to build and run the app.

---

## Granting Accessibility Permissions

Because AutoTyper injects low-level system keyboard events (`CGEvent`) and listens for global hotkeys (`NSEvent`), macOS security requires explicit Accessibility authorization.

1. Open **System Settings** > **Privacy & Security** > **Accessibility**.
2. Click the **`+` (Plus)** button at the bottom of the list.
3. Locate and select **`typer.app`** (or select **Xcode** if running directly from the IDE during development).
4. Ensure the toggle switch next to **`typer`** is enabled (blue).

> **Note:** If you re-compile or clean-build the project in Xcode, macOS may invalidate the previous binary signature. If typing stops working, remove `typer` from the Accessibility list using the **`-` (Minus)** button and re-add it.

---

## How to Use

1. Copy any text or code snippet to your local clipboard (`Cmd + C`).
2. Focus the target window (e.g., Zoom Screen Share window or VS Code).
3. Trigger typing in one of two ways:
   * Press **`Control` + `Option` + `V`** (`⌃ ⌥ V`).
   * Click the **AutoTyper** menu bar icon (`keyboard`) and select your target application from the drop-down menu.
4. AutoTyper will bring the target window to the front and type out your clipboard contents.

---

## Target Applications

By default, AutoTyper is configured to recognize:
* **Visual Studio Code** (`com.microsoft.VSCode`)
* **Zoom** (`us.zoom.xos`)
* **Microsoft Teams (New)** (`com.microsoft.teams2`)
* **Microsoft Teams (Classic)** (`com.microsoft.teams`)
* **Cisco Webex** (`com.cisco.webexmeetingsapp`)

You can add additional target bundle identifiers in `TyperLogic.swift` under the `targetBundleIDs` set.

## Command Line Build (`xcodebuild`)

You can build the project from Terminal using `xcodebuild`:

```bash
# Clone and enter directory
cd /path/to/typer

# Build Release binary to a local ./build folder
xcodebuild build \
  -project typer.xcodeproj \
  -scheme typer \
  -configuration Release \
  -derivedDataPath ./build

# Launch the built application
open ./build/Build/Products/Release/typer.app