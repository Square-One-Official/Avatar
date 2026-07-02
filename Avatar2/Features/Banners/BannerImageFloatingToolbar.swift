// E37.14–37.15 — Freeform-stijl floating toolbar voor logo / achtergrond-image.

import AvatarUI
import SwiftUI

enum BannerImageToolbarKind {
    case logo
    case backgroundFill
}

struct BannerImageFloatingToolbar: View {
    let kind: BannerImageToolbarKind
    let filename: String
    let byteCount: Int
    let imageData: Data
    let onReplace: () -> Void
    let onRemove: () -> Void
    /// Verhoog vanuit canvas-chrome om het info-menu te sluiten (tik buiten).
    var menuDismissNonce: Int = 0
    var onMenusOpenChange: ((Bool) -> Void)?

    @State private var showInfoMenu = false

    var body: some View {
        HStack(spacing: DSSpacing.gap4) {
            toolButton("photo", active: showInfoMenu) {
                showInfoMenu.toggle()
            }
            .dsDropdownMenu(isPresented: $showInfoMenu, anchorHeight: 32) {
                infoMenu
            }

            if kind == .backgroundFill {
                toolButton("hand.draw", active: false) { }
                    .opacity(0.85)
                    .help("Drag the canvas to reframe")
            } else {
                toolButton("crop", active: false) { }
                    .opacity(0.35)
                    .disabled(true)
                    .help("Crop — coming soon")
            }

            toolButton("eye", active: false) {
                BannerNativePanels.quickLook(data: imageData, filename: filename)
            }
            .help("Preview")
        }
        .padding(.horizontal, DSSpacing.gap4)
        .padding(.vertical, DSSpacing.gap2)
        .background(
            Capsule(style: .continuous)
                .fill(DSColor.Background.card)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        )
        .onChange(of: menuDismissNonce) { _, _ in showInfoMenu = false }
        .onChange(of: showInfoMenu) { _, open in onMenusOpenChange?(open) }
    }

    private func toolButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : DSColor.Foreground.primary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var infoMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            HStack {
                Text(truncatedFilename)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            Text(BannerNativePanels.formatByteCount(byteCount))
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)

            Divider()

            Button("Replace image") { showInfoMenu = false; onReplace() }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Remove") { showInfoMenu = false; onRemove() }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DSSpacing.gap3)
        .frame(width: 240)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: $showInfoMenu)
    }

    private var truncatedFilename: String {
        if filename.count <= 28 { return filename }
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        let head = String(base.prefix(12))
        return ext.isEmpty ? "\(head)…" : "\(head)….\(ext)"
    }
}
