// PoC (left-nav): Portraits-grid — toont de beelden van de in de sidebar
// geselecteerde map (of álle beelden) in een NET rooster van max 3 naast
// elkaar. De mappen zelf wonen nu in de left-nav (inklapbare Portraits-sectie),
// niet meer als kaarten hier. Dubbelklik opent een portret in de editor;
// rechtermuis verplaatst het naar een map of verwijdert het. Net-nieuw scherm —
// DS-tokens, in de geest van het hoofddesign.

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct PortraitsGalleryView: View {
    let model: ShellModel
    let entitlement: EntitlementModel

    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]

    /// Gemeten hoogte van de zwevende header → top-inset voor elke lens.
    @State private var headerHeight: CGFloat = 0
    @State private var menuTarget: Portrait2?
    @State private var menuAnchor: CGRect = .zero

    // "max 3 naast elkaar" — een vast 3-koloms rooster.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.gap4), count: 3)

    private var selectedFolder: Folder2? {
        guard let id = model.selectedFolderID else { return nil }
        return folders.first { $0.persistentModelID == id }
    }

    private var items: [Portrait2] {
        guard let id = model.selectedFolderID else { return portraits }
        return portraits.filter { $0.folder?.persistentModelID == id }
    }

    var body: some View {
        // Header (titel + switcher) ZWEEFT bovenaan; elke lens krijgt een top-inset
        // ter grootte van de (gemeten) header zodat z'n inhoud er nooit achter valt.
        //
        // Waarom niet een VStack-broer of `.safeAreaInset`: de full-bleed board-lens
        // (BoardView) is verticaal gulzig — als VStack-broer drukt 'ie de header van
        // het scherm (titel + switcher verdwenen, alleen de subtitle lekt op y≈0) en
        // als safeAreaInset-content klapt de inset in. De scroll-lenzen gedragen zich
        // wél netjes, maar één uniforme, board-proof layout is robuuster: de header
        // als bovenliggende laag (vult nooit mee, verdwijnt dus nooit) + een top-inset
        // per lens. De board fit z'n nodes onder de inset; de scroll-lenzen scrollen
        // eronder.
        // De buitenste GeometryReader is hier een MIN-WIDTH-firewall, geen
        // gulzigaard: hij voedt z'n kinderen ALTIJD een concrete maat (geo.size),
        // dus de board-lens krijgt een exacte `.frame(width:height:)` i.p.v. via
        // `.frame(maxWidth:.infinity)` terug te vallen op z'n grote ideale boardSize
        // wanneer de ouder een nil-breedte voorstelt. Dát terugvallen lekte de
        // board-breedte omhoog en perste de vaste 236pt-nav in elkaar (de echte
        // oorzaak; het weghalen van BoardView's eigen GeometryReader in d00387e
        // raakte 'm niet). Met een exacte maat kan geen enkele lens de nav of de
        // header nog verdringen.
        GeometryReader { geo in
            ZStack(alignment: .top) {
                lensContent
                    .frame(width: geo.size.width,
                           height: max(0, geo.size.height - headerHeight),
                           alignment: .top)
                    .clipped()
                    .padding(.top, headerHeight)
                header
                    .background(
                        GeometryReader { hGeo in
                            Color.clear.preference(key: HeaderHeightKey.self, value: hGeo.size.height)
                        }
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
        // E50.1: ⌘A selecteert de hele zichtbare scope (huidige map of alles) in
        // de grid/list/gallery-lens — zelfde patroon als de board-lens, die z'n
        // eigen ⌘A op de canvas-selectie registreert (BoardView; daarom hier
        // uitgesloten, anders twee registraties op dezelfde shortcut).
        .background {
            if model.portraitsViewMode != .canvas && !items.isEmpty {
                Button("") { model.selectAllPortraits(items.map(\.persistentModelID)) }
                    .keyboardShortcut("a", modifiers: .command)
                    .opacity(0)
            }
        }
        .coordinateSpace(name: PortraitContextMenuSpace.name)
        .portraitContextMenuOverlay(
            target: $menuTarget,
            anchor: menuAnchor,
            model: model,
            folders: folders,
            selectedTargets: { items.filter { model.isPortraitSelected($0) } }
        )
        .dsMotion(DSMotion.fast, value: model.portraitsViewMode)
    }

    @ViewBuilder private var lensContent: some View {
        if items.isEmpty {
            emptyState
        } else {
            switch model.portraitsViewMode {
            case .grid: gridBody
            case .list:
                ListLens(items: items, model: model, folders: folders)
            case .gallery:
                GalleryLens(items: items, model: model, folders: folders)
            // Canvas = de vrije board-lens, gescope op de huidige map.
            case .canvas: BoardView(folderID: model.selectedFolderID, model: model,
                                    entitlement: entitlement, onOpen: { model.openPortrait($0) })
            }
        }
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DSSpacing.gap4) {
                ForEach(items) { portrait in
                    PortraitGridTile(
                        portrait: portrait, folders: folders, model: model,
                        isSelected: model.isPortraitSelected(portrait),
                        ordered: { items.map(\.persistentModelID) },
                        selectedTargets: { items.filter { model.isPortraitSelected($0) } },
                        onContextMenu: { frame in
                            model.preparePortraitContextMenu(on: portrait)
                            menuTarget = portrait
                            menuAnchor = frame
                        }
                    )
                }
            }
            .padding(.horizontal, DSSpacing.gap6)
            .padding(.bottom, DSSpacing.gap6)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DSSpacing.gap4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedFolder?.name ?? "All portraits")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("\(items.count) \(items.count == 1 ? "portrait" : "portraits")")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            Spacer(minLength: 0)
            // Finder-stijl lens-switcher — de header rendert 'm, dus alleen op
            // de Portraits-surface zichtbaar.
            LibraryViewSwitcher(mode: model.portraitsViewMode) { model.setPortraitsViewMode($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.top, DSSpacing.gap8)
        .padding(.bottom, DSSpacing.gap4)
        // Eigen dekvlak: als top-inset zweeft de header over de lens-inhoud
        // (de canvas, of een gescrollde grid), dus hij heeft een achtergrond nodig.
        .background(DSColor.Background.app)
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.gap2) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DSColor.Foreground.muted)
            Text(model.selectedFolderID == nil ? "No portraits yet" : "This folder is empty")
                .dsTextStyle(.labelLarge).foregroundStyle(DSColor.Foreground.subtle)
            Text("Right-click a portrait to move it into a folder.")
                .dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Meet de zwevende-header-hoogte zodat elke lens er precies onder begint.
private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Gedeelde portret-tegel (Home + Portraits-grid). Vierkant, met naam/rol eronder.
/// Dubbelklik opent de editor; rechtermuis verplaatst naar een map of verwijdert.
struct PortraitGridTile: View {
    let portrait: Portrait2
    let folders: [Folder2]
    let model: ShellModel
    let isSelected: Bool
    /// Zichtbare volgorde (voor ⇧-bereikselectie) — lazy, alleen bij een klik.
    let ordered: () -> [PersistentIdentifier]
    /// De huidige selectie als modellen (voor bulk-acties) — lazy, bij menu-actie.
    let selectedTargets: () -> [Portrait2]
    let onContextMenu: (CGRect) -> Void

    @State private var hovering = false

    var body: some View {
        // Vierkante tegel via het canonieke Color.clear + aspectRatio(.fit) +
        // overlay-patroon — robuust in een LazyVGrid (nooit groter dan de kolom,
        // dus geen overloop/overlap). De tegel toont de ECHTE compositie zoals de
        // editor: de gekozen achtergrond (kleur/afbeelding/origineel) met het
        // vrijstaande onderwerp erover — niet langer de kale cutout.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { composed }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                    .strokeBorder(
                        (isSelected || hovering) ? DSColor.Action.primary : DSColor.Foreground.divider,
                        lineWidth: (isSelected || hovering) ? DSBorderWidth.medium : DSBorderWidth.thin
                    )
            )
            // Selectie-vinkje (Finder-stijl) rechtsboven.
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    DSSelectionCheckBadge(size: 20)
                        .padding(DSSpacing.gap2)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .dsMotion(DSMotion.micro, value: hovering)
            .dsMotion(DSMotion.micro, value: isSelected)
            // Plain klik = openen; ⌘/⇧ = multi-select (gedeeld via ShellModel).
            .onTapGesture {
                model.handlePortraitClick(portrait, ordered: ordered(), mods: NSApp.currentEvent?.modifierFlags ?? [])
            }
            .help("Click to open · ⌘-click to select")
            // Sleep een portret naar een map in de left-nav (zie LeftNavView).
            // Een klik zonder beweging blijft 'open'; pas bij verslepen start de drag.
            .draggable(PortraitDragItem(id: portrait.persistentModelID))
            .contextMenuTrigger(in: PortraitContextMenuSpace.coordinateSpace, onTrigger: onContextMenu)
            // UXS-7 (UX28): de tegel als één AX-element met open/selecteer/menu.
            .portraitCardAccessibility(
                portrait: portrait, model: model, isSelected: isSelected,
                ordered: ordered, onContextMenu: onContextMenu
            )
    }

    // De compositie binnen het vierkant: de gedeelde achtergrond+onderwerp-
    // render + de naam/rol-overlay onderin.
    @ViewBuilder
    private var composed: some View {
        ZStack(alignment: .bottomLeading) {
            PortraitCompositeMeasured(portrait: portrait)

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                    .dsTextStyle(.labelBase).foregroundStyle(.white).lineLimit(1)
                if !portrait.role.isEmpty {
                    Text(portrait.role).dsTextStyle(.labelSmall).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            .padding(DSSpacing.gap3)
        }
    }
}

