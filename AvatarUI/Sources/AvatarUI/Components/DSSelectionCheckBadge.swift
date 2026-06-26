// Finder-stijl selectie-vinkje: diep-groene inkt op lime cirkel (on-action op
// action-primary). Gebruik op thumbnails/tegels waar multi-select actief is.

import SwiftUI

/// Selectie-badge voor raster-tegels — `checkmark.circle.fill` met het
/// canonieke ink-on-lime tokenpaar uit het design system.
public struct DSSelectionCheckBadge: View {
    private let size: CGFloat

    public init(size: CGFloat = 20) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(DSColor.Action.onAction, DSColor.Action.primary)
    }
}
