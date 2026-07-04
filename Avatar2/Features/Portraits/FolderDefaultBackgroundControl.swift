// Subtiele folder-header control: standaardachtergrond voor nieuwe imports
// in een user-created map. Opent het bestaande BackgroundPanel in
// folder-default-modus (Gallery only).

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct FolderDefaultBackgroundControl: View {
    @Bindable var folder: Folder2
    let entitlement: EntitlementModel
    @Binding var isPickerOpen: Bool

    var body: some View {
        Button { isPickerOpen.toggle() } label: {
            HStack(spacing: DSSpacing.gap2) {
                FolderDefaultBackgroundSwatch(background: folder.defaultBackground)
                Text(FolderDefaultBackgroundControl.label(for: folder.defaultBackground))
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted.opacity(0.8))
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .help("Default background for new imports in this folder")
        .dsDropdownMenu(isPresented: $isPickerOpen, anchorHeight: 24, gap: DSSpacing.gap2) {
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

    static func label(for background: PortraitBackground?) -> String {
        guard let background else { return "Default background · None" }
        switch background {
        case .transparent, .original:
            return "Default background · None"
        case .color(let hex):
            return "Default background · \(hex.uppercased())"
        case .image:
            return "Default background · Image"
        }
    }
}

private struct FolderDefaultBackgroundSwatch: View {
    let background: PortraitBackground?

    var body: some View {
        Group {
            switch background {
            case .color(let hex):
                if let color = Color(hexRGB: hex) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DSColor.Background.neutral)
                }
            case .image(let data):
                if let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DSColor.Background.neutral)
                }
            case .transparent, .original, .none:
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(DSColor.Background.neutral)
            }
        }
        .frame(width: 14, height: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
        }
    }
}
