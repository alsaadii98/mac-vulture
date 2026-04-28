import SwiftUI
import MacVultureCore

@main
struct MacVultureApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Mac Vulture", id: "main") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
                .background(WindowAccessor { window in
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.styleMask.insert(.fullSizeContentView)
                    window.isMovableByWindowBackground = true
                })
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Mac Vulture", systemImage: "bird.fill") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: Tab = .clean

    enum Tab: String, CaseIterable, Identifiable {
        case clean, analyze, uninstall, purge, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .clean: return "Clean"
            case .analyze: return "Analyze"
            case .uninstall: return "Uninstall"
            case .purge: return "Project Purge"
            case .settings: return "Settings"
            }
        }
        var icon: String {
            switch self {
            case .clean: return "sparkles"
            case .analyze: return "chart.pie.fill"
            case .uninstall: return "trash.fill"
            case .purge: return "shippingbox.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
                }
            VStack(spacing: 0) {
                HeaderBar()
                Group {
                    switch selection {
                    case .clean: CleanView()
                    case .analyze: AnalyzeView()
                    case .uninstall: UninstallView()
                    case .purge: PurgeView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                FooterBar()
            }
            .background(Color(red: 0.10, green: 0.11, blue: 0.12))
        }
    }
}
