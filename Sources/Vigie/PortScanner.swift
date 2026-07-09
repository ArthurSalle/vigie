import Foundation

enum PortScanner {

    static func scan() async -> [ListeningPort] {
        await Task.detached(priority: .utility) { scanSync() }.value
    }

    static func scanSync() -> [ListeningPort] {
        let raw = parseNetstat(Shell.run("/usr/sbin/netstat", ["-anv", "-p", "tcp"]))
        guard !raw.isEmpty else { return [] }

        let pids = Array(Set(raw.map(\.pid))).sorted()
        let psInfo = fetchProcessInfo(pids: pids)
        let cwds = fetchCwds(pids: pids)
        let ancestry = ProcessAncestry.snapshot()

        var ports: [ListeningPort] = []
        for entry in raw {
            let info = psInfo[entry.pid]
            var port = ListeningPort(
                port: entry.port,
                pid: entry.pid,
                bindAddress: entry.bindAddress,
                exposed: entry.exposed,
                name: info?.name ?? entry.nameHint,
                commPath: info?.commPath ?? "",
                commandLine: info?.commandLine ?? entry.nameHint,
                user: info?.user ?? "?",
                etimeSeconds: info?.etimeSeconds ?? 0,
                rssKB: info?.rssKB ?? 0,
                cwd: cwds[entry.pid]
            )
            PortClassifier.classify(&port, ancestry: ancestry)
            ports.append(port)
        }
        return ports.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    // MARK: - netstat

    struct RawEntry {
        let port: Int
        let pid: Int
        let bindAddress: String
        let exposed: Bool
        let nameHint: String
    }

    /// netstat -anv -p tcp line layout (macOS 15/26):
    /// Proto Recv-Q Send-Q Local Foreign (state) rxbytes txbytes rhiwat shiwat process:pid state options gencnt flags flags1 usecnt rtncnt fltrs
    /// The process name may contain spaces, so we take the 10 leading fixed tokens,
    /// the 8 trailing fixed tokens, and join whatever is left as "name:pid".
    static func parseNetstat(_ output: String) -> [RawEntry] {
        var seen = Set<String>()   // dedupe tcp4/tcp6 rows for the same pid+port
        var entries: [RawEntry] = []

        for line in output.split(separator: "\n") {
            guard line.hasPrefix("tcp") else { continue }
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 19, tokens[5] == "LISTEN" else { continue }

            let procToken = tokens[10 ..< (tokens.count - 8)].joined(separator: " ")
            guard let colon = procToken.lastIndex(of: ":"),
                  let pid = Int(procToken[procToken.index(after: colon)...]) else { continue }
            let nameHint = String(procToken[..<colon])

            let local = tokens[3]
            guard let dot = local.lastIndex(of: "."),
                  let port = Int(local[local.index(after: dot)...]) else { continue }
            let bind = String(local[..<dot])

            let key = "\(port)-\(pid)"
            let exposed = bind == "*" || bind == "0.0.0.0" || bind == "::"
            if let idx = entries.firstIndex(where: { "\($0.port)-\($0.pid)" == key }) {
                // Merge v4/v6 rows: exposed if any of them is.
                if exposed && !entries[idx].exposed {
                    entries[idx] = RawEntry(port: port, pid: pid, bindAddress: bind,
                                            exposed: true, nameHint: nameHint)
                }
                continue
            }
            seen.insert(key)
            entries.append(RawEntry(port: port, pid: pid, bindAddress: bind,
                                    exposed: exposed, nameHint: nameHint))
        }
        return entries
    }

    // MARK: - ps enrichment

    struct ProcInfo {
        let name: String
        let commPath: String
        let commandLine: String
        let user: String
        let etimeSeconds: Int
        let rssKB: Int
    }

    static func fetchProcessInfo(pids: [Int]) -> [Int: ProcInfo] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")

        // comm= gives the untruncated executable path.
        var commPaths: [Int: String] = [:]
        for line in Shell.run("/bin/ps", ["-o", "pid=,comm=", "-p", list]).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = Int(trimmed[..<space]) else { continue }
            commPaths[pid] = trimmed[trimmed.index(after: space)...]
                .trimmingCharacters(in: .whitespaces)
        }

        var result: [Int: ProcInfo] = [:]
        let out = Shell.run("/bin/ps", ["-o", "pid=,user=,etime=,rss=,command=", "-p", list])
        for line in out.split(separator: "\n") {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 5, let pid = Int(tokens[0]) else { continue }
            let commandLine = tokens[4...].joined(separator: " ")
            let commPath = commPaths[pid] ?? tokens[4]
            result[pid] = ProcInfo(
                name: (commPath as NSString).lastPathComponent,
                commPath: commPath,
                commandLine: commandLine,
                user: tokens[1],
                etimeSeconds: parseEtime(tokens[2]),
                rssKB: Int(tokens[3]) ?? 0
            )
        }
        return result
    }

    /// etime formats: "ss", "mm:ss", "hh:mm:ss", "dd-hh:mm:ss"
    static func parseEtime(_ etime: String) -> Int {
        var days = 0
        var clock = etime
        if let dash = etime.firstIndex(of: "-") {
            days = Int(etime[..<dash]) ?? 0
            clock = String(etime[etime.index(after: dash)...])
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        var seconds = 0
        for part in parts { seconds = seconds * 60 + part }
        return days * 86400 + seconds
    }

    // MARK: - cwd (own processes only; others silently missing)

    static func fetchCwds(pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        var result: [Int: String] = [:]
        var current: Int? = nil
        for line in Shell.run("/usr/sbin/lsof", ["-a", "-p", list, "-d", "cwd", "-Fpn"])
            .split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }
}
