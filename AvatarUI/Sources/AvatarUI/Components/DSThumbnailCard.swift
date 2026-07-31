// Gedeelde thumbnail-kaart (E24.15) voor de subject-panelen (Effects/Face,
// klaar voor Clothing/Hair). Eén vierkante preview-tile met: optionele
// top-leading Pro-badge, optionele credit-kost onderin over een
// donker-fade-gradient, een label eronder, selectie-ring en hover-scale.
//
// Icoon-agnostisch: de Phosphor-glyphs hangen aan het app-target (niet aan
// AvatarUI — zie project.yml), dus de aanroeper levert het icoon als view.
// Zo blijft de kaart in de DS-library en delen Effects + Face exact dezelfde
// vorm.

import SwiftUI

public struct DSThumbnailCard<Icon: View>: View {
    private let label: String
    private let isPro: Bool
    private let isSelected: Bool
    private let isWorking: Bool
    private let tileSize: CGFloat
    private let tileHeight: CGFloat
    private let onRefresh: (() -> Void)?
    private let icon: Icon

    /// `tileHeight` defaults to `tileSize` (square). Pass an explicit height
    /// for portrait-shaped cards (e.g. Effects: 112 × 152).
    public init(
        label: String,
        isPro: Bool = false,
        isSelected: Bool = false,
        isWorking: Bool = false,
        tileSize: CGFloat = 88,
        tileHeight: CGFloat? = nil,
        onRefresh: (() -> Void)? = nil,
        @ViewBuilder icon: () -> Icon
    ) {
        self.label = label
        self.isPro = isPro
        self.isSelected = isSelected
        self.isWorking = isWorking
        self.tileSize = tileSize
        self.tileHeight = tileHeight ?? tileSize
        self.onRefresh = onRefresh
        self.icon = icon()
    }

    public var body: some View {
        tile
            .dsHoverScale()
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg)
            .fill(DSColor.Background.neutral)
            .overlay {
                icon
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            // UXS-3: gedeelde scrim — dekking is klaar vóór de tekstzone, dus
            // het label blijft leesbaar op élke tint (ook een witte cutout in
            // light mode).
            .overlay(alignment: .bottom) {
                DSCardLabelScrim()
                    .frame(height: tileHeight * 0.45)
            }
            .overlay(alignment: .bottomLeading) {
                Text(label)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DSSpacing.gap2)
                    .padding(.bottom, DSSpacing.gap2)
            }
            // Werk-spinner (Effects-stijl genereren).
            .overlay {
                if isWorking {
                    ZStack {
                        Color.black.opacity(0.35)
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .frame(width: tileSize, height: tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            // Pro-badge bovenin (boven de clip zodat 'm niet afsnijdt).
            .overlay(alignment: .topLeading) {
                if isPro {
                    DSProChip()
                        .padding(DSSpacing.gap1)
                }
            }
            // Selectie-/active-ring + check-badge.
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(DSColor.Action.primary, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected, let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(DSSpacing.gap1)
                    .help("Regenerate")
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DSColor.Action.primary)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .padding(DSSpacing.gap1)
                }
            }
    }
}
