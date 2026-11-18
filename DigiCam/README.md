# DigiCam

Retro digicam app for iOS: old-iPhone-style and compact-CCD-style modes, natural grain,
small photos, and low-bitrate video. Requires iOS 16+ and a real iPhone (the simulator has no camera).

## Build option A: manual (no extra tools)

1. Xcode > File > New > Project > iOS > App. Name it `DigiCam`, Interface: SwiftUI, Language: Swift.
2. Delete the template `ContentView.swift` and `DigiCamApp.swift`.
3. Drag every `.swift` file from `DigiCam/DigiCam/` into the project (tick "Copy items if needed").
4. Select the target > Info tab > add these keys:
   - `Privacy - Camera Usage Description`
   - `Privacy - Microphone Usage Description`
   - `Privacy - Photo Library Additions Usage Description`
   (any text works for each)
5. Target > General > Deployment Info: iOS 16.0, iPhone only, Portrait only.
6. Target > Signing & Capabilities: pick your Team (a free Apple ID works).

## Build option B: XcodeGen

```
brew install xcodegen
cd DigiCam
xcodegen
open DigiCam.xcodeproj
```
Then set your Team under Signing & Capabilities.

## Run on your phone

Plug in the iPhone, select it as the run destination, press Run.
On the phone: Settings > General > VPN & Device Management > trust your developer profile
(and enable Developer Mode under Settings > Privacy & Security if asked).

## Make an IPA

Product > Archive > Distribute App > choose:
- **Development** or **Ad Hoc**: gives an .ipa for devices registered to your Apple Developer account.
- **App Store Connect**: for TestFlight / App Store (needs the paid $99/yr program).

Without the paid program, Xcode builds expire after 7 days. Tools like AltStore or Sideloadly
can re-sign an .ipa for personal use.

## Tweaking the look

Everything lives in `CameraProfile.swift`. Each profile has photo size, video size/bitrate,
JPEG quality, color, softness, bloom, fringing, vignette, grain, and date stamp.
Copy a profile, change the numbers, and it appears in the app automatically.

## Notes

- Photos come from the 1080p video stream (what you see is what you get), so the max photo width is 1080.
- Mode names are generic on purpose. Using "iPhone" or "Cyber-shot" in the app name or
  store listing can get you rejected or a trademark notice.
- The "Flash" bolt simulates a harsh flash look for photos (it does not fire the LED).
- This code was written without compiling it (no Xcode here). If Xcode shows a build
  error, paste it to me and I'll fix it.
