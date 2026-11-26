import Foundation

extension SkySample {
    /// Bright enough to see with the naked eye: sunlit ISS, dark sky, at least 10° up.
    var isNakedEyeVisible: Bool {
        sunlit && sunElevation < PassPredictor.sunLimit && elevation >= PassPredictor.minVisibleElevation
    }
}

extension ISSPass {
    /// When to start looking: the start of visibility, or the rise for passes that can't be seen.
    var displayStart: SkySample { visibleStart ?? rise }
    var displayEnd: SkySample { visibleEnd ?? setting }
    var displayPeak: Double { maxVisibleElevation ?? culmination.elevation }

    var summary: String {
        "\(displayStart.compass) → \(Int(displayPeak.rounded()))° → \(displayEnd.compass)"
    }
}

extension Date {
    var clock: String { formatted(date: .omitted, time: .shortened) }
    var clockWithSeconds: String { formatted(.dateTime.hour().minute().second()) }
    var dayTitle: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInTomorrow(self) { return "Tomorrow" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}

extension TimeInterval {
    var minutesText: String {
        let m = Int((self / 60).rounded())
        return m < 1 ? "< 1 min" : "\(m) min"
    }
}
