import AvatarKit
import AvatarUI
import SwiftUI

/// Vaste Enhance-kaart: titel boven, preview onder. Breed paneel i.p.v. hoog,
/// zodat de foto minder bedekt wordt.
enum EnhanceTileMetrics {
    /// E53.10: 176 i.p.v. 144 — de plaat toont zo ~73 % van de vierkante
    /// head-crop (was ~52 %): meer gezicht, kin in beeld.
    static let height: CGFloat = 176
    static let columns = 3
    /// Vierkante tegel (= `height`): bij 160 brak "Remove background ⌄" op
    /// twee regels (feedback Thierry 2026-09-02); titel + chevron meet 137pt,
    /// dus 176 − 2 × inset − gap houdt 144pt over.
    static let tileWidth: CGFloat = 176
    /// 3 × 176 + 2 × gap-3 + 2 × DSEditPanel-padding (gap-5 + gap-2).
    static let panelWidth: CGFloat = 608
    /// 3 rijen × 176 + 2 × gap-3.
    static let panelContentHeight: CGFloat = 552
    static let gridSpacing: CGFloat = DSSpacing.gap3
    static let hoverLift: CGFloat = 8
    static let pressScale: CGFloat = 0.97
    /// Eén regel labelSmall (16) + top-inset (12); de chevron loopt inline mee.
    static let headerHeight: CGFloat = 28
    static let contentInset: CGFloat = DSSpacing.gap3
    static let headerImageGap: CGFloat = DSSpacing.gap3
    /// Eén pass van de hover-animatie (wipes/crossfades; sequenties hebben een eigen duur).
    static let motionDuration: Double = 0.9
    /// Portrait: "scherpstelling trekt de diepte" — lichte push-in.
    static let depthPullScale: CGFloat = 0.04

    static func imageShift(hovering: Bool, reduceMotion: Bool) -> CGFloat {
        hovering && !reduceMotion ? -hoverLift : 0
    }
}

/// NSImage-lagen van één tegel (uit `EnhanceTilePreview.Layers`).
struct EnhanceTileLayers {
    let base: NSImage
    let reveal: NSImage?
    /// Head-crop mét alpha — masker voor subject-gebonden overlays.
    let subject: NSImage
    /// Gezichts-rect genormaliseerd (0…1, linksboven) in `base`-ruimte.
    let focus: CGRect?
    /// Tussenstappen (Boost: steeds fijnere pixels) tussen `base` en `reveal`.
    let steps: [NSImage]

    init(base: NSImage, reveal: NSImage? = nil, subject: NSImage, focus: CGRect? = nil, steps: [NSImage] = []) {
        self.base = base
        self.reveal = reveal
        self.subject = subject
        self.focus = focus
        self.steps = steps
    }

    init(_ layers: EnhanceTilePreview.Layers) {
        func image(_ cg: CGImage) -> NSImage {
            NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        self.init(
            base: image(layers.base),
            reveal: layers.reveal.map(image),
            subject: image(layers.subject),
            focus: layers.focus,
            steps: layers.steps.map(image)
        )
    }
}

/// Hoe een tegel tussen `base` en `reveal` beweegt op hover (E53.10). Eén
/// pass per hover-in; rust = statisch effect; Reduce Motion = altijd rust.
enum EnhanceTileMotion: Equatable {
    enum Edge: Equatable { case leading, trailing }

    case none
    /// `reveal` groeit vanaf `from`-rand tot de hele plaat.
    case wipeHorizontal(rest: Double, from: Edge)
    /// `reveal` vult van boven naar beneden (Fill in body).
    case wipeVertical(rest: Double)
    /// Spot op het gezicht: gaat aan, wordt groter en feller, dimt weer uit
    /// (Studio Light); geen `reveal`.
    case spotlight
    /// Crossfade base→reveal + lichte push-in (Portrait).
    case depthPull
    /// Rust toont `reveal` (checker); hover toont eerst de originele
    /// achtergrond, knippert, en laat 'm dan verdwijnen (Remove background).
    case dissolve
    /// Stapt door `steps` naar `reveal`: het beeld wordt in stappen scherper
    /// (Boost). Geen wipe — de pixels lossen ter plekke op.
    case resolve

