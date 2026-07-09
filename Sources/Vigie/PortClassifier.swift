import Foundation

// MARK: - Ancestry (who launched this process?)

struct ProcessAncestry {
    let parents: [Int: Int]      // pid -> ppid
    let comms: [Int: String]     // pid -> executable path

    static func snapshot() -> ProcessAncestry {
        var parents: [Int: Int] = [:]
        var comms: [Int: String] = [:]
        for line in Shell.run("/bin/ps", ["-axo", "pid=,ppid=,comm="]).split(separator: "\n") {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 3, let pid = Int(tokens[0]), let ppid = Int(tokens[1]) else { continue }
            parents[pid] = ppid
            comms[pid] = tokens[2...].joined(separator: " ")
        }
        return ProcessAncestry(parents: parents, comms: comms)
    }

    /// Walks up the parent chain and returns (label, isAIAgent) for the first notable ancestor.
    func launcher(of pid: Int) -> (String, Bool)? {
        var current = parents[pid]
        var hops = 0
        while let pid = current, pid > 1, hops < 25 {
            if let comm = comms[pid], let hit = Self.identify(comm) { return hit }
            current = parents[pid]
            hops += 1
        }
        return nil
    }

    static func identify(_ comm: String) -> (String, Bool)? {
        let base = (comm as NSString).lastPathComponent.lowercased()
        let aiAgents = ["claude", "codex", "aider", "opencode", "goose", "gemini", "copilot"]
        if aiAgents.contains(base) { return (base.capitalized == "Claude" ? "Claude Code" : base.capitalized, true) }
        if comm.contains("Claude.app") { return ("Claude", true) }
        if comm.contains("Cursor.app") { return ("Cursor", false) }
        if comm.contains("Visual Studio Code.app") || comm.contains("Code.app") { return ("VS Code", false) }
        if comm.contains("Zed.app") { return ("Zed", false) }
        if comm.contains("Warp.app") { return ("Warp", false) }
        if comm.contains("iTerm.app") { return ("iTerm", false) }
        if comm.contains("Terminal.app") { return ("Terminal", false) }
        if comm.contains("Ghostty.app") || base == "ghostty" { return ("Ghostty", false) }
        if base == "kitty" || base == "alacritty" || comm.contains("WezTerm") { return (base.capitalized, false) }
        if comm.contains("Docker.app") || base.hasPrefix("com.docker") { return ("Docker", false) }
        return nil
    }
}

// MARK: - Classifier

enum PortClassifier {

    static let knownPorts: [Int: String] = [
        22: "SSH", 80: "HTTP", 443: "HTTPS", 88: "Kerberos (macOS)",
        445: "SMB (partage fichiers)", 548: "AFP (partage fichiers)", 631: "CUPS (impression)",
        3000: "dev server (Next/React/Express)", 3001: "dev server", 4200: "Angular",
        4321: "Astro", 5173: "Vite", 5174: "Vite", 8080: "HTTP alternatif",
        8000: "Python/uvicorn/Django", 8888: "Jupyter", 9000: "PHP-FPM/SonarQube",
        5432: "PostgreSQL", 3306: "MySQL", 6379: "Redis", 27017: "MongoDB",
        9200: "Elasticsearch", 5672: "RabbitMQ", 9092: "Kafka", 1883: "MQTT",
        11434: "Ollama", 1234: "LM Studio", 8081: "dev server",
        5000: "Flask / AirPlay", 7000: "AirPlay", 6463: "Discord RPC",
        24678: "Vite HMR", 1313: "Hugo", 4000: "Phoenix/Jekyll", 8025: "Mailpit/MailHog",
    ]

    static let devRuntimes: Set<String> = [
        "node", "npm", "npx", "pnpm", "yarn", "bun", "deno",
        "python", "python3", "uvicorn", "gunicorn", "flask", "fastapi",
        "ruby", "rails", "puma", "php", "java", "gradle", "mvn",
        "go", "air", "cargo", "dotnet", "beam.smp", "erl",
    ]

    static let systemPathPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]

    static func classify(_ port: inout ListeningPort, ancestry: ProcessAncestry) {
        port.knownAs = knownPorts[port.port]

        if let hit = ancestry.launcher(of: port.pid) {
            port.launchedBy = hit.0
            port.isAI = hit.1
        }

        let path = port.commPath
        let base = port.name.lowercased()
        let home = NSHomeDirectory()
        let currentUser = NSUserName()

        // System: another user's process (root, _daemons…) or an Apple system path.
        if port.user != currentUser || systemPathPrefixes.contains(where: { path.hasPrefix($0) }) {
            port.category = .system
            return
        }

        // Dev: known runtime, dev-ish install location, or a working directory inside $HOME.
        let devPathMarkers = ["/node_modules/", "/.nvm/", "/.bun/", "/.deno/", "/.cargo/",
                              "/.rustup/", "/.local/", "/opt/homebrew/", "/usr/local/"]
        let isDevRuntime = devRuntimes.contains(base)
        let isDevPath = devPathMarkers.contains(where: { path.contains($0) }) || path.hasPrefix(home + "/Dev")
        let hasProjectCwd = port.cwd.map { $0.hasPrefix(home) && $0 != home } ?? false

        if isDevRuntime || isDevPath || (hasProjectCwd && !path.contains(".app/")) {
            port.category = .dev
            return
        }

        if path.contains(".app/") {
            port.category = .app
            return
        }

        port.category = .other
    }
}
