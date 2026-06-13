// Editor-framework (E06.1, Figma: App / Edit 4008:7340). Het raamwerk waar
// alle feature-panelen in hangen: DSEditPanelContainer (E03.3) regelt
// toolbar, actief paneel en het centrale foto-verkleint-gedrag. De zes
// tools volgen het frame; iconen benaderen de gerenderde Figma-glyphs met
// SF Symbols (de icon-lagen in Figma heten nog allemaal
// "square.and.arrow.up" — namen zijn stale, de render is de bron).
// Panelen zelf zijn latere stories (6.3 Edit, E07 Background, E09 Effects,
// E10 Clothes, E11 Hair, E05.4 Images/sidebar) en tonen tot die landen een
// lege paneel-chrome. Undo/redo naast de toolbar komen met E06.2.

import AvatarUI
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case edit, effects, clothing, hair, background, images

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edit: "Edit"
        case .effects: "Effects"
        case .clothing: "Clothing"
        case .hair: "Hair"
        case .background: "Background"
        case .images: "Images"
        }
    }

    /// SF-benadering van de gerenderde toolbar-glyphs uit App / Edit.
    var icon: Image {
        switch self {
        case .edit: Image(systemName: "wand.and.stars")
        case .effects: Image(systemName: "sparkles")
        case .clothing: Image(systemName: "tshirt.fill")
        case .hair: Image(systemName: "comb.fill")
        case .background: Image(systemName: "person.and.background.dotted")
        case .images: Image(systemName: "photo.on.rectangle.angled")
        }
    }

    /// De story die het echte paneel levert (zichtbaar in de stub-copy
    /// zolang het paneel er niet is).
    var pendingStory: String {
        switch self {
        case .edit: "E06.3"
        case .effects: "E09.2"
        case .clothing: "E10.2"
        case .hair: "E11.2"
        case .background: "E07.1"
        case .images: "E05.4"
        }
    }
}

struct EditorView: View {
    let portrait: NSImage
    /// Model-referentie voor de persistente canvas-transform (E06.4);
    /// nil = transform alleen in-memory (komt in de praktijk niet voor).
    var portraitModel: Portrait2?
    /// Images-tool is geen bottom-paneel maar de sidebar-toggle (E05.4):
    /// de lime ring volgt de sidebar-staat, het paneel blijft leeg.
    @Binding var isSidebarVisible: Bool
    @State private var activeTool: EditorTool?
    /// E06.2: tijdens indrukken toont het canvas de originele importfoto.
    @State private var isComparing = false
    @Environment(\.undoManager) private var undoManager
    /// UndoManager is niet observable; deze tick (gebumpt op undo-
    /// notificaties) forceert her-evaluatie van de enabled-state.
    @State private var undoTick = 0

    #if DEBUG
    /// Smoke-run-haak (--open-panel <tool>); gezet door ShellView.
    @MainActor static var debugInitialTool: EditorTool?
    #endif

    /// Originele importfoto (hold-to-compare); nil voor rijen van vóór E06.2.
    private var originalImage: NSImage? {
        guard let data = portraitModel?.originalData else { return nil }
        return NSImage(data: data)
    }

    private static let toolbarItems: [DSToolbarItem<EditorTool>] =
        EditorTool.allCases.map { DSToolbarItem(id: $0, icon: $0.icon, label: $0.label) }

    /// Onderschept .images: ring aan = sidebar open; andere tools sluiten
    /// de sidebar en openen hun paneel. Eén withAnimation-transactie zodat
    /// kaart, toolbar en sidebar samen veren — geen sprong (bevinding 5).
    private var toolSelection: Binding<EditorTool?> {
        Binding(
            get: { isSidebarVisible ? .images : activeTool },
            set: { newValue in
                withAnimation(.spring(duration: 0.35)) {
                    switch newValue {
                    case .images:
                        isSidebarVisible = true
                        activeTool = nil
                    case nil:
                        isSidebarVisible = false
                        activeTool = nil
                    default:
                        isSidebarVisible = false
                        activeTool = newValue
                    }
                }
            }
        )
    }

