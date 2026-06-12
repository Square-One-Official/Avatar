// Figma "Components" → Button, Type=Fill, Color=Neutral (12:216): zelfde
// maten als de brand-variant (DSPrimaryButton), maar bg background/neutral
// en label/icoon in foreground/primary. DSAddButton is dé add-knop uit het
// designbesluit (10 jun, sidebar): deze neutral button met plus-icoon.

import SwiftUI

public struct DSNeutralButton: View {
    private let title: String
    private let icon: Image?
    private let size: DSPrimaryButton.Size
    private let action: () -> Void

    public init(
        _ title: String,
        icon: Image? = nil,
        size: DSPrimaryButton.Size = .default,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: size.contentGap) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.iconSize, height: size.iconSize)
                }
                Text(title)
                    .dsTextStyle(size.textStyle)
                    .lineLimit(1)
            }
            .foregroundStyle(DSColor.Foreground.primary)
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
