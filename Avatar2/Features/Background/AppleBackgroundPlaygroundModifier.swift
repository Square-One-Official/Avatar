// E42.7 — Native Image Playground sheet vanuit GenerateBackgroundSheet.

import SwiftUI

#if canImport(ImagePlayground)
import ImagePlayground

@available(macOS 15.1, *)
struct AppleBackgroundPlaygroundModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onCompletion: (URL) -> Void
    let onCancellation: () -> Void

    func body(content: Content) -> some View {
        content.imagePlaygroundGenerationSheet(
            isPresented: $isPresented,
            sourceImage: nil,
            onCompletion: onCompletion,
            onCancellation: onCancellation
        )
    }
}

@available(macOS 15.1, *)
extension View {
    func appleBackgroundPlaygroundSheet(
        isPresented: Binding<Bool>,
        onCompletion: @escaping (URL) -> Void,
        onCancellation: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            AppleBackgroundPlaygroundModifier(
                isPresented: isPresented,
                onCompletion: onCompletion,
                onCancellation: onCancellation
            )
        )
    }
}
#endif
