import SwiftUI

#if !APP_STORE
struct SidebarUpdateCard: View {
    @Environment(UpdateManager.self) private var updater
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false

    var body: some View {
        if case let .readyToRelaunch(version) = updater.state {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text(Loc.updatedTo(version))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                    Text(Loc.relaunchToApply)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button {
                    updater.relaunchAndInstall()
                } label: {
                    Text(Loc.relaunch)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.accentColor.opacity(0.30))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color.appSurface)
                                             : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.08))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .onHover { hovering = $0 }
            .motionAwareAnimation(.easeOut(duration: 0.15), value: hovering)
            .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
        }
    }
}
#endif
