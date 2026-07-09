import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var store: PortStore
    @AppStorage(SettingsKeys.scanInterval) private var scanInterval = 5
    @AppStorage(SettingsKeys.staleHours) private var staleHours = 3
    @AppStorage(SettingsKeys.notifyNewPorts) private var notifyNew = true
    @AppStorage(SettingsKeys.notifyStalePorts) private var notifyStale = true
    @AppStorage(SettingsKeys.showSystemPorts) private var showSystem = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String? = nil

    var body: some View {
        Form {
            Section("Scan") {
                Picker("Fréquence de scan", selection: $scanInterval) {
                    Text("2 s").tag(2)
                    Text("5 s").tag(5)
                    Text("10 s").tag(10)
                    Text("30 s").tag(30)
                }
                Toggle("Afficher les ports système", isOn: $showSystem)
            }

            Section("Notifications") {
                Toggle("Nouveau port détecté", isOn: $notifyNew)
                Toggle("Rappel pour les ports qui traînent", isOn: $notifyStale)
                Picker("Rappel après", selection: $staleHours) {
                    Text("1 h").tag(1)
                    Text("2 h").tag(2)
                    Text("3 h").tag(3)
                    Text("6 h").tag(6)
                    Text("12 h").tag(12)
                    Text("24 h").tag(24)
                }
                .disabled(!notifyStale)
            }

            Section("Général") {
                Toggle("Lancer au démarrage de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let error = loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            if !store.ignoredKeys.isEmpty {
                Section("Ports ignorés (\(store.ignoredKeys.count))") {
                    ForEach(store.ignoredKeys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).font(.system(.callout, design: .monospaced))
                            Spacer()
                            Button("Réactiver") {
                                store.ignoredKeys.remove(key)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .frame(minHeight: 380)
    }
}
