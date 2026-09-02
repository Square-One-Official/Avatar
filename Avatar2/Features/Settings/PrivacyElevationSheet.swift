// Just-in-time elevation modal: one-click Turn on Cloud.

import AvatarUI
import SwiftUI

struct PrivacyElevationRequest: Equatable {
    let feature: AIFeature
    let requiredTier: AIPrivacyTier
}

struct PrivacyElevationSheet: View {
    let request: PrivacyElevationRequest
    var onEnableCloud: () -> Void
    var onDismiss: () -> Void

    private var creditSuffix: String {
        guard let cost = request.feature.creditCost else { return "" }
        return " Costs \(cost) credit\(cost == 1 ? "" : "s")."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                DSIconButton(Image(systemName: "xmark"), label: "Close", size: .small, action: onDismiss)
            }
            .padding(.bottom, DSSpacing.gap2)

            DSIcon(AIPrivacyTier.thirdParty.icon, size: 32, weight: .regular)
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(.bottom, DSSpacing.gap4)

            Text("Turn on Cloud to use \(request.feature.uiLabel)")
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
                DSPrimaryButton("Turn on Cloud", action: onEnableCloud)
            }
            .padding(.top, DSSpacing.gap8)
        }
        .padding(DSSpacing.gap6)
        .frame(width: 360)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }
}
