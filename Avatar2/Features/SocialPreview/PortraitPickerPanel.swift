// Portret-kiezer voor de social-preview — raster van bestaande avatars;
// klik op de mockup-profielfoto opent dit paneel.

import AvatarUI
import SwiftData
import SwiftUI

struct PortraitPickerPanel: View {
    let current: Portrait2?
    var onSelect: (Portrait2) -> Void

    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]

    private let columns = [
        GridItem(.adaptive(minimum: 52, maximum: 56), spacing: DSSpacing.gap2),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            Text("Avatars")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)

            if portraits.isEmpty {
                Text("No portraits yet.")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            } else {
                LazyVGrid(columns: columns, spacing: DSSpacing.gap2) {
                    ForEach(portraits) { portrait in
                        portraitTile(portrait)
                    }
                }
            }
        }
    }

    private func portraitTile(_ portrait: Portrait2) -> some View {
        let selected = current?.persistentModelID == portrait.persistentModelID
        return Button { onSelect(portrait) } label: {
            PortraitComposite(portrait: portrait, maxDimension: 112)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            selected ? DSColor.Foreground.primary : Color.clear,
                            lineWidth: 2
                        )
                }
        }
        .buttonStyle(.plain)
        .help(portrait.name.isEmpty ? "Untitled" : portrait.name)
    }
}
