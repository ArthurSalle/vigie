import Foundation
import AppKit

enum SettingsKeys {
    static let scanInterval = "scanInterval"          // seconds, default 5
    static let staleHours = "staleHours"              // default 3
    static let notifyNewPorts = "notifyNewPorts"      // default true
    static let notifyStalePorts = "notifyStalePorts"  // default true
    static let showSystemPorts = "showSystemPorts"    // default true

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            scanInterval: 5,
            staleHours: 3,
            notifyNewPorts: true,
            notifyStalePorts: true,
            showSystemPorts: true,
        ])
    }
}

@MainActor
final class PortStore: ObservableObject {

    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var lastScan: Date? = nil
    @Published private(set) var killingPids: Set<Int> = []
    @Published var ignoredKeys: Set<String> {
        didSet { UserDefaults.standard.set(Array(ignoredKeys), forKey: "ignoredKeys") }
    }

    let notifier = Notifier()

    private var snoozeUntil: [String: Date] {
        didSet {
            if let data = try? JSONEncoder().encode(snoozeUntil) {
                UserDefaults.standard.set(data, forKey: "snoozeUntil")
            }
        }
    }
    private var seenIds = Set<String>()
    private var staleNotifiedIds = Set<String>()
    private var isFirstScan = true
    private var scanTask: Task<Void, Never>? = nil

    var devPorts: [ListeningPort] { ports.filter { $0.category == .dev || $0.category == .other } }
    var appPorts: [ListeningPort] { ports.filter { $0.category == .app } }
    var systemPorts: [ListeningPort] { ports.filter { $0.category == .system } }
    var staleIds: Set<String> {
        let threshold = staleThresholdSeconds
        return Set(devPorts.filter { $0.etimeSeconds >= threshold }.map(\.id))
    }

    private var staleThresholdSeconds: Int {
        UserDefaults.standard.integer(forKey: SettingsKeys.staleHours) * 3600
    }

    init() {
        SettingsKeys.registerDefaults()
        ignoredKeys = Set(UserDefaults.standard.stringArray(forKey: "ignoredKeys") ?? [])
        if let data = UserDefaults.standard.data(forKey: "snoozeUntil"),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            snoozeUntil = decoded
        } else {
            snoozeUntil = [:]
        }

        notifier.setup()
        notifier.onAction = { [weak self] action, pid, port, ignoreKey in
            guard let self else { return }
            switch action {
            case .kill: self.kill(pid: pid)
            case .snooze: self.snooze(id: "\(port)-\(pid)")
            case .ignore: self.ignoredKeys.insert(ignoreKey)
            }
        }
        startScanning()
    }

    func startScanning() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await PortScanner.scan()
                self.apply(snapshot)
                let interval = max(2, UserDefaults.standard.integer(forKey: SettingsKeys.scanInterval))
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func rescanNow() {
        Task {
            let snapshot = await PortScanner.scan()
            apply(snapshot)
        }
    }

    private func apply(_ snapshot: [ListeningPort]) {
        ports = snapshot
        lastScan = Date()
        killingPids.formIntersection(snapshot.map(\.pid))

        let defaults = UserDefaults.standard
        let currentIds = Set(snapshot.map(\.id))

        if isFirstScan {
            // Baseline: everything already open at launch is "known", no notification.
            isFirstScan = false
            seenIds = currentIds
            return
        }

        // New ports → notification (dev/unknown only).
        if defaults.bool(forKey: SettingsKeys.notifyNewPorts) {
            for port in snapshot where !seenIds.contains(port.id) {
                guard port.category == .dev || port.category == .other,
                      !ignoredKeys.contains(port.ignoreKey) else { continue }
                notifier.notifyNewPort(port)
            }
        }
        seenIds = currentIds

        // Ports open past the threshold → reminder with Kill / Snooze / Ignore.
        if defaults.bool(forKey: SettingsKeys.notifyStalePorts) {
            let threshold = staleThresholdSeconds
            let hours = defaults.integer(forKey: SettingsKeys.staleHours)
            for port in devPorts where port.etimeSeconds >= threshold {
                guard !ignoredKeys.contains(port.ignoreKey),
                      !staleNotifiedIds.contains(port.id) else { continue }
                if let until = snoozeUntil[port.id], until > Date() { continue }
                notifier.notifyStalePort(port, thresholdHours: hours)
                staleNotifiedIds.insert(port.id)
            }
        }
        staleNotifiedIds.formIntersection(currentIds)
        snoozeUntil = snoozeUntil.filter { currentIds.contains($0.key) || $0.value > Date() }
    }

    // MARK: - Actions

    /// SIGTERM first; SIGKILL 3 s later if the process is still alive.
    func kill(pid: Int) {
        killingPids.insert(pid)
        Darwin.kill(pid_t(pid), SIGTERM)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if Darwin.kill(pid_t(pid), 0) == 0 {
                Darwin.kill(pid_t(pid), SIGKILL)
            }
            try? await Task.sleep(for: .seconds(1))
            self?.rescanNow()
        }
    }

    func forceKill(pid: Int) {
        killingPids.insert(pid)
        Darwin.kill(pid_t(pid), SIGKILL)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.rescanNow()
        }
    }

    func snooze(id: String) {
        let hours = max(1, UserDefaults.standard.integer(forKey: SettingsKeys.staleHours))
        snoozeUntil[id] = Date().addingTimeInterval(Double(hours) * 3600)
        staleNotifiedIds.remove(id)
    }

    func openInBrowser(port: Int) {
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }
}
