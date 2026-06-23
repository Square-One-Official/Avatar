// Figma "Components" → Toast (State=Default).
// Kaart: bg Card, border b-thin in divider, radius r-lg, breedte 360,
// Shadows/Default. Body: padding gap-4, kolomgap gap-1; titel UI/Labels/Large
// (primary), omschrijving Content/Body/Small (subtle), sluitknop = small
// ghost Icon-Only Button (16pt X). Onderin 3pt timer-track: bg neutral,
// vulling foreground/action/primary.

import SwiftUI

public struct DSToast: View {
    private let title: String
    private let description: String?
    /// Resterend deel van de timer, 1...0; nil verbergt de track.
    private let progress: Double?
    /// Toont een kleine spinner links van de titel (voor lopende acties).
    private let isLoading: Bool
    private let onClose: () -> Void

    public init(
        title: String,
        description: String? = nil,
        progress: Double? = nil,
        isLoading: Bool = false,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.description = description
        self.progress = progress
        self.isLoading = isLoading
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                HStack(alignment: .top, spacing: 0) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, DSSpacing.gap2)
                            .padding(.top, 1)
                    }
                    Text(title)
                        .dsTextStyle(.labelLarge)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DSIconButton(
                        Image(systemName: "xmark"),
                        style: .ghostNeutral,
                        size: .small,
                        action: onClose
                    )
                }
                if let description {
                    Text(description)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DSSpacing.gap4)

            if let progress {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(DSColor.Action.primary)
                            .frame(width: proxy.size.width * progress.clamped01)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 3)
                .background(DSColor.Background.neutral)
            }
        }
        .frame(width: 360)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
        )
        // Shadows/Default (0, 80, blur 80, spread -40): SwiftUI kent geen
        // spread; offset en blur gehalveerd als visuele benadering.
        .shadow(
            color: DSShadow.default.color,
            radius: DSShadow.default.radius / 2,
            x: DSShadow.default.offset.width,
            y: DSShadow.default.offset.height / 2
        )
    }
}
