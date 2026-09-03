// Image Playground bridge (@available macOS 15.1+). Weak-linked via project.yml;
// oude macOS-versies en Intel-Macs vallen terug zonder te linken.

import AppKit
import SwiftUI

#if canImport(ImagePlayground)
import ImagePlayground

@available(macOS 15.1, *)
enum ImagePlaygroundBridge {

    static var isAvailable: Bool {
        ImagePlaygroundViewController.isAvailable
    }

    static func pngData(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else {
            return try? Data(contentsOf: url)
        }
        return image.pngData()
    }
}

@available(macOS 15.1, *)
private struct ImagePlaygroundGenerationSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    var sourceImage: Image?
    let onCompletion: (URL) -> Void
    let onCancellation: () -> Void

    func body(content: Content) -> some View {
        content.imagePlaygroundSheet(
            isPresented: $isPresented,
            sourceImage: sourceImage,
            onCompletion: onCompletion,
            onCancellation: onCancellation
        )
    }
}

@available(macOS 15.1, *)
extension View {
    func imagePlaygroundGenerationSheet(
        isPresented: Binding<Bool>,
        sourceImage: Image? = nil,
        onCompletion: @escaping (URL) -> Void,
        onCancellation: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            ImagePlaygroundGenerationSheetModifier(
                isPresented: isPresented,
                sourceImage: sourceImage,
                onCompletion: onCompletion,
                onCancellation: onCancellation
            )
        )
    }
}
#endif