// MARK: - Kaart-accessibility (UXS-7 / UX28)

/// Maakt een portret-kaart (grid-tegel, Home-hero) één VoiceOver-element:
/// naam+rol als label, button-trait (+selected), en drie acties — activeren
/// = openen (zelfde pad als de plain klik), "Select"/"Deselect" (zelfde pad
/// als ⌘-klik) en "Show Context Menu" (zelfde pad als rechtsklik, verankerd
/// op de gemeten kaart-frame in de context-menu-coordinate-space). Zonder dit
/// bestonden de kaarten niet voor de AX-boom (audit UX28, live geverifieerd).
struct PortraitCardAccessibility: ViewModifier {
    let portrait: Portrait2
    let model: ShellModel
    let isSelected: Bool
    let ordered: () -> [PersistentIdentifier]
    let onContextMenu: (CGRect) -> Void

    /// Kaart-frame in `PortraitContextMenuSpace` — anker voor de AX-menu-actie.
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.onChange(
                        of: geo.frame(in: PortraitContextMenuSpace.coordinateSpace),
                        initial: true
                    ) { _, new in frame = new }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Opens the portrait in the editor")
            .accessibilityAction { model.openPortrait(portrait) }
            .accessibilityAction(named: isSelected ? "Deselect" : "Select") {
                model.handlePortraitClick(portrait, ordered: ordered(), mods: .command)
            }
            .accessibilityAction(named: "Show Context Menu") {
                // Punt-anker (zoals rechtsklik) op de kaart-oorsprong.
                onContextMenu(CGRect(origin: frame.origin, size: .zero))
            }
    }

    private var axLabel: String {
        let name = portrait.name.isEmpty ? "Untitled portrait" : portrait.name
        return portrait.role.isEmpty ? name : "\(name), \(portrait.role)"
    }
}

