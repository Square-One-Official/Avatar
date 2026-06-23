// Figma "Stories" → App / Effects e.v. (dark) → dropdownMenu, plus het
// designbesluit (10 jun 2026, bouwplan E06): de foto verkleint wanneer een
// paneel actief is — dat regelt DSEditPanelContainer centraal, identiek
// voor álle panelen.

import SwiftUI

/// Paneel-chrome: bg Card, radius r-4xl, kaartpadding gap-2 met daarbinnen
/// een sectie met padding gap-5 (totale inset 28); titel UI/Labels/Base
/// (primary), kolomgap gap-2. Figma-schaduw 0/12/24/-12 zwart 25%
/// (hardcoded in design, geen token; spread benaderd via halve blur).
/// E18.18: meet de natuurlijke inhoudshoogte zodat het paneel de inhoud
/// "hugt" (geen lege ruimte onderaan bij korte panelen zoals Background) en
/// pas scrollt wanneer de inhoud de cap overschrijdt.
private struct DSPanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct DSEditPanel<Content: View>: View {
    private let title: String
    private let credits: String?
    private let content: Content
    private let maxWidth: CGFloat
    private let maxContentHeight: CGFloat
    @State private var contentHeight: CGFloat = 0

    /// E18.15: panelen waren overweldigend — volle vensterbreedte en hoog.
    /// Default nu compacter: `maxWidth` houdt het paneel weg van de randen
    /// (foto groter), `maxContentHeight` begrenst de hoogte → inhoud scrollt
    /// i.p.v. het paneel op te rekken.
    public init(
        title: String,
        credits: String? = nil,
        maxWidth: CGFloat = 600,
        maxContentHeight: CGFloat = 280,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.credits = credits
        self.maxWidth = maxWidth
        self.maxContentHeight = maxContentHeight
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            HStack {
                Text(title)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                if let credits {
                    Spacer()
                    Text(credits)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
            }
            // E18.15/18.18: één scrollbare kolom die de inhoud hugt — de
            // ScrollView krijgt exact de inhoudshoogte (gemeten) tot de cap;
            // daarboven scrollt hij. Géén lege ruimte bij korte panelen.
            ScrollView(.vertical, showsIndicators: true) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: DSPanelContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .frame(height: scrollHeight, alignment: .top)
            // E18.20: de eerste meting (0 → inhoudshoogte) mag niet meeveren
            // met de open-animatie — dat gaf een snelle "naspring" bij de
            // eerste klik. Zet 'm zonder animatie zodat het paneel meteen op
            // maat opent.
            .onPreferenceChange(DSPanelContentHeightKey.self) { height in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { contentHeight = height }
            }
            // E24.18: GEEN content-fade meer — de 24.12-`dsEdgeFade` kapte
            // kaarten/chips/tekst af bovenin/onderin álle panelen. Inhoud is nu
            // overal volledig zichtbaar (scrollt bij overflow; de scrollbar +
            // de paneel-rand zijn de enige rand-affordance).
        }
        .padding(DSSpacing.gap5)
        .padding(DSSpacing.gap2)
        .frame(maxWidth: maxWidth)
        // Solid achtergrond (geen glas): edit-panelen liggen over de foto
        // en moeten massief zijn zodat de inhoud niet door het portret scheemert.
        .dsPanelSurface(cornerRadius: DSRadius.xl4, solid: true)
    }

    /// nil tot de eerste meting (en in ImageRenderer, dat preferences niet
    /// propageert) → natuurlijke maat; daarna de inhoudshoogte, gecapt.
    private var scrollHeight: CGFloat? {
        contentHeight > 0 ? min(contentHeight, maxContentHeight) : nil
    }
}

