import SwiftUI
import AppKit

struct Sidebar: View {
    @Binding var selection: RootView.Tab
    @Namespace private var pillNS

    private struct Section: Identifiable {
        let id: String
        let title: String
        let tabs: [RootView.Tab]
    }

    private let sections: [Section] = [
        Section(id: "cleanup", title: "Cleanup", tabs: [.clean, .analyze, .purge]),
        Section(id: "apps", title: "Apps", tabs: [.uninstall])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // reserve space for traffic lights (matches HeaderBar top padding)
            Color.clear.frame(height: 36)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 4)
                            ForEach(section.tabs) { tab in
                                SidebarItem(
                                    tab: tab,
                                    isSelected: selection == tab,
                                    namespace: pillNS,
                                    action: {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                            selection = tab
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 4)
            }

            Spacer(minLength: 0)
            Divider().opacity(0.4).padding(.horizontal, 16).padding(.vertical, 6)
            SidebarItem(
                tab: .settings,
                isSelected: selection == .settings,
                namespace: pillNS,
                action: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = .settings
                    }
                }
            )
            .padding(.bottom, 12)
        }
        .frame(minWidth: 210, idealWidth: 220, maxWidth: 240)
        .background(
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.09)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        )
    }

}

private struct SidebarItem: View {
    let tab: RootView.Tab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.85))
                    .scaleEffect(isSelected ? 1.08 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: isSelected)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
                            .matchedGeometryEffect(id: "pill", in: namespace)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
            )
            .padding(.horizontal, 8)
            .scaleEffect(pressing ? 0.97 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onLongPressGesture(minimumDuration: 0.0001, pressing: { pressing = $0 }, perform: {})
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressing)
    }
}
