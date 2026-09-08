# PinchDial 0.1

A small experimental macOS menu-bar utility that translates **F18/F19 into a smoothed magnification gesture**. It uses no Keychron APIs and works with any device that emits the configured keys.

The app intercepts input through public Core Graphics APIs. **The magnification backend uses undocumented CGEvent fields.** Building successfully, passing unit tests, or counting submitted events does not prove that a particular macOS/app combination accepts the gesture. Validate the backend before tuning sensitivity.

## Build and launch

Requires macOS 13+ and an installed Xcode/Swift toolchain. Complete the one-time local signing setup below before building. There are no external packages. The scripts keep build caches in this project.

```sh
cd /Users/yangshiliang/Desktop/projects/PinchDial
bash scripts/test.sh
bash scripts/build.sh
open dist/PinchDial.app
```

The build produces `dist/PinchDial.app` for the current machine's architecture and signs it with the persistent local identity **PinchDial Local Development**. The bundle identifier remains **`local.pinchdial.app`**. Run that bundle rather than `swift run` or the executable inside `.build`: permissions and login registration should refer to the app bundle.

For normal use, quit the development copy and copy the bundle to a stable location such as `~/Applications/PinchDial.app` **before granting permissions and enabling login startup**. Run only one copy. The build script does not install anything or enable login startup automatically.

## One-time local signing setup

Create this certificate once and keep using the same certificate **and private key**. Creating a new certificate with the same name does not preserve its identity. No Apple Developer account is needed.

1. Open **Keychain Access** using Spotlight (not the Passwords app). Select your **login** keychain and unlock it if necessary.
2. In the menu bar choose **Keychain Access → Certificate Assistant → Create a Certificate…**.
3. Enter **PinchDial Local Development** as the name. Choose **Self Signed Root** for Identity Type and **Code Signing** for Certificate Type.
4. Check **Let me override defaults**, then continue. Set the validity period to **3650 days** so this personal certificate will not expire after the usual short default. Keep the certificate name/common name unchanged, use **RSA, 2048 bits** (or 4096), and retain the Code Signing template's remaining defaults, including its code-signing usage. Continue through the assistant, choosing **login** as the destination keychain, and finish creating the certificate.
5. In the login keychain, find the certificate under **My Certificates**. Expand it to confirm that a private key is present. Double-click the certificate, expand **Trust**, and set **Code Signing → Always Trust**, leaving other trust purposes at their defaults. Close the dialog and authenticate if macOS asks.
6. In Terminal, run `security find-identity -v -p codesigning`. It should list `"PinchDial Local Development"` as a valid identity. If not, check its private key, validity, Code Signing trust, and that the login keychain is unlocked. Avoid creating duplicate certificates with this name.
7. Quit PinchDial and run `bash scripts/build.sh`. If Keychain asks whether `/usr/bin/codesign` may use this certificate's private key, allow it; **Always Allow** can remember access for future local builds. Do not change the key to allow every application to access it.

