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
    var zoomToFit: () -> Void
    /// Optioneel: alleen een canvas met een ECHTE pixelmaat (Banner Studio) biedt
    /// "Actual Size" (100%, 1 punt per pixel). De portret-editor is een cover-canvas
    /// zonder exportpixels en laat 'm weg → het menu-item grijst daar uit.
    var actualSize: (() -> Void)? = nil
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
        // ⌘0 = "alles in beeld": het hele frame/canvas volledig zichtbaar. Dit
        // cover-canvas heeft geen pixel-echte 100% (1× laat de kaart juist buiten
        // beeld lopen), dus ⌘0 is de fit — de natuurlijke betekenis van "reset zoom".
        Button("Zoom to Fit") { zoom?.zoomToFit() }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(zoom == nil)
        // ⌘1 = "Actual Size" (100%, 1 punt per pixel). Alleen zinvol op een canvas
        // met een echte exportmaat (Banner Studio); grijst uit op de portret-editor.
        Button("Actual Size") { zoom?.actualSize?() }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(zoom?.actualSize == nil)
    }
}

/// E27.10 (audit C2): ⌘= — de shift-loze variant van ⌘+ (op een US-toetsenbord
/// is "+" shift+"=", dus wie "⌘+" typt zonder shift raakt "="). Een menu-item
/// voert maar ÉÉN key-equivalent: het View-menu toont "Zoom In ⌘+"; deze
/// onzichtbare knop registreert ⌘= ernaast, zodat beide hetzelfde doen. Elke
/// view die `canvasZoom` publiceert hangt 'm in z'n hiërarchie (editor, board,
/// Banner Studio) — samen met de focused-scene-value is dít het ene gedeelde
/// zoom-mechanisme; de losse verborgen +/=/−/0-knoppen van de board zijn weg.
struct CanvasZoomEqualsShortcut: View {
    var zoomIn: () -> Void

    var body: some View {
        Button("") { zoomIn() }
            .keyboardShortcut("=", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
