# PinchDial

A small macOS menu-bar utility originally made for the **Keychron Nape Pro’s dial**. It turns **F18 into smooth pinch-to-zoom in** and **F19 into zoom out**, and works with any keyboard or mouse that can be configured to send those keys.

Requires macOS 13+ and an Xcode/Swift toolchain. No external dependencies.

## Build and run

From the project directory, with PinchDial quit:

```sh
bash scripts/build.sh
open dist/PinchDial.app
```

The build requires a valid local code-signing certificate named **PinchDial Local Development**. If it is already installed, reuse it.

For a new machine, create it in **Keychain Access → Certificate Assistant → Create a Certificate**: choose **Self Signed Root** and **Code Signing**, save it in the login keychain, and set its **Code Signing** trust to **Always Trust**. Keep the certificate and its private key for subsequent builds. Verify it appears in `security find-identity -v -p codesigning`.

To use another certificate, run `CODE_SIGN_IDENTITY='Your Certificate Name' bash scripts/build.sh`.

Run the app bundle from a consistent location and keep the same signing identity so macOS can recognize it across rebuilds. Run only one copy.

## Setup and use

1. Map the dial clockwise to **F18** and counterclockwise to **F19**, with one key press/release per step.
2. Open PinchDial and use its menu to grant **Accessibility** access. Grant **Input Monitoring** if input is unavailable.
3. Quit and reopen PinchDial after granting permissions.
4. Keep **Enable PinchDial** on. Focus the target app, place the pointer over its content, and turn the dial.

Sensitivity can be changed from the menu. Disable PinchDial to pass F18/F19 through normally, or choose Quit to stop it. While enabled, it captures F18/F19 from every device; other keys pass through.

If the dial does nothing, use **Show Setup & Diagnostics** to check permissions and whether key presses arrive.

## Tests

```sh
bash scripts/test.sh
```

The unit tests cover key handling and gesture smoothing. To check gesture encoding locally without posting input:

```sh
dist/PinchDial.app/Contents/MacOS/PinchDial --check-gesture-encoding
```

Verify actual zooming with the physical dial in your target apps. The gesture backend uses undocumented macOS event fields, so compatibility can vary by app and OS version; automated checks do not prove delivery.
