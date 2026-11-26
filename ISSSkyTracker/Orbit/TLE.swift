import Foundation

/// A NORAD two-line element set, parsed into the fields SGP4 needs.
struct TLE: Codable, Hashable {
    let name: String
    let line1: String
    let line2: String

    let catalogNumber: Int
    let epoch: Date
    let bstar: Double
    let inclinationDeg: Double
    let raanDeg: Double
    let eccentricity: Double
    let argPerigeeDeg: Double
    let meanAnomalyDeg: Double
    /// Revolutions per day (Kozai mean motion).
    let meanMotion: Double

    enum ParseError: LocalizedError {
        case badFormat(String)
        var errorDescription: String? {
            switch self {
            case .badFormat(let why): return "Could not read orbital data: \(why)"
            }
        }
    }

    /// Parses text containing a 2-line or 3-line (name + 2 lines) element set.
    static func parse(_ text: String) throws -> TLE {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let i1 = lines.firstIndex(where: { $0.hasPrefix("1 ") }),
              i1 + 1 < lines.count, lines[i1 + 1].hasPrefix("2 ") else {
            throw ParseError.badFormat("expected lines starting with '1 ' and '2 '")
        }
        let name = i1 > 0 ? lines[i1 - 1] : "SATELLITE"
        return try TLE(name: name, line1: lines[i1], line2: lines[i1 + 1])
    }

    init(name: String, line1: String, line2: String) throws {
        guard line1.count >= 64, line2.count >= 63 else {
            throw ParseError.badFormat("lines are too short")
        }
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.line1 = line1
        self.line2 = line2

        let l1 = Array(line1), l2 = Array(line2)
        /// 1-based inclusive column range, as in the TLE spec.
        func field(_ l: [Character], _ from: Int, _ to: Int) -> String {
            String(l[(from - 1)..<min(to, l.count)]).trimmingCharacters(in: .whitespaces)
        }
        func number(_ l: [Character], _ from: Int, _ to: Int) throws -> Double {
            let s = field(l, from, to)
            guard let v = Double(s) else { throw ParseError.badFormat("bad number '\(s)' at column \(from)") }
            return v
        }

        guard let cat = Int(field(l1, 3, 7)) else { throw ParseError.badFormat("bad catalog number") }
        catalogNumber = cat

        let yy = Int(try number(l1, 19, 20))
        let epochDay = try number(l1, 21, 32)
        let year = yy < 57 ? 2000 + yy : 1900 + yy
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        epoch = jan1.addingTimeInterval((epochDay - 1) * 86_400)

        bstar = try TLE.impliedDecimal(field(l1, 54, 61))
        inclinationDeg = try number(l2, 9, 16)
        raanDeg = try number(l2, 18, 25)
        guard let ecc = Double("0." + field(l2, 27, 33)) else { throw ParseError.badFormat("bad eccentricity") }
        eccentricity = ecc
        argPerigeeDeg = try number(l2, 35, 42)
        meanAnomalyDeg = try number(l2, 44, 51)
        meanMotion = try number(l2, 53, 63)
    }

    /// Parses the TLE "assumed decimal point" exponent format, e.g. " 28098-4" -> 0.28098e-4.
    static func impliedDecimal(_ raw: String) throws -> Double {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return 0 }
        var sign = 1.0
        if s.hasPrefix("-") { sign = -1; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        guard let expIndex = s.lastIndex(where: { $0 == "-" || $0 == "+" }) else {
            guard let m = Double("0." + s) else { throw ParseError.badFormat("bad value '\(raw)'") }
            return sign * m
        }
        let mantissa = String(s[..<expIndex])
        let exponent = String(s[expIndex...])
        guard let m = Double("0." + mantissa), let e = Double(exponent) else {
            throw ParseError.badFormat("bad value '\(raw)'")
        }
        return sign * m * pow(10, e)
    }
}
