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
    @State private var selection: Tab = .dashboard

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard, clean, analyze, uninstall, purge, status, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .clean: return "Clean"
            case .analyze: return "Analyze"
            case .uninstall: return "Uninstall"
            case .purge: return "Project Purge"
            case .status: return "Status"
            case .settings: return "Settings"
            }
        }
        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.50percent"
            case .clean: return "sparkles"
            case .analyze: return "chart.pie.fill"
            case .uninstall: return "trash.fill"
            case .purge: return "shippingbox.fill"
            case .status: return "waveform.path.ecg"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection {
            case .dashboard: DashboardView()
            case .clean: CleanView()
            case .analyze: AnalyzeView()
            case .uninstall: UninstallView()
            case .purge: PurgeView()
            case .status: StatusView()
            case .settings: SettingsView()
            }
        }
    }
}