    var body: some View {
        editorBody
            // E06.2: undo/redo + hold-to-compare. Frame App / Edit zet undo/
            // redo ín de toolbar-strip (x344/x400) en de compare-thumb
            // top-right; integratie in DSBottomToolbar is DS-werk (E03.19).
            // Tot die landt staan ze als glass-cirkels rechtsonder, op één
            // lijn met de toolbar — gedocumenteerde tijdelijke plaatsing.
            .overlay(alignment: .bottomTrailing) { editorControls }
            // UndoManager publiceert geen state → luister op de
            // change-notificaties en bump de tick zodat de knoppen
            // enable/disablen.
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in undoTick += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in undoTick += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in undoTick += 1 }
    }

    @ViewBuilder
    private var editorControls: some View {
        HStack(spacing: DSSpacing.gap2) {
            DSToolButton(Image(systemName: "arrow.uturn.backward"), label: "Undo") {
                undoManager?.undo()
            }
            .disabled(undoManager?.canUndo != true)
            DSToolButton(Image(systemName: "arrow.uturn.forward"), label: "Redo") {
                undoManager?.redo()
            }
            .disabled(undoManager?.canRedo != true)
            if originalImage != nil {
                DSToolButton(Image(systemName: "rectangle.2.swap"), label: "Hold to compare original", isActive: isComparing) {}
                    .opacity(isComparing ? 0.85 : 1)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isComparing = true }
                            .onEnded { _ in isComparing = false }
                    )
            }
        }
        .padding(.trailing, DSSpacing.gap3)
        .padding(.bottom, DSSpacing.gap4)
    }

    private var editorBody: some View {
        DSEditPanelContainer(tools: Self.toolbarItems, activeTool: toolSelection) {
            // Canvas-kaart (bevinding 6/7): cutout gevuld op de kaart, met
            // dot-grid eronder zolang er geen achtergrond is ingesteld
            // (E07 zet showsDotGrid uit zodra een achtergrond actief is) —
            // transparante delen tonen het raster: achtergrond verwijderd.
            DSCanvasCard(showsDotGrid: true) {
                // E06.2: hold-to-compare toont de originele importfoto
                // (aspect-fit, geen transform) bovenop het cutout-canvas.
                if isComparing, let original = originalImage {
                    Image(nsImage: original)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // E06.4: pan/zoom/snap-canvas i.p.v. statische fill.
                    EditorCanvasView(image: portrait, portrait: portraitModel)
                }
            }
            // E04.7: altijd 1:1 en responsief — de kaart vult de foto-slot
            // (aspect-fit, dus nooit clippen) en groeit/krimpt met venster
            // en geopend paneel; de 3.16-garantie houdt paneel en toolbar
            // buiten schot. 456 was de Figma-maat bij 1000×700, geen cap.
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, DSSpacing.gap8)
        } panel: { tool in
            if tool == .images {
                // Sidebar-toggle: geen bottom-paneel, foto blijft groot.
                EmptyView()
            } else if tool == .edit {
                // E06.5: de eerste echte actie in het Edit-paneel; E06.3
                // neemt hem op in de volledige actielijst.
                DSEditPanel(title: tool.label) {
                    VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                        DSNeutralButton("Automatic framing") {
                            runAutomaticFraming()
                        }
                        Text("More tools land here (E06.3).")
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                DSEditPanel(title: tool.label) {
                    Text("\(tool.label) tools land here (\(tool.pendingStory)).")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.bottom, DSSpacing.gap2)
        #if DEBUG
        .onAppear {
            if let tool = Self.debugInitialTool {
                activeTool = tool
                Self.debugInitialTool = nil
            }
        }
        #endif
    }

    /// E06.5: AutoFramer op het huidige portret; zonder model of CGImage
    /// is er niets te kadreren (knop is dan een no-op).
    private func runAutomaticFraming() {
        guard let portraitModel,
              let cg = portrait.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Task { await AutoFramer.apply(to: portraitModel, image: cg, undoManager: undoManager) }
    }
}
