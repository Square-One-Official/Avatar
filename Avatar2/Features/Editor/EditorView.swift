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
    @State private var activeTool: EditorTool?

    private static let toolbarItems: [DSToolbarItem<EditorTool>] =
        EditorTool.allCases.map { DSToolbarItem(id: $0, icon: $0.icon, label: $0.label) }

    var body: some View {
        DSEditPanelContainer(tools: Self.toolbarItems, activeTool: $activeTool) {
            Image(nsImage: portrait)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, DSSpacing.gap8)
                .padding(.top, DSSpacing.gap8)
        } panel: { tool in
            DSEditPanel(title: tool.label) {
                Text("\(tool.label) tools land here (\(tool.pendingStory)).")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.bottom, DSSpacing.gap2)
    }
}
