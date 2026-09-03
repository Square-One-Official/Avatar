// Vector-exportmodus (Figma-sync via SVG). ImageRenderer kan geen AppKit-
// gebaseerde subviews tekenen (NSTextField, NSVisualEffectView, event-
// catchers als NSViewRepresentable): die verschijnen als geel "verboden"-
// vlak in de PDF. Met `\.dsVectorExport == true` vervangen componenten die
// stukken door een puur-SwiftUI-equivalent met dezelfde geometrie, zodat de
// export vectorzuiver is. Gedrag in de app verandert niet (default false).

import SwiftUI
import UniformTypeIdentifiers

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

/// `ProgressView`-vervanger die in vector-export (ImageRenderer tekent
/// NSProgressIndicator niet) een statische ring of balk toont. Buiten de
/// export een gewone `ProgressView`; `.controlSize`/`.progressViewStyle`
/// blijven als modifier werken.
public struct DSProgressView: View {
    private let value: Double?
    @Environment(\.dsVectorExport) private var vectorExport
    @Environment(\.controlSize) private var controlSize

    public init() { value = nil }
    public init(value: Double) { self.value = value }

    public var body: some View {
        if vectorExport {
            if let value {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DSColor.Background.neutral)
                        Capsule().fill(DSColor.Action.primary).frame(width: geo.size.width * value)
                    }
                }
                .frame(height: 4)
            } else {
                let side: CGFloat = controlSize == .large ? 32 : controlSize == .mini ? 12 : 16
                Circle()
                    .trim(from: 0.1, to: 0.85)
                    .stroke(DSColor.Foreground.primary, style: StrokeStyle(lineWidth: side / 8, lineCap: .round))
                    .frame(width: side, height: side)
            }
        } else if let value {
            ProgressView(value: value)
        } else {
            ProgressView()
        }
    }
}

/// `.blur(radius:)` die in vector-export wegvalt: een blur-filter kan niet
/// naar PDF en laat ImageRenderer de hele laag als placeholder tekenen.
private struct DSVectorSafeBlur: ViewModifier {
    let radius: CGFloat
    @Environment(\.dsVectorExport) private var vectorExport
    func body(content: Content) -> some View {
        if vectorExport { content } else { content.blur(radius: radius) }
    }
}

public extension View {
    func dsVectorSafeBlur(radius: CGFloat) -> some View {
        modifier(DSVectorSafeBlur(radius: radius))
    }
}

/// `.onDrop(of:isTargeted:perform:)` die in vector-export wegvalt: de drop-
/// destination is AppKit-backed en laat ImageRenderer de hele host als
/// placeholder-vlak tekenen (zichtbaar zodra de achtergrond transparant is).
private struct DSVectorSafeDrop: ViewModifier {
    let types: [UTType]
    let isTargeted: Binding<Bool>?
    let perform: ([NSItemProvider]) -> Bool
    @Environment(\.dsVectorExport) private var vectorExport

    func body(content: Content) -> some View {
        if vectorExport {
            content
        } else {
            content.onDrop(of: types, isTargeted: isTargeted, perform: perform)
        }
    }
}

public extension View {
    func dsVectorSafeOnDrop(
        of types: [UTType],
        isTargeted: Binding<Bool>?,
        perform: @escaping ([NSItemProvider]) -> Bool
    ) -> some View {
        modifier(DSVectorSafeDrop(types: types, isTargeted: isTargeted, perform: perform))
    }
}

/// `ScrollView`-vervanger: ImageRenderer rendert een ScrollView als niets
/// (geen viewport). In vector-export toont hij de inhoud plat (afgekapt door
/// het omliggende frame); daarbuiten een gewone `ScrollView`.
public struct DSScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let content: Content
    @Environment(\.dsVectorExport) private var vectorExport

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: some View {
        if vectorExport {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView(axes, showsIndicators: showsIndicators) { content }
        }
    }
}

/// `Link`-vervanger: `Link` is AppKit-backed en tekent als placeholder in
/// vector-export → dan onderstreepte tekst; daarbuiten een gewone `Link`.
public struct DSLink: View {
    private let title: String
    private let destination: URL
    @Environment(\.dsVectorExport) private var vectorExport

    public init(_ title: String, destination: URL) {
        self.title = title
        self.destination = destination
    }

    public var body: some View {
        if vectorExport {
            Text(title).underline()
        } else {
            Link(title, destination: destination)
        }
    }
}
