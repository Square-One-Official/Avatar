// Capsule segmented control — dezelfde stijl als de Monthly/Yearly-toggle in de
// paywall en de tab-pillen in manage-surfaces: track = background/neutral,
// selectie = background/neutral-stronger, label = UI/Labels/Base.

import SwiftUI

public struct DSSegmentedControl<Tag: Hashable>: View {
    @Binding private var selection: Tag
    @Namespace private var selectionNamespace
    private let segments: [Segment]
    private let equalWidth: Bool

    public struct Segment: Identifiable, Sendable {
        public let tag: Tag
        public let label: String
        public var id: Tag { tag }

        public init(tag: Tag, label: String) {
            self.tag = tag
            self.label = label
        }
    }

    public init(
        selection: Binding<Tag>,
        segments: [Segment],
        equalWidth: Bool = false
    ) {
        self._selection = selection
        self.segments = segments
        self.equalWidth = equalWidth
    }

    /// UXS-25: welk segment de muis raakt — een segmented control zonder hover
    /// voelt dood, want niets verraadt dat de niet-gekozen kant klikbaar is.
    @State private var hoveredTag: Tag?

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(DSSpacing.gap0_5)
        .background(DSColor.Background.neutral, in: Capsule())
        .dsMotion(DSMotion.springSmall, value: selection)
        // UXS-25: ←/→ lopen door de segmenten zodra de control focus heeft.
        // Systeemring uit: een muisklik zou anders het lichtblauwe rechthoekje
        // rond de capsule zetten (Figma heeft die staat niet).
        .dsKeyboardFocusable()
        .onMoveCommand { direction in
            switch direction {
            case .left:  moveSelection(by: -1)
            case .right: moveSelection(by: 1)
            default:     break
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Verschuift de selectie binnen de grenzen (geen wrap-around: op een
    /// tweeknops-toggle zou wrappen de selectie laten stuiteren).
    private func moveSelection(by offset: Int) {
        guard let index = segments.firstIndex(where: { $0.tag == selection }) else { return }
        let next = index + offset
        guard segments.indices.contains(next) else { return }
        DSMotion.animate(DSMotion.springSmall) { selection = segments[next].tag }
    }

    @ViewBuilder
    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = selection == segment.tag
        let isHovered = hoveredTag == segment.tag
        let horizontalPadding = equalWidth ? DSSpacing.gap2 : DSSpacing.gap4
        Button {
            DSMotion.animate(DSMotion.springSmall) { selection = segment.tag }
        } label: {
            Text(segment.label)
                .dsTextStyle(.labelBase)
                .foregroundStyle(isSelected ? DSColor.Foreground.primary : DSColor.Foreground.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, DSSpacing.gap2)
                .frame(maxWidth: equalWidth ? .infinity : nil)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(DSColor.Background.neutralStronger)
                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                    } else if isHovered {
                        // Alleen op níet-gekozen segmenten: de selectie heeft al
                        // een vulling, daar zou hover er alleen troebel op staan.
                        Capsule().fill(DSColor.Background.neutralStronger.opacity(0.5))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .onHover { hoveredTag = $0 ? segment.tag : (hoveredTag == segment.tag ? nil : hoveredTag) }
        .dsMotion(DSMotion.micro, value: isHovered)
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
