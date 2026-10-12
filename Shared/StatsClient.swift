import Foundation

enum StatsClientError: Error {
    case invalidSettings
    case network(Error)
    case invalidResponse
    case httpStatus(Int)
}

/// Thin async wrapper around `GET /stats`, shared by the widget's
/// TimelineProvider (which fetches on its own schedule) and the main app's
/// PulseMonitor (which polls much more frequently while running).
enum StatsClient {
    static func fetch(settings: PulseSettings, timeout: TimeInterval = 3.0) async throws -> StatsResponse {
        guard settings.isConfigured, !settings.apiKey.isEmpty,
              let base = settings.baseURL,
              let url = URL(string: "/stats", relativeTo: base) else {
            throw StatsClientError.invalidSettings
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-Key")

        let result = try await SecureHTTP.send(request, pin: settings.certificateFingerprint)
        guard result.status == 200 else { throw StatsClientError.httpStatus(result.status) }
        let data = result.data

        do {
            return try JSONDecoder().decode(StatsResponse.self, from: data)
        } catch {
            throw StatsClientError.network(error)
        }
    }
}
