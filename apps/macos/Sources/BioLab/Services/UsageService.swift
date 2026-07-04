import Foundation

/// Reads each agent CLI's local usage data — no auth, no network:
///   * Claude Code — JSONL transcripts under ~/.claude/projects.
///   * Codex       — per-turn token telemetry in ~/.codex/logs_2.sqlite.
///   * OpenCode    — per-session token/cost columns in opencode.db.
///
/// Refreshes are incremental: Claude files are cached by (mtime, size) so an
/// unchanged transcript is never re-parsed, and Codex rows are fetched past the
/// last seen rowid only. Token counts are exact; Claude costs are estimated
/// from public per-token pricing.
actor UsageService {
    static let shared = UsageService()

    // MARK: Caches

    private struct FileCache {
        let mtime: Date
        let size: Int64
        let events: [UsageEvent]
    }

    private var claudeCache: [String: FileCache] = [:]
    private var codexEvents: [UsageEvent] = []
    private var codexMaxRow: Int64 = 0

    // MARK: Public

    func report() -> UsageReport {
        var report = UsageReport()
        report.providers = [claude(), codex(), opencode()]
        return report
    }

    // MARK: Claude — JSONL transcripts

    /// Anthropic per-token USD (input, output, cache-write, cache-read).
    private func claudeRates(_ model: String) -> (Double, Double, Double, Double) {
        let m = model.lowercased()
        let perM = { (i: Double, o: Double, cw: Double, cr: Double) in
            (i / 1e6, o / 1e6, cw / 1e6, cr / 1e6)
        }
        if m.contains("opus") { return perM(15, 75, 18.75, 1.5) }
        if m.contains("haiku") { return perM(1, 5, 1.25, 0.10) }
        return perM(3, 15, 3.75, 0.30) // Sonnet / unknown default
    }

    private func claude() -> ProviderUsage {
        let fm = FileManager.default
        var files: [URL] = []
        if let walker = fm.enumerator(
            at: Paths.claudeProjects, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                files.append(url)
            }
        }

        var events: [UsageEvent] = []
        var alive = Set<String>()
        for url in files {
            let path = url.path
            alive.insert(path)
            let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = attrs?.contentModificationDate ?? .distantPast
            let size = Int64(attrs?.fileSize ?? 0)

            if let cached = claudeCache[path], cached.mtime == mtime, cached.size == size {
                events.append(contentsOf: cached.events)
                continue
            }
            let parsed = parseClaudeFile(url)
            claudeCache[path] = FileCache(mtime: mtime, size: size, events: parsed)
            events.append(contentsOf: parsed)
        }
        // Drop cache entries for deleted transcripts.
        claudeCache = claudeCache.filter { alive.contains($0.key) }

        return aggregate(.claude, events: events, note: nil)
    }

    private func parseClaudeFile(_ url: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else { return [] }

        var events: [UsageEvent] = []
        for line in text.split(separator: "\n") {
            // Cheap pre-filter before the JSON parse.
            guard line.contains("\"assistant\""), line.contains("\"usage\"") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                obj["type"] as? String == "assistant",
                let message = obj["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any],
                let tsString = obj["timestamp"] as? String,
                let ts = ISO.parse(tsString)
            else { continue }

            let int = { (key: String) -> Int64 in (usage[key] as? NSNumber)?.int64Value ?? 0 }
            let input = int("input_tokens")
            let output = int("output_tokens")
            let cacheRead = int("cache_read_input_tokens")
            let cacheCreation = int("cache_creation_input_tokens")
            let model = message["model"] as? String ?? "unknown"

            let (ri, ro, rcw, rcr) = claudeRates(model)
            let cost =
                Double(input) * ri + Double(output) * ro + Double(cacheCreation) * rcw
                + Double(cacheRead) * rcr

            var event = UsageEvent(
                timestamp: ts, model: model, input: input, output: output,
                cacheRead: cacheRead, cacheCreation: cacheCreation, cost: cost,
                project: obj["cwd"] as? String, session: obj["sessionId"] as? String
            )
            if let tools = usage["server_tool_use"] as? [String: Any] {
                event.webSearch = (tools["web_search_requests"] as? NSNumber)?.int64Value ?? 0
                event.webFetch = (tools["web_fetch_requests"] as? NSNumber)?.int64Value ?? 0
            }
            events.append(event)
        }
        return events
    }

    // MARK: Codex — per-turn telemetry in SQLite

    /// Pull `key=<value>` out of a Codex tracing line.
    private func kv(_ line: String, _ key: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        let rest = line[range.upperBound...]
        let end = rest.firstIndex { $0 == " " || $0 == "}" || $0 == "\n" } ?? rest.endIndex
        let value = String(rest[..<end])
        return value.isEmpty ? nil : value
    }

    private func codex() -> ProviderUsage {
        guard let db = SQLiteDB(readOnly: Paths.codexLogsDB) else {
            return ProviderUsage(
                id: .codex, tracked: false,
                note: "No local Codex log database found.")
        }

        // Incremental: only rows past the last seen id.
        let sql = """
            SELECT id, ts, feedback_log_body FROM logs \
            WHERE id > \(codexMaxRow) AND feedback_log_body LIKE '%total_usage_tokens=%'
            """
        let fresh: [UsageEvent] = db.query(sql) { row in
            guard row.count >= 3, let body = row[2].string else { return nil }
            self.codexMaxRow = max(self.codexMaxRow, row[0].int)
            guard let tokens = self.kv(body, "total_usage_tokens=").flatMap({ Int64($0) }),
                tokens > 0
            else { return nil }
            return UsageEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(row[1].int)),
                model: self.kv(body, "model=") ?? "gpt",
                input: tokens, output: 0, cacheRead: 0, cacheCreation: 0,
                cost: 0,
                project: self.kv(body, "cwd="),
                session: self.kv(body, "thread_id=")
            )
        }
        codexEvents.append(contentsOf: fresh)

        return aggregate(
            .codex, events: codexEvents,
            note: "Per-turn token totals from Codex's local telemetry. Cost is metered by your ChatGPT plan."
        )
    }

    // MARK: OpenCode — session table

    private func opencode() -> ProviderUsage {
        guard let db = SQLiteDB(readOnly: Paths.opencodeDB) else {
            return ProviderUsage(
                id: .opencode, tracked: false,
                note: "No local OpenCode database found.")
        }

        let sql = """
            SELECT time_updated, model, directory, id, \
            tokens_input, tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write, cost \
            FROM session
            """
        let events: [UsageEvent] = db.query(sql) { row in
            guard row.count >= 10 else { return nil }
            let input = row[4].int
            let output = row[5].int + row[6].int
            let cacheRead = row[7].int
            let cacheWrite = row[8].int
            guard input + output + cacheRead + cacheWrite > 0 else { return nil }

            var ms = row[0].int
            if ms > 1_000_000_000_000 { ms /= 1000 }

            var model = row[1].string ?? "unknown"
            if model.hasPrefix("{"),
                let obj = try? JSONSerialization.jsonObject(with: Data(model.utf8)) as? [String: Any],
                let id = obj["id"] as? String
            {
                model = id
            }

            return UsageEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(ms)),
                model: model, input: input, output: output,
                cacheRead: cacheRead, cacheCreation: cacheWrite,
                cost: row[9].double,
                project: row[2].string, session: row[3].string
            )
        }

        return aggregate(.opencode, events: events, note: nil)
    }

    // MARK: Shared aggregation

    private func aggregate(_ id: ToolID, events: [UsageEvent], note: String?) -> ProviderUsage {
        let now = Date()
        var session = WindowStat(key: "session", label: "Session · 5h")
        var today = WindowStat(key: "today", label: "Last 24h")
        var week = WindowStat(key: "week", label: "Last 7 days")
        var all = WindowStat(key: "all", label: "All time")

        var models: [String: ModelStat] = [:]
        var projects: [String: ProjectStat] = [:]
        var sessions = Set<String>()
        var webSearch: Int64 = 0
        var webFetch: Int64 = 0
        var lastActive: Date?
        var sessionEarliest: Date?

        func add(_ w: inout WindowStat, _ e: UsageEvent) {
            w.input += e.input
            w.output += e.output
            w.cacheRead += e.cacheRead
            w.cacheCreation += e.cacheCreation
            w.cost += e.cost
            w.messages += 1
        }

        for e in events {
            let age = now.timeIntervalSince(e.timestamp)
            add(&all, e)
            if age >= 0 && age <= Const.sessionWindow {
                add(&session, e)
                sessionEarliest = min(sessionEarliest ?? e.timestamp, e.timestamp)
            }
            if age >= 0 && age <= Const.dayWindow { add(&today, e) }
            if age >= 0 && age <= Const.weekWindow { add(&week, e) }

            models[e.model, default: ModelStat(model: e.model, total: 0, cost: 0, messages: 0)]
                .absorb(e)
            if let p = e.project {
                projects[p, default: ProjectStat(path: p, total: 0, messages: 0)].absorb(e)
            }
            if let s = e.session { sessions.insert(s) }
            webSearch += e.webSearch
            webFetch += e.webFetch
            lastActive = max(lastActive ?? e.timestamp, e.timestamp)
        }

        session.resetsAt = sessionEarliest?.addingTimeInterval(Const.sessionWindow)

        var provider = ProviderUsage(id: id, tracked: true, note: note)
        provider.windows = [session, today, week, all]
        provider.models = models.values.sorted { $0.total > $1.total }
        provider.projects = Array(projects.values.sorted { $0.total > $1.total }.prefix(6))
        provider.webSearch = webSearch
        provider.webFetch = webFetch
        provider.sessions = sessions.count
        provider.lastActive = lastActive
        return provider
    }
}

extension ModelStat {
    fileprivate mutating func absorb(_ e: UsageEvent) {
        total += e.total
        cost += e.cost
        messages += 1
    }
}

extension ProjectStat {
    fileprivate mutating func absorb(_ e: UsageEvent) {
        total += e.total
        messages += 1
    }
}
