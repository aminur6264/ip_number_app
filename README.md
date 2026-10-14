# IP Number Calling App (IP Call BD)

A cross-platform **SIP softphone** built with **Flutter** for the
[IP Call BD](https://ipcall.bd) PBX. It registers as a SIP extension over
**WebSocket Secure (WSS)** and places/receives **audio calls using WebRTC**
(DTLS/SRTP media, Opus/PCMU/PCMA) — the mobile/desktop equivalent of the
[ipcall-bd-webrtc-demo](https://github.com/ipcallbd/ipcall-bd-webrtc-demo/)
browser phone.

Runs on **Android, Web (Chrome), and Windows** (iOS scaffolding is also
included).

## Repository layout

```
ip_number_app/
├── CallingApp/                  # Flutter project (the actual app source)
│   ├── lib/
│   │   ├── main.dart            # App entry, routing, remote audio sink
│   │   ├── models/
│   │   │   └── sip_config.dart  # SIP account config + persistence
│   │   ├── services/
│   │   │   └── sip_service.dart # SIPUAHelper wrapper (registration + calls)
│   │   └── screens/
│   │       ├── login_screen.dart
│   │       ├── dialpad_screen.dart
│   │       └── call_screen.dart
│   ├── android/  web/  windows/  ios/   # Platform runners
│   ├── tool/generate_app_icon.dart      # Launcher icon generator (pure Dart)
│   └── pubspec.yaml
└── IP Number Calling App.apk    # Pre-built release APK
```

## Features

- **SIP registration** with extension + password (credentials saved on device
  via `shared_preferences`)
- **Outgoing calls** from a dialpad (`*` / `0` / `#` supported)
- **Incoming call screen** with answer / reject
- **In-call controls**: mute, speaker toggle, hold, DTMF keypad (RFC 2833
  telephone events), hangup
- **Registration status chip** with one-tap reconnect and sign out
- **Graceful teardown**: BYE/CANCEL is sent on app close so the far end is not
  left hanging
- Dark Material 3 theme, custom launcher icon generated from
  `assets/icon/app_icon.png`

## Tech stack

| Layer             | Package                                        |
|-------------------|------------------------------------------------|
| SIP over WebRTC   | [`sip_ua`](https://pub.dev/packages/sip_ua) (Dart port of JsSIP) |
| WebRTC media      | [`flutter_webrtc`](https://pub.dev/packages/flutter_webrtc) |
| Credential storage| [`shared_preferences`](https://pub.dev/packages/shared_preferences) |
| Framework         | Flutter ≥ 3.41 / Dart ≥ 3.11                   |

## Prerequisites

1. **Flutter SDK** ≥ 3.41 (stable). Verify with:

   ```bash
   flutter doctor
   ```

2. Platform-specific extras:
   - **Android**: Android Studio + SDK, and a device/emulator. To deploy over
     USB, enable *Developer options → USB debugging* on the phone.
   - **Web**: Google Chrome (or any WebRTC-capable browser).
   - **Windows**: Visual Studio 2022 with the *Desktop development with C++*
     workload.

3. A **SIP extension** issued by the IP Call BD PBX (extension number +
   password). The demo server `talk.ipcall.bd` is pre-filled in the login
   form; the WebSocket URL is derived automatically as `wss://<server>/ws`.

## Running the app

All commands are run from the `CallingApp/` directory:

```bash
cd CallingApp
flutter pub get
```

### 📱 Android

```bash
flutter devices               # confirm your device/emulator is listed
flutter run -d <device-id>    # e.g. flutter run -d R58N...)
```

Or simply:

```bash
flutter run
```

and pick the Android target when prompted. The microphone permission
(`RECORD_AUDIO`) is requested on the first call. `INTERNET`, `MODIFY_AUDIO_SETTINGS`
and `WAKE_LOCK` permissions are already declared in
`android/app/src/main/AndroidManifest.xml`.

**Install the pre-built APK directly** (no toolchain needed): copy
`IP Number Calling App.apk` from the repo root to the phone and open it, or:

```bash
adb install "IP Number Calling App.apk"
```

### 🌐 Web (Chrome)

```bash
flutter run -d chrome
```

- Allow **microphone access** when the browser prompts — WebRTC calls will not
  work without it.
- Browsers only grant microphone access on `https://` pages (or `localhost`
  during development). A deployed web build must be served over HTTPS; the
  SIP signaling always uses `wss://` so there are no mixed-content issues.
- The speaker toggle is a UI flag only on web (browsers control audio routing).

### 🪟 Windows

```bash
flutter run -d windows
```

First build downloads the engine artifacts and compiles the C++ runner, so it
takes a while. Windows Defender may prompt about microphone access on the
first call.

## Building release artifacts

```bash
# Android APK (output: build/app/outputs/flutter-apk/app-release.apk)
flutter build apk --release

# Split per ABI (smaller downloads)
flutter build apk --release --split-per-abi

# Web (output: build/web/)
flutter build web --release

# Windows (output: build/windows/x64/runner/Release/)
flutter build windows --release
```

### Regenerating the launcher icon

The launcher icons are generated from a single master image by a pure-Dart
script, then applied to Android/iOS/web/Windows via `flutter_launcher_icons`:

```bash
dart run tool/generate_app_icon.dart    # regenerate assets/icon/*.png
dart run flutter_launcher_icons         # re-apply to all platforms
```

## Configuring your SIP account

On first launch the app shows the login screen:

| Field      | Value                        |
|------------|------------------------------|
| SIP server | `talk.ipcall.bd` (default)   |
| Extension  | *your extension number*      |
| Password   | *your extension password*    |

Credentials persist between launches; use **Sign out** on the dialpad screen
to clear them.

## Architecture

`SipService` is an app-wide singleton (`ChangeNotifier`) wrapping `SIPUAHelper`.
It re-emits SIP registration/call events as notifier updates; the screens watch
it and rebuild. `HomeRouter` in `main.dart` swaps between login and dialpad and
overlays the call screen whenever a call is live. An always-mounted, invisible
`RTCVideoRenderer` sink keeps remote audio playing regardless of which screen
is visible (WebRTC requires the stream to be attached to a renderer).

```
login_screen ─┐
              ├─ watch SipService ── SIPUAHelper ── WSS ──> PBX (talk.ipcall.bd)
dialpad     ──┘                        │
call_screen (overlay) <──── call events ┘
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `488 Not Acceptable Here` | The PBX extension is not WebRTC-enabled (DTLS/SRTP + Opus/PCMU/PCMA). Ask IP Call BD to enable WebRTC. |
| No audio on web | Browser blocked the microphone — check the site permissions (padlock icon). |
| Registration fails | Verify extension/password; check the server is reachable at `wss://<server>/ws`. |
| Silent incoming audio | Ensure the remote stream is attached (handled by the always-on `RtcAudioSink`). |

## Known limitations

- **Background incoming calls**: the SIP WebSocket dies when the app is
  backgrounded, so inbound calls are only received while the app is in the
  foreground. Production-grade inbound calling needs push notifications
  (FCM on Android, VoIP push + CallKit on iOS).
- **No TURN server** configured; calls behind symmetric NAT rely on the PBX
  relaying media, or add a TURN server in `SipService.connect()`
  (`lib/services/sip_service.dart`).
- Speaker routing is a no-op on web.
