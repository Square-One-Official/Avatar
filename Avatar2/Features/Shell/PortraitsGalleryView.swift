// Portraits-library: de beelden van de in de sidebar geselecteerde map
// (of álle beelden) in een vast 3-koloms rooster. Geen list/gallery/canvas-
// switcher — grid is de enige weergave. Dubbelklik opent de editor;
// rechtermuis verplaatst naar een map of verwijdert.

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

    /// E53.7: leeft in de gedeelde store, niet in view-@State — de gallery-view
    /// wordt bij tabwissel opnieuw gebouwd en sloeg het menu anders weg.
    private var folderBackgroundPickerOpen: Binding<Bool> {
        Binding(
            get: { model.presentation.folderBackgroundPickerOpen },
            set: { model.presentation.folderBackgroundPickerOpen = $0 }
        )
    }

    // "max 3 naast elkaar" — een vast 3-koloms rooster.
    // UXS-9: gedeelde grid-maten met Home — dezelfde kaart kreeg per scherm
    // een andere celbreedte (3 vs 4 kolommen).
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: ShellMetrics.portraitGridSpacing),
        count: ShellMetrics.portraitGridColumnCount
    )

    private var selectedFolder: Folder2? {
        guard let id = model.selectedFolderID else { return nil }
        return folders.first { $0.persistentModelID == id }
    }

    private var items: [Portrait2] {
        guard let id = model.selectedFolderID else { return portraits }
        return portraits.filter { $0.folder?.persistentModelID == id }
    }

    /// Batch-import: tijdelijke tegels voor beelden die in deze lens landen en
    /// nog vrijstaand gemaakt worden (zie `ShellModel.importImages`).
    private var importJobs: [ShellModel.LibraryImportJob] {
        model.visibleLibraryImportJobs(folderID: model.selectedFolderID)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                if items.isEmpty && importJobs.isEmpty {
                    emptyState
                } else {
                    gridBody
                }
                if folderBackgroundPickerOpen.wrappedValue {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { folderBackgroundPickerOpen.wrappedValue = false }
                }
            }
        }
        // E50.1: ⌘A selecteert de hele zichtbare scope (huidige map of alles).
        .background {
            if !items.isEmpty {
                Button("") { model.selectAllPortraits(items.map(\.persistentModelID)) }
                    .keyboardShortcut("a", modifiers: .command)
                    .opacity(0)
            }
        }
        .coordinateSpace(name: PortraitContextMenuSpace.name)
        .onChange(of: model.folderBackgroundPickerID) { _, id in
            guard id == model.selectedFolderID else { return }
            folderBackgroundPickerOpen.wrappedValue = true
            model.folderBackgroundPickerID = nil
        }
        // Zelfde entree als Home (scale+fade vanuit het midden), zodat
        // Home → Portraits → map één en dezelfde beweging is. ShellView geeft
        // de gallery een identiteit per map, dus dit vuurt ook bij mapwissel.
        .transition(.dsScaleFade(anchor: .center, reduceMotion: reduceMotion))
    }

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DSSpacing.gap4) {
                // Lopende imports vóór het echte grid (omgekeerde drop-volgorde:
                // de tegel die nú verwerkt wordt grenst aan de jongste portretten
                // en wordt in-place door z'n portret vervangen).
                ForEach(importJobs) { job in
                    LibraryImportTile(job: job)
                }
                ForEach(items) { portrait in
                    PortraitGridTile(
                        portrait: portrait, folders: folders, model: model,
                        isSelected: model.isPortraitSelected(portrait),
                        ordered: { items.map(\.persistentModelID) },
                        selectedTargets: { items.filter { model.isPortraitSelected($0) } },
                        onContextMenu: { frame in
                            model.preparePortraitContextMenu(on: portrait)
                            model.presentation.openPortraitContextMenu(
                                portraitID: portrait.persistentModelID,
                                anchor: frame,
                                scope: .portraitsGallery
                            )
                        }
                    )
                }
            }
            .padding(.horizontal, DSSpacing.gap6)
            .padding(.bottom, DSSpacing.gap6)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                Text(selectedFolder?.name ?? "All portraits")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("\(items.count) \(items.count == 1 ? "portrait" : "portraits")")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            if let folder = selectedFolder {
                FolderDefaultBackgroundControl(
                    folder: folder,
                    entitlement: entitlement,
                    presentation: model.presentation,
                    isPickerOpen: folderBackgroundPickerOpen
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.top, ShellMetrics.pageTitleTopInset)
        .padding(.bottom, ShellMetrics.pageTitleBottomInset)
        .background(DSColor.Background.app)
        // Het Gallery-dropdown steekt onder de header uit over het grid.
        // Zonder deze z-index winnen de portret-Images de AppKit-laagstrijd
        // (menu onder de foto's) én vangt de dismiss-scrim de tegel-klikken.
        .zIndex(folderBackgroundPickerOpen.wrappedValue ? 1000 : 0)
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.gap4) {
            VStack(spacing: DSSpacing.gap2) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: DSIconSize.xxl, weight: .light))
                    .foregroundStyle(DSColor.Foreground.subtle)
                Text(model.selectedFolderID == nil ? "No portraits yet" : "This folder is empty")
                    .dsTextStyle(.labelLarge).foregroundStyle(DSColor.Foreground.subtle)
                Text(emptyStateBody)
                    .dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DSPrimaryButton("Upload portrait") { model.presentOpenPanel() }
        }
        .padding(DSSpacing.gap8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateBody: String {
        if selectedFolder?.defaultBackground != nil, model.selectedFolderID != nil {
            return "Drop a photo here — it will use this folder's default background."
        }
        if model.selectedFolderID != nil {
            return "Drop a photo here or upload one."
        }
        return "Drop a photo or upload one to make a portrait."
    }
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
    /// Home-hero: dezelfde kaart op dubbele kolombreedte — grotere labels,
    /// ruimere inzet en een groter selectie-vinkje; verder identiek.
    var prominent: Bool = false

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
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                    .strokeBorder(
                        (isSelected || hovering) ? DSColor.Action.primaryForeground : .clear,
                        lineWidth: DSBorderWidth.medium
                    )
            )
            // Selectie-vinkje (Finder-stijl) rechtsboven.
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    DSSelectionCheckBadge(size: prominent ? 22 : 20)
                        .padding(prominent ? DSSpacing.gap3 : DSSpacing.gap2)
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
            // Verse batch-import: de al gerenderde reveal-compositie als
            // placeholder tot de eigen render klaar is (geen lege flits).
            PortraitCompositeMeasured(
                portrait: portrait, placeholder: model.freshImportPreview(for: portrait)
            )

            // UXS-3: gedeelde scrim i.p.v. een eigen ramp — zie DSCardLabelScrim.
            DSCardLabelScrim()

            VStack(alignment: .leading, spacing: 0) {
                Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                    .dsTextStyle(prominent ? .labelLarge : .labelBase).foregroundStyle(.white).lineLimit(1)
                    .help(portrait.name.isEmpty ? "Untitled" : portrait.name)
                if !portrait.role.isEmpty {
                    Text(portrait.role)
                        .dsTextStyle(prominent ? .labelBase : .labelSmall)
                        .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            .padding(prominent ? DSSpacing.gap4 : DSSpacing.gap3)
        }
    }
}

