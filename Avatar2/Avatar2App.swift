import AvatarKit
import SwiftUI

@main
struct Avatar2App: App {
    var body: some Scene {
        WindowGroup {
            ContentPlaceholderView()
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}

/// Tijdelijke placeholder tot de main-shell (E05) landt.
struct ContentPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.square.badge.camera")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Aaavatar 2.0")
                .font(.title2.weight(.semibold))
            Text("Scaffold — E01.1")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Engines: \(CutoutEngineKind.allCases.map(\.rawValue).joined(separator: " · "))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
