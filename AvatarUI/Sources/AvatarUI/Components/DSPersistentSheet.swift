// Taak-modals die open blijven bij tab-/vensterwissel (E53.7). Alleen
// expliciete ×/Cancel sluit — geen swipe-outside of focus-verlies dismiss.

import SwiftUI

public extension View {
    /// Sheet die niet per ongeluk sluit bij focusverlies of vensterwissel.
    /// `onDismiss` wordt alleen aangeroepen wanneer SwiftUI de sheet echt
    /// sluit (expliciete actie in de inhoud); combineer met presentatiestate
    /// in een model i.p.v. view-`@State`.
    func dsPersistentSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
            .interactiveDismissDisabled(true)
    }

    /// Item-variant — zelfde persistentie-gedrag.
    func dsPersistentSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss, content: content)
            .interactiveDismissDisabled(true)
    }
}
