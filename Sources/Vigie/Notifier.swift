import Foundation
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    enum Action: String {
        case kill = "VIGIE_KILL"
        case snooze = "VIGIE_SNOOZE"
        case ignore = "VIGIE_IGNORE"
    }

    /// UNUserNotificationCenter crashes outside a real .app bundle (e.g. `swift run`).
    static let available: Bool = Bundle.main.bundleIdentifier != nil

    var onAction: ((Action, _ pid: Int, _ port: Int, _ ignoreKey: String) -> Void)?

    func setup() {
        guard Self.available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let kill = UNNotificationAction(identifier: Action.kill.rawValue,
                                        title: "Tuer le process", options: [.destructive])
        let snooze = UNNotificationAction(identifier: Action.snooze.rawValue,
                                          title: "Rappeler plus tard", options: [])
        let ignore = UNNotificationAction(identifier: Action.ignore.rawValue,
                                          title: "Ne plus me prévenir", options: [])

        let newPort = UNNotificationCategory(identifier: "NEW_PORT",
                                             actions: [kill, ignore],
                                             intentIdentifiers: [])
        let stalePort = UNNotificationCategory(identifier: "STALE_PORT",
                                               actions: [kill, snooze, ignore],
                                               intentIdentifiers: [])
        center.setNotificationCategories([newPort, stalePort])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyNewPort(_ port: ListeningPort) {
        var lines = [port.commandLine.prefix(120)]
        if let cwd = port.cwdDisplay { lines.append("Dossier : \(cwd)"[...]) }
        if let by = port.launchedBy { lines.append("Lancé via \(by)\(port.isAI ? " 🤖" : "")"[...]) }
        send(id: "new-\(port.id)",
             title: "Nouveau port : \(port.port) (\(port.name))",
             body: lines.joined(separator: "\n"),
             category: "NEW_PORT", port: port)
    }

    func notifyStalePort(_ port: ListeningPort, thresholdHours: Int) {
        var body = "\(port.name) écoute sur le port \(port.port) depuis \(port.uptimeText)."
        if let cwd = port.cwdDisplay { body += "\nDossier : \(cwd)" }
        body += "\nToujours utile ?"
        send(id: "stale-\(port.id)",
             title: "Port \(port.port) ouvert depuis plus de \(thresholdHours) h",
             body: body,
             category: "STALE_PORT", port: port)
    }

    private func send(id: String, title: String, body: String, category: String, port: ListeningPort) {
        guard Self.available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["pid": port.pid, "port": port.port, "ignoreKey": port.ignoreKey]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let pid = info["pid"] as? Int,
              let port = info["port"] as? Int,
              let ignoreKey = info["ignoreKey"] as? String,
              let action = Action(rawValue: response.actionIdentifier) else { return }
        await MainActor.run {
            self.onAction?(action, pid, port, ignoreKey)
        }
    }
}
