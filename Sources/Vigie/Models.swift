import Foundation

enum PortCategory: String, Codable, CaseIterable {
    case dev
    case app
    case system
    case other
}

struct ListeningPort: Identifiable, Equatable {
    let port: Int
    let pid: Int
    let bindAddress: String
    /// Bound to * / 0.0.0.0 / :: — reachable from the network, not just localhost.
    let exposed: Bool
    let name: String
    let commPath: String
    let commandLine: String
    let user: String
    let etimeSeconds: Int
    let rssKB: Int
    let cwd: String?
    var category: PortCategory = .other
    var knownAs: String? = nil
    var launchedBy: String? = nil
    var isAI: Bool = false

    var id: String { "\(port)-\(pid)" }
    /// Stable across process restarts — used for the ignore list.
    var ignoreKey: String { "\(port):\(name)" }

    var uptimeText: String {
        let s = etimeSeconds
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86400 {
            let h = s / 3600
            let m = (s % 3600) / 60
            return m > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(h) h"
        }
        let d = s / 86400
        let h = (s % 86400) / 3600
        return h > 0 ? "\(d) j \(h) h" : "\(d) j"
    }

    var memoryText: String {
        let mb = Double(rssKB) / 1024.0
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    var cwdDisplay: String? {
        guard let cwd, cwd != "/" else { return nil }
        let home = NSHomeDirectory()
        if cwd == home { return nil }
        if cwd.hasPrefix(home) { return "~" + cwd.dropFirst(home.count) }
        return cwd
    }
}
