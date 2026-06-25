// Hero-morph plumbing voor de Portraits-drill-in. De getikte portret-tegel
// (grid/list/gallery-lens) "groeit" naar de editor-canvas i.p.v. een generieke
// scale+fade. Implementatie: één gedeelde `matchedGeometryEffect`-namespace die
// via de Environment naar de lens-tegels zakt (geen parameter-threading door vier
// lens-views), plus een korte hero-overlay in de editor die na de morph naar de
// echte EditorView crossfadet. Reduce-motion → de namespace blijft nil en alles
// valt terug op de kale fade (zie ShellView).
//
// Eerste versie — bedoeld om samen met Thierry te tunen (framing/curve/back-nav).

import SwiftData
import SwiftUI

/// De gedeelde hero-namespace, geïnjecteerd door ShellView. nil = geen hero
/// (reduce-motion of buiten de drill-in) → de modifier is een no-op.
private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Markeer dit (geclipte) portret-beeld als hero-element voor portret `id`.
    /// Pas toe ná de clipShape zodat de gematchte rect de ZICHTBARE tegel is.
    /// `isSource` = de geometrische autoriteit: de tegel levert de bronrect (true),
    /// de editor-overlay leest 'm en morpht ernaartoe (false).
    func heroPortrait(_ id: PersistentIdentifier, isSource: Bool) -> some View {
        modifier(HeroPortraitModifier(id: id, isSource: isSource))
    }
}

private struct HeroPortraitModifier: ViewModifier {
    let id: PersistentIdentifier
    let isSource: Bool
    @Environment(\.heroNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}
