// Share/export-popup (E19.1) — DS-stijl, met de v1-ExportSheet-functionaliteit
// (vorm + maat) op de Avatar2-exporter (BackgroundCompositor-WYSIWYG +
// free-tier-watermerk uit E08.2/E07.2).
//
// E33-redesign (Thierry, 2026-06-25):
//  - Geen inset-kaart meer achter de preview: het beeld zweeft in de gekozen
//    vorm op de sheet-achtergrond (de kaart leek deel van de export).
//  - Vorm = de enige echte keuze. Default Square (past op élk platform, dat
//    croppt zelf), plus Circle en Rounded (Slack/Discord). Onder de preview
//    een passieve "waar past dit"-regel die meebeweegt met de vorm — platform
//    is géén configuratie, want álle platforms nemen hetzelfde vierkante beeld.
//  - Geschatte bestandsgrootte per gekozen maat.
//  - Share werkt nu écht: de native NSSharingServicePicker wordt verankerd aan
//    de Share-knop (i.p.v. een nil-anker), en de sheet sluit niet meer meteen
//    waardoor het venster onder de picker wegviel.

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct ExportSheet: View {
    let portraitID: PersistentIdentifier
    var isPro: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // E33: standaard Square — dat is wat de meeste platforms nodig hebben (zij
    // croppen zelf naar cirkel/afgerond). Volgt niet langer portrait.frameShape.
    @State private var shape: ExportShape = .square
    @State private var size: Int = PortraitExporter.exportSide
    /// 256px-preview, één keer per vorm-wissel gerenderd.
    @State private var previewImage: NSImage?
    /// Byte-grootte van de 256px-preview-PNG — referentie voor een goedkope
    /// grootteschatting per maat (geen volle render nodig).
    @State private var referenceBytes: Int?
    /// Wordt gezet bij Share → triggert de verankerde native share-picker.
    @State private var shareURL: URL?

    private var portrait: Portrait2? {
        modelContext.model(for: portraitID) as? Portrait2
    }

    private var watermark: Bool { !isPro }

    var body: some View {
        Group {
            if let portrait {
                sheetContent(portrait: portrait)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if portrait == nil { dismiss() }
        }
    }

    @ViewBuilder
    private func sheetContent(portrait: Portrait2) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            HStack {
                Text("Export").dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
                Spacer()
                DSIconButton(Image(systemName: "xmark"), label: "Close", size: .small) { dismiss() }
            }

            preview
            platformHint

            field("Shape") {
                DSSegmentedControl(
                    selection: $shape,
                    segments: ExportShape.allCases.map { .init(tag: $0, label: $0.label) },
                    equalWidth: true
                )
            }

            field("Size") {
                DSSegmentedControl(
                    selection: $size,
                    segments: PortraitExporter.sizeOptions.map { .init(tag: $0, label: "\($0)px") },
                    equalWidth: true
                )
                Text(sizeCaption)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }

            if watermark {
                Text("Free exports include a small “Made with Aaavatar” mark. Upgrade to remove it.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DSSpacing.gap3) {
                DSNeutralButton("Save…", fullWidth: true) { save(portrait: portrait) }
                DSPrimaryButton("Share", fullWidth: true) { share(portrait: portrait) }
                    .background(SharePresenter(shareURL: $shareURL))
            }
        }
        .padding(DSSpacing.gap8)
        .frame(width: 420)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
        // Preview (256px) alléén opnieuw bij een vorm-wissel. De byte-grootte van
        // diezelfde PNG dient als referentie voor de grootteschatting per maat.
        .task(id: shape) {
            let data = await PortraitExporter.makePNGAsync(for: portrait, watermark: watermark, side: 256, shape: shape)
            previewImage = data.flatMap { NSImage(data: $0) }
            referenceBytes = data?.count
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        Group {
            if let previewImage {
                // makePNG levert het beeld al in de gekozen vorm (cirkel/afgerond
                // = transparante hoeken) → gewoon tonen, zonder kaart eromheen. De
                // schaduw volgt de alpha en laat de vorm los van de sheet komen.
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    @ViewBuilder
    private var platformHint: some View {
        HStack(spacing: DSSpacing.gap1_5) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DSColor.Foreground.muted)
            Text(Self.platformHintText(for: shape))
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
        }
        .frame(maxWidth: .infinity)
    }

    /// Passieve "waar past dit"-regel per export-vorm (unit-getest).
    static func platformHintText(for shape: ExportShape) -> String {
        switch shape {
        case .square:
            return "Upload this — LinkedIn, Instagram and most apps crop it to a circle."
        case .circle:
            return "Already circular — transparent corners. For when the file itself should look round."
        case .rounded:
            return "Matches Slack, Discord & Teams."
        }
    }

    private var sizeCaption: String {
        let perfect: String
        switch size {
        case 512: perfect = "Crisp on profiles"
        case 1024: perfect = "Best for retina displays"
        default: perfect = "Print & large displays"
        }
        guard let bytes = estimatedBytes else { return "\(perfect) · estimating size…" }
        return "\(perfect) · ≈ \(formatted(bytes))"
    }

    /// Goedkope grootteschatting i.p.v. de volle PNG te renderen: schaal de
    /// 256px-referentie met de pixel-verhouding, licht gedempt (grotere renders
    /// comprimeren iets beter per pixel). Heuristiek — vandaar de "≈".
    private var estimatedBytes: Int? {
        Self.estimatedBytes(referenceBytes: referenceBytes, side: size)
    }

    /// Pure schatting (E47.3-seam; unit-getest in `ExportSheetTests`): identiek
    /// aan de oude inline-berekening, alleen zonder de view-state eraan.
    static func estimatedBytes(referenceBytes: Int?, side: Int) -> Int? {
        guard let ref = referenceBytes else { return nil }
        let ratio = Double(side) / 256.0
        return Int(Double(ref) * pow(ratio, 1.85))
    }

    private func formatted(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1_5) {
            Text(label).dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
            content()
        }
    }

    // MARK: - Actions

    private func data(portrait: Portrait2) -> Data? {
        PortraitExporter.makePNG(for: portrait, watermark: watermark, side: size, shape: shape)
    }

    /// Export-/share-bestandsnaam op basis van de portretnaam (zoals de
    /// bulk-export); lege naam valt terug op het oude "Aaavatar-portrait".
    private func exportFileName(for portrait: Portrait2) -> String {
        let trimmed = portrait.name.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "Aaavatar-portrait" : trimmed.replacingOccurrences(of: "/", with: "-")
        return base + ".png"
    }

    private func share(portrait: Portrait2) {
        guard let data = data(portrait: portrait) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFileName(for: portrait))
        try? data.write(to: url)
        // Sheet NIET sluiten: de native picker is verankerd aan de Share-knop;
        // de sheet wegtrekken zou ook de picker meenemen (de oude bug).
        shareURL = url
    }

    private func save(portrait: Portrait2) {
        guard let data = data(portrait: portrait) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = exportFileName(for: portrait)
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
        dismiss()
    }
}

/// Verankert de native macOS share-picker aan zijn eigen (knop-grote) NSView.
/// Zodra `shareURL` wordt gezet, toont hij de picker en reset de binding.
private struct SharePresenter: NSViewRepresentable {
    @Binding var shareURL: URL?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let url = shareURL else { return }
        DispatchQueue.main.async {
            shareURL = nil
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
        }
    }
}
