// Prompt-dialog: titel + inhoud + Cancel/Confirm, op het gedeelde
// menu-oppervlak. Zelfde chrome als DSMessageSheet (kaart + schaduw),
// zelfde actie-rij als RenameSheet. De caller plaatst 'm in een overlay
// boven een gedimde backdrop — geen systeem-`.alert`.

import SwiftUI

public struct DSDialog<Content: View>: View {
    private let title: String
    private let cancelLabel: String
    private let confirmLabel: String
    private let confirmEnabled: Bool
    private let onConfirm: () -> Void
    private let onDismiss: () -> Void
    private let content: Content

    public init(
        title: String,
        cancelLabel: String = "Cancel",
        confirmLabel: String,
        confirmEnabled: Bool = true,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.cancelLabel = cancelLabel
        self.confirmLabel = confirmLabel
        self.confirmEnabled = confirmEnabled
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            HStack {
                Text(title)
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DSSpacing.gap2)
                DSIconButton(Image(systemName: "xmark"), label: "Close", size: .small) {
                    onDismiss()
                }
            }
            content
            HStack(spacing: DSSpacing.gap3) {
                DSNeutralButton(cancelLabel, fullWidth: true) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                DSPrimaryButton(confirmLabel, fullWidth: true) { onConfirm() }
                    .disabled(!confirmEnabled)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DSSpacing.gap8)
        .frame(width: 360)
        .dsMenuSurface()
    }
}
