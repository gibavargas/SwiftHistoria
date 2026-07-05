import SwiftUI

@main
struct PaxHistoriaApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 700)
        }
        #if os(macOS)
        .commands {
            NativeCommandMenu(appState: appState)
        }
        #endif
    }
}

/// Shared navigation state accessible from the menu bar commands.
@MainActor
final class AppState: ObservableObject {
    #if os(macOS)
        /// Navigation target for the macOS sidebar / toolbar.
        @Published var macDestination: NativeMacDestination? = .overview
    #endif

    /// Whether the game is currently active (country selected).
    @Published var isGameActive = false
}

#if os(macOS)
    /// macOS menu bar commands for SwiftHistoria.
    /// Uses standard menu locations (File, Game, Navigate) so the menu bar
    /// is fully functional — not just decorative.
    struct NativeCommandMenu: Commands {
        @ObservedObject var appState: AppState

        var body: some Commands {
            // Replace the File menu with our own campaign management actions
            CommandGroup(replacing: .importExport) {
                Button("Export Campaign…") {
                    NotificationCenter.default.post(name: .exportCampaign, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Import Campaign…") {
                    NotificationCenter.default.post(name: .importCampaign, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            // Game menu — advance turn, refresh suggestions
            CommandGroup(after: .toolbar) {
                Section("Game") {
                    Button("Advance Turn") {
                        NotificationCenter.default.post(name: .advanceTurn, object: nil)
                    }
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(!appState.isGameActive)

                    Button("Cancel Turn") {
                        NotificationCenter.default.post(name: .cancelTurn, object: nil)
                    }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!appState.isGameActive)

                    Divider()

                    Button("Refresh Decision Matrix") {
                        NotificationCenter.default.post(name: .refreshSuggestions, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!appState.isGameActive)
                }
            }

            // Navigate menu — jump to any destination
            CommandGroup(after: .windowArrangement) {
                Section("Navigate") {
                    ForEach(NativeMacDestination.allCases) { dest in
                        Button(dest.title) {
                            appState.macDestination = dest
                        }
                        .keyboardShortcut(dest.keyboardShortcutKey, modifiers: [.command, .option])
                    }
                }
            }
        }
    }
#endif

extension Notification.Name {
    static let exportCampaign = Notification.Name("NativeExportCampaign")
    static let importCampaign = Notification.Name("NativeImportCampaign")
    static let advanceTurn = Notification.Name("NativeAdvanceTurn")
    static let cancelTurn = Notification.Name("NativeCancelTurn")
    static let refreshSuggestions = Notification.Name("NativeRefreshSuggestions")
}

#if os(macOS)
    extension NativeMacDestination {
        var keyboardShortcutKey: KeyEquivalent {
            switch self {
            case .overview: "1"
            case .orders: "2"
            case .advisor: "3"
            case .diplomacy: "4"
            case .events: "5"
            case .worldEconomics: "6"
            case .library: "7"
            case .settings: "8"
            }
        }
    }
#endif
