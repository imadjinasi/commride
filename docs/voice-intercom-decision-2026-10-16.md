# Voice Intercom — Provider and Architecture Decision

Date: 16 October 2026
Status: Accepted by the product owner (provider, join behavior, talk modes,
moderation). Repository implementation only — no Provider, Device or Field PASS.
Related: `docs/ux/active-ride-navigation-intercom.md` (product intent)

## Context

The Active Ride riding screen already reserves an Interkom row under the group
summary. Product intent (accepted 21 September 2026): Group Intercom with a
persistent Mic On/Off is the default; an alternate talk mode exists; Listen
Only exists; mic state is always visible; joining a Ride never silently turns a
microphone on. The Durable Object Ride room carries control metadata only and
must not relay audio. Audio uses WebRTC through an SFU-class provider.

Pilot shape: 5–15 Riders per Ride, Indonesian mobile data (4G with gaps),
Android first (Redmi 8 / LineageOS / Android 16 is the reference device),
music app playing in parallel, often a Bluetooth helmet headset.

## Options compared

Figures are from public price pages read on 16 October 2026 and must be
re-checked before any paid plan is enabled. Audio-only, everyone hears
everyone, one Ride-hour = Riders × 60 participant-minutes.

| | Cloudflare RealtimeKit | LiveKit Cloud | Cloudflare Realtime SFU (raw) |
|---|---|---|---|
| What it is | Managed rooms + SDKs on Cloudflare Realtime | Managed rooms + SDKs (open-source server) | Bare WebRTC SFU; we build rooms/signalling |
| Flutter SDK | **Discontinued 7 Aug 2026**; native Android SDK `com.cloudflare.realtimekit:core` 3.2.0 is maintained | `livekit_client` 2.13.x, widely used | none — `flutter_webrtc` + our own protocol |
| Price | $0.0005 / audio participant-minute, no free allowance, no monthly fee | Build: free, 5,000 participant-min/month; Ship: $50/month incl. 150,000 min, then ~$0.0005/min | $0.05/GB egress after 1 TB/month free |
| 5 Riders · 1 h | ≈ $0.15 | free inside allowance / ≈ $0.15 over | ≈ $0 |
| 10 Riders · 1 h | ≈ $0.30 | free inside allowance / ≈ $0.30 over | ≈ $0 |
| 15 Riders · 1 h | ≈ $0.45 | free inside allowance / ≈ $0.45 over | ≈ $0 |
| Join token | Worker calls Cloudflare API (meeting + participant) | Worker signs a JWT locally | Worker calls Realtime API per session/track |
| Per-listener mute of one Rider | **Not exposed** by the Android SDK | Supported | Ours to build |

Common to all: Opus speech, WebRTC echo cancellation, noise suppression and
auto gain on the device. Expected Rider data use is roughly 10–30 MB per
Ride-hour depending on how much the group talks (not yet measured). Expected
mouth-to-ear latency on Indonesian 4G is a few hundred milliseconds (Cloudflare
has a Jakarta PoP) — unverified until a field test.

## Decision

**Cloudflare RealtimeKit**, chosen by the product owner for one Cloudflare
account and per-minute billing without a monthly fee. Because the Flutter SDK
was discontinued, CommRide ships its own small Android bridge
(`apps/mobile/tool/android/CommRideIntercom.kt`, installed by
`tool/configure_platforms.py`) over the maintained native Android SDK.

Consequences accepted with this choice:

- **Android only for now.** iOS shows "Interkom belum tersedia di HP ini" until
  an iOS bridge over the native iOS SDK is built and verified.
- **No "mute one Rider only for me".** The Android SDK has no per-listener
  volume for a single participant, so the control stays hidden rather than
  faked. Leader mute (for everyone) is supported.
- The SDK requires `compileSdk 37` and core-library desugaring; it adds roughly
  the size of a WebRTC build to the APK. `targetSdk` and `minSdk 24` are
  unchanged.
- The SDK manifest also asks for camera, storage and screen sharing; CommRide
  removes those from the merged manifest (`tools:node="remove"`).

LiveKit stays the documented fallback if RealtimeKit's Android SDK or pricing
stops fitting; the Dart side talks to a `RideVoiceTransport` interface, so a
provider swap replaces the transport and the Worker adapter only.

## Talk modes and controls

Riders cannot tap the screen while riding.

- **Join:** when guidance starts, the Rider joins the Ride room **listening**.
  The microphone turns on only after the Rider taps it.
- **Mic aktif terus (default):** after the tap the mic stays on until the Rider
  turns it off. WebRTC noise suppression keeps non-speech traffic low.
- **Tap untuk bicara:** tap the mic, speak, tap again. A turn closes by itself
  after 30 seconds so a forgotten tap never leaves the mic open.
- **Dengar saja:** never transmits.
- Switching mode always closes the mic; the Rider opens it again deliberately.
- **Leader mute:** only the Ride Leader (RealtimeKit preset with host permission
  to disable participant audio) can mute a Rider for everyone. It never turns
  anyone's mic on. The muted Rider sees "Mic dimatikan Ketua" and can turn the
  mic on again with their own tap.
- The Interkom row stays one 48 dp row: state or "<name> bicara", a settings
  button (mode, Riders in the room, Leader mute, leave) and one large mic
  button.

## Android realities

- **Foreground service, type `microphone`** (`IntercomService`) starts only
  after the Rider's mic tap succeeds (permission granted, app visible), so the
  mic keeps working with the screen locked. Google Play needs a
  `FOREGROUND_SERVICE_MICROPHONE` declaration with a short video before
  release. The location service keeps its own `location` type.
- **Bluetooth helmet headsets.** Classic Bluetooth headsets switch to the call
  profile (HFP/SCO) while the mic is in use: voice works, but music in the
  headset becomes mono "phone call" quality while the intercom is connected.
  This is a Bluetooth limitation. LE Audio headsets can avoid it but are rare.
  Must be checked per headset on device.
- **Music.** The intercom uses communication audio mode; music keeps playing
  and the music row keeps working (media keys are not repurposed). Android may
  lower music while someone speaks. Must be checked on device.
- **Leaving.** Leaving the riding screen, ending the Ride or "Keluar interkom"
  leaves the room and stops the service.

## Security and data

- `REALTIMEKIT_ACCOUNT_ID`, `REALTIMEKIT_APP_ID` and secret
  `REALTIMEKIT_API_TOKEN` live only in the Worker. Presets
  `commride_rider` / `commride_leader` (names configurable) must exist in the
  RealtimeKit app, audio only.
- `POST /v1/rides/{rideId}/intercom/token` returns a join token only for an
  authenticated Rider with a participating membership in an Active Ride. One
  RealtimeKit meeting per Ride is stored in `ride_intercom_rooms` (migration
  0012). The Rider's callsign (or display name) and Rider id are sent to
  Cloudflare as the participant name and custom id.
- CommRide records and stores no audio. RealtimeKit recording stays off.

## Gates

Repository PASS (tests, build) ≠ Provider PASS (real meeting with real
credentials) ≠ Device PASS (two phones in one Ride, lock screen, Bluetooth,
music) ≠ Field convoy PASS. The client stays behind
`COMMRIDE_VOICE_INTERCOM_ENABLED=false` and the Worker answers
`503 intercom_not_configured` until secrets exist. Device evidence goes in
`docs/deployment/voice-intercom-device-evidence.md`.
