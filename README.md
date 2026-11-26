# ISS Sky Tracker

An iPhone app that uses your location to predict when the International Space Station will
be visible from where you are, and draws its trajectory over the live camera view when you point the phone at the sky.

## Features

- **Sky view (camera):** hold the phone up and the app draws the horizon, compass points, the ISS's
  current position and the path of the current or next pass, with a time tick every minute.
  An arrow at the screen edge points to the ISS (or to where it will appear) when it's out of frame.
- **Pass list:** every pass over the next 10 days, grouped by day, with the date, time, direction,
  maximum height and duration. By default it shows only the passes you can actually see.
- **Pass detail:** a sky chart of the path, exact appear/peak/disappear times and directions,
  a "Show this pass in the sky" button, and a reminder 10 minutes before the pass starts.

A pass counts as *visible* when the ISS is lit by the sun, your sky is dark (sun at least 6° below the
horizon) and the ISS is at least 10° above the horizon.

## How it works

| Piece | File |
|---|---|
| Orbit data (TLE) from [CelesTrak](https://celestrak.org), cached for 6 h | `ISSSkyTracker/Services/TLEService.swift` |
| SGP4 orbit propagator (near-Earth), checked against the Vallado 2006 reference values | `ISSSkyTracker/Orbit/SGP4.swift` |
| Sidereal time, Earth-fixed frames, sun position, Earth's shadow | `ISSSkyTracker/Orbit/Astro.swift` |
| Pass search and visibility | `ISSSkyTracker/Orbit/PassPredictor.swift` |
| Phone orientation (CoreMotion, true-north frame) | `ISSSkyTracker/Services/MotionService.swift` |
| Projection of sky directions onto the camera image | `ISSSkyTracker/Views/SkyOverlay.swift` |

The orbit code depends only on Foundation, and there are no third-party dependencies.

## Building

Requires a Mac with **Xcode 16 or newer** (free from the Mac App Store). You need an iPhone to test the camera and compass;
the simulator has no camera or compass, but the Passes tab works there.

1. Open `ISSSkyTracker.xcodeproj` in Xcode.
2. Select the **ISSSkyTracker** target → *Signing & Capabilities* → choose your Team
   (a free Apple ID works for running on your own phone).
3. Plug in your iPhone, select it as the run destination, and press **Run** (⌘R).
4. On the phone, allow Location, Camera and Motion access when asked.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
After adding or removing source files, regenerate it:

```bash
brew install xcodegen && xcodegen generate
```

## Continuous integration

Each push to `main` runs `.github/workflows/build.yml` on a GitHub-hosted macOS runner, which builds the app and runs
the unit tests in the iOS Simulator. This confirms the app compiles. It does not put the app on a phone: that needs
Xcode on your Mac (steps above), or TestFlight with a paid Apple Developer account.

## Accuracy notes

- Predictions use the latest CelesTrak orbit data and are typically accurate to within a few seconds for the next few days.
  The ISS sometimes fires its engines, so the app refreshes the orbit data every few hours.
- Overlay accuracy depends on your phone's compass. If the path looks shifted sideways, move the phone in a
  figure-8 to recalibrate, and keep it away from metal and magnets.
