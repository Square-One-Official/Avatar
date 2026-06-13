// Sidebar/set (E05.4 + E04.5-fix bevinding 8, Figma: App / Sidebar images
// 4011:4986, paneel "Siri AI" 248 breed). Losstaande afgeronde kaart
// (bg Card, r-4xl continuous — zelfde kaarttaal als DSEditPanel; ShellView
// geeft de marge rondom) met DSSearchField (capsule h48, E03.10) bovenin,
// DSSidebarRow-slots (thumb 48, continuous corners; selectie = afgeronde
// Inset-highlight) en de DSAddButton (sidebar-add-besluit 10 jun).
// Thumbnails in Figma zijn placeholderfoto's; wij renderen de cutouts.

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

    @Environment(\.undoManager) private var undoManager
    /// E05.7: loopt tijdens een set-brede align (knop disabled + pulse).
    @State private var isAligning = false

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
    }

    @ViewBuilder
    private func thumbnail(for portrait: Portrait2) -> some View {
        if let image = NSImage(data: portrait.cutoutData) {
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
        let targets = portraits
        Task {
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
}
