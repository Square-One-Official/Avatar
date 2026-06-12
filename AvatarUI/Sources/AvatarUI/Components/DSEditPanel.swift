// Figma "Stories" → App / Effects e.v. (dark) → dropdownMenu, plus het
// designbesluit (10 jun 2026, bouwplan E06): de foto verkleint wanneer een
// paneel actief is — dat regelt DSEditPanelContainer centraal, identiek
// voor álle panelen.

import SwiftUI

/// Paneel-chrome: bg Card, radius r-4xl, kaartpadding gap-2 met daarbinnen
/// een sectie met padding gap-5 (totale inset 28); titel UI/Labels/Base
/// (primary), kolomgap gap-2. Figma-schaduw 0/12/24/-12 zwart 25%
/// (hardcoded in design, geen token; spread benaderd via halve blur).
public struct DSEditPanel<Content: View>: View {
    private let title: String
    private let content: Content

    public init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text(title)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
            content
        }
        .padding(DSSpacing.gap5)
        .padding(DSSpacing.gap2)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 12)
    }
}

/// Het edit-raamwerk waar alle feature-panelen in hangen (interface voor
/// E06): foto bovenin, actief paneel daaronder, toolbar onderaan. De foto
/// krijgt minder hoogte zodra een paneel verschijnt (centrale animatie);
/// panelen hoeven hier niets voor te doen.
public struct DSEditPanelContainer<Tool: Hashable, Photo: View, Panel: View>: View {
    private let tools: [DSToolbarItem<Tool>]
    @Binding private var activeTool: Tool?
    private let photo: Photo
    private let panel: (Tool) -> Panel

    public init(
        tools: [DSToolbarItem<Tool>],
        activeTool: Binding<Tool?>,
        @ViewBuilder photo: () -> Photo,
        @ViewBuilder panel: @escaping (Tool) -> Panel
    ) {
        self.tools = tools
        self._activeTool = activeTool
        self.photo = photo()
        self.panel = panel
    }

    public var body: some View {
        VStack(spacing: DSSpacing.gap2) {
            photo
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let tool = activeTool {
                panel(tool)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            DSBottomToolbar(items: tools, selection: $activeTool)
        }
        .animation(.spring(duration: 0.35), value: activeTool)
    }
}