    /// Ruststand (zonder hover).
    var rest: Double {
        switch self {
        case .none: 0
        case .wipeHorizontal(let rest, _): rest
        case .wipeVertical(let rest): rest
        case .spotlight: 0
        case .depthPull: 0
        case .dissolve: 1
        case .resolve: 0
        }
    }

    /// Waar hover-in (zonder animatie) begint.
    var start: Double {
        switch self {
        case .dissolve: 0
        default: rest
        }
    }

    /// Hover-out geanimeerd terug naar rust? Spot/dissolve/resolve springen —
    /// terugspelen van een sequentie leest als fout.
    var animatesExit: Bool {
        switch self {
        case .spotlight, .dissolve, .resolve: false
        default: true
        }
    }

    /// Duur van één hover-pass.
    var duration: Double {
        switch self {
        case .dissolve: 1.9
        case .spotlight: 1.7
        default: EnhanceTileMetrics.motionDuration
        }
    }

    /// Doelstand: hover → 1, anders rust; Reduce Motion → altijd rust.
    static func target(_ motion: EnhanceTileMotion, hovering: Bool, reduceMotion: Bool) -> Double {
        if reduceMotion || motion == .none { return motion.rest }
        return hovering ? 1 : motion.rest
    }
}

struct EnhanceActionTile: View {
    let title: String
    var credit: String? = nil
    var pro: Bool = false
    var showsMenu: Bool = false
    var isOn: Bool = false
    var isMenuOpen: Bool = false
    var privacy: DSPrivacyExecutionTier? = nil
    var layers: EnhanceTileLayers? = nil
    var motion: EnhanceTileMotion = .none
    var fallback: NSImage
    var help: String? = nil
    var accessibilitySubtitle: String? = nil
    /// Alleen voor tests/snapshots: vaste animatiestand (0…1), negeert hover.
    var debugProgress: Double? = nil
    let action: () -> Void

    @State private var hovering = false
    @State private var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        credit: String? = nil,
        pro: Bool = false,
        showsMenu: Bool = false,
        isOn: Bool = false,
        isMenuOpen: Bool = false,
        privacy: DSPrivacyExecutionTier? = nil,
        layers: EnhanceTileLayers? = nil,
        motion: EnhanceTileMotion = .none,
        fallback: NSImage,
        help: String? = nil,
        accessibilitySubtitle: String? = nil,
        debugProgress: Double? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.credit = credit
        self.pro = pro
        self.showsMenu = showsMenu
        self.isOn = isOn
        self.isMenuOpen = isMenuOpen
        self.privacy = privacy
        self.layers = layers
        self.motion = motion
        self.fallback = fallback
        self.help = help
        self.accessibilitySubtitle = accessibilitySubtitle
        self.debugProgress = debugProgress
        self.action = action
        _progress = State(initialValue: motion.rest)
    }

    private var plate: NSImage { layers?.base ?? fallback }
    private var effectiveProgress: Double { debugProgress ?? progress }

