# IP Call BD — Flutter Calling App

A Flutter softphone for the IP Call BD PBX, equivalent to the
[ipcall-bd-webrtc-demo](https://github.com/ipcallbd/ipcall-bd-webrtc-demo/)
browser phone. Uses **SIP over WebRTC** (WSS signaling, DTLS/SRTP audio) via
the [`sip_ua`](https://pub.dev/packages/sip_ua) package.

## Features

- SIP registration with extension + password (saved on the device)
- Audio calls: dialpad, incoming call screen (answer / reject)
- In-call controls: mute, speaker toggle, hold, DTMF keypad, hangup
- Registration status chip with one-tap reconnect, sign out

## Configure your extension

The app ships with the demo server pre-filled — just enter your extension and
password on the login screen:

| Field     | Value            |
|-----------|------------------|
| SIP server| `talk.ipcall.bd` |
| Extension | *yours*          |
| Password  | *yours*          |

The WebSocket URL is derived automatically: `wss://<server>/ws`.

## Run

```bash
flutter pub get
flutter run                 # pick an Android device or Chrome
```

Note: on Chrome you must allow microphone access; on Android the mic permission
is requested on first call.

## Build

```bash
flutter build apk --release
```

```bash
flutter run -d windows
```

## Architecture

```
lib/
  main.dart                  app entry, screen routing + remote audio sink
  models/sip_config.dart     server/extension/password, persistence
  services/sip_service.dart  SIPUAHelper wrapper: registration + call state
  screens/login_screen.dart  sign-in form
  screens/dialpad_screen.dart dialpad + status
  screens/call_screen.dart   in-call UI (answer/reject, mute/hold/DTMF)
```

## Known limitations

- **Incoming calls in background**: the SIP WebSocket dies when the app is
  backgrounded. Push notification support (FCM on Android, VoIP push + CallKit
  on iOS) is required for production-grade inbound calling.
- **PBX must be WebRTC-enabled** (DTLS/SRTP, Opus/PCMU/PCMA). If calls fail
  with `488 Not Acceptable Here`, ask IP Call BD to enable WebRTC for the
  extension.
- No TURN server configured; calls behind symmetric NAT rely on the PBX side
  relaying or adding a TURN server in `SipService.connect()`.
