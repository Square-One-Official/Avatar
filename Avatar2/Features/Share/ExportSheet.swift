// Share/export-popup (E19.1) — DS-stijl, met de v1-ExportSheet-functionaliteit
// (vorm + maat) op de Avatar2-exporter (BackgroundCompositor-WYSIWYG +
// free-tier-watermerk uit E08.2/E07.2). Live preview; Save… (NSSavePanel) of
// Share (NSSharingServicePicker).

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

struct ExportSheet: View {
    let portrait: Portrait2
    var isPro: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var shape: ExportShape
    @State private var size: Int = PortraitExporter.exportSide

    init(portrait: Portrait2, isPro: Bool = false) {
        self.portrait = portrait
        self.isPro = isPro
        // E24.16: de export-vorm volgt standaard de per-portret frame-vorm.
        _shape = State(initialValue: portrait.frameShape)
    }

    private var watermark: Bool { !isPro }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            HStack {
                Text("Export").dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
                Spacer()
                DSIconButton(Image(systemName: "xmark"), size: .small) { dismiss() }
                    .accessibilityLabel("Close")
            }

            preview

            field("Shape") {
                Picker("", selection: $shape) {
                    ForEach(ExportShape.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            field("Size") {
                Picker("", selection: $size) {
                    ForEach(PortraitExporter.sizeOptions, id: \.self) { Text("\($0)px").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if watermark {
                Text("Free exports include a small “Made with Aaavatar” mark. Upgrade to remove it.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DSSpacing.gap3) {
                DSNeutralButton("Save…", fullWidth: true) { save() }
                DSPrimaryButton("Share", fullWidth: true) { share() }
            }
        }
        .padding(DSSpacing.gap8)
        .frame(width: 420)
        .background(DSColor.Background.app)
    }

    @ViewBuilder
    private var preview: some View {
        if let data = PortraitExporter.makePNG(for: portrait, watermark: watermark, side: 256, shape: shape),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.xl))
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1_5) {
            Text(label).dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
            content()
        }
    }

    private func data() -> Data? {
        PortraitExporter.makePNG(for: portrait, watermark: watermark, side: size, shape: shape)
    }

    private func share() {
        guard let data = data() else { return }
        PortraitExporter.share(data, from: nil)
        dismiss()
    }

    private func save() {
        guard let data = data() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Aaavatar-portrait.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
        dismiss()
    }
}
