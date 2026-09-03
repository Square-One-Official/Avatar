// E53.8 — Image Playground op een stabiele host.
//
// De Apple-Intelligence-sheet werd gepresenteerd vanuit de chip zelf, diep in
// het Enhance-paneel (`EditColorPanel`). Dat is precies wat regel 2 van
// `ds-persistent-presentation.mdc` verbiedt: bij een tab-/lens-wissel wordt die
// child-view opnieuw gebouwd, de `@State`-vlag valt terug op false en de sheet
// verdwijnt — mét de generatie die eronder liep. Image Playground kan tientallen
// seconden bezig zijn, dus dat is niet theoretisch.
//
// Zelfde oplossing als E42's `GenerateBackgroundPresenter`: de presentatiestate
// leeft in een presenter, de sheet hangt op ShellView, en de call site geeft
// alleen een bronbeeld + completion mee. Bewust dat patroon en niet de
// `UIPresentationStore`-route van E09.3: dit is een sheet mét een resultaat-
// callback, en die combinatie was hier al opgelost.

import AppKit
import AvatarUI
import SwiftUI

@MainActor
@Observable
final class ImagePlaygroundPresenter {
    static let shared = ImagePlaygroundPresenter()

    private(set) var isPresented = false
    /// Het beeld dat Image Playground als vertrekpunt krijgt. nil = vrij
    /// genereren zonder bron.
    private(set) var sourceImage: NSImage?
    private var onCompleted: ((Data) -> Void)?

    private init() {}

    func present(sourceImage: NSImage?, onCompleted: @escaping (Data) -> Void) {
        self.sourceImage = sourceImage
        self.onCompleted = onCompleted
        isPresented = true
    }

    /// Sluiten zonder resultaat (Cancel of ×). Ruimt de callback op zodat een
    /// volgende sessie niet per ongeluk de vorige call site terugbelt.
    func dismiss() {
        isPresented = false
        sourceImage = nil
        onCompleted = nil
    }

    /// Image Playground levert een bestands-URL; de PNG-decode gebeurt hier zodat
    /// elke call site dezelfde bytes krijgt. Onleesbaar resultaat = stil sluiten
    /// (er is dan niets toe te passen), niet de callback met lege data roepen.
    func complete(url: URL) {
        let handler = onCompleted
        let data = ImagePlaygroundEntry.pngData(from: url)
        dismiss()
        if let data { handler?(data) }
    }
}

// MARK: - Host

extension View {
    /// Hangt de Image-Playground-sheet op deze view. Hoort op een stabiele host
    /// (ShellView), niet op een paneel of chip.
    func imagePlaygroundHost() -> some View {
        modifier(ImagePlaygroundHostModifier())
    }
}

private struct ImagePlaygroundHostModifier: ViewModifier {
    @State private var presenter = ImagePlaygroundPresenter.shared
    /// Vector-export: de Image Playground-host is AppKit-backed en wordt door
    /// ImageRenderer als paginagroot placeholder-vlak getekend → overslaan.
    @Environment(\.dsVectorExport) private var vectorExport

    func body(content: Content) -> some View {
        if vectorExport {
            content
        } else {
            host(content: content)
        }
    }

    @ViewBuilder
    private func host(content: Content) -> some View {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) {
            content.imagePlaygroundGenerationSheet(
                isPresented: Binding(
                    get: { presenter.isPresented },
                    // Alleen een échte dismiss (Cancel/×) mag hier landen; de
                    // completion-route loopt via `complete(url:)`.
                    set: { if !$0 { presenter.dismiss() } }
                ),
                sourceImage: presenter.sourceImage.map { Image(nsImage: $0) },
                onCompletion: { presenter.complete(url: $0) },
                onCancellation: { presenter.dismiss() }
            )
        } else {
            content
        }
        #else
        content
        #endif
    }
}