    var body: some View {
        Button(action: action) {
            card
        }
        .buttonStyle(EnhanceTileChrome(hovering: $hovering))
        .dsFocusEffectDisabled()
        .help(help ?? title)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : (accessibilitySubtitle ?? ""))
        .accessibilityAddTraits((isOn || isMenuOpen) ? [.isButton, .isSelected] : .isButton)
        .onChange(of: hovering) { _, isHovering in
            hoverChanged(isHovering)
        }
        .onChange(of: motion) { _, newMotion in
            progress = newMotion.rest
        }
    }

    /// Hover-in: spring (zonder animatie) naar `start`, animeer dan naar 1.
    /// De sprong en de animatie zitten in aparte runloop-ticks, anders vouwt
    /// SwiftUI ze tot één diff en start de animatie vanaf de vorige stand.
    private func hoverChanged(_ isHovering: Bool) {
        guard motion != .none, !reduceMotion else { return }
        var still = Transaction()
        still.disablesAnimations = true
        if isHovering {
            withTransaction(still) { progress = motion.start }
            let m = motion
            Task { @MainActor in
                await Task.yield()
                guard hovering, motion == m else { return }
                // Sequenties (spot/dissolve/resolve) lineair: de curve zit in
                // de view zelf; wipes/crossfades ease-out.
                let animation = m.animatesExit
                    ? DSMotion.easeOut(m.duration)
                    : Animation.linear(duration: m.duration)
                DSMotion.animate(animation) {
                    progress = 1
                }
            }
        } else if motion.animatesExit {
            DSMotion.animate(DSMotion.base) { progress = motion.rest }
        } else {
            withTransaction(still) { progress = motion.rest }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: EnhanceTileMetrics.headerImageGap) {
            header
            plateView
        }
        .background {
            // E53.10: één trede lichter dan `inset` (= de plaat) zodat de kaart
            // op de paneelkaart leest; hairline maakt de rand ook zonder hover zichtbaar.
            shape.fill(hovering ? DSColor.Background.neutralStrongest : DSColor.Background.neutralStronger)
        }
        .frame(maxWidth: .infinity, minHeight: EnhanceTileMetrics.height, maxHeight: EnhanceTileMetrics.height)
        .clipShape(shape)
        .overlay {
            if isOn || isMenuOpen {
                shape.strokeBorder(DSColor.Action.primary, lineWidth: DSBorderWidth.medium)
            } else {
                shape.strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            }
        }
        .contentShape(shape)
        .dsMotion(DSMotion.fast, value: hovering)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap2) {
            titleText
                .dsTextStyle(.labelSmall)
                .lineLimit(1)
                .layoutPriority(1)
                .foregroundStyle(DSColor.Foreground.primary)
            Spacer(minLength: 0)
            // Alleen renderen als er iets in zit: een lege HStack kost anders
            // nog steeds de stack-spacing, en die 8pt maakt het verschil voor
            // "Remove background ⌄" op één regel.
            if privacy != nil || pro || credit != nil {
                HStack(spacing: DSSpacing.gap1) {
                    if let privacy {
                        DSPrivacyBadge(tier: privacy)
                    }
                    if pro {
                        DSProChip()
                    }
                    if let credit {
                        DSCreditBadge(credit)
                    }
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, EnhanceTileMetrics.contentInset)
        .padding(.top, EnhanceTileMetrics.contentInset)
        .frame(height: EnhanceTileMetrics.headerHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var titleText: Text {
        guard showsMenu else { return Text(title) }
        // Non-breaking space: chevron blijft aan het laatste woord geplakt.
        // `sm` i.p.v. `xxs`: de 9pt-chevron viel weg naast labelSmall
        // (feedback Thierry 2026-09-02).
        return Text(title) + Text("\u{00A0}")
            + Text(Image(systemName: "chevron.down"))
                .font(.system(size: DSIconSize.sm, weight: .semibold))
                .foregroundColor(DSColor.Foreground.muted)
    }

    /// Plaat vult de tegel; portret scaledToFill zodat het effect groot leesbaar is.
    private var plateView: some View {
        GeometryReader { geo in
            let inset = EnhanceTileMetrics.contentInset
            let width = max(0, geo.size.width - inset)
            let height = geo.size.height
            let lift = EnhanceTileMetrics.hoverLift
            let frameHeight = height + lift
            let shift = EnhanceTileMetrics.imageShift(
                hovering: hovering, reduceMotion: reduceMotion
            )
            let scale: CGFloat = motion == .depthPull
                ? 1 + EnhanceTileMetrics.depthPullScale * CGFloat(effectiveProgress)
                : 1
            ZStack(alignment: .top) {
                DSColor.Background.inset
                Group {
                    plateImage(plate, width: width, frameHeight: frameHeight, shift: shift)
                    if let layers {
                        motionLayers(layers, width: width, frameHeight: frameHeight, shift: shift)
                    }
                }
                .scaleEffect(scale, anchor: .top)
            }
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: DSRadius.lg,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// Eén plaat-laag; álle lagen (base, reveal, maskers) delen deze layout
    /// zodat maskers pixel-exact op de foto vallen.
    private func plateImage(_ image: NSImage, width: CGFloat, frameHeight: CGFloat, shift: CGFloat) -> some View {
        EnhancePlateImage.make(image, width: width, frameHeight: frameHeight, shift: shift)
    }

    @ViewBuilder
    private func motionLayers(_ layers: EnhanceTileLayers, width: CGFloat, frameHeight: CGFloat, shift: CGFloat) -> some View {
        let p = CGFloat(effectiveProgress)
        switch motion {
        case .none:
            EmptyView()
        case .wipeHorizontal(_, let from):
            if let reveal = layers.reveal {
                plateImage(reveal, width: width, frameHeight: frameHeight, shift: shift)
                    .mask(alignment: from == .leading ? .leading : .trailing) {
                        Rectangle().frame(width: width * p)
                    }
            }
        case .wipeVertical:
            if let reveal = layers.reveal {
                // Vierkante plaat: hoogte in beeld-ruimte (zijde), niet plaat-hoogte,
                // zodat de rust-stand exact op de solide bovenkant van `base` valt.
                plateImage(reveal, width: width, frameHeight: frameHeight, shift: shift)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: max(width, frameHeight) * p)
                    }
            }
        case .spotlight:
            if !reduceMotion {
                // Gemaskerd met het subject: geen rechte plaatrand in het licht,
                // de spot valt alleen op gezicht en haar.
                EnhanceSpotlight(
                    progress: effectiveProgress, focus: layers.focus,
                    width: width, frameHeight: frameHeight, shift: shift
                )
                .mask {
                    plateImage(layers.subject, width: width, frameHeight: frameHeight, shift: shift)
                }
            }
        case .depthPull:
            if let reveal = layers.reveal {
                plateImage(reveal, width: width, frameHeight: frameHeight, shift: shift)
                    .opacity(effectiveProgress)
            }
        case .dissolve:
            if let reveal = layers.reveal {
                EnhanceCurvedOpacity(
                    progress: effectiveProgress, curve: EnhanceMotionCurves.dissolve
                ) {
                    plateImage(reveal, width: width, frameHeight: frameHeight, shift: shift)
                }
            }
        case .resolve:
            EnhanceResolveFrames(
                progress: effectiveProgress,
                frames: layers.steps + (layers.reveal.map { [$0] } ?? []),
                width: width, frameHeight: frameHeight, shift: shift
            )
        }
    }

    private var accessibilityLabel: String {
        var parts = [title]
        if let accessibilitySubtitle, !accessibilitySubtitle.isEmpty {
            parts.append(accessibilitySubtitle)
        }
        if let credit {
            if let n = Int(credit) {
                parts.append(n == 1 ? "1 credit" : "\(n) credits")
            } else {
                parts.append(credit)
            }
        }
        if pro { parts.append("Pro") }
        if showsMenu { parts.append("Menu") }
        return parts.joined(separator: ", ")
    }
}

enum EnhancePlateImage {
    static func make(_ image: NSImage, width: CGFloat, frameHeight: CGFloat, shift: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: frameHeight, alignment: .top)
            .offset(y: shift)
    }
}

/// Stapt op een geanimeerde `progress` door discrete frames (Boost: steeds
/// fijnere pixels). `Animatable` zodat SwiftUI de tussenwaarden levert —
/// een @State-progress springt zelf direct naar het eind.
struct EnhanceResolveFrames: View, Animatable {
    var progress: Double
    let frames: [NSImage]
    let width: CGFloat
    let frameHeight: CGFloat
    let shift: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Frame-index voor een stand: 0…count-1 ná de eerste stap; nil = nog `base`.
    static func frameIndex(progress: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let slot = Int((progress * Double(count)).rounded(.down))
        guard slot >= 1 else { return nil }
        return min(count - 1, slot - 1 + (progress >= 1 ? 1 : 0))
    }

    var body: some View {
        if let index = Self.frameIndex(progress: progress, count: frames.count) {
            EnhancePlateImage.make(frames[index], width: width, frameHeight: frameHeight, shift: shift)
        }
    }
}

/// Curves voor sequentie-animaties (input 0…1 → output 0…1). Puur, testbaar.
enum EnhanceMotionCurves {
    /// Lineaire interpolatie door keyframes `(p, value)`.
    static func keyframes(_ frames: [(Double, Double)], at p: Double) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        if p <= first.0 { return first.1 }
        if p >= last.0 { return last.1 }
        for i in 1..<frames.count where p <= frames[i].0 {
            let (p0, v0) = frames[i - 1], (p1, v1) = frames[i]
            let t = p1 == p0 ? 1 : (p - p0) / (p1 - p0)
            return v0 + (v1 - v0) * t
        }
        return last.1
    }

    /// Remove background — opacity van de checker-laag. Alles fades (geen
    /// sprongen): origineel fade-in, hold, fade-out, zachte blink, weg.
    static func dissolve(_ p: Double) -> Double {
        keyframes([(0, 1), (0.16, 0), (0.42, 0), (0.58, 1), (0.68, 0.55), (0.82, 1), (1, 1)], at: p)
    }

    /// Studio Light — spot-alpha (screen-blend): aan, feller, even
    /// "bijstellen", uit. Piek 0.5 — hoger overbelicht de huid.
    static func spotlightAlpha(_ p: Double) -> Double {
        keyframes([(0, 0), (0.12, 0.26), (0.5, 0.45), (0.6, 0.32), (0.72, 0.45), (1, 0)], at: p)
    }

    /// Studio Light — spot-straal (factor): begint klein, groeit.
    static func spotlightRadius(_ p: Double) -> Double {
        keyframes([(0, 0.45), (0.55, 1), (1, 1.05)], at: p)
    }
}

