import SwiftUI
import Combine
import CoreLocation

/// App-wide state: orbital elements, the user's location, predicted passes and the live ISS position.
@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case sky, passes }

    @Published var tab: Tab = .sky
    /// A pass the user picked to show in the sky view (otherwise the current or next visible one is shown).
    @Published var selectedPass: ISSPass?
    @Published private(set) var tle: TLE?
    @Published private(set) var passes: [ISSPass] = []
    @Published private(set) var now: ISSNow?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    let location = LocationService()
    private let tleService = TLEService()
    private var predictor: PassPredictor?
    private var lastPredictionDate: Date?
    private var lastPredictionLocation: CLLocation?
    private var cancellables = Set<AnyCancellable>()
    private var ticker: Timer?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        location.start()
        location.$location
            .compactMap { $0 }
            .sink { [weak self] in self?.locationChanged($0) }
            .store(in: &cancellables)
        location.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        Task { await loadTLE(force: false) }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func refresh() async {
        await loadTLE(force: true)
    }

    // MARK: - Derived

    var currentPass: ISSPass? {
        let date = Date()
        return passes.first { $0.rise.date <= date && $0.setting.date >= date }
    }

    var nextVisiblePass: ISSPass? {
        passes.first { $0.isVisible && ($0.visibleEnd?.date ?? .distantPast) > Date() }
    }

    /// The pass drawn in the camera view.
    var skyPass: ISSPass? {
        selectedPass ?? currentPass ?? nextVisiblePass ?? passes.first
    }

    // MARK: - Updates

    private func loadTLE(force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            tle = try await tleService.load(forceRefresh: force)
            errorMessage = nil
            await recompute()
        } catch {
            errorMessage = "Couldn't download ISS orbit data. Check your internet connection, then pull down to refresh."
        }
    }

    private func locationChanged(_ newLocation: CLLocation) {
        if let last = lastPredictionLocation, newLocation.distance(from: last) < 5_000 { return }
        Task { await recompute() }
    }

    private func recompute() async {
        guard let tle, let loc = location.location, let sgp4 = try? SGP4(tle: tle) else { return }
        let observer = Observer(latitude: loc.coordinate.latitude,
                                longitude: loc.coordinate.longitude,
                                altitudeKm: max(0, loc.altitude) / 1000)
        let predictor = PassPredictor(sgp4: sgp4, observer: observer)
        self.predictor = predictor
        lastPredictionLocation = loc
        lastPredictionDate = Date()
        let result = await Task.detached(priority: .userInitiated) {
            predictor.passes(from: Date(), days: 10)
        }.value
        passes = result
        if let selected = selectedPass {
            selectedPass = result.first { abs($0.rise.date.timeIntervalSince(selected.rise.date)) < 120 }
        }
        tick()
    }

    private func tick() {
        guard let predictor else { return }
        let date = Date()
        now = predictor.now(date)
        if let first = passes.first, first.setting.date < date {
            passes.removeAll { $0.setting.date < date }
        }
        if let selected = selectedPass, selected.setting.date < date {
            selectedPass = nil
        }
        // Refresh elements and predictions every few hours so they stay accurate.
        if let last = lastPredictionDate, date.timeIntervalSince(last) > 6 * 3600 {
            lastPredictionDate = date
            Task { await loadTLE(force: false) }
        }
    }
}
