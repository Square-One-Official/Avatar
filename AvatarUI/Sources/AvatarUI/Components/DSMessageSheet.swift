// In-app bericht-UI (E17.4) voor het verenigde Message-model: een sheet-
// variant (hero + body + CTA + dismiss) en een compacte banner-variant.
// Stijl spiegelt DSEditPanel (bg Card, r-xl4, shadow) in de v2-huisstijl
// (lime/dark); tokens uit E03. Geen netwerk-afhankelijkheid buiten AsyncImage.

import SwiftUI

/// Markdown → AttributedString, met platte tekst als fallback.
private func attributed(_ markdown: String) -> AttributedString {
    (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
}

/// Volledig bericht als kaart-sheet: optionele 16:9 hero, titel, markdown-
/// body, optionele lime CTA en een dismiss-kruis. De caller plaatst 'm in een
/// overlay/sheet en geeft de acties.
public struct DSMessageSheet: View {
    private let title: String
    private let messageBody: String
    private let imageURL: URL?
    private let ctaLabel: String?
    private let onCTA: () -> Void
    private let onDismiss: () -> Void

    public init(
        title: String,
        body: String,
        imageURL: URL? = nil,
        ctaLabel: String? = nil,
        onCTA: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.title = title
        self.messageBody = body
        self.imageURL = imageURL
        self.ctaLabel = ctaLabel
        self.onCTA = onCTA
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            if let imageURL {
                hero(imageURL)
            }
            HStack(alignment: .top, spacing: DSSpacing.gap2) {
                Text(title)
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: DSSpacing.gap2)
                DSIconButton(Image(systemName: "xmark"), label: "Dismiss", size: .small) { onDismiss() }
            }
            Text(attributed(messageBody))
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let ctaLabel, !ctaLabel.isEmpty {
                DSPrimaryButton(ctaLabel, fullWidth: true) { onCTA() }
                    .padding(.top, DSSpacing.gap1)
            }
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 420, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 12)
    }

    private func hero(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                DSColor.Background.neutral
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }
}

/// Compacte inline-banner: optionele thumb, titel + 1-regel body, optionele
/// CTA-chevron en dismiss. Voor een rustiger, niet-blokkerende presentatie.
public struct DSMessageBanner: View {
    private let title: String
    private let messageBody: String
    private let imageURL: URL?
    private let hasCTA: Bool
    private let onCTA: () -> Void
    private let onDismiss: () -> Void

    public init(
        title: String,
        body: String,
        imageURL: URL? = nil,
        hasCTA: Bool = false,
        onCTA: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.title = title
        self.messageBody = body
        self.imageURL = imageURL
        self.hasCTA = hasCTA
        self.onCTA = onCTA
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap3) {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DSColor.Background.neutral
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
            }
            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text(title)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .lineLimit(1)
                Text(messageBody)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: DSSpacing.gap2)
            if hasCTA {
                DSIconButton(Image(systemName: "chevron.right"), label: "Open", size: .small) { onCTA() }
            }
            DSIconButton(Image(systemName: "xmark"), label: "Dismiss", size: .small) { onDismiss() }
        }
        .padding(DSSpacing.gap3)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }
}