/// Het edit-raamwerk waar alle feature-panelen in hangen (interface voor
/// E06): foto bovenin, actief paneel daaronder, toolbar onderaan. De foto
/// krijgt minder hoogte zodra een paneel verschijnt (centrale animatie);
/// panelen hoeven hier niets voor te doen.
public struct DSEditPanelContainer<Tool: Hashable, Photo: View, Panel: View, Accessory: View>: View {
    private let tools: [DSToolbarItem<Tool>]
    // E31.1: secundaire tools in de capsule-overflow (`⋯`).
    private let overflowTools: [DSToolbarItem<Tool>]
    // E-fix: losse acties in de capsule-overflow (`⋯`) zonder eigen paneel.
    private let overflowActions: [DSToolbarAction]
    @Binding private var activeTool: Tool?
    // E-fix: schakelt de feature-pillen uit (gedimd) terwijl er niets is om op te
    // werken — bv. tijdens een vervangende import waarin de cutout nog rekent.
    private let toolsEnabled: Bool
    private let photo: Photo
    private let panel: (Tool) -> Panel
    // E03.19: trailing accessoires (undo/redo/compare) die FEAT in de
    // toolbar-strip hangt i.p.v. als losse overlay ernaast.
    private let toolbarAccessory: Accessory

    public init(
        tools: [DSToolbarItem<Tool>],
        activeTool: Binding<Tool?>,
        overflowTools: [DSToolbarItem<Tool>] = [],
        overflowActions: [DSToolbarAction] = [],
        toolsEnabled: Bool = true,
        @ViewBuilder photo: () -> Photo,
        @ViewBuilder panel: @escaping (Tool) -> Panel,
        @ViewBuilder toolbarAccessory: () -> Accessory
    ) {
        self.tools = tools
        self.overflowTools = overflowTools
        self.overflowActions = overflowActions
        self._activeTool = activeTool
        self.toolsEnabled = toolsEnabled
        self.photo = photo()
        self.panel = panel
        self.toolbarAccessory = toolbarAccessory()
    }

    public var body: some View {
        VStack(spacing: DSSpacing.gap2) {
            // E18.22: de foto houdt een CONSTANTE maat — het paneel overlapt
            // de onderkant i.p.v. de foto te verkleinen.
            // E24.25-fix: de foto is een ZUSTER van het paneel (geen overlay-
            // kind van het transitionende paneel) MET een STABIELE identity
            // (.id) zodat hij niet mee-animeert/faded als `activeTool` wisselt.
            // Alléén het paneel transitionet (schuift in van onderen); de foto
            // blijft volledig stabiel — geen korte fade meer bij menu-open.
            ZStack(alignment: .bottom) {
                photo
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id("editorPhoto")

                if let tool = activeTool {
                    panel(tool)
                        .padding(.bottom, DSSpacing.gap2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Clip zodat het paneel netjes vanaf de onderrand in schuift.
            .clipped()

            DSBottomToolbar(
                items: tools, selection: $activeTool,
                overflow: overflowTools, overflowActions: overflowActions,
                toolsEnabled: toolsEnabled
            ) {
                toolbarAccessory
            }
                .fixedSize()
        }
        // E24.25: animeer alléén de paneel-insert/-remove, niet de foto.
        .animation(.spring(duration: 0.35), value: activeTool)
    }
}

// Bestaande call sites zonder accessoires blijven werken (EmptyView-slot).
extension DSEditPanelContainer where Accessory == EmptyView {
    public init(
        tools: [DSToolbarItem<Tool>],
        activeTool: Binding<Tool?>,
        overflowTools: [DSToolbarItem<Tool>] = [],
        overflowActions: [DSToolbarAction] = [],
        toolsEnabled: Bool = true,
        @ViewBuilder photo: () -> Photo,
        @ViewBuilder panel: @escaping (Tool) -> Panel
    ) {
        self.init(
            tools: tools,
            activeTool: activeTool,
            overflowTools: overflowTools,
            overflowActions: overflowActions,
            toolsEnabled: toolsEnabled,
            photo: photo,
            panel: panel,
            toolbarAccessory: { EmptyView() }
        )
    }
}
