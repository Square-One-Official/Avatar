// Sidebar/set (E05.4 + E04.5-fix bevinding 8, Figma: App / Sidebar images
// 4011:4986, paneel "Siri AI" 248 breed). Losstaande afgeronde kaart
// (bg Card, r-4xl continuous — zelfde kaarttaal als DSEditPanel; ShellView
// geeft de marge rondom) met DSSearchField (capsule h48, E03.10) bovenin,
// DSSidebarRow-slots (thumb 48, continuous corners; selectie = afgeronde
// Inset-highlight) en de DSAddButton (sidebar-add-besluit 10 jun).
// Thumbnails in Figma zijn placeholderfoto's; wij renderen de cutouts.

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct SidebarView: View {
    /// Marge t.o.v. de vensterrand — ShellView gebruikt dezelfde waarde
    /// als padding, de kaartradius rekent er concentrisch mee.
    static let edgeInset: CGFloat = ShellMetrics.windowEdgeInset

    // Laatst bewerkt bovenaan, zoals v1 (punt 13).
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @State private var searchText = ""

    let selectedID: PersistentIdentifier?
    let onSelect: (Portrait2) -> Void
    let onAdd: () -> Void
    /// E19.2: export het portret via de shell (selecteert + opent de popup).
    var onExport: (Portrait2) -> Void = { _ in }
    /// E19.5: set-brede voortgang (Align/Match lighting) → shell-toast.
    var onSetBusy: (String?) -> Void = { _ in }

    @Environment(\.undoManager) private var undoManager
    @Environment(\.modelContext) private var modelContext
    /// E19.2/19.3: context-menu-acties.
    @State private var renameTarget: Portrait2?
    @State private var deleteTarget: Portrait2?
    /// E05.7: loopt tijdens een set-brede align (knop disabled + pulse).
    @State private var isAligning = false
    /// E12.2: loopt tijdens de set-brede lichtnormalisatie.
    @State private var isMatchingLight = false

    private var filtered: [Portrait2] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return portraits }
        return portraits.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.role.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DSSearchField(text: $searchText)
                .padding(DSSpacing.gap4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { portrait in
                        DSSidebarRow(
                            name: portrait.name.isEmpty ? "Name" : portrait.name,
                            role: portrait.role.isEmpty ? "Role" : portrait.role,
                            isSelected: portrait.persistentModelID == selectedID,
                            action: { onSelect(portrait) },
                            avatar: { thumbnail(for: portrait) }
                        )
                        // E19.2: rechtermuis → Rename / Export / Delete.
                        .contextMenu {
                            Button("Rename") { renameTarget = portrait }
                            Button("Export…") { onExport(portrait) }
                            Divider()
                            Button("Delete", role: .destructive) { deleteTarget = portrait }
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.gap4)
                .padding(.top, DSSpacing.gap4)
            }

            VStack(spacing: DSSpacing.gap2) {
                // E05.7: de kern-merkbelofte als één knop — prominent
                // (brand) maar rustig; alleen zinvol bij een set (≥2).
                if portraits.count >= 2 {
                    DSPrimaryButton(
                        isAligning ? "Aligning…" : "Align set",
                        icon: Image(systemName: "wand.and.stars"),
                        fullWidth: true
                    ) {
                        alignSet()
                    }
                    .disabled(isAligning)
                    // E12.2: set-brede lichtnormalisatie naar het geselecteerde
                    // portret als referentie. Secundair t.o.v. "Align set".
                    DSNeutralButton(
                        isMatchingLight ? "Matching lighting…" : "Match lighting",
                        icon: Image(systemName: "sun.max"),
                        fullWidth: true
                    ) {
                        matchLighting()
                    }
                    .disabled(isMatchingLight)
                }
                DSAddButton("Add portrait") {
                    onAdd()
                }
            }
            .padding(DSSpacing.gap4)
        }
        .frame(width: 248)
        .frame(maxHeight: .infinity)
        // Concentrisch met de vensterrand (E03.15, bevinding 17):
        // binnenradius = vensterradius − marge; ShellView zet de kaart op
        // dezelfde `edgeInset`.
        .background(
            DSColor.Background.card,
            in: .rect(
                cornerRadius: DSRadius.concentric(inset: Self.edgeInset),
                style: .continuous
            )
        )
        // E19.3: rename-modal.
        .sheet(isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            if let target = renameTarget { RenameSheet(portrait: target) }
        }
        // E19.2: delete met bevestiging.
        .confirmationDialog(
            "Delete this portrait?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget { modelContext.delete(target) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    @ViewBuilder
    private func thumbnail(for portrait: Portrait2) -> some View {
        // E19.6: gecachte, gedownscalede thumb i.p.v. full-res decode per render.
        if let image = SidebarThumbnailCache.thumbnail(for: portrait) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                // Previewanimatie (E05.7): korte puls tijdens het alignen.
                .scaleEffect(isAligning ? 0.9 : 1)
                .animation(.spring(duration: 0.4), value: isAligning)
        } else {
            DSColor.Background.inset
        }
    }

    /// E05.7: past het auto-frame-profiel (E06.5) toe op álle portretten,
    /// als één set-brede undo-stap. Detectie draait off-main; het schrijven
    /// + de undo-registratie gebeuren binnen één NSUndoManager-groep zodat
    /// Cmd+Z de hele set in één keer terugdraait.
    private func alignSet() {
        guard !isAligning else { return }
        isAligning = true
        onSetBusy("Aligning set…")
        let targets = portraits
        Task {
            defer { onSetBusy(nil) }
            // 1. Bereken alle transforms (off-main per cutout).
            var items: [(Portrait2, TransformUndo.Snapshot, AutoFramer.Transform)] = []
            for portrait in targets {
                guard let cg = NSImage(data: portrait.cutoutData)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let before = TransformUndo.snapshot(of: portrait)
                let transform = await AutoFramer.transform(forCutout: cg)
                items.append((portrait, before, transform))
            }
            // 2. Schrijf + registreer alles in één undo-groep.
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Align Set")
            withAnimation(.spring(duration: 0.45)) {
                for (portrait, before, transform) in items {
                    portrait.offsetX = transform.offset.width
                    portrait.offsetY = transform.offset.height
                    portrait.scale = transform.scale
                    portrait.touch()
                    TransformUndo.register(
                        undoManager,
                        portrait: portrait,
                        undoTo: before,
                        redoTo: TransformUndo.snapshot(of: portrait),
                        actionName: "Align Set"
                    )
                }
            }
            undoManager?.endUndoGrouping()
            isAligning = false
        }
    }

    /// E12.2: trekt de belichting/kleurbalans van álle portretten naar het
    /// geselecteerde portret (of het meest recente) als referentie, in één
    /// set-brede undo-groep. Lokaal (SetLightingNormalizer); de referentie
    /// zelf blijft ongemoeid (gain ≈ 1 → geen wijziging → geen undo-stap).
    private func matchLighting() {
        guard !isMatchingLight else { return }
        isMatchingLight = true
        onSetBusy("Matching lighting…")
        let targets = portraits
        let reference = targets.first { $0.persistentModelID == selectedID } ?? targets.first
        Task {
            defer { isMatchingLight = false; onSetBusy(nil) }
            guard let reference,
                  let refCG = Self.cgImage(from: reference.cutoutData),
                  let refStats = SetLightingNormalizer.referenceStats(of: refCG) else { return }

            // 1. Bereken de genormaliseerde bytes per (niet-referentie-)portret.
            var items: [(Portrait2, Data, Data)] = []
            for portrait in targets where portrait.persistentModelID != reference.persistentModelID {
                guard let cg = Self.cgImage(from: portrait.cutoutData),
                      let outCG = SetLightingNormalizer.match(cg, to: refStats),
                      let png = Self.pngData(from: outCG) else { continue }
                items.append((portrait, portrait.cutoutData, png))
            }

            // 2. Schrijf + registreer alles in één undo-groep.
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Match Lighting")
            withAnimation(.spring(duration: 0.4)) {
                for (portrait, before, after) in items {
                    portrait.cutoutData = after
                    portrait.touch()
                    CutoutDataUndo.register(
                        undoManager, portrait: portrait,
                        undoTo: before, redoTo: after, actionName: "Match Lighting"
                    )
                }
            }
            undoManager?.endUndoGrouping()
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
