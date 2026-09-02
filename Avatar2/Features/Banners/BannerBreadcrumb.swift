// Drill-in-breadcrumb voor de Banner Studio (zelfde patroon als LibraryBreadcrumb).
// Toont "Banners ▸ <Naam>"; crumbs zijn klikbaar, back-chevron sluit de studio.

import AvatarUI
import SwiftUI

struct BannerBreadcrumb: View {
    let model: ShellModel

    private var doc: BannerDoc? { model.editingBanner }

    var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            Button { model.goBackFromBanner() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: DSIconSize.sm, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsHoverHighlight(cornerRadius: DSRadius.md)
            .help("Back")

            trail
        }
        .padding(.leading, DSSpacing.gap1_5)
        .padding(.trailing, DSSpacing.gap2)
        .frame(height: 28)
        .background(DSColor.Background.card, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
    }

    @ViewBuilder private var trail: some View {
        let name = doc.map { $0.name.isEmpty ? "Untitled" : $0.name } ?? "Untitled"
        crumb("Banners") { model.goBackFromBanner() }
        sep
        leaf(name)
    }

    private func crumb(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.muted)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.gap1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .dsHoverHighlight(cornerRadius: DSRadius.md)
        .help("Go to \(text)")
    }

    private func leaf(_ text: String) -> some View {
        Text(text)
            .dsTextStyle(.labelBase)
            .foregroundStyle(DSColor.Foreground.primary)
            .lineLimit(1)
    }

    private var sep: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: DSIconSize.xxs, weight: .semibold))
            .foregroundStyle(DSColor.Foreground.muted.opacity(0.7))
    }
}
