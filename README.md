# PinchDial

Turn a keyboard or mouse dial into smooth pinch-to-zoom on macOS. Originally made for the **Keychron Nape Pro**, PinchDial works with any device that can send **F18** (zoom in) and **F19** (zoom out), or your own assigned keys.

Requires **macOS 13+** and a **Swift 5.9+ toolchain** to build. No external dependencies.

## Build and run

Complete the signing setup below before your first build. Then, from the project directory with PinchDial quit:

```sh
bash scripts/build.sh
open dist/PinchDial.app
```

### One-time local signing setup

The build requires a code-signing certificate named **PinchDial Local Development**. Reuse it if already installed; otherwise, create it in **Keychain Access → Certificate Assistant → Create a Certificate**:

- **Name:** PinchDial Local Development
- **Identity Type:** Self Signed Root
- **Certificate Type:** Code Signing
- Save it in the **login** keychain, then set its **Code Signing** trust to **Always Trust**.

Verify it appears in `security find-identity -v -p codesigning`. Keep the certificate and its private key for future builds. To use another certificate:

```sh
CODE_SIGN_IDENTITY='Your Certificate Name' bash scripts/build.sh
```

Keep the same signing identity and app location across rebuilds so macOS can recognize the app. Run only one copy.

## Setup

1. Map your dial clockwise to **F18** and counterclockwise to **F19**, sending one key press/release per step.
2. Open **Show Setup…** and use the **Permissions** buttons to grant **Accessibility** access. Grant **Input Monitoring** if input is unavailable.
3. Return to PinchDial. If input still doesn’t work or macOS requests a restart, quit and reopen the app.
4. Keep **Enable PinchDial** on, focus the target app, place the pointer over its content, and turn the dial.

## Everyday use

- **Sensitivity:** Adjust the slider in Setup for finer or faster zoom.
- **Zoom shortcuts:** Search for a key or choose **Record a key**. Each direction needs a different single key; modifier-only, media, and power keys aren’t supported. Changes save automatically. Configure your device separately to send those keys.
- **Press or hold:** A quick press zooms one step; holding a key starts continuous zoom. Command, Option, Control, and Shift combinations pass through normally.
- **Enable or disable:** Assigned keys are captured in other apps while enabled. Disable PinchDial to use them normally. F18/F19 are recommended to avoid taking over typing keys.
- **Launch at Login:** Enable it in Setup. If **Approval Needed…** appears, click it and approve PinchDial in System Settings.
- **Show in menu bar:** Hide or show the status icon. You can always reopen Setup from the Dock. Closing Setup keeps zooming active; **Quit** stops the app.

## Development and compatibility

Run the unit tests:

```sh
bash scripts/test.sh
```

Check gesture encoding without posting input:

```sh
dist/PinchDial.app/Contents/MacOS/PinchDial --check-gesture-encoding
```

The gesture backend uses undocumented macOS event fields, so compatibility varies by app and OS version. Verify actual zooming with your dial in the apps you use; automated checks do not confirm gesture delivery.
