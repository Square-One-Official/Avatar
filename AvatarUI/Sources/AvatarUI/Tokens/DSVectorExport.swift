// Vector-exportmodus (Figma-sync via SVG). ImageRenderer kan geen AppKit-
// gebaseerde subviews tekenen (NSTextField, NSVisualEffectView, event-
// catchers als NSViewRepresentable): die verschijnen als geel "verboden"-
// vlak in de PDF. Met `\.dsVectorExport == true` vervangen componenten die
// stukken door een puur-SwiftUI-equivalent met dezelfde geometrie, zodat de
// export vectorzuiver is. Gedrag in de app verandert niet (default false).

import SwiftUI

private struct DSVectorExportKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// true tijdens een vector-export (zie `DSVectorExportKey`).
    var dsVectorExport: Bool {
        get { self[DSVectorExportKey.self] }
        set { self[DSVectorExportKey.self] = newValue }
    }
}

public extension View {
    /// Zet de vector-exportmodus voor deze subtree.
    func dsVectorExport(_ enabled: Bool = true) -> some View {
        environment(\.dsVectorExport, enabled)
    }
}

/// Schaduw die in vector-export wegvalt: CoreGraphics rastert `.shadow` tot
/// een bitmap-softmask in de PDF, wat de SVG onzuiver maakt. In Figma wordt de
/// schaduw als effect teruggezet (zie scripts/export-vectors.sh).
private struct DSVectorSafeShadow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    @Environment(\.dsVectorExport) private var vectorExport

    func body(content: Content) -> some View {
        if vectorExport {
            content
        } else {
            content.shadow(color: color, radius: radius, x: x, y: y)
        }
    }
}

extension View {
    /// `.shadow(...)` die in vector-export een no-op is.
    func dsVectorSafeShadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(DSVectorSafeShadow(color: color, radius: radius, x: x, y: y))
    }
}
