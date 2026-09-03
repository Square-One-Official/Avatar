// FigJam-stijl naam-chip linksboven het frame (E33). Vervangt de gecentreerde
// PortraitHeader in de enkel-editor: toont de portretnaam als pill; één klik
// opent de rename-modal. Lege naam → "Add name" (zelfde copy als het
// editor-broodkruim). Het frame is altijd actief — de chip deelt één rij
// met Frame/Background/grid naast de kaart.

import AvatarUI
import SwiftUI

struct CanvasFrameChip: View {
    var name: String?
    var onRename: () -> Void

    private var displayName: String {
        let n = name ?? ""
        return n.isEmpty ? "Add name" : n
    }
    private var hasName: Bool { !(name ?? "").isEmpty }

    var body: some View {
        Button(action: onRename) {
            Text(displayName)
                .dsTextStyle(.bodyMedium)
                .lineLimit(1)
                .frame(height: 28)
                .padding(.horizontal, DSSpacing.gap3)
        }
        .buttonStyle(FrameChipButtonStyle(hasName: hasName))
        .help(hasName ? "Rename" : "Add name")
        .accessibilityLabel(hasName ? "Rename \(displayName)" : "Add name")
    }
}

/// Zelfde 1-klik ButtonStyle-patroon als de Frame/Background-pillen ernaast.
private struct FrameChipButtonStyle: ButtonStyle {
    let hasName: Bool

    func makeBody(configuration: Configuration) -> some View {
        FrameChipChrome(hasName: hasName, configuration: configuration)
    }
}

private struct FrameChipChrome: View {
    let hasName: Bool
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hasName ? DSColor.Foreground.primary : DSColor.Foreground.muted)
            .background(
                DSColor.neutralSurface(
                    pressed: configuration.isPressed,
                    hovering: hovering,
                    base: DSColor.Background.neutralStronger
                ),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(EditorView.frameSelectionGrey, lineWidth: 1.5)
            )
            .contentShape(Capsule(style: .continuous))
            .onHover { hovering = $0 }
            .dsMotion(DSMotion.micro, value: hovering)
            .dsMotion(DSMotion.micro, value: configuration.isPressed)
    }
}