/// Opacity uit een curve op een geanimeerde `progress` (Animatable, anders
/// springt een @State-progress direct naar het eind).
struct EnhanceCurvedOpacity<Content: View>: View, Animatable {
    var progress: Double
    let curve: (Double) -> Double
    @ViewBuilder let content: () -> Content

    init(progress: Double, curve: @escaping (Double) -> Double, @ViewBuilder content: @escaping () -> Content) {
        self.progress = progress
        self.curve = curve
        self.content = content
    }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content().opacity(curve(progress))
    }
}

/// Spot op het gezicht (Studio Light): warme radial op het `focus`-centrum
/// (anders plaat-midden), straal en alpha uit de curves.
struct EnhanceSpotlight: View, Animatable {
    var progress: Double
    let focus: CGRect?
    let width: CGFloat
    let frameHeight: CGFloat
    let shift: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // Plaat = vierkante afbeelding scaledToFill (zijde = grootste maat),
        // top-aligned en horizontaal gecentreerd.
        let side = max(width, frameHeight)
        let originX = (width - side) / 2
        let center = focus.map {
            CGPoint(x: originX + $0.midX * side, y: ($0.minY + 0.55 * $0.height) * side + shift)
        } ?? CGPoint(x: width / 2, y: frameHeight * 0.45 + shift)
        // Straal ≈ 0.8× gezichtsbreedte: de spot blijft op het gezicht en
        // haalt het haar niet grijs.
        let baseRadius = (focus?.width ?? 0.4) * side * 0.8
        let radius = baseRadius * CGFloat(EnhanceMotionCurves.spotlightRadius(progress))
        let alpha = EnhanceMotionCurves.spotlightAlpha(progress)
        let warm = Color(red: 1, green: 0.94, blue: 0.82)
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: warm.opacity(alpha), location: 0),
                    .init(color: warm.opacity(alpha * 0.5), location: 0.35),
                    .init(color: warm.opacity(alpha * 0.1), location: 0.7),
                    .init(color: .clear, location: 1)
                ],
                center: .center, startRadius: 0, endRadius: radius
            ))
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            .frame(width: width, height: frameHeight)
            .clipped()
            .blendMode(.screen)
    }
}

/// Hover + press in de ButtonStyle — `.onHover` op de Button zelf vuurt op
/// macOS niet betrouwbaar met een custom style.
private struct EnhanceTileChrome: ButtonStyle {
    @Binding var hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? EnhanceTileMetrics.pressScale : 1)
            .onHover { hovering = $0 }
            .dsMotion(DSMotion.easeOut(0.16), value: configuration.isPressed)
    }
}
