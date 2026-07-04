import Darwin
import Foundation

enum PortsService {
    /// One `ps` call → pid → full command line, so the list can show real
    /// commands without spawning a process per row.
    private static func fullCommands() -> [Int32: String] {
        var map: [Int32: String] = [:]
        guard let text = try? Shell.run("/bin/ps", ["-axo", "pid=,command="]) else { return map }
        for line in text.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            guard let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            guard let pid = Int32(trimmed[..<space]) else { continue }
            map[pid] = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    /// Parse an lsof name field ("*:3000", "127.0.0.1:8080", "[::1]:5000").
    private static func parseName(_ name: String) -> (address: String, port: Int)? {
        guard let idx = name.lastIndex(of: ":") else { return nil }
        guard let port = Int(name[name.index(after: idx)...]) else { return nil }
        var addr = String(name[..<idx])
        addr = addr.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return (addr.isEmpty ? "*" : addr, port)
    }

    static func list() throws -> [PortInfo] {
        // -FpcLPn = field output: process (p,c,L) + per-file (P protocol, n name).
        // +c 0 disables command-name truncation. lsof exits non-zero when nothing
        // matches — that's not an error for us.
        let text = try Shell.run(
            "/usr/sbin/lsof",
            ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLPn"],
            allowFailure: true
        )
        let commands = fullCommands()

        // One listener can bind dozens of sockets (IPv4, IPv6, one per
        // link-local interface). Group by process × port so the UI shows one
        // row per listener with its addresses collapsed.
        struct Listener {
            let pid: Int32
            let processName: String
            let user: String
            let proto: String
            let port: Int
            var addresses: [String]
        }
        var order: [String] = []
        var listeners: [String: Listener] = [:]
        var pid: Int32 = 0
        var processName = ""
        var user = ""
        var proto = ""

        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value) ?? 0
                processName = ""
                user = ""
                proto = ""
            case "c": processName = value
            case "L": user = value
            case "f": proto = ""
            case "P": proto = value
            case "n":
                guard let (address, port) = parseName(value) else { continue }
                let key = "\(pid):\(port)"
                if var listener = listeners[key] {
                    if !listener.addresses.contains(address) {
                        listener.addresses.append(address)
                        listeners[key] = listener
                    }
                } else {
                    listeners[key] = Listener(
                        pid: pid, processName: processName, user: user,
                        proto: proto, port: port, addresses: [address])
                    order.append(key)
                }
            default: break
            }
        }

        let ports: [PortInfo] = order.compactMap { key in
            guard let listener = listeners[key] else { return nil }
            return PortInfo(
                pid: listener.pid,
                processName: listener.processName,
                user: listener.user,
                protocolName: listener.proto.isEmpty ? "TCP" : listener.proto,
                address: primaryAddress(listener.addresses),
                addresses: listener.addresses,
                port: listener.port,
                command: commands[listener.pid] ?? listener.processName
            )
        }

        return ports.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Pick the most recognizable binding for display: wildcard, then
    /// any-address forms, then IPv4, then whatever came first.
    private static func primaryAddress(_ addresses: [String]) -> String {
        addresses.first { $0 == "*" }
            ?? addresses.first { $0 == "0.0.0.0" || $0 == "::" }
            ?? addresses.first { $0.contains(".") }
            ?? addresses.first
            ?? "*"
    }

    static func kill(pid: Int32, force: Bool) throws {
        let signal = force ? SIGKILL : SIGTERM
        guard Darwin.kill(pid, signal) == 0 else {
            throw NSError(
                domain: "BioLab", code: Int(errno),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Failed to kill pid \(pid): \(String(cString: strerror(errno)))"
                ])
        }
    }
}
