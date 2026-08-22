import SwiftUI

/// Capsule-style segmented control with a sliding selected pill driven by
/// `matchedGeometryEffect` + spring. Selected segment gets a subtle elevated
/// surface; unselected segments are transparent on a slightly recessed track.
///
/// Use for compact chrome (inspector tabs, small mode switches). For 3+
/// segments with longer labels prefer the system `Picker(.segmented)`.
struct PillSegmentedControl<Tag: Hashable>: View {
    @Binding var selection: Tag
    let segments: [Segment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Segment: Identifiable {
        let tag: Tag
        let label: String
        let symbol: String
        var id: Tag { tag }
    }

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(3)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = selection == segment.tag
        Button {
            // Spring matches Apple's UIKit segment animation — alive but no overshoot.
            Motion.run(reduceMotion, .spring(response: 0.32, dampingFraction: 0.78)) {
                selection = segment.tag
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: segment.symbol)
                    .imageScale(.small)
                Text(segment.label)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule(style: .continuous))
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.appSurface)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .matchedGeometryEffect(id: "pillSelection", in: ns)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(segment.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
