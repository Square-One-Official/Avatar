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

public struct DSEditPanel<Content: View, Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let credits: String?
    private let content: Content
    private let headerAccessory: Accessory
    private let maxWidth: CGFloat
    private let maxContentHeight: CGFloat
    @Environment(\.dsVectorExport) private var vectorExport
    @State private var contentHeight: CGFloat = 0

    /// E18.15: panelen waren overweldigend — volle vensterbreedte en hoog.
    /// Default nu compacter: `maxWidth` houdt het paneel weg van de randen
    /// (foto groter), `maxContentHeight` begrenst de hoogte → inhoud scrollt
    /// i.p.v. het paneel op te rekken.
    ///
    /// E55.4: `headerAccessory` — een compact trailing control in de titelrij
    /// (na de credits-chip), bv. de "Create"-knop van Effects. Zelfde
    /// back-compat-patroon als `DSEditPanelContainer`: bestaande call sites
    /// zonder accessoire gebruiken de EmptyView-convenience hieronder.
    public init(
        title: String,
        subtitle: String? = nil,
        credits: String? = nil,
        maxWidth: CGFloat = 600,
        maxContentHeight: CGFloat = 280,
        @ViewBuilder headerAccessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.credits = credits
        self.maxWidth = maxWidth
        self.maxContentHeight = maxContentHeight
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                HStack(spacing: DSSpacing.gap2) {
                    Text(title)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Spacer(minLength: 0)
                    if let credits {
                        Text(credits)
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.subtle)
                    }
                    headerAccessory
                }
                if let subtitle {
                    Text(subtitle)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // E18.15/18.18: één scrollbare kolom die de inhoud hugt — de
            // ScrollView krijgt exact de inhoudshoogte (gemeten) tot de cap;
            // daarboven scrollt hij. Géén lege ruimte bij korte panelen.
            // Vector-export: ScrollView meet z'n inhoud via een preference die
            // ImageRenderer niet propageert → klapt dicht; toon de inhoud plat.
            if vectorExport {
                content.frame(maxWidth: .infinity, alignment: .leading)
            } else {
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
            .scrollClipDisabled()
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
            }
            // E24.18: GEEN content-fade meer — de 24.12-`dsEdgeFade` kapte
            // kaarten/chips/tekst af bovenin/onderin álle panelen. Inhoud is nu
            // overal volledig zichtbaar (scrollt bij overflow; de scrollbar +
            // de paneel-rand zijn de enige rand-affordance).
        }
        .padding(DSSpacing.gap5)
        .padding(DSSpacing.gap2)
        .frame(maxWidth: maxWidth)
        // Zelfde massieve 24pt-card als Frame/Background/account-menu's.
        .dsMenuSurface()
    }

    /// nil tot de eerste meting (en in ImageRenderer, dat preferences niet
    /// propageert) → natuurlijke maat; daarna de inhoudshoogte, gecapt.
    private var scrollHeight: CGFloat? {
        contentHeight > 0 ? min(contentHeight, maxContentHeight) : nil
    }
}

