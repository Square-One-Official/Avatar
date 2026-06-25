// "Create effect" modal (E34, Figma TODO — interpreted in the spirit of the
// edit panels + DS sheet pattern, registreren in ASSETS.md zodra Figma landt).
// Een simpele modal: drop een referentiebeeld + schrijf een beschrijving, dan
// "Save" (alleen bewaren) of "Apply & Save" (bewaren + meteen op het portret
// genereren). Het referentiebeeld stuurt de stijl (tweede model-beeld) én is de
// thumbnail. Pro-only — het paneel toont deze sheet alleen voor Pro.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI
import UniformTypeIdentifiers

/// Resultaat van een geslaagde aanmaak, terug naar het paneel: de nieuwe rij,
/// het lokaal-gedropte referentiebeeld (voor de instant-thumbnail) en of het
/// meteen toegepast moet worden.
struct CreateEffectResult {
    let effect: RemoteCustomEffect
    let referenceImage: NSImage
    let apply: Bool
}

struct CreateEffectSheet: View {
    let entitlement: EntitlementModel
    var onCreated: (CreateEffectResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var referencePNG: Data?
    @State private var referenceImage: NSImage?
    @State private var description: String = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var isDropTargeted = false

    private let tileSide: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            header
            HStack(alignment: .top, spacing: DSSpacing.gap4) {
                dropZone
                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    Text("Describe the look")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.muted)
                    DSTextField(
                        placeholder: "e.g. glossy enamel pin, bold outline",
                        text: $description
                    )
                    Text("The reference image sets the style; the description fine-tunes it.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            footer
        }
        .padding(DSSpacing.gap8)
        .frame(width: 480)
        .background(DSColor.Background.app)
        .overlay(alignment: .bottom) {
            if let errorText {
                DSToast(title: "Couldn't create the effect", description: errorText) {
                    self.errorText = nil
                }
                .padding(DSSpacing.gap4)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                Text("Create effect").dsTextStyle(.h3)
                Text("Make your own style from a reference image.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            Spacer()
            DSIconButton(Image(systemName: "xmark"), size: .small) { dismiss() }
                .accessibilityLabel("Close")
        }
    }

    /// Drop-/klikzone voor het referentiebeeld; toont een preview zodra gekozen.
    private var dropZone: some View {
        Button(action: pickImage) {
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .fill(DSColor.Background.neutral)
                .frame(width: tileSide, height: tileSide)
                .overlay {
                    if let referenceImage {
                        Image(nsImage: referenceImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: tileSide, height: tileSide)
                            .clipped()
                    } else {
                        VStack(spacing: DSSpacing.gap2) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 26, weight: .regular))
                            Text("Drop image\nor click")
                                .multilineTextAlignment(.center)
                                .dsTextStyle(.labelSmall)
                        }
                        .foregroundStyle(DSColor.Foreground.subtle)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(
                            isDropTargeted ? DSColor.Action.primary : DSColor.Foreground.divider,
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: referenceImage == nil ? [5] : [])
                        )
                }
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap2) {
                Spacer()
                DSGhostButton("Save", action: { create(apply: false) })
                    .disabled(!canSave || isBusy)
                DSPrimaryButton("Apply & Save", action: { create(apply: true) })
                    .disabled(!canSave || isBusy)
            }
            Text("Applying generates on your portrait and uses \(CreditMeter.chipLabel(for: .generativeStandard)).")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var canSave: Bool { referencePNG != nil }

    // MARK: - Actions

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        setReference(from: data)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url, let data = try? Data(contentsOf: url) else { return }
                Task { @MainActor in setReference(from: data) }
            }
            return true
        }
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in setReference(from: data) }
            }
            return true
        }
        return false
    }

    /// Downscale + her-encodeer als PNG (zoals custom-achtergronden) zodat de
    /// upload klein blijft; bewaar zowel de PNG (upload) als een preview-beeld.
    private func setReference(from rawData: Data) {
        guard let png = BackgroundKit.downscaledPNG(rawData), let img = NSImage(data: png) else {
            errorText = "That image couldn't be read. Try a PNG or JPEG."
            return
        }
        referencePNG = png
        referenceImage = img
    }

    private func create(apply: Bool) {
        guard let referencePNG, let referenceImage, !isBusy else { return }
        isBusy = true
        errorText = nil
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let effect = try await entitlement.backend.createCustomEffect(
                    description: trimmed,
                    label: nil,
                    referencePNG: referencePNG
                )
                onCreated(CreateEffectResult(effect: effect, referenceImage: referenceImage, apply: apply))
                dismiss()
            } catch BackendError.proRequired {
                dismiss()
                entitlement.requestUpgrade()
            } catch {
                isBusy = false
                errorText = "Something went wrong saving your effect. Please try again."
            }
        }
    }
}
