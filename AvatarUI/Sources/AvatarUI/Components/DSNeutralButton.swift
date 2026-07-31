// Figma "Components" → Button, Type=Fill, Color=Neutral (12:216): zelfde
// maten als de brand-variant (DSPrimaryButton), maar bg background/neutral
// en label/icoon in foreground/primary. DSAddButton is dé add-knop uit het
// designbesluit (10 jun, sidebar): deze neutral button met plus-icoon.

import SwiftUI

public struct DSNeutralButton: View {
    private let title: String
    private let icon: Image?
    private let size: DSPrimaryButton.Size
    private let fullWidth: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        icon: Image? = nil,
        size: DSPrimaryButton.Size = .default,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            DSButtonLabel(title: title, icon: icon, size: size)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(DSColor.Background.neutral, in: Capsule())
        }
        .buttonStyle(DSStateOpacityButtonStyle())
    }
}

/// Add-knop (sidebar: nieuw persoon toevoegen) — één patroon app-breed.
public struct DSAddButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        DSNeutralButton(title, icon: Image(systemName: "plus"), action: action)
    }
}
