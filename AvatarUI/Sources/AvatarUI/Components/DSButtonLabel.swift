// Gedeelde knop-inhoud (icoon + titel) voor de Fill/Neutral/Ghost-knoppen
// (DSPrimaryButton/DSNeutralButton/DSGhostButton). Kleur + achtergrond zet elke
// variant zelf eromheen; dit is één plek voor de icoon-maat/gap/lijnlimiet.

import SwiftUI

struct DSButtonLabel: View {
    let title: String
    let icon: Image?
    let size: DSPrimaryButton.Size

    var body: some View {
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
    }
}
