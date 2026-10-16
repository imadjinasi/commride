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

| | LiveKit Cloud | Cloudflare RealtimeKit | Cloudflare Realtime SFU (raw) |
|---|---|---|---|
| Flutter SDK | `livekit_client` 2.13.x, maintained, widely used | **Discontinued 7 Aug 2026** (native Android SDK only) | none — `flutter_webrtc` + our own protocol |
| Free allowance | **Build plan $0: 5,000 participant-minutes, 50 GB downstream, 100 concurrent connections per month** | none | 1 TB egress/month |
| Paid | Ship $50/month: 150,000 min + 250 GB, then $0.0005/min and $0.12/GB | $0.0005 / audio participant-minute | $0.05/GB after the free TB |
| 10 Riders · 1 h | 600 min (free inside Build) | ≈ $0.30 | ≈ $0 |
| Join token | Worker signs a JWT locally | Worker calls Cloudflare API per join | Worker calls Realtime API per track |
| Per-listener mute of one Rider | Supported | Not exposed | Ours to build |
| Exit path | Server is Apache-2.0; can self-host later | Proprietary | Proprietary |

What the free Build plan covers: 5,000 minutes ≈ 8 Ride-hours with 10 Riders,
≈ 5.5 Ride-hours with 15 Riders, ≈ 16 Ride-hours with 5 Riders per month. The
pricing page does not say whether Build stops or bills past the allowance;
treat the allowance as a hard ceiling and check the LiveKit Cloud dashboard
usage before larger Rides.

Common to all: Opus speech with DTX (silence costs almost no data), WebRTC
echo cancellation, noise suppression and auto gain on the device. Expected
Rider data use is roughly 10–30 MB per Ride-hour depending on how much the
group talks (not yet measured). Latency on Indonesian 4G is unverified until a
field test (LiveKit Cloud routes to its nearest region, Singapore).

## Decision

**LiveKit Cloud, Build (free) plan for the pilot.** The product owner first
chose Cloudflare RealtimeKit, then switched after its Flutter SDK turned out to
be discontinued and it has no free allowance ("Ganti ke LiveKit Cloud yang ada
kuota gratis untuk masa pilot.").

- The app uses the maintained `livekit_client` Flutter SDK
  (`lib/src/active_ride/livekit_voice_transport.dart`) behind the
  `RideVoiceTransport` interface. Android first; iOS needs its own background
  audio declarations and device check before it is enabled.
- The Worker signs join tokens locally (HS256, `jose`) with
  `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` and performs Leader mute through
  LiveKit's RoomService API. No provider call happens on join, and no client
  ever holds room-admin rights.
- One LiveKit room per Ride, named `commride-ride-<rideId>`, created by LiveKit
  on the first join. No D1 table is needed.
- Moving off Build (paid Ship plan or self-hosting the open-source server)
  changes Worker configuration only.

## Talk modes and controls

Riders cannot tap the screen while riding.

- **Join:** when guidance starts, the Rider joins the Ride room **listening**.
  The microphone turns on only after the Rider taps it.
- **Mic aktif terus (default):** after the tap the mic stays on until the Rider
  turns it off.
- **Tap untuk bicara:** tap the mic, speak, tap again. A turn closes by itself
  after 30 seconds so a forgotten tap never leaves the mic open.
- **Dengar saja:** never transmits.
- Switching mode always closes the mic; the Rider opens it again deliberately.
- **Bisukan untuk saya:** any Rider can silence one other Rider for themselves
  only (the audio is not received at all, which also saves data).
- **Leader mute:** only the Ride Leader can mute a Rider for everyone
  (`POST /v1/rides/{rideId}/intercom/mute`). It never turns anyone's mic on.
  The muted Rider sees "Mic dimatikan Ketua" and can turn the mic on again
  with their own tap.
- The Interkom row stays one 48 dp row: state or "<name> bicara", a settings
  button (mode, Riders in the room, mutes, leave) and one large mic button.

## Android realities

- **Foreground service, type `microphone`** (`IntercomService`, installed by
  `tool/configure_platforms.py`) starts only after the Rider's mic tap
  succeeds, so the mic keeps working with the screen locked. Google Play needs
  a `FOREGROUND_SERVICE_MICROPHONE` declaration with a short video before
  release. The location service keeps its own `location` type. The camera
  permission declared by WebRTC is removed from the merged manifest.
- **Bluetooth helmet headsets.** Classic Bluetooth headsets switch to the call
  profile (HFP/SCO) while the mic is in use: voice works, but music in the
  headset becomes mono "phone call" quality while the intercom is connected.
  This is a Bluetooth limitation. Android 12+ may also need the Nearby devices
  (`BLUETOOTH_CONNECT`) permission for headset routing — check on device.
- **Music.** WebRTC uses communication audio mode; music keeps playing and the
  music row keeps working (media keys are not repurposed). Android may lower
  music while someone speaks. Must be checked on device.
- **Leaving.** Leaving the riding screen, ending the Ride or "Keluar interkom"
  leaves the room and stops the service.

## Security and data

- `LIVEKIT_URL` (non-secret) and secrets `LIVEKIT_API_KEY`,
  `LIVEKIT_API_SECRET` live only in the Worker.
- `POST /v1/rides/{rideId}/intercom/token` returns a 6-hour join token only
  for an authenticated Rider with a participating membership in an Active
  Ride. The token allows joining that Ride's room, listening and publishing a
  microphone — no camera, screen share, data messages or admin rights.
- The Rider's callsign (or display name) and Rider id are sent to LiveKit as
  the participant name and identity.
- CommRide records and stores no audio. LiveKit recording/egress stays off.

## Gates

Repository PASS (tests, build) ≠ Provider PASS (real room with real
credentials) ≠ Device PASS (two phones in one Ride, lock screen, Bluetooth,
music) ≠ Field convoy PASS. The client stays behind
`COMMRIDE_VOICE_INTERCOM_ENABLED=false` and the Worker answers
`503 intercom_not_configured` until secrets exist. Setup steps and device
evidence: `docs/deployment/voice-intercom-device-evidence.md`.
