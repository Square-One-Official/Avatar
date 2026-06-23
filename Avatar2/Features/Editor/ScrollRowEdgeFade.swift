// Zachte trailing-rand-fade voor horizontaal-scrollbare knoppenrijen in de
// editor-panelen. Het laatste item lost zachtjes op tegen de paneelrand i.p.v.
// hard te clippen — de scroll-affordance die BackgroundPanel al gebruikte
// (E24-fix), hier gedeeld door álle panelen met een scroll-rij (Effects, Face,
// Hair, Clothes, Edit/quick-actions) zodat ze identiek ogen.
//
// Trailing-only (net als BackgroundPanel): bij rust blijft het eerste item links
// volledig zichtbaar. Het masker is per kolom vol-opaak → géén verticaal clippen,
// dus dit herintroduceert NIET de E24.18-bug (die kapte kaarten boven/onder af).
//
// Combineer met `scrollRowTrailingInset()` op de rij-INHOUD zodat een item nooit
// strak ónder de fade plakt; de fade zelf gaat op de SCROLLVIEW.

import AvatarUI
import SwiftUI

extension View {
    /// Verzacht de trailing rand van een horizontale scroll-rij met een
    /// gradient-masker. Plaats op de `ScrollView`.
    func horizontalScrollEdgeFade() -> some View {
        mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    /// Trailing-inset voor de rij-inhoud (de `HStack` ín de `ScrollView`) zodat
    /// het laatste item onder de fade valt i.p.v. hard tegen de rand. Plaats op
    /// de inhoud, niet op de `ScrollView`.
    func scrollRowTrailingInset() -> some View {
        padding(.trailing, DSSpacing.gap4)
    }
}
