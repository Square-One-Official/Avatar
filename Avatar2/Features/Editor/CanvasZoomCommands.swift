// Canvas-zoom in de macOS-menubalk (vervangt de zwevende zoom-HUD, E27.2).
// De viewport-camera (E27.1) leeft als @State in `EditorView`; de menu-items
// staan op app-niveau (`Avatar2App`). De brug is een FOCUSED SCENE VALUE: de
// editor publiceert zijn zoom-acties zolang hij in beeld is, en het View-menu
// leest ze terug. Geen editor in beeld → `canvasZoom == nil` → de items
// grijzen vanzelf uit.

import SwiftUI

/// De zoom-acties die de editor aanbiedt aan het View-menu. Puur closures —
/// de camera-math (clamp, zoom-rond-midden) blijft in `CanvasCamera`/`EditorView`.
struct CanvasZoomActions {
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var zoomTo100: () -> Void
    var zoomToFit: () -> Void
}

private struct CanvasZoomKey: FocusedValueKey {
    typealias Value = CanvasZoomActions
}

extension FocusedValues {
    /// Door de actieve `EditorView` gezet via `.focusedSceneValue`; nil als er
    /// geen canvas in beeld is (board, settings, onboarding).
    var canvasZoom: CanvasZoomActions? {
        get { self[CanvasZoomKey.self] }
        set { self[CanvasZoomKey.self] = newValue }
    }
}

/// De inhoud van het View-menu. Een eigen `View` zodat `@FocusedValue` per
/// render meeverandert en de items enable/disablen met de actieve canvas.
/// De keyboard-shortcuts hangen nu hier (de oude verborgen ⌘-knoppen in de
/// editor zijn vervallen) — menu-items leveren ze native aan de menubalk.
struct CanvasZoomCommands: View {
    @FocusedValue(\.canvasZoom) private var zoom

    var body: some View {
        // Geen actieve canvas → uitgegrijsd (en de shortcuts doen niets).
        Button("Zoom In") { zoom?.zoomIn() }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(zoom == nil)
        Button("Zoom Out") { zoom?.zoomOut() }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoom == nil)
        Button("Zoom to 100%") { zoom?.zoomTo100() }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(zoom == nil)
        Button("Zoom to Fit") { zoom?.zoomToFit() }
            // ⇧⌘1 i.p.v. een shift-only ⇧1 — een shortcut zonder ⌘ zou "!" in
            // tekstvelden (hernoemen/zoeken/e-mail) onderscheppen.
            .keyboardShortcut("1", modifiers: [.command, .shift])
            .disabled(zoom == nil)
    }
}
