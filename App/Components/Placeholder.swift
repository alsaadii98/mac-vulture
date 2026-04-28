import SwiftUI

struct Placeholder: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
