import SwiftUI

struct MenuView: View {
    @EnvironmentObject var store: PortStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKeys.showSystemPorts) private var showSystem = true
    @State private var systemExpanded = false
    @State private var appsExpanded = true

    /// ScrollView inside a MenuBarExtra window collapses to zero height unless
    /// given an explicit frame — estimate from row counts, capped at 480.
    private var listHeight: CGFloat {
        var h: CGFloat = 14
        if store.devPorts.isEmpty && store.appPorts.isEmpty
            && (store.systemPorts.isEmpty || !showSystem) {
            h += 50
        }
        if !store.devPorts.isEmpty {
            h += 26 + CGFloat(store.devPorts.count) * 46
        }
        if !store.appPorts.isEmpty {
            h += 26 + (appsExpanded ? CGFloat(store.appPorts.count) * 26 : 0)
        }
        if showSystem && !store.systemPorts.isEmpty {
            h += 26 + (systemExpanded ? CGFloat(store.systemPorts.count) * 26 : 0)
        }
        return min(h, 480)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if store.devPorts.isEmpty && store.appPorts.isEmpty
                        && (store.systemPorts.isEmpty || !showSystem) {
                        Text("Aucun port en écoute")
                            .foregroundStyle(.secondary)
                            .padding()
                    }

                    if !store.devPorts.isEmpty {
                        sectionHeader("Dev / inconnu", count: store.devPorts.count)
                        ForEach(store.devPorts) { port in
                            DevPortRow(port: port, isStale: store.staleIds.contains(port.id))
                        }
                    }

                    if !store.appPorts.isEmpty {
                        collapsibleHeader("Applications", count: store.appPorts.count,
                                          expanded: $appsExpanded)
                        if appsExpanded {
                            ForEach(store.appPorts) { port in
                                CompactPortRow(port: port, killable: true)
                            }
                        }
                    }

                    if showSystem && !store.systemPorts.isEmpty {
                        collapsibleHeader("Système", count: store.systemPorts.count,
                                          expanded: $systemExpanded)
                        if systemExpanded {
                            ForEach(store.systemPorts) { port in
                                CompactPortRow(port: port, killable: false)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: listHeight)
            Divider()
            footer
        }
        .frame(width: 400)
    }

    private var header: some View {
        HStack {
            Image(systemName: "network")
            Text("Vigie").font(.headline)
            if !store.staleIds.isEmpty {
                Label("\(store.staleIds.count)", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button {
                store.rescanNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescanner maintenant")

            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Réglages")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quitter Vigie")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            if let last = store.lastScan {
                Text("Dernier scan : \(last.formatted(date: .omitted, time: .standard))")
            } else {
                Text("Scan en cours…")
            }
            Spacer()
            Text("\(store.ports.count) ports")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
            Text("\(count)")
            Spacer()
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func collapsibleHeader(_ title: String, count: Int, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text(title.uppercased())
                Text("\(count)")
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2)
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}

// MARK: - Rows

struct DevPortRow: View {
    @EnvironmentObject var store: PortStore
    let port: ListeningPort
    let isStale: Bool

    private var isKilling: Bool { store.killingPids.contains(port.pid) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(":\(String(port.port))")
                        .font(.system(.body, design: .monospaced).bold())
                    Text(port.name)
                        .font(.body)
                        .lineLimit(1)
                    if let known = port.knownAs {
                        Text(known)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if port.exposed {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("Exposé au réseau local (écoute sur toutes les interfaces)")
                    }
                    if isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("Ouvert depuis longtemps")
                    }
                }
                HStack(spacing: 4) {
                    if let by = port.launchedBy {
                        Text("\(port.isAI ? "🤖 " : "")\(by)")
                    }
                    Text("· \(port.uptimeText) · \(port.memoryText)")
                    if let cwd = port.cwdDisplay {
                        Text("· \(cwd)").lineLimit(1).truncationMode(.head)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .help(port.commandLine)

            Spacer(minLength: 4)

            Button {
                store.openInBrowser(port: port.port)
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("Ouvrir http://localhost:\(port.port)")

            if isKilling {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 20)
            } else {
                Button {
                    store.kill(pid: port.pid)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Arrêter (SIGTERM, puis SIGKILL si besoin)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Copier le port") { copy("\(port.port)") }
        Button("Copier le PID") { copy("\(port.pid)") }
        Button("Copier la commande") { copy(port.commandLine) }
        if let cwd = port.cwd {
            Button("Ouvrir le dossier dans le Finder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
            }
        }
        Divider()
        Button("Forcer l'arrêt (SIGKILL)") { store.forceKill(pid: port.pid) }
        Button("Ignorer ce port (plus de notifications)") {
            store.ignoredKeys.insert(port.ignoreKey)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct CompactPortRow: View {
    @EnvironmentObject var store: PortStore
    let port: ListeningPort
    let killable: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(":\(String(port.port))")
                .font(.system(.callout, design: .monospaced))
                .frame(width: 62, alignment: .leading)
            Text(port.name).font(.callout).lineLimit(1)
            if let known = port.knownAs {
                Text(known).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            if killable {
                if store.killingPids.contains(port.pid) {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        store.kill(pid: port.pid)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Arrêter")
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Process système (\(port.user)) — non modifiable")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .help(port.commandLine)
    }
}
