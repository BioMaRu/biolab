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
        let url: URL  // release page (html_url)
        let zipURL: URL?  // downloadable .zip asset
        let publishedAt: Date?
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case rateLimited
        case noAsset
        case invalidPackage
        case notWritable

        var errorDescription: String? {
            switch self {
            case .badResponse: "Couldn't read the latest release from GitHub."
            case .rateLimited: "GitHub is rate-limiting update checks — try again later."
            case .noAsset: "This release has no downloadable app archive."
            case .invalidPackage: "The downloaded update looked corrupt — try again."
            case .notWritable:
                "BioLab can't update itself here — move it into your Applications folder and try again."
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

        let assets = obj["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let zipURL = (zip?["browser_download_url"] as? String).flatMap { URL(string: $0) }

        return Release(
            version: normalize(tag),
            name: (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
            url: url,
            zipURL: zipURL,
            publishedAt: (obj["published_at"] as? String).flatMap(ISO.parse)
        )
    }

    /// Strip a leading "v" from a tag ("v1.2.0" → "1.2.0").
    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    // MARK: One-click install

    /// Download the release's zip asset and unzip it, returning the staged
    /// BioLab.app. Runs off the main actor. An app the process downloads itself
    /// is not quarantined, so the swapped-in copy launches without a Gatekeeper
    /// prompt — even for an un-notarized build.
    static func downloadAndStage(_ release: Release) async throws -> URL {
        guard let zipURL = release.zipURL else { throw UpdateError.noAsset }

        let (tempFile, response) = try await URLSession.shared.download(from: zipURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.badResponse
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("BioLabUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zipPath = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: tempFile, to: zipPath)

        // Extract the PKZip archive.
        try Shell.run("/usr/bin/ditto", ["-x", "-k", zipPath.path, work.path])

        let appURL = work.appendingPathComponent("BioLab.app")
        let executable = appURL.appendingPathComponent("Contents/MacOS/BioLab").path
        guard fm.fileExists(atPath: executable) else { throw UpdateError.invalidPackage }
        return appURL
    }

    /// Replace the running bundle with `stagedApp` and relaunch. Spawns a
    /// detached helper that waits for this process to quit, swaps the bundle
    /// (keeping a rollback copy), and reopens the app. The caller must then
    /// terminate the app so the helper can proceed.
    static func install(stagedApp: URL) throws {
        let dest = Bundle.main.bundleURL
        let parent = dest.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable
        }

        let script = """
            #!/bin/sh
            PID="$1"; SRC="$2"; DEST="$3"
            i=0
            while kill -0 "$PID" 2>/dev/null && [ $i -lt 150 ]; do sleep 0.2; i=$((i+1)); done
            sleep 0.3
            BACKUP="${DEST}.old"
            rm -rf "$BACKUP"
            if [ -d "$DEST" ]; then mv "$DEST" "$BACKUP" || exit 1; fi
            if /usr/bin/ditto "$SRC" "$DEST"; then
              /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
              rm -rf "$BACKUP"
            else
              rm -rf "$DEST"
              [ -d "$BACKUP" ] && mv "$BACKUP" "$DEST"
            fi
            open "$DEST"
            """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("biolab-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            dest.path,
        ]
        try task.run()  // detached — survives our termination
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
