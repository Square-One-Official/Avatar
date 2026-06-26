// E37.6 — Size/Layout-paneel van de Banner Studio. Platform-maatpresets
// (LinkedIn 1584×396, X 1500×500, generiek wijd 1600×500). Wisselen herschaalt
// het canvas non-destructief: tekst/logo-posities zijn genormaliseerd (0…1) en
// overleven dus de maatwissel; de fill her-rendert op de nieuwe maat.

import AvatarUI
import SwiftUI

struct BannerSizePanel: View {
    @Bindable var doc: BannerDoc
    var subtitle: String?

    private struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        let size: CGSize
    }

    private let presets: [Preset] = [
        Preset(label: "X / Twitter", detail: "1500 × 500", size: CGSize(width: 1500, height: 500)),
        Preset(label: "LinkedIn", detail: "1584 × 396", size: CGSize(width: 1584, height: 396)),
        Preset(label: "Wide", detail: "1600 × 500", size: CGSize(width: 1600, height: 500)),
    ]

    var body: some View {
        DSEditPanel(title: "Size", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                ForEach(presets) { preset in
                    row(preset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ preset: Preset) -> some View {
        let selected = isSelected(preset.size)
        return Button { apply(preset.size) } label: {
            HStack(spacing: DSSpacing.gap3) {
                RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                    .strokeBorder(DSColor.Foreground.subtle, lineWidth: DSBorderWidth.medium)
                    .frame(width: 44, height: 44 * (preset.size.height / preset.size.width))
                    .frame(height: 30, alignment: .center)
                VStack(alignment: .leading, spacing: 0) {
                    Text(preset.label).dsTextStyle(.labelBase).foregroundStyle(DSColor.Foreground.primary)
                    Text(preset.detail).dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
                }
                Spacer(minLength: 0)
                if selected {
                    DSSelectionCheckBadge()
                }
            }
            .padding(DSSpacing.gap2)
            .background(
                selected ? DSColor.Background.neutralStronger : .clear,
                in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ size: CGSize) -> Bool {
        abs(doc.canvasWidth - size.width) < 1 && abs(doc.canvasHeight - size.height) < 1
    }

    private func apply(_ size: CGSize) {
        doc.canvasWidth = size.width
        doc.canvasHeight = size.height
        doc.touch()
    }
}
