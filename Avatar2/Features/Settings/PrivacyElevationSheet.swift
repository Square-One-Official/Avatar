// Just-in-time elevation modal: legt uit welke tier nodig is en stuurt naar Settings.

import AvatarUI
import SwiftUI

struct PrivacyElevationRequest: Equatable {
    let feature: AIFeature
    let requiredTier: AIPrivacyTier
}

struct PrivacyElevationSheet: View {
    let request: PrivacyElevationRequest
    var onOpenSettings: () -> Void
    var onDismiss: () -> Void

    private var creditSuffix: String {
        guard let cost = request.feature.creditCost else { return "" }
        return " Costs \(cost) credit\(cost == 1 ? "" : "s")."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                DSIconButton(Image(systemName: "xmark"), size: .small, action: onDismiss)
            }
            .padding(.bottom, DSSpacing.gap2)

            DSIcon(request.requiredTier.icon, size: 32, weight: .regular)
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(.bottom, DSSpacing.gap4)

            Text("\(request.feature.uiLabel) requires \(request.requiredTier.title)")
                .dsTextStyle(.h4)
                .foregroundStyle(DSColor.Foreground.primary)
                .multilineTextAlignment(.center)
                .padding(.bottom, DSSpacing.gap3)

            Text(request.feature.elevationBody + creditSuffix)
                .dsTextStyle(.bodyMedium)
                .foregroundStyle(DSColor.Foreground.subtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DSSpacing.gap3) {
                DSNeutralButton("Not now", action: onDismiss)
                DSPrimaryButton("Privacy settings", action: onOpenSettings)
            }
            .padding(.top, DSSpacing.gap8)
        }
        .padding(DSSpacing.gap6)
        .frame(width: 360)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }
}
