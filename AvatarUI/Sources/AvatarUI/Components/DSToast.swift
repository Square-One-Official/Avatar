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
    /// Resterend deel van de timer, 1...0; nil verbergt de track. Wordt genegeerd
    /// zodra `autoDismiss` is gezet — de toast telt dan zelf af.
    private let progress: Double?
    /// Toont een kleine spinner links van de titel (voor lopende acties).
    private let isLoading: Bool
    /// UXS-2: laat de toast zichzelf opruimen na deze duur, met een zichtbare
    /// timer-track en pauze zolang de muis erboven hangt. nil = de call site
    /// bepaalt zelf wanneer de toast verdwijnt.
    private let autoDismiss: Duration?
    /// nil = geen sluit-affordance. Een sluitknop die niets doet mag niet
    /// bestaan (UXS-2), dus zonder actie renderen we de knop óók niet.
    private let onClose: (() -> Void)?

    /// Resterende fractie van `autoDismiss`, 1 → 0.
    @State private var remaining: Double = 1
    @State private var isHovering = false

    public init(
        title: String,
        description: String? = nil,
        progress: Double? = nil,
        isLoading: Bool = false,
        autoDismiss: Duration? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.title = title
        self.description = description
        self.progress = progress
        self.isLoading = isLoading
        self.autoDismiss = autoDismiss
        self.onClose = onClose
    }

    /// Hertelt de timer zodra de inhoud wijzigt: een vervángende melding krijgt
    /// de volle duur i.p.v. de resterende tijd van z'n voorganger (UX4).
    private var contentKey: String { "\(title)|\(description ?? "")" }

    private var trackProgress: Double? {
        autoDismiss == nil ? progress : remaining
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
                    if let onClose {
                        DSIconButton(
                            Image(systemName: "xmark"),
                            label: "Dismiss",
                            style: .ghostNeutral,
                            size: .small,
                            action: onClose
                        )
                    }
                }
                if let description {
                    Text(description)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DSSpacing.gap4)

            if let trackProgress {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(DSColor.Action.primary)
                            .frame(width: proxy.size.width * trackProgress.clamped01)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 3)
                .background(DSColor.Background.neutral)
            }
        }
        // UXS-2: hover bevriest de timer — je kunt een melding lezen zonder dat
        // 'ie onder je muis vandaan verdwijnt.
        .onHover { isHovering = $0 }
        .task(id: contentKey) {
            guard let autoDismiss, let onClose else { return }
            remaining = 1
            let step = Duration.milliseconds(50)
            let total = Double(autoDismiss.components.seconds)
                + Double(autoDismiss.components.attoseconds) / 1e18
            guard total > 0 else { return }
            let stepFraction = 0.05 / total
            while remaining > 0 {
                try? await Task.sleep(for: step)
                if Task.isCancelled { return }
                guard !isHovering else { continue }
                remaining -= stepFraction
            }
            onClose()
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