extension View {
    func portraitCardAccessibility(
        portrait: Portrait2,
        model: ShellModel,
        isSelected: Bool,
        ordered: @escaping () -> [PersistentIdentifier],
        onContextMenu: @escaping (CGRect) -> Void
    ) -> some View {
        modifier(PortraitCardAccessibility(
            portrait: portrait, model: model, isSelected: isSelected,
            ordered: ordered, onContextMenu: onContextMenu
        ))
    }
}

/// Rendert `PortraitComposite` op retina-resolutie passend bij de container —
/// zelfde visuele maat, scherp op 2×/3× schermen.
struct PortraitCompositeMeasured: View {
    let portrait: Portrait2

    @Environment(\.displayScale) private var displayScale
    @State private var sidePoints: CGFloat = 0

    private var pixelSide: CGFloat {
        ceil(sidePoints * displayScale)
    }

    var body: some View {
        Group {
            if sidePoints > 0 {
                PortraitComposite(portrait: portrait, maxDimension: pixelSide)
            } else {
                DSColor.Background.inset
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PortraitCompositeMeasuredSideKey.self,
                    value: max(geo.size.width, geo.size.height)
                )
            }
        }
        .onPreferenceChange(PortraitCompositeMeasuredSideKey.self) { sidePoints = $0 }
    }
}

private struct PortraitCompositeMeasuredSideKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Gedeelde portret-compositie. Rendert via dezelfde `PortraitExporter`-pijplijn
/// als de export/editor (achtergrond + de OPGESLAGEN transform/zoom + Adjust),
/// als een vierkant — zo matchen de framing/cropping en de achtergrond in elke
/// thumbnail exact wat de editor toont (i.p.v. een kale, anders-gekadreerde
/// cutout). Resultaat wordt gecachet op (portret, updatedAt, maat).
struct PortraitComposite: View {
    let portrait: Portrait2
    let maxDimension: CGFloat

    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            DSColor.Background.inset
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: cacheKey) { await load() }
    }

    private var cacheKey: String {
        "\(portrait.persistentModelID.hashValue)-\(portrait.updatedAt.timeIntervalSince1970)-\(Int(maxDimension))"
    }

    private func load() async {
        let key = cacheKey as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        // De waarden van het SwiftData-model op de main-thread lichten, dan de
        // (zware) compositie OFF-MAIN renderen — anders blokkeert elke nieuwe
        // tegel tijdens het scrollen de main-thread. Resultaat wordt gecachet, dus
        // het is effectief een snapshot dat één keer berekend wordt.
        // Achtergrondlaag: bij actief effect de gestylede volle foto (zodat de
        // backdrop bij het effect past), anders de rauwe import — zelfde als
        // PortraitExporter / EditorView.originalBackdropImage.
        let spec = PortraitThumbnailRenderer.Spec(
            cutoutData: portrait.cutoutData,
            originalData: portrait.effectBackgroundData ?? portrait.originalData,
            backgroundImageData: portrait.backgroundImageData,
            backgroundColorHex: portrait.backgroundColorHex,
            useOriginalBackground: portrait.useOriginalBackground,
            portraitBlur: portrait.portraitBlur,
            offsetX: portrait.offsetX, offsetY: portrait.offsetY, scale: portrait.scale,
            brightness: portrait.adjustBrightness, contrast: portrait.adjustContrast,
            saturation: portrait.adjustSaturation, temperature: portrait.adjustTemperature,
            side: Int(maxDimension)
        )
        let boxed = await Task.detached(priority: .userInitiated) { () -> SendableImage? in
            guard let cg = PortraitThumbnailRenderer.render(spec) else { return nil }
            return SendableImage(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        }.value
        guard let boxed, !Task.isCancelled else { return }
        Self.cache.setObject(boxed.image, forKey: key)
        image = boxed.image
    }
}

