import Foundation

/// Checks GitHub Releases for a newer BioLab and links to it — a notify-and-link
/// updater, not a silent installer (an auto-downloaded update would be
/// quarantined and blocked until the app is notarized). No dependency: plain
/// URLSession + JSON, like LimitsService.
enum UpdateService {
    static let repo = "BioMaRu/biolab"

    struct Release: Sendable, Equatable {
        let version: String  // normalized, e.g. "1.1.0"
        let name: String
        let url: URL
        let publishedAt: Date?
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .badResponse: "Couldn't read the latest release from GitHub."
            case .rateLimited: "GitHub is rate-limiting update checks — try again later."
            }
        }
    }

    static func latest() async throws -> Release {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BioLab", forHTTPHeaderField: "User-Agent")  // GitHub requires a UA

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw UpdateError.rateLimited
        }
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = obj["tag_name"] as? String,
            let urlString = obj["html_url"] as? String,
            let url = URL(string: urlString)
        else { throw UpdateError.badResponse }

        return Release(
            version: normalize(tag),
            name: (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
            url: url,
            publishedAt: (obj["published_at"] as? String).flatMap(ISO.parse)
        )
    }

    /// Strip a leading "v" from a tag ("v1.2.0" → "1.2.0").
    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Numeric, component-wise semver compare — is `candidate` newer than `current`?
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func components(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = components(candidate)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let ai = i < a.count ? a[i] : 0
            let bi = i < b.count ? b[i] : 0
            if ai != bi { return ai > bi }
        }
        return false
    }
}