The certificate wizard is documented in [Apple's self-signed certificate guide](https://support.apple.com/guide/keychain-access/kyca8916/mac). The script does not create certificates or modify Keychain settings. It fails before compilation or replacing the existing app if the selected identity is missing or invalid, and never falls back to ad-hoc signing.

To use a differently named local Code Signing certificate:

```sh
CODE_SIGN_IDENTITY='My Local Code Signing Certificate' bash scripts/build.sh
```

Each successful build performs strict signature verification and displays the signature and designated requirement:

```sh
codesign --verify --strict dist/PinchDial.app
codesign -dv --verbose=4 dist/PinchDial.app
codesign -d -r- dist/PinchDial.app
```

Expect `Identifier=local.pinchdial.app`, an `Authority` identifying your local certificate, and a designated requirement based on the identifier and certificate anchor, rather than just `cdhash`. The executable's `CDHash` may still change on every rebuild; the **designated requirement** is what should remain stable. A missing TeamIdentifier is normal for this local certificate. See [Apple's explanation of designated requirements](https://developer.apple.com/library/archive/technotes/tn2206/).

Switching from the old ad-hoc signature is an identity change. After the first certificate-signed build, quit the app, remove its old entries in **Accessibility** and **Input Monitoring** if present, add/enable the new app from your chosen stable path, and relaunch. Keep using that same certificate, bundle identifier, and app location for subsequent rebuilds. This removes the code-hash-based identity churn; macOS can still require reauthorization for other reasons, so permission persistence is not an unconditional guarantee.

Quit PinchDial before rebuilding or replacing the app. This is exclusively a local development workflow: no provisioning profiles, additional entitlements, notarization, or distribution tooling are used.

## First run

1. In Keychron Launcher, set clockwise rotation to **F18**, counterclockwise to **F19**. Use a normal key press/release per detent, not a held key or a repeating macro.
2. Open PinchDial. It has a magnifying-glass menu-bar icon and no Dock icon. The setup/diagnostics window opens on first launch and while Accessibility access is missing. Reopening the running app brings back diagnostics and retries the input connection.
3. Choose **Grant Accessibility…** from the menu; enable PinchDial in System Settings → Privacy & Security → Accessibility.
4. If listening is unavailable, choose **Grant Input Monitoring…** and enable it in Privacy & Security → Input Monitoring. macOS can require quitting and reopening the app.
5. Choose **Retry Input Connection**. Diagnostics reports Accessibility, listen access, post access, and actual event-tap state separately.
6. First enable **Observe Only (Pass Keys Through)**. Turn the dial and check that “Matched key presses” increases and the last key changes between F18 and F19. This mode creates a passive tap and does not synthesize or swallow keys. It resets on the next launch.
7. Turn Observe Only off and keep **Enable PinchDial** checked. Close diagnostics, activate Safari/Preview/Maps, put the pointer over the content, and turn the dial.

F18/F19 from every device are reserved while translation is enabled. Other key events pass through unchanged and are not recorded. Auto-repeat does not generate additional zoom steps. Standard sensitivity requests roughly 3.6% scale change per clockwise detent before application-specific interpretation.

## Test the backend separately

Choose **Test Zoom In After 3 Seconds** from the diagnostics window or menu bar, then focus the target application and position the pointer over content. After three seconds PinchDial submits one clockwise detent, including begin/change/end. The current sensitivity and direction settings apply, so reverse direction makes this test zoom out.

This bypasses the hardware key bridge but still requires a working tap and posting permissions. It will not send a gesture if PinchDial's own diagnostics window is frontmost. Disable, configuration changes, sleep/session suspension, and Quit cancel a scheduled test.

“Submitted gesture samples” counts successful event construction/posting calls, **not confirmed delivery or rendering**. A zero-delta changed event is deliberately sent after began, following the historical experimental recipe.

For an additional developer check that does not inject events or request permissions:

```sh
dist/PinchDial.app/Contents/MacOS/PinchDial --check-gesture-encoding
```

This constructs begin/change/end/cancel events and converts them locally to `NSEvent`, checking the magnify type, phase, and signed magnitude. Passing establishes that AppKit recognizes the local encoding on this OS; it does not establish system-wide delivery.

## Manual acceptance checks

Start with other input remappers disabled to isolate this app.

| Check | Expected result |
| --- | --- |
| Observe-only, slow turns | One matched key-down per detent, correct F18/F19 direction, no synthesized samples |
| Observe-only, fast turns | Counter continues increasing; check for firmware batching or dropped steps |
| Safari over webpage content | Pinch-like visual magnification; compare against a real trackpad pinch |
| Preview image and PDF | Smooth zoom in both directions, no lingering movement |
| Maps over the map | Continuous zoom, sensible anchor at the initial pointer location |
| Stop turning | Gesture active becomes “no”; frame timer stops |
| Fast reversal | New direction takes effect without fighting the old smoothing tail |
| Change active apps while turning | Old pending zoom is discarded; no old tail sent into the new app |
| Disable | Subsequent F18/F19 pass through, no synthetic output |
| Sleep/wake and session switching | Pending gesture clears; reconnect with Retry if necessary |
| Ordinary typing and scrolling | Unmodified |
| Launch at Login | Enable from stable installed copy, log out/in, verify exactly one instance |
| Idle CPU | Close diagnostics and menus, wait a few seconds, inspect Activity Monitor; no animation timer runs |

The diagnostics window deliberately refreshes twice per second while open. Close it for an idle-energy measurement. A small tap callback still runs for ordinary keyboard events and immediately passes them through.

## Troubleshooting

- **No matched keys:** enable Observe Only, check actual tap connectivity and Input Monitoring, then Retry or relaunch. Verify Launcher is emitting F18/F19, not a consumer/media key or a held key. Test away from a password field or an app using Secure Input.
- **Keys counted, no submitted samples:** turn Observe Only off, enable PinchDial, check Accessibility/post access, and focus another application. The utility intentionally does not zoom its own setup window.
- **Samples submitted, no zoom:** focus supported content under the pointer and try the delayed test in Safari, Preview, and Maps. This points toward routing/gesture-format/app compatibility, not the wheel mapping. There is no automatic keyboard-zoom fallback.
- **Tap disconnected after permission changes:** Retry; if macOS asks for a restart, quit and reopen. When first switching from ad-hoc signing to the persistent local certificate, remove/re-add PinchDial in the appropriate privacy settings. See the local signing setup above.
- **Unexpected direction or speed:** use Reverse Zoom Direction and Gentle/Standard/Fast. Disable other zoom/scroll remappers during diagnosis.
- **Login startup fails:** use the bundled, signed app from a stable location. Check System Settings → General → Login Items and the error shown by PinchDial. Main-app login registration is not a crash-restarting supervisor.
- **Stop immediately:** uncheck Enable PinchDial or choose Quit from its menu. The app installs no driver, daemon, or virtual device.

## Architecture

```text
Device F18/F19
    → InputService: session CGEventTap on a dedicated run-loop thread
    → KeyBridge: one signed step per non-repeating key-down
    → MagnificationEngine: lifecycle + bounded log-scale smoothing
    → GestureBackend: experimental CGEvent encoding and posting
    → macOS routing → target application's gesture handler
```

- `Sources/PinchDial/AppDelegate.swift`: AppKit menu, setup/diagnostics, preferences, permission entry points, and `SMAppService.mainApp` registration. UI stays on the main thread. A 0.5-second refresh timer exists only while diagnostics is open.
- `Sources/PinchDial/InputService.swift`: owns the tap and active-only 60 Hz timer on one worker run loop. It recognizes only F18/F19, suppresses their down/up events when translating, and leaves unrelated input alone. First input captures the active application's PID and the current pointer location; that location stays fixed for the gesture. It does not move the cursor or activate target apps.
- `Sources/PinchDialCore/KeyBridge.swift`: deterministic suppression and auto-repeat bookkeeping. Key-up does not end a gesture; successive detents belong to one burst. A release belonging to a swallowed press remains swallowed if translation is disabled mid-press.
- `Sources/PinchDialCore/MagnificationEngine.swift`: receives explicit timestamps. Each step adds signed log-scale movement, capped at 0.5 pending units. Frames exponentially approach the target with a 45 ms time constant, emit `exp(delta) - 1`, and clamp frame movement to 0.04 log units. Reversal discards the old pending tail. It ends once input has been quiet for at least 160 ms and the tiny remaining tail has drained. A scheduling stall over 500 ms cancels rather than replaying backlog.
- `Sources/PinchDial/GestureBackend.swift`: all undocumented constants live here: type 29, subtype field 110 = 8, phase field 132, magnitude field 113; phase bits 1/2/4/8. It posts into the HID event stream. On interruption it attempts a terminal cancellation directly to the original PID to avoid sending cleanup into a newly active app. Delivery of this cancellation is also experimental and unacknowledged.

The worker serializes all engine state and receives commands through `CFRunLoopPerformBlock`. The app cancels pending gestures on focus/configuration changes, session suspension, sleep, or shutdown, and attempts to reenable a tap disabled by macOS. Synthetic output is tagged with a private source marker. Permissions and Secure Input gate generation.

The pure core is tested independently of macOS event posting. Tests cover complete lifecycle, burst grouping, frame-rate-independent total scale, bounded output/backlog, reversal, interruption, reciprocal opposite gestures, direction inversion, repeat handling, and key-up suppression. These tests cannot validate application compatibility or permission behavior.

## Validation of this first build

On the development Mac (Apple Silicon, macOS 26.6.2):

- Release compilation and strict code-signature verification passed.
- All 12 core tests passed.
- All five local AppKit encoding checks passed: begin, positive change, negative change, end, and cancellation became `.magnify` events with the expected phases and values.
- The bundled app launched; the setup window, diagnostic text, permission controls, and Retry control were inspected through native UI automation.
- On September 8, 2026, after granting permissions to the certificate-signed app, the delayed test submitted 25 gesture samples and visibly magnified the temporary grid image in Preview. Preview's Actual Size reset control became available, and PinchDial returned to an inactive gesture state.
- A subsequent code change and rebuild with the same local certificate preserved Accessibility, listen, and post access, with a connected event tap. The executable hash changed while its certificate-based designated requirement stayed identical.
- Automation-generated F18 presses targeted at Preview did not register in PinchDial's global listener, so they did not validate the key bridge. Physical dial input, Safari/Maps compatibility, login startup, and active/idle CPU measurements remain manual acceptance checks.

## Limitations and next steps

- The event backend is unsupported and can stop working after an OS update. Test each macOS/app combination explicitly.
- This generates recognized magnification events, not raw finger contacts or a virtual trackpad. An app requiring additional touch metadata may ignore it.
- No per-device identification, HID integration, scroll input adapter, app profiles, or acceleration.
- The pointer anchor is held for a burst. Changing windows inside the same process, physical pinches overlapping synthetic ones, unusual modifier combinations, and third-party remappers need further compatibility testing.
- Target apps choose zoom limits, sensitivity, and rendering cadence. 60 Hz submission does not guarantee 60 FPS rendering.
- Accessibility or Input Monitoring revocation may require manual Retry/relaunch; there is no periodic permission polling while idle.

Once magnification is verified on the intended apps, the next priorities are device timing measurements, smoothing tuning, and a recorded app/OS compatibility matrix.

## Research references

- [Apple: Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz-event-services)
- [Apple: Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)
- [Apple: Input Monitoring guidance](https://developer.apple.com/forums/thread/724608)
- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Historical standalone magnification experiment in Mac Mouse Fix discussion #366](https://github.com/noah-nuebling/mac-mouse-fix/discussions/366)
- [Calftrail TouchSynthesis](https://github.com/calftrail/Touch/blob/master/TouchSynthesis/TouchSynthesis.m)
- [BetterTouchTool: Scroll Modifiers](https://docs.folivora.ai/docs/normal-mouse/scroll-modifiers/)
