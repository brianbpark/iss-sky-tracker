import Foundation

/// Downloads the latest ISS orbital elements from CelesTrak and caches them on device.
/// The ISS orbit changes (drag, reboosts), so elements older than a few days give poor predictions.
struct TLEService {
    static let issCatalogNumber = 25544
    private let url = URL(string: "https://celestrak.org/NORAD/elements/gp.php?CATNR=\(issCatalogNumber)&FORMAT=TLE")!
    private let cacheKey = "cachedISSTLE"
    private let fetchedKey = "cachedISSTLEFetchedAt"
    private let maxAge: TimeInterval = 6 * 3600

    /// Returns cached elements if fresh, otherwise downloads new ones (falling back to the cache when offline).
    func load(forceRefresh: Bool = false) async throws -> TLE {
        let defaults = UserDefaults.standard
        let cached = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(TLE.self, from: $0) }
        let fetchedAt = defaults.object(forKey: fetchedKey) as? Date ?? .distantPast

        if let cached, !forceRefresh, Date().timeIntervalSince(fetchedAt) < maxAge {
            return cached
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            let tle = try TLE.parse(text)
            defaults.set(try JSONEncoder().encode(tle), forKey: cacheKey)
            defaults.set(Date(), forKey: fetchedKey)
            return tle
        } catch {
            if let cached { return cached }
            throw error
        }
    }
}
