// Uitklapbare Local / Cloud feature-lijst (Settings).

import AvatarUI
import SwiftUI

struct PrivacyFeatureMatrix: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                DSMotion.animate(DSMotion.fast) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: DSSpacing.gap1) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: DSIconSize.xxs, weight: .semibold))
                        .foregroundStyle(DSColor.Foreground.primary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: DSIconSize.sm, height: DSIconSize.sm)
                    Text("What works on each choice")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .padding(.vertical, DSSpacing.gap1)
                        .padding(.horizontal, DSSpacing.gap1)
                        .dsHoverHighlight(cornerRadius: DSRadius.md)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What works on each choice")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(
                isExpanded
                    ? "Hides which features work on each privacy choice"
                    : "Shows which features work on each privacy choice"
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                    matrixSection(title: "Local only", features: localFeatures)
                    matrixSection(title: "Cloud", features: cloudFeatures)
                }
                .padding(.top, DSSpacing.gap3)
                .padding(.leading, DSSpacing.gap4)
            }
        }
        .dsMotion(DSMotion.fast, value: isExpanded)
    }

    private func matrixSection(title: String, features: [String]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            Text(title)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
            ForEach(features, id: \.self) { name in
                Text(name)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
        }
    }

    private var localFeatures: [String] {
        var rows = [
            "Import cutout, retouch, blur, adjust",
            "Remove background (Regular & High quality)",
            "Boost resolution (on device)",
        ]
        if AppFeatureFlags.bannersEnabled {
            rows.append("Banner Studio shaders")
        }
        return rows
    }

    private var cloudFeatures: [String] {
        var rows = [
            "Boost resolution (online)",
            "Colorise, Fill in body",
        ]
        rows.append(cloudEditsLine)
        rows.append("Generate backgrounds")
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            rows.append("Edit with Apple Intelligence")
        }
        return rows
    }

    /// Effects blijft; Hair / Clothing / Face alleen als hun compile-time
    /// poort open is, zodat Settings niet belooft wat de toolbar verbergt.
    private var cloudEditsLine: String {
        var parts = ["Effects"]
        if AppFeatureFlags.hairEnabled { parts.append("Hair") }
        if AppFeatureFlags.clothesEnabled { parts.append("Clothing") }
        if AppFeatureFlags.faceEnabled { parts.append("Face edits") }
        return parts.joined(separator: ", ")
    }
}
