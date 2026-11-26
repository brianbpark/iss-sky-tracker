import XCTest
@testable import ISSSkyTracker

final class OrbitTests: XCTestCase {
    /// Reference case from Vallado et al. 2006 ("Revisiting Spacetrack Report #3"), satellite 00005.
    private let line1 = "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753"
    private let line2 = "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667"

    func testTLEParsing() throws {
        let tle = try TLE(name: "TEST", line1: line1, line2: line2)
        XCTAssertEqual(tle.catalogNumber, 5)
        XCTAssertEqual(tle.bstar, 0.28098e-4, accuracy: 1e-12)
        XCTAssertEqual(tle.eccentricity, 0.1859667, accuracy: 1e-9)
        XCTAssertEqual(tle.meanMotion, 10.82419157, accuracy: 1e-8)
    }

    func testSGP4MatchesVerificationVectors() throws {
        let sgp4 = try SGP4(tle: TLE(name: "TEST", line1: line1, line2: line2))
        let cases: [(Double, Vec3, Vec3)] = [
            (0, Vec3(x: 7022.46529266, y: -1400.08296755, z: 0.03995155),
                Vec3(x: 1.893841015, y: 6.405893759, z: 4.534807250)),
            (360, Vec3(x: -7154.03120202, y: -3783.17682504, z: -3536.19412294),
                  Vec3(x: 4.741887409, y: -4.151817765, z: -2.093935425)),
        ]
        for (t, r, v) in cases {
            let state = try sgp4.propagate(minutesSinceEpoch: t)
            XCTAssertLessThan((state.position - r).length, 1e-3, "position at t=\(t)")
            XCTAssertLessThan((state.velocity - v).length, 1e-6, "velocity at t=\(t)")
        }
    }

    func testPassesAreOrderedAndAboveHorizon() throws {
        let iss = try TLE.parse("""
        ISS (ZARYA)
        1 25544U 98067A   26329.13827948  .00005332  00000+0  10279-3 0  9998
        2 25544  51.6318 223.5844 0007440  62.9833 297.1915 15.49581308596705
        """)
        let predictor = PassPredictor(sgp4: try SGP4(tle: iss),
                                      observer: Observer(latitude: 37.77, longitude: -122.42))
        let passes = predictor.passes(from: iss.epoch, days: 3)
        XCTAssertGreaterThan(passes.count, 8)
        for (a, b) in zip(passes, passes.dropFirst()) {
            XCTAssertLessThan(a.setting.date, b.rise.date)
        }
        for pass in passes {
            XCTAssertEqual(pass.rise.elevation, 0, accuracy: 0.05)
            XCTAssertEqual(pass.setting.elevation, 0, accuracy: 0.05)
            XCTAssertGreaterThan(pass.culmination.elevation, 0)
            XCTAssertLessThan(pass.duration, 15 * 60)
        }
        XCTAssertTrue(passes.contains(where: \.isVisible))
    }

    func testCompass() {
        XCTAssertEqual(Astro.compass(0), "N")
        XCTAssertEqual(Astro.compass(359), "N")
        XCTAssertEqual(Astro.compass(90), "E")
        XCTAssertEqual(Astro.compass(225), "SW")
    }
}
