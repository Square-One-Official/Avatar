// PoC (left-nav): "Manage backgrounds"-surface vanuit het gebruikersmenu in de
// left-nav. Twee tabs: Backgrounds (de echte, door de gebruiker geüploade
// achtergronden uit BackgroundImageKit + brand-kleuren uit BrandColorKit, met
// upload + delete) en Effects (placeholder — er bestaat nog geen door de
// gebruiker beheerde effecten-bron; CMS-effecten zijn read-only).

import AppKit
import AvatarUI
import SwiftUI

struct ManageBackgroundsSheet: View {
    var entitlement: EntitlementModel? = nil

    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable { case backgrounds, effects; var id: String { rawValue } }
    @State private var tab: Tab = .backgrounds

    /// Singletons (beide @Observable @MainActor) — direct gelezen in body, dus
    /// Observation ververst de grid bij upload/delete.
    private var imageKit: BackgroundImageKit { .shared }
    private var colorKit: BrandColorKit { .shared }

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 84), spacing: DSSpacing.gap3)]

    var body: some View {
        VStack(spacing: 0) {
            header
            segmented
                .padding(.horizontal, DSSpacing.gap5)
                .padding(.bottom, DSSpacing.gap4)
            Divider().overlay(DSColor.Foreground.divider)
            DSScrollView {
                switch tab {
                case .backgrounds: backgroundsTab
                case .effects: effectsTab
                }
            }
        }
        .frame(width: 540, height: 480)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Manage backgrounds")
                .dsTextStyle(.h4)
                .foregroundStyle(DSColor.Foreground.primary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: DSIconSize.sm, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
        }
        .padding(.horizontal, DSSpacing.gap5)
        .padding(.top, DSSpacing.gap5)
        .padding(.bottom, DSSpacing.gap4)
    }

    // UXS-25: tweede hand-gerolde kopie — nu dezelfde DS-component als de
    // paywall, inclusief hover, ←/→ en de selected-trait.
    private var segmented: some View {
        HStack(spacing: 0) {
            DSSegmentedControl(
                selection: $tab,
                segments: Tab.allCases.map { .init(tag: $0, label: $0.rawValue.capitalized) }
            )
            Spacer()
        }
    }

    // MARK: - Backgrounds-tab (echt)

    private var backgroundsTab: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            sectionHeader("Your uploads") {
                HStack(spacing: DSSpacing.gap2) {
                    if BackgroundGenerationCatalog.hasGenerationPath {
                        DSNeutralButton("Generate", icon: Image(systemName: "sparkles")) {
                            openGenerate()
                        }
                        .cloudFeatureMuted()
                    }
                    DSNeutralButton("Upload", icon: Image(systemName: "arrow.up.doc")) { upload() }
                }
            }
            if imageKit.imageIDs.isEmpty {
                hint("No uploads yet. Add an image to reuse it as a background.")
            } else {
                LazyVGrid(columns: columns, spacing: DSSpacing.gap3) {
                    ForEach(imageKit.imageIDs, id: \.self) { id in
                        if let image = imageKit.image(for: id) {
                            swatch {
                                Image(nsImage: image).resizable().scaledToFill()
                            } onDelete: {
                                imageKit.remove(id)
                            }
                        }
                    }
                }
            }

            sectionHeader("Brand colors", trailing: { EmptyView() })
            if colorKit.hexColors.isEmpty {
                hint("Brand colors you pick with the eyedropper appear here.")
            } else {
                LazyVGrid(columns: columns, spacing: DSSpacing.gap3) {
                    ForEach(colorKit.hexColors, id: \.self) { hex in
                        swatch {
                            (Color(hexRGB: hex) ?? .gray)
                        } onDelete: {
                            colorKit.remove(hex)
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.gap5)
    }

    // MARK: - Effects-tab (placeholder)

    private var effectsTab: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            sectionHeader("Saved effects") { EmptyView() }
            VStack(spacing: DSSpacing.gap2) {
                Image(systemName: "sparkles")
                    .font(.system(size: DSIconSize.xxl, weight: .light))
                    .foregroundStyle(DSColor.Foreground.muted)
                Text("Your saved effects will live here")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.subtle)
                Text("Effects are still managed in the editor for now. Saving your own presets is coming soon.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.gap8)
            // Placeholder-tegels die de toekomstige plek tonen.
            LazyVGrid(columns: columns, spacing: DSSpacing.gap3) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .fill(DSColor.Background.inset)
                        .frame(width: 84, height: 84)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: DSIconSize.lg, weight: .regular))
                                .foregroundStyle(DSColor.Foreground.muted)
                        )
                }
            }
            .opacity(DSOpacity.subtle)
        }
        .padding(DSSpacing.gap5)
    }

    // MARK: - Bouwstenen

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).dsTextStyle(.labelLarge).foregroundStyle(DSColor.Foreground.primary)
            Spacer()
            trailing()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.muted)
    }

    private func swatch<Content: View>(@ViewBuilder content: () -> Content, onDelete: @escaping () -> Void) -> some View {
        content()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            )
            .overlay(alignment: .topTrailing) {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DSIconSize.lg))
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .dsFocusEffectDisabled()
            }
    }

    private func openGenerate() {
        presentGenerateBackground(
            context: .portrait,
            entitlement: entitlement,
            applyAfterSave: false,
            onSaved: { _ in }
        )
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) {
                imageKit.add(data)
            }
        }
    }
}