// Bestaande call sites zonder header-accessoire blijven werken (EmptyView-slot).
extension DSEditPanel where Accessory == EmptyView {
    public init(
        title: String,
        subtitle: String? = nil,
        credits: String? = nil,
        maxWidth: CGFloat = 600,
        maxContentHeight: CGFloat = 280,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            credits: credits,
            maxWidth: maxWidth,
            maxContentHeight: maxContentHeight,
            headerAccessory: { EmptyView() },
            content: content
        )
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
    /// UXS-4/E53.7: open-state van de `⋯`-dropdown, doorgegeven aan de toolbar.
    private let overflowOpen: Binding<Bool>?
    @Binding private var activeTool: Tool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        overflowOpen: Binding<Bool>? = nil,
        toolsEnabled: Bool = true,
        @ViewBuilder photo: () -> Photo,
        @ViewBuilder panel: @escaping (Tool) -> Panel,
        @ViewBuilder toolbarAccessory: () -> Accessory
    ) {
        self.tools = tools
        self.overflowTools = overflowTools
        self.overflowActions = overflowActions
        self.overflowOpen = overflowOpen
        self._activeTool = activeTool
        self.toolsEnabled = toolsEnabled
        self.photo = photo()
        self.panel = panel
        self.toolbarAccessory = toolbarAccessory()
    }

    /// Ruimte tussen paneel-onderkant en venster-onderkant: zwevende toolbar +
    /// gap (identiek aan de oude VStack-spacing, maar zonder layout-shift).
    private var panelBottomClearance: CGFloat {
        DSToolbarSize.regular.height
            + DSToolbarSize.regular.containerPadding * 2
            + DSSpacing.gap2
    }

    public var body: some View {
        // Besluit Thierry (2026-06-24): het canvas loopt door tot de onderrand van
        // het venster en de toolbar ZWEEFT eroverheen (Figma floatingToolbar) —
        // i.p.v. een eigen VStack-rij die onder de toolbar een lege Background.app-
        // band achterliet ("toolbar heeft al een achtergrondkleur"). De foto vult
        // dus de volle hoogte; paneel + toolbar liggen als bottom-overlay erover.
        // E18.22: de foto houdt een CONSTANTE maat — het paneel overlapt de
        // onderkant i.p.v. de foto te verkleinen. STABIELE identity (.id) zodat de
        // foto niet mee-animeert/faded als `activeTool` wisselt.
        //
        // E-fix (motion): toolbar blijft vast onderaan (ZStack); alléén het paneel
        // slide't. De oude VStack klapte de hoogte dicht terwijl `.move(.bottom)`
        // naar een verschuivende onderrand rende → hang/stutter bij dismiss.
        photo
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id("editorPhoto")
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if let tool = activeTool {
                        panel(tool)
                            // STABIELE identity over tool-wissels heen. Tool→tool
                            // is een in-place update; alléén nil ↔ tool triggert slide.
                            .padding(.bottom, panelBottomClearance)
                            .id("editPanel")
                            .transition(.dsSlide(.bottom, reduceMotion: reduceMotion))
                    }

                    DSBottomToolbar(
                        items: tools, selection: $activeTool,
                        overflow: overflowTools, overflowActions: overflowActions,
                        overflowOpen: overflowOpen,
                        toolsEnabled: toolsEnabled
                    ) {
                        toolbarAccessory
                    }
                    .fixedSize()
                }
                .padding(.bottom, DSSpacing.gap2)
            }
            // E24.25: transactie voor paneel-insert/-remove — exit bij dicht,
            // enter bij open (matcht dsSlide-asymmetrie). Geen hoogte-settle: de
            // toolbar staat vast, dus geen layout-animatie die de slide verstoort.
            .dsMotion(activeTool == nil ? DSMotion.exit : DSMotion.enter, value: activeTool)
    }
}

// Bestaande call sites zonder accessoires blijven werken (EmptyView-slot).
extension DSEditPanelContainer where Accessory == EmptyView {
    public init(
        tools: [DSToolbarItem<Tool>],
        activeTool: Binding<Tool?>,
        overflowTools: [DSToolbarItem<Tool>] = [],
        overflowActions: [DSToolbarAction] = [],
        overflowOpen: Binding<Bool>? = nil,
        toolsEnabled: Bool = true,
        @ViewBuilder photo: () -> Photo,
        @ViewBuilder panel: @escaping (Tool) -> Panel
    ) {
        self.init(
            tools: tools,
            activeTool: activeTool,
            overflowTools: overflowTools,
            overflowActions: overflowActions,
            overflowOpen: overflowOpen,
            toolsEnabled: toolsEnabled,
            photo: photo,
            panel: panel,
            toolbarAccessory: { EmptyView() }
        )
    }
}
