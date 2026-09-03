// Execution-tier badge op feature chips (Privacy Tier Picker).

import SwiftUI

public enum DSPrivacyExecutionTier: Sendable, Equatable {
    case onDevice
    case appleCloud
    case thirdParty

    var icon: DSIcon.Symbol {
        switch self {
        case .onDevice: return .privacyOnDevice
        case .appleCloud: return .privacyAppleCloud
        case .thirdParty: return .privacyAdvanced
        }
    }

    public init(privacyTier: Int) {
        switch privacyTier {
        case 1: self = .onDevice
        case 2: self = .appleCloud
        default: self = .thirdParty
        }
    }
}

public struct DSPrivacyBadge: View {
    private let tier: DSPrivacyExecutionTier
    private let label: String?

    public init(tier: DSPrivacyExecutionTier, label: String? = nil) {
        self.tier = tier
        self.label = label
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap0_5) {
            DSIcon(tier.icon, size: 11, weight: .regular)
            if let label {
                Text(label)
                    .dsTextStyle(.labelSmall)
            }
        }
        .foregroundStyle(DSColor.Foreground.muted)
    }
}
