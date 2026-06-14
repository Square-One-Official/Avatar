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
    private let credits: String?
    private let isSelected: Bool
    private let isWorking: Bool
    private let tileSize: CGFloat
    private let icon: Icon

    public init(
        label: String,
        isPro: Bool = false,
        credits: String? = nil,
        isSelected: Bool = false,
        isWorking: Bool = false,
        tileSize: CGFloat = 88,
        @ViewBuilder icon: () -> Icon
    ) {
        self.label = label
        self.isPro = isPro
        self.credits = credits
        self.isSelected = isSelected
        self.isWorking = isWorking
        self.tileSize = tileSize
        self.icon = icon()
    }

    public var body: some View {
        VStack(spacing: DSSpacing.gap2) {
            tile
            Text(label)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(isSelected ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
                .lineLimit(1)
        }
        .dsHoverScale()
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg)
            .fill(DSColor.Background.neutral)
            // Icoon/preview gecentreerd (placeholder-tinten tot echte
            // thumbnails landen — zie ASSETS.md voor de Effects-tiles).
            .overlay {
                icon
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            // Credit-kost onderin over een donkere fade (leesbaar op elke tint).
            .overlay(alignment: .bottom) {
                if credits != nil {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: tileSize * 0.55)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let credits {
                    Text(credits)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpacing.gap1_5)
                        .padding(.bottom, DSSpacing.gap1)
                }
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
            .frame(width: tileSize, height: tileSize)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            // Pro-badge bovenin (boven de clip zodat 'm niet afsnijdt).
            .overlay(alignment: .topLeading) {
                if isPro {
                    DSProChip()
                        .padding(DSSpacing.gap1)
                }
            }
            // Selectie-/active-ring + check-badge (E24.28: duidelijke
            // active-state, gedeelde regel voor toggle-/selectie-acties).
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(DSColor.Action.primary, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DSColor.Action.primary)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .padding(DSSpacing.gap1)
                }
            }
    }
}
