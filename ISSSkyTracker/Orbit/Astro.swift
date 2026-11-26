import Foundation

/// Time, reference-frame and sun-position helpers.
enum Astro {
    static let deg = Double.pi / 180
    static let wgs84A = 6378.137              // km
    static let wgs84F = 1 / 298.257223563
    static let auKm = 149_597_870.7

    static func julianDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    /// Greenwich mean sidereal time (radians), IAU-82 model.
    static func gmst(_ date: Date) -> Double {
        let t = (julianDate(date) - 2_451_545.0) / 36_525
        var s = -6.2e-6 * t * t * t + 0.093104 * t * t
            + (876_600.0 * 3600 + 8_640_184.812866) * t + 67_310.54841
        s = fmod(s * deg / 240, 2 * Double.pi)
        return s < 0 ? s + 2 * Double.pi : s
    }

    /// Rotates an inertial (TEME) vector into the Earth-fixed frame (polar motion ignored).
    static func temeToEcef(_ r: Vec3, gmst g: Double) -> Vec3 {
        Vec3(x: cos(g) * r.x + sin(g) * r.y,
             y: -sin(g) * r.x + cos(g) * r.y,
             z: r.z)
    }

    /// Low-precision solar position (Astronomical Almanac), inertial frame, km. Good to ~0.01°.
    static func sunPosition(_ date: Date) -> Vec3 {
        let n = julianDate(date) - 2_451_545.0
        let L = (280.460 + 0.9856474 * n) * deg
        let g = (357.528 + 0.9856003 * n) * deg
        let lambda = L + (1.915 * sin(g) + 0.020 * sin(2 * g)) * deg
        let eps = (23.439 - 0.0000004 * n) * deg
        let rAU = 1.00014 - 0.01671 * cos(g) - 0.00014 * cos(2 * g)
        let r = rAU * auKm
        return Vec3(x: r * cos(lambda), y: r * cos(eps) * sin(lambda), z: r * sin(eps) * sin(lambda))
    }

    /// True if a satellite at inertial position `sat` is lit by the sun (cylindrical Earth-shadow model).
    static func isSunlit(sat: Vec3, sun: Vec3) -> Bool {
        let s = sun * (1 / sun.length)
        let along = sat.dot(s)
        if along >= 0 { return true }               // on the day side of Earth
        let perp = sat - s * along
        return perp.length > wgs84A
    }

    /// Converts an Earth-fixed position to geodetic latitude/longitude (degrees) and altitude (km).
    static func geodetic(_ r: Vec3) -> (latitude: Double, longitude: Double, altitudeKm: Double) {
        let e2 = wgs84F * (2 - wgs84F)
        let p = sqrt(r.x * r.x + r.y * r.y)
        let lon = atan2(r.y, r.x)
        var lat = atan2(r.z, p * (1 - e2))
        var h = 0.0
        for _ in 0..<5 {
            let n = wgs84A / sqrt(1 - e2 * sin(lat) * sin(lat))
            h = p / cos(lat) - n
            lat = atan2(r.z, p * (1 - e2 * n / (n + h)))
        }
        return (lat / deg, lon / deg, h)
    }

    /// 16-point compass name for an azimuth in degrees.
    static func compass(_ azimuth: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((azimuth.truncatingRemainder(dividingBy: 360) + 360 + 11.25) / 22.5) % 16
        return names[i]
    }
}

/// A place on Earth from which the sky is observed.
struct Observer: Hashable {
    var latitude: Double      // degrees
    var longitude: Double     // degrees
    var altitudeKm: Double = 0

    /// Earth-fixed position (WGS-84), km.
    var ecef: Vec3 {
        let lat = latitude * Astro.deg, lon = longitude * Astro.deg
        let e2 = Astro.wgs84F * (2 - Astro.wgs84F)
        let n = Astro.wgs84A / sqrt(1 - e2 * sin(lat) * sin(lat))
        return Vec3(x: (n + altitudeKm) * cos(lat) * cos(lon),
                    y: (n + altitudeKm) * cos(lat) * sin(lon),
                    z: (n * (1 - e2) + altitudeKm) * sin(lat))
    }

    /// Azimuth (degrees from true north, clockwise), elevation (degrees) and range (km)
    /// of an Earth-fixed target as seen from this observer.
    func lookAngles(toEcef target: Vec3) -> (azimuth: Double, elevation: Double, rangeKm: Double) {
        let d = target - ecef
        let lat = latitude * Astro.deg, lon = longitude * Astro.deg
        let east = -sin(lon) * d.x + cos(lon) * d.y
        let north = -sin(lat) * cos(lon) * d.x - sin(lat) * sin(lon) * d.y + cos(lat) * d.z
        let up = cos(lat) * cos(lon) * d.x + cos(lat) * sin(lon) * d.y + sin(lat) * d.z
        let range = d.length
        var az = atan2(east, north) / Astro.deg
        if az < 0 { az += 360 }
        return (az, asin(up / range) / Astro.deg, range)
    }
}
