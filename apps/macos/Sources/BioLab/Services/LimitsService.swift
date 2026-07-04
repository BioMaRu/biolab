import Foundation

/// Live Claude plan limits — the same data Claude Code's "Your usage limits"
/// panel shows (session / weekly / model-scoped %-of-plan with authoritative
/// resets). Reads the OAuth token Claude Code keeps in the macOS Keychain and
/// calls Anthropic's OAuth usage endpoint. The token is sent only to Anthropic.
enum LimitsService {
    enum LimitsError: LocalizedError {
        case keychain
        case noToken
        case badResponse
        case api(String)

        var errorDescription: String? {
            switch self {
            case .keychain: "Couldn't read Claude credentials from the Keychain."
            case .noToken: "No Claude OAuth token found — sign in with Claude Code first."
            case .badResponse:
                "Anthropic returned an unexpected response — your token may be expired (open Claude Code to refresh)."
            case .api(let message): "Anthropic: \(message)"
            }
        }
    }

    /// Read the OAuth access token (+ subscription type) from the Keychain via
    /// /usr/bin/security — the same binary Claude Code itself uses, so an
    /// existing "Always Allow" grant carries over.
    private static func credentials() throws -> (token: String, plan: String?) {
        guard
            let raw = try? Shell.run(
                "/usr/bin/security",
                ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        else { throw LimitsError.keychain }

        guard
            let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
            let oauth = obj["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw LimitsError.noToken }

        let plan = (oauth["subscriptionType"] as? String).map { $0.capitalized }
        return (token, plan)
    }

    static func fetch() async throws -> ClaudeLimits {
        let (token, plan) = try credentials()

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LimitsError.badResponse
        }
        if let err = obj["error"] as? [String: Any] {
            throw LimitsError.api(err["message"] as? String ?? "unknown error")
        }

        var bars: [LimitBar] = []
        for limit in obj["limits"] as? [[String: Any]] ?? [] {
            let kind = limit["kind"] as? String ?? ""
            let scopeModel =
                ((limit["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"]
                as? String
            let label =
                switch kind {
                case "session": "Current session"
                case "weekly_all": "Weekly · All models"
                case "weekly_scoped": "Weekly · \(scopeModel ?? "Scoped")"
                default: kind.replacingOccurrences(of: "_", with: " ").capitalized
                }
            bars.append(
                LimitBar(
                    kind: kind,
                    label: label,
                    percent: (limit["percent"] as? NSNumber)?.doubleValue ?? 0,
                    severity: limit["severity"] as? String ?? "normal",
                    resetsAt: (limit["resets_at"] as? String).flatMap(ISO.parse),
                    isActive: limit["is_active"] as? Bool ?? false
                ))
        }
        guard !bars.isEmpty else { throw LimitsError.badResponse }

        var extra: ExtraUsage?
        if let spend = obj["spend"] as? [String: Any] {
            func money(_ key: String) -> Double {
                guard let m = spend[key] as? [String: Any],
                    let minor = (m["amount_minor"] as? NSNumber)?.doubleValue
                else { return 0 }
                let exponent = (m["exponent"] as? NSNumber)?.intValue ?? 2
                return minor / pow(10, Double(exponent))
            }
            let currency =
                ((spend["used"] as? [String: Any])?["currency"] as? String) ?? "USD"
            extra = ExtraUsage(
                enabled: spend["enabled"] as? Bool ?? false,
                used: money("used"),
                limit: money("limit"),
                currency: currency,
                percent: (spend["percent"] as? NSNumber)?.doubleValue ?? 0
            )
        }

        return ClaudeLimits(plan: plan, bars: bars, extra: extra, fetchedAt: Date())
    }
}
