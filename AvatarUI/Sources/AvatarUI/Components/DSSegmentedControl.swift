// Capsule segmented control — dezelfde stijl als de Monthly/Yearly-toggle in de
// paywall en de tab-pillen in manage-surfaces: track = background/neutral,
// selectie = background/neutral-stronger, label = UI/Labels/Base.

import SwiftUI

public struct DSSegmentedControl<Tag: Hashable>: View {
    @Binding private var selection: Tag
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

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(DSSpacing.gap0_5)
        .background(DSColor.Background.neutral, in: Capsule())
        .dsMotion(DSMotion.base, value: selection)
    }

    @ViewBuilder
    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = selection == segment.tag
        let horizontalPadding = equalWidth ? DSSpacing.gap2 : DSSpacing.gap4
        Button {
            DSMotion.animate(DSMotion.base) { selection = segment.tag }
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
                        Capsule().fill(DSColor.Background.neutralStronger)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
