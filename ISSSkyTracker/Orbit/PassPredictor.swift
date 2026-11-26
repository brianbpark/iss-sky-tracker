import Foundation

/// Where the satellite appears in the observer's sky at one instant.
struct SkySample: Hashable {
    let date: Date
    let azimuth: Double        // degrees from true north
    let elevation: Double      // degrees above horizon
    let rangeKm: Double
    let sunlit: Bool           // satellite is lit by the sun
    let sunElevation: Double   // sun's elevation at the observer, degrees

    var compass: String { Astro.compass(azimuth) }
}

/// One passage of the satellite above the observer's horizon.
struct ISSPass: Identifiable, Hashable {
    var id: Date { rise.date }
    let rise: SkySample
    let culmination: SkySample
    let setting: SkySample
    /// Samples every few seconds from rise to set.
    let path: [SkySample]
    /// First and last moments the ISS can be seen with the naked eye (nil if never).
    let visibleStart: SkySample?
    let visibleEnd: SkySample?
    let maxVisibleElevation: Double?

    var isVisible: Bool { visibleStart != nil }
    var duration: TimeInterval { setting.date.timeIntervalSince(rise.date) }

    /// Why this pass cannot be seen, if it can't.
    var invisibilityReason: String? {
        guard !isVisible else { return nil }
        let dark = path.filter { $0.sunElevation < PassPredictor.sunLimit }
        if dark.isEmpty { return "Daylight" }
        let darkAndLit = dark.filter(\.sunlit)
        if darkAndLit.isEmpty { return "ISS in Earth's shadow" }
        return "Too low"
    }
}

/// Current state of the ISS for the "now" readout.
struct ISSNow {
    let sky: SkySample
    let latitude: Double
    let longitude: Double
    let altitudeKm: Double
    let speedKmS: Double
}

struct PassPredictor {
    /// Naked-eye visibility needs the ISS at least this high...
    static let minVisibleElevation = 10.0
    /// ...and the sky dark enough (civil twilight or darker).
    static let sunLimit = -6.0

    let sgp4: SGP4
    let observer: Observer

    func sample(at date: Date) -> SkySample? {
        guard let state = try? sgp4.propagate(to: date) else { return nil }
        let g = Astro.gmst(date)
        let look = observer.lookAngles(toEcef: Astro.temeToEcef(state.position, gmst: g))
        let sun = Astro.sunPosition(date)
        let sunLook = observer.lookAngles(toEcef: Astro.temeToEcef(sun, gmst: g))
        return SkySample(date: date, azimuth: look.azimuth, elevation: look.elevation,
                         rangeKm: look.rangeKm, sunlit: Astro.isSunlit(sat: state.position, sun: sun),
                         sunElevation: sunLook.elevation)
    }

    func now(_ date: Date = Date()) -> ISSNow? {
        guard let state = try? sgp4.propagate(to: date), let sky = sample(at: date) else { return nil }
        let geo = Astro.geodetic(Astro.temeToEcef(state.position, gmst: Astro.gmst(date)))
        return ISSNow(sky: sky, latitude: geo.latitude, longitude: geo.longitude,
                      altitudeKm: geo.altitudeKm, speedKmS: state.velocity.length)
    }

    private func elevation(_ date: Date) -> Double {
        sample(at: date)?.elevation ?? -90
    }

    /// Finds the moment between `a` and `b` where elevation crosses 0°.
    private func horizonCrossing(_ a: Date, _ b: Date) -> Date {
        var lo = a, hi = b
        let rising = elevation(a) < 0
        for _ in 0..<20 {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            if (elevation(mid) < 0) == rising { lo = mid } else { hi = mid }
        }
        return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
    }

    /// All passes (visible or not) that end after `start` and begin within `days`.
    func passes(from start: Date = Date(), days: Double = 10, step: TimeInterval = 30,
                pathStep: TimeInterval = 5) -> [ISSPass] {
        var result: [ISSPass] = []
        let end = start.addingTimeInterval(days * 86_400)
        // Begin a bit earlier so a pass already in progress is found from its rise.
        var t = start.addingTimeInterval(-20 * 60)
        var prevEl = elevation(t)
        while t < end {
            let next = t.addingTimeInterval(step)
            let el = elevation(next)
            if prevEl < 0 && el >= 0 {
                let rise = horizonCrossing(t, next)
                // Walk forward to the set.
                var a = next, b = next.addingTimeInterval(step)
                while elevation(b) >= 0 && b.timeIntervalSince(rise) < 30 * 60 {
                    a = b; b = b.addingTimeInterval(step)
                }
                let setTime = horizonCrossing(a, b)
                if setTime > start, let pass = makePass(rise: rise, set: setTime, pathStep: pathStep) {
                    result.append(pass)
                }
                t = b
                prevEl = elevation(b)
                continue
            }
            t = next
            prevEl = el
        }
        return result
    }

    private func makePass(rise: Date, set: Date, pathStep: TimeInterval) -> ISSPass? {
        var path: [SkySample] = []
        var d = rise
        while d < set {
            if let s = sample(at: d) { path.append(s) }
            d = d.addingTimeInterval(pathStep)
        }
        guard let first = path.first, let last = sample(at: set) else { return nil }
        path.append(last)
        let top = path.max(by: { $0.elevation < $1.elevation })!
        let visible = path.filter {
            $0.sunlit && $0.sunElevation < Self.sunLimit && $0.elevation >= Self.minVisibleElevation
        }
        return ISSPass(rise: first, culmination: top, setting: last, path: path,
                       visibleStart: visible.first, visibleEnd: visible.last,
                       maxVisibleElevation: visible.map(\.elevation).max())
    }
}
