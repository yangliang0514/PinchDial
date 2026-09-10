# PinchDial

A small macOS menu-bar utility originally made for the **Keychron Nape Pro’s dial**. By default, it turns **F18 into smooth pinch-to-zoom in** and **F19 into zoom out**, and works with any keyboard or mouse that can be configured to send those keys.

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

In **Show Setup…**, move the **Sensitivity** slider toward **Slower** for finer zoom control or **Faster** to zoom more with each dial step. Changes apply immediately and are saved automatically.

Disable PinchDial to pass assigned keys through normally, or choose Quit to stop it. While enabled, it captures assigned keys from every device in other apps; keys remain available inside PinchDial for setup. Each quick press generates one zoom step. Holding a key for 400 ms starts continuous zoom at 12 steps per second, independent of macOS keyboard repeat settings. Releasing the key stops repeating zoom. Changing apps or settings, pressing a shortcut modifier, or losing input access cancels the hold; press again to resume. Command, Option, Control, and Shift combinations pass through.

**Show Setup… → Zoom shortcuts** lets you choose a key for each direction. Search the supported-key list (including F1–F20) and click a result to apply it immediately. Double-click a result to apply it and close the picker, or click outside to close it. **Use Default F18/F19** restores that direction’s default key (unless the other direction is using it). You can also choose **Record a key** and press a key or turn a configured dial to apply the recorded key immediately. Recording only listens while PinchDial is active; switching apps stops it.

Assignments apply immediately and persist across launches. Invalid searches cannot become shortcuts, and both directions cannot use the same key. Only single ordinary keys are supported in this version; modifier-only, media, and power keys are excluded. Letter and punctuation names refer to physical US keyboard positions, which may differ from the characters on another layout. Caps Lock and the Fn/numeric-pad event flags do not change shortcut matching. F18/F19 remain recommended because choosing a typing key takes that key away from other apps while enabled. Map your device to send the selected keys separately; selecting a key in PinchDial does not reprogram your device.

**Show in menu bar** immediately shows or hides the right-side PinchDial icon and remembers the choice across launches. PinchDial stays in the Dock and app switcher, even after closing Setup. Click its Dock icon to reopen Setup, or use **PinchDial → Show Setup…** (Command-comma) when the app is active. The left-side application menu also offers About, Hide, and Quit (Command-Q). Closing Setup does not stop zooming; Quit does.

**Launch at Login** in Setup registers or unregisters PinchDial with macOS immediately. Its checkbox reflects the system registration, including pending approval. If **Approval Needed…** appears, click it and allow PinchDial in System Settings; the status refreshes when you return to the app. Errors are shown without saving an incorrect checkbox state. This option is available only in Setup, not the right-side status-icon menu.

The permission buttons in the setup window remain a UI preview. Continue using the existing status-icon menu commands to request access; turn **Show in menu bar** back on if needed.

## Tests

```sh
bash scripts/test.sh
```

The unit tests cover custom shortcuts, modifier filtering, persistence validation, held-key ownership during reassignment, the key catalog, and gesture smoothing. To check gesture encoding locally without posting input:

```sh
dist/PinchDial.app/Contents/MacOS/PinchDial --check-gesture-encoding
```

Verify actual zooming with the physical dial in your target apps. The gesture backend uses undocumented macOS event fields, so compatibility can vary by app and OS version; automated checks do not prove delivery.
