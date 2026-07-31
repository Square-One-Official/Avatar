// E37.14–37.15 — Freeform-stijl floating toolbar voor logo / achtergrond-image.

import AvatarUI
import SwiftUI

enum BannerImageToolbarKind {
    case logo
    case backgroundFill
}

struct BannerImageFloatingToolbar: View {
    let kind: BannerImageToolbarKind
    var presentation: UIPresentationStore
    let filename: String
    let byteCount: Int
    let imageData: Data
    let onReplace: () -> Void
    let onRemove: () -> Void
    /// Verhoog vanuit canvas-chrome om het info-menu te sluiten (tik buiten).
    var menuDismissNonce: Int = 0
    var onMenusOpenChange: ((Bool) -> Void)?

    private var infoMenuOpen: Binding<Bool> {
        Binding(
            get: { presentation.bannerFloatingMenu == .imageInfo },
            set: { presentation.bannerFloatingMenu = $0 ? .imageInfo : nil }
        )
    }

    var body: some View {
        HStack(spacing: DSSpacing.gap4) {
            toolButton("photo", active: presentation.bannerFloatingMenu == .imageInfo) {
                presentation.bannerFloatingMenu = presentation.bannerFloatingMenu == .imageInfo ? nil : .imageInfo
            }
            .dsDropdownMenu(isPresented: infoMenuOpen, anchorHeight: 32) {
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
                .dsShadow(.card)
        )
        .onChange(of: menuDismissNonce) { _, _ in presentation.bannerFloatingMenu = nil }
        .onChange(of: presentation.bannerFloatingMenu) { _, menu in
            onMenusOpenChange?(menu == .imageInfo)
        }
    }

    private func toolButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? DSColor.Action.primary : DSColor.Foreground.primary)
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

            Button("Replace image") { presentation.bannerFloatingMenu = nil; onReplace() }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // UXS-23: dit is een destructieve actie maar stond in de muted-
            // kleur — dus onopvallender dan "Replace image" ernaast. Zelfde
            // token als de andere destructieve rijen.
            Button("Remove") { presentation.bannerFloatingMenu = nil; onRemove() }
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DSSpacing.gap3)
        .frame(width: 240)
        .dsPanelSurface(cornerRadius: DSRadius.lg, solid: true)
        .dsDropdownDismissOverlay(isPresented: infoMenuOpen)
    }

    private var truncatedFilename: String {
        if filename.count <= 28 { return filename }
        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        let head = String(base.prefix(12))
        return ext.isEmpty ? "\(head)…" : "\(head)….\(ext)"
    }
}
