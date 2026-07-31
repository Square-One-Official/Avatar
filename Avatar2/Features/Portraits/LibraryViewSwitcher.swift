// Finder-stijl lens-switcher voor de Portraits-surface: een compacte capsule met
// vier lens-iconen (Canvas/Grid/List/Gallery), dezelfde DS-capsule als de board-
// en editor-toolbars. De Portraits-header rendert 'm, dus hij verschijnt ALLEEN
// op de Portraits-surface (section == .portraits) — Home blijft lens-vrij.

import AvatarUI
import SwiftUI

struct LibraryViewSwitcher: View {
    let mode: LibraryViewMode
    let onSelect: (LibraryViewMode) -> Void

    var body: some View {
        HStack(spacing: DSSpacing.gap1) {
            ForEach(LibraryViewMode.allCases) { m in
                DSCapsuleToolButton(
                    isActive: m == mode,
                    size: .compact,
                    action: { onSelect(m) }
                ) {
                    Image(systemName: m.symbol)
                        .font(.system(size: DSToolbarSize.compact.iconPointSize, weight: .medium))
                }
                .help(m.label)
            }
        }
        .dsToolbarCapsule(size: .compact)
    }
}
