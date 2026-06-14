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
        maxWidth: CGFloat = 600,
        maxContentHeight: CGFloat = 280,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.maxWidth = maxWidth
        self.maxContentHeight = maxContentHeight
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text(title)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
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
        }
        .padding(DSSpacing.gap5)
        .padding(DSSpacing.gap2)
        .frame(maxWidth: maxWidth)
        // E18.22: subtiel glas — in-window-blur + een donkere tint die net
        // genoeg doorlaat om de foto erachter te voelen, maar donker genoeg
        // blijft om de inhoud helder te lezen.
        .background {
            ZStack {
                WithinWindowBlur(material: .hudWindow)
                DSColor.Background.card.opacity(0.82)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 12)
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
            // E18.22: de foto houdt een CONSTANTE maat — het paneel overlapt
            // de onderkant i.p.v. de foto te verkleinen. Wisselen tussen
            // menu's geeft zo geen onrustige resize meer. Het paneel schuift
            // van onderen in (glas-materiaal: de foto schemert subtiel door).
            photo
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if let tool = activeTool {
                        panel(tool)
                            .padding(.bottom, DSSpacing.gap2)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // Clip zodat het paneel netjes vanaf de onderrand in schuift.
                .clipped()

            DSBottomToolbar(items: tools, selection: $activeTool)
                .fixedSize()
        }
        .animation(.spring(duration: 0.35), value: activeTool)
    }
}
