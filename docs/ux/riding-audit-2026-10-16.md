# Riding screen audit — 16 October 2026

Scope: the Active Ride navigation screen as a Rider uses it with the phone
mounted. Rendered at Redmi 8 size (360×760 dp, status and 3-button navigation
bars) with `tool/ui_audit/redmi8_ride_screens_test.dart`.

## Findings and changes

| # | Finding | Change |
|---|---|---|
| 1 | The dock crashed layout (a stretched row inside an unbounded column), leaving the whole riding screen blank in release builds. No test covered the screen. | Fixed-height dock; `test/active_ride_navigation_screen_test.dart` now renders the screen at Redmi 8 size in CI. |
| 2 | Status cepat needed two taps (open sheet, choose). | Berhenti, Tertinggal and Bantuan are dock buttons that send with one tap; long-press adds a note. |
| 3 | Other Riders' Status cepat, SOS and convoy separation were not visible while navigating; Leader/Sweeper had to open Rombongan. | One attention strip on the map shows the most urgent item; tap opens the detail. |
| 4 | App bar plus a wrapping status row took ~100 dp and the dock carried a permanent two-line disclaimer and status line. | Overlays on the map; disclaimer kept on the SOS screen; SOS state shown on the button. |
| 5 | Maneuver text used body sizes on a light card. | High-contrast card: 30 sp distance, 18 sp instruction, remaining distance/time; orange while off route. |
| 6 | The SOS label overflowed narrow slots. | Compact SOS label that scales down instead of overflowing. |
| 7 | The screen could time out mid-ride (Redmi default 30 s–1 min). | Screen stays on while navigation is shown. |
| 8 | Before navigation started, the group summary showed red "Koneksi terputus". | Neutral until the Ride session has started. |

## Not changed yet (recommendations)

- Voice guidance (spoken turns) for riders who cannot look at the screen.
- Night/dark map style and automatic dark mode for night rides.
- Landscape layout for handlebar mounts that hold the phone sideways.
- Live Group, Comms and SOS screens were not audited at the same depth.

These need device evidence (Redmi 8 field test) before prioritising.
