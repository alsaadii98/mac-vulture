import SwiftUI
import MacVultureCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var whitelistText: String = WhitelistEditor.read()

    var body: some View {
        Form {
            Section("Defaults") {
                Toggle("Dry-run by default", isOn: $appState.dryRunDefault)
            }
            Section("Whitelist") {
                Text("One path or glob per line. `~/` and `*` supported. Lines starting with `#` are comments.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $whitelistText)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 140)
                    .border(.separator)
                HStack {
                    Button("Save") { WhitelistEditor.write(whitelistText) }
                        .keyboardShortcut("s")
                    Button("Reload") { whitelistText = WhitelistEditor.read() }
                    Spacer()
                    Button("Open file") {
                        Reveal.inFinder(WhitelistEditor.path.path)
                    }
                }
            }
            Section("Logs") {
                Text("~/Library/Logs/mac-vulture/operations.log").font(.callout.monospaced())
                Button("Reveal in Finder") {
                    let url = URL(fileURLWithPath: NSHomeDirectory())
                        .appendingPathComponent("Library/Logs/mac-vulture/operations.log")
                    Reveal.inFinder(url.path)
                }
            }
            Section("About") {
                LabeledContent("Version", value: MacVultureCore.version)
                Link("github.com/alsaadii98/mac-vulture", destination: URL(string: "https://github.com/alsaadii98/mac-vulture")!)
            }
        }
        .formStyle(.grouped)
    }
}
