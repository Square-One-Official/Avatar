// Folder-header control: grote achtergrond-thumbnail (Figma-kaartstijl) die
// het BackgroundPanel opent in folder-default-modus (Gallery only).

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct FolderDefaultBackgroundControl: View {
    @Bindable var folder: Folder2
    let entitlement: EntitlementModel
    @Binding var isPickerOpen: Bool

    private static let thumbWidth: CGFloat = 220
    private static let thumbAspect: CGFloat = 16.0 / 10.0
    private static var thumbHeight: CGFloat { thumbWidth / thumbAspect }

    var body: some View {
        Button { isPickerOpen.toggle() } label: {
            FolderDefaultBackgroundThumbnail(background: folder.defaultBackground)
                .frame(width: Self.thumbWidth, height: Self.thumbHeight)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DSColor.Foreground.primary)
                        .padding(DSSpacing.gap2)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(DSSpacing.gap2)
                }
                .contentShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .dsHoverScale(1.02)
        .help(FolderDefaultBackgroundControl.help(for: folder.defaultBackground))
        .dsDropdownMenu(isPresented: $isPickerOpen, anchorHeight: Self.thumbHeight, gap: DSSpacing.gap2) {
            BackgroundPanel(
                portrait: nil,
                folder: folder,
                onApply: { background in
                    folder.setDefaultBackground(background)
                    isPickerOpen = false
                },
                entitlement: entitlement
            )
            .padding(DSSpacing.gap4)
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
            .dsPanelSurface(cornerRadius: DSRadius.xl4)
        }
    }

    static func help(for background: PortraitBackground?) -> String {
        guard let background else { return "Default background for new imports — none" }
        switch background {
        case .transparent, .original:
            return "Default background for new imports — none"
        case .color(let hex):
            return "Default background for new imports — \(hex.uppercased())"
        case .image:
            return "Default background for new imports — image"
        }
    }
}

private struct FolderDefaultBackgroundThumbnail: View {
    let background: PortraitBackground?

    var body: some View {
        Group {
            switch background {
            case .color(let hex):
                if let color = Color(hexRGB: hex) {
                    color
                } else {
                    DSColor.Background.inset
                }
            case .image(let data):
                if let image = NSImage(data: data) {
                    Color.clear
                        .overlay { Image(nsImage: image).resizable().scaledToFill() }
                        .clipped()
                } else {
                    DSColor.Background.inset
                }
            case .transparent, .original, .none:
                DSColor.Background.inset
            }
        }
    }
}
