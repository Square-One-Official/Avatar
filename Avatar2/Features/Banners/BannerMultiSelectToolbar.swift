// E37.16 — Floating toolbar bij een multi-selectie: de 6 uitlijn-assen
// (links/midden-H/rechts/boven/midden-V/onder), gemodelleerd naar BoardView's
// align-pil. Lijnt uit t.o.v. de gezamenlijke selectie-bounds.

import AvatarUI
import SwiftUI

struct BannerMultiSelectToolbar: View {
    let count: Int
    var onAlign: (BannerGroupTransform.AlignAxis) -> Void

    var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            Text("\(count)")
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .monospacedDigit()
            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            alignButton("align.horizontal.left", .left, "Align left")
            alignButton("align.horizontal.center", .centerH, "Align center")
            alignButton("align.horizontal.right", .right, "Align right")
            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)
            alignButton("align.vertical.top", .top, "Align top")
            alignButton("align.vertical.center", .centerV, "Align middle")
            alignButton("align.vertical.bottom", .bottom, "Align bottom")
        }
        .padding(.horizontal, DSSpacing.gap2)
        .dsToolbarCapsule(size: .compact)
    }

    private func alignButton(_ symbol: String, _ axis: BannerGroupTransform.AlignAxis, _ label: String) -> some View {
        DSCapsuleToolButton(Image(systemName: symbol), size: .compact) {
            onAlign(axis)
        }
        .help(label)
    }
}
