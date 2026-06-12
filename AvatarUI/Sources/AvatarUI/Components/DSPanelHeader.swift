// Figma "Stories" → Onboarding / Email, OTP, Splash, Permissions (dark) →
// "Copy"-blok: titel Content/Headings/H1 (primary) met daaronder subtitel
// Content/Body/Medium (subtle), kolomgap gap-2, gecentreerd. Onboarding
// centreert; voor toekomstige zijpanelen is leading beschikbaar.

import SwiftUI

public struct DSPanelHeader: View {
    private let title: String
    private let subtitle: String?
    private let alignment: HorizontalAlignment

    public init(_ title: String, subtitle: String? = nil, alignment: HorizontalAlignment = .center) {
        self.title = title
        self.subtitle = subtitle
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: DSSpacing.gap2) {
            Text(title)
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)
            if let subtitle {
                Text(subtitle)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}