// MARK: - Kaart-accessibility (UXS-7 / UX28)

/// Maakt een portret-kaart (grid-tegel, Home-hero) één VoiceOver-element:
/// naam+rol als label, button-trait (+selected), en drie acties — activeren
/// = openen (zelfde pad als de plain klik), "Select"/"Deselect" (zelfde pad
/// als ⌘-klik) en "Show Context Menu" (zelfde pad als rechtsklik, verankerd
/// op de gemeten kaart-frame in SwiftUI `.global`). Zonder dit
/// bestonden de kaarten niet voor de AX-boom (audit UX28, live geverifieerd).
struct PortraitCardAccessibility: ViewModifier {
    let portrait: Portrait2
    let model: ShellModel
    let isSelected: Bool
    let ordered: () -> [PersistentIdentifier]
    let onContextMenu: (CGRect) -> Void

    /// Kaart-frame in SwiftUI `.global` — zelfde space als `DSContextMenuOverlay`.
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.onChange(
                        of: geo.frame(in: .global),
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
    /// Getoond zolang de compositie nog rendert (i.p.v. de kale inset).
    var placeholder: NSImage? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var sidePoints: CGFloat = 0

    private var pixelSide: CGFloat {
        ceil(sidePoints * displayScale)
    }

    var body: some View {
        Group {
            if sidePoints > 0 {
                PortraitComposite(portrait: portrait, maxDimension: pixelSide, placeholder: placeholder)
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
/// cutout). Resultaat wordt gecachet op (portret, revision, maat).
struct PortraitComposite: View {
    let portrait: Portrait2
    let maxDimension: CGFloat
    /// Getoond zolang de eigen render nog loopt (verse batch-import).
    var placeholder: NSImage? = nil

    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            DSColor.Background.inset
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let placeholder {
                Image(nsImage: placeholder).resizable().scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: cacheKey) { await load() }
    }

    private var cacheKey: String {
        "\(portrait.persistentModelID.hashValue)-\(portrait.revision)-\(Int(maxDimension))"
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
