// 48-cirkel-toolknop (E03.11; Figma Components → Icon-Only Button en de
// toolbar/gear in App / Edit). De cirkels zijn in het design geen vlakke
// fill maar een glazige donkere material met subtiele rand/highlight —
// Figma exposeert dat effect niet als variabele, dus: ultraThinMaterial
// + background/neutral + dunne rim die van boven licht oploopt (geijkt op
// de frames). Active = lime ring b-medium + lime icoon (E03.3-gedrag).

import SwiftUI

public struct DSToolButton: View {
    private let icon: Image
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    public init(
        _ icon: Image,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? DSColor.Action.primary : DSColor.Foreground.primary)
                .frame(width: 48, height: 48)
                .background { DSGlassCircle() }
                .overlay {
                    if isActive {
                        Circle().strokeBorder(
                            DSColor.Action.primary,
                            lineWidth: DSBorderWidth.medium
                        )
                    }
                }
        }
        .buttonStyle(DSStateOpacityButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// De glass-surface van de toolcirkels: donkere material, neutral-tint en
/// een rim die bovenaan subtiel oplicht.
struct DSGlassCircle: View {
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(DSColor.Background.neutral)
            Circle().strokeBorder(
                LinearGradient(
                    colors: [
                        DSColor.Foreground.primary.opacity(0.18),
                        DSColor.Foreground.primary.opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: DSBorderWidth.thin
            )
        }
    }
}
