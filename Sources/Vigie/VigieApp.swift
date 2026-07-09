import SwiftUI

@main
enum Entry {
    static func main() {
        // Headless mode for testing the scanner without the UI: `Vigie --scan`
        if CommandLine.arguments.contains("--scan") {
            let ports = PortScanner.scanSync()
            for p in ports {
                let flags = [
                    p.category.rawValue,
                    p.exposed ? "EXPOSÉ" : nil,
                    p.isAI ? "IA" : nil,
                    p.launchedBy.map { "via \($0)" },
                    p.knownAs,
                    p.cwdDisplay,
                ].compactMap { $0 }.joined(separator: " | ")
                let col1 = ":\(p.port)".padding(toLength: 7, withPad: " ", startingAt: 0)
                let col2 = String(p.name.prefix(24)).padding(toLength: 25, withPad: " ", startingAt: 0)
                let col3 = p.uptimeText.padding(toLength: 10, withPad: " ", startingAt: 0)
                let col4 = p.memoryText.padding(toLength: 9, withPad: " ", startingAt: 0)
                print("\(col1)\(col2)\(col3)\(col4)\(flags)")
            }
            print("\n\(ports.count) ports en écoute.")
            exit(0)
        }
        VigieApp.main()
    }
}

struct VigieApp: App {
    @StateObject private var store = PortStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(store)
        } label: {
            Image(systemName: "network")
            let count = store.devPorts.count
            if count > 0 {
                Text("\(count)")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