/// `NSImage` is niet Sendable; off-main gemaakt en daarna alléén op de main-actor
/// gelezen → veilig over de actorgrens (zelfde patroon als ShellModel).
private struct SendableImage: @unchecked Sendable { let image: NSImage }

/// Off-main portret-compositie — dezelfde pijplijn als `PortraitExporter`
/// (achtergrond + opgeslagen transform + Adjust), maar nonisolated zodat het de
/// scroll niet blokkeert. Werkt op uitgelichte waarden (geen SwiftData-model).
enum PortraitThumbnailRenderer {
    struct Spec: Sendable {
        let cutoutData: Data
        /// Backdrop-bron: `effectBackgroundData ?? originalData` (niet rauw
        /// `originalData` alleen — anders dubbel beeld bij actief effect).
        let originalData: Data?
        let backgroundImageData: Data?
        let backgroundColorHex: String?
        let useOriginalBackground: Bool
        let portraitBlur: Bool
        let offsetX: Double, offsetY: Double, scale: Double
        let brightness: Double, contrast: Double, saturation: Double, temperature: Double
        let side: Int
    }

    static func render(_ s: Spec) -> CGImage? {
        guard var cutout = cgImage(from: s.cutoutData) else { return nil }

        // Niet-destructieve Adjust-laag (alleen als hij niet neutraal is).
        let neutral = s.brightness == 0 && s.contrast == 1 && s.saturation == 1 && s.temperature == 0
        if !neutral, let adjusted = PortraitEnhancer.colorAdjust(
            cutout, brightness: s.brightness, contrast: s.contrast,
            saturation: s.saturation, temperatureShift: s.temperature
        ) { cutout = adjusted }

        let placement = BackgroundCompositor.Placement(
            offsetX: s.offsetX, offsetY: s.offsetY, scale: s.scale, canvasUnit: 1024
        )
        let originalCG = s.originalData.flatMap { cgImage(from: $0) }
        let bgIsAlignedOriginal = s.backgroundImageData == nil && s.backgroundColorHex == nil
            && (s.useOriginalBackground || s.portraitBlur)

        let backgroundImage: CGImage? = {
            if let data = s.backgroundImageData, let bg = cgImage(from: data) { return bg }
            if s.backgroundColorHex != nil { return nil }
            if s.useOriginalBackground || s.portraitBlur { return originalCG }
            return nil
        }()

        if var bg = backgroundImage {
            if s.portraitBlur { bg = BackgroundBlur.blurred(bg) ?? bg }
            let background: BackgroundCompositor.Background =
                bgIsAlignedOriginal ? .alignedImage(bg) : .image(bg)
            return (try? BackgroundCompositor.composite(
                cutout: cutout, over: background, placement: placement, outputSize: s.side
            )) ?? cutout
        }
        if let hex = s.backgroundColorHex, let rgb = rgb(hex) {
            return (try? BackgroundCompositor.composite(
                cutout: cutout, over: .color(red: rgb.r, green: rgb.g, blue: rgb.b),
                placement: placement, outputSize: s.side
            )) ?? cutout
        }
        // Geen achtergrond → onderwerp op transparant (de tegel-inset schijnt erdoor).
        return (try? BackgroundCompositor.composite(
            cutout: cutout, over: .image(clearPixel), placement: placement, outputSize: s.side
        )) ?? cutout
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var str = hex
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let v = UInt32(str, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    private static let clearPixel: CGImage = {
        let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
        return ctx.makeImage()!
    }()
}
