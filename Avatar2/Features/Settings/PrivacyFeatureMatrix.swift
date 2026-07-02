// Uitklapbare tier×feature matrix (Settings, intern/QA).

import AvatarUI
import SwiftUI

struct PrivacyFeatureMatrix: View {
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                matrixSection(title: "On-device", features: onDeviceFeatures)
                matrixSection(title: "Apple Private Cloud", features: appleCloudFeatures)
                matrixSection(title: "Advanced", features: advancedFeatures)
            }
            .padding(.top, DSSpacing.gap3)
        } label: {
            Text("What works on each tier")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
        }
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

    private var onDeviceFeatures: [String] {
        [
            "Import cutout, retouch, blur, adjust",
            "Remove background (Regular & High quality)",
            "Boost resolution (on device)",
            "Banner Studio shaders",
        ]
    }

    private var appleCloudFeatures: [String] {
        if AppleIntelligenceAvailability.supportsApplePrivateCloud {
            return [
                "Generate backgrounds (Background panel sparkle button)",
                "Edit with Apple Intelligence (Enhance panel)",
            ]
        }
        return ["Generate / edit with Apple Intelligence (when available)"]
    }

    private var advancedFeatures: [String] {
        [
            "Boost resolution (online)",
            "Colorise, Fill in body",
            "Effects, Hair, Clothing, Face edits",
            "Generate backgrounds (Gemini / OpenAI)",
        ]
    }
}
