// PoC (left-nav): Home — het overzicht (Granola-stijl). Toont het laatst
// toegevoegde portret groot, met de eerdere eronder in een net rooster.
// Onderin een "Upload new portrait"-balk i.p.v. een ask-anything-veld. Bij een
// lege store toont Home onze bestaande first-use-empty-state (avatars) met een
// welkomsttekst erboven. Net-nieuw scherm — DS-tokens, in de geest van het
// hoofddesign.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct HomeView: View {
    let model: ShellModel
    let entitlement: EntitlementModel

    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]
    // E36.3: banners als tweede sectie in het overzicht.
    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var bannerDocs: [BannerDoc]
    private var savedBanners: [BannerDoc] { bannerDocs.filter { $0.previewImageData != nil } }
    @State private var featuredHovering = false
    @State private var menuTarget: Portrait2?
    @State private var menuAnchor: CGRect = .zero

    // Vast 4-koloms rooster met duidelijke ruimte ertussen. De tegel zelf
    // (Color.clear + aspectRatio(.fit)) wordt nooit breder dan z'n kolom, dus
    // gewone flexibele kolommen volstaan nu — geen overloop, echte gaps.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.gap5), count: 4)

    var body: some View {
        if portraits.isEmpty {
            firstUse
        } else {
            overview
        }
    }

    // MARK: - First-use (lege store): welkom + bestaande empty-state

    private var firstUse: some View {
        VStack(spacing: DSSpacing.gap5) {
            VStack(spacing: DSSpacing.gap2) {
                Text("Welcome to Aaavatar")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("Drop a photo or upload one to make your first portrait.")
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DSSpacing.gap8)
            FirstUseEmptyState(onChooseFile: { model.presentOpenPanel() }, entitlement: entitlement)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overzicht (niet-lege store)

    private var overview: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.gap5) {
                    Text("Recent")
                        .dsTextStyle(.h3)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .padding(.top, DSSpacing.gap6)

                    if let latest = portraits.first {
                        featured(latest)
                    }

                    if portraits.count > 1 {
                        Text("Earlier")
                            .dsTextStyle(.labelLarge)
                            .foregroundStyle(DSColor.Foreground.subtle)
                        LazyVGrid(columns: columns, spacing: DSSpacing.gap5) {
                            ForEach(Array(portraits.dropFirst())) { portrait in
                                PortraitGridTile(
                                    portrait: portrait, folders: folders, model: model,
                                    isSelected: model.isPortraitSelected(portrait),
                                    ordered: { portraits.map(\.persistentModelID) },
                                    selectedTargets: { portraits.filter { model.isPortraitSelected($0) } },
                                    onContextMenu: { frame in
                                        model.preparePortraitContextMenu(on: portrait)
                                        menuTarget = portrait
                                        menuAnchor = frame
                                    }
                                )
                            }
                        }
                    }

                    bannersSection
                }
                .padding(.horizontal, DSSpacing.gap6)
                // Extra bottom padding so last row isn't hidden behind the floating button.
                .padding(.bottom, 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            uploadBar
                .padding(.bottom, DSSpacing.gap5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: PortraitContextMenuSpace.name)
        .portraitContextMenuOverlay(
            target: $menuTarget,
            anchor: menuAnchor,
            model: model,
            folders: folders,
            selectedTargets: { portraits.filter { model.isPortraitSelected($0) } }
        )
    }

    // MARK: - Banners-sectie (E36.3)

    @ViewBuilder private var bannersSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            HStack {
                Text("Banners")
                    .dsTextStyle(.labelLarge)
                    .foregroundStyle(DSColor.Foreground.subtle)
                Spacer()
                Button { model.showBanners() } label: {
                    Text("See all").dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, DSSpacing.gap2)

            if savedBanners.isEmpty {
                Button { model.showBanners() } label: {
                    RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                        .strokeBorder(DSColor.Foreground.divider, style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .frame(height: 64)
                        .overlay {
                            HStack(spacing: DSSpacing.gap2) {
                                Image(systemName: "plus")
                                Text("Make a banner").dsTextStyle(.labelBase)
                            }
                            .foregroundStyle(DSColor.Foreground.muted)
                        }
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap4) {
                        ForEach(savedBanners.prefix(8)) { doc in
                            homeBannerCard(doc)
                        }
                    }
                    .padding(.bottom, DSSpacing.gap1)
                }
            }
        }
    }

    private func homeBannerCard(_ doc: BannerDoc) -> some View {
        Button { model.openBannerStudio(doc) } label: {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                ZStack {
                    DSColor.Background.inset
                    if let data = doc.previewImageData, let img = NSImage(data: data) {
                        Image(nsImage: img).resizable().scaledToFill()
                    }
                }
                .frame(width: 240, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                )
                Text(doc.name.isEmpty ? "Untitled banner" : doc.name)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .dsHoverScale(1.02)
    }

    /// Max-breedte van de featured-kaart — compacter dan de volledige
    /// vensterbreedte, maar iets groter dan voorheen (gebruikersfeedback).
    private let featuredMaxWidth: CGFloat = 420

    private func featured(_ portrait: Portrait2) -> some View {
        let isSelected = model.isPortraitSelected(portrait)
        // Zelfde robuuste vierkant als de grid-tegels: Color.clear bepaalt de
        // 1:1-maat, de compositie ligt eroverheen (anders dicteert de
        // achtergrond-afbeelding z'n eigen — tweemaal zo hoge — ratio).
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    PortraitComposite(portrait: portrait, maxDimension: 600)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center, endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                            .dsTextStyle(.labelLarge).foregroundStyle(.white).lineLimit(1)
                        if !portrait.role.isEmpty {
                            Text(portrait.role).dsTextStyle(.labelSmall).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                        }
                    }
                    .padding(DSSpacing.gap4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous)
                    .strokeBorder(
                        (isSelected || featuredHovering) ? DSColor.Action.primary : DSColor.Foreground.divider,
                        lineWidth: (isSelected || featuredHovering) ? DSBorderWidth.medium : DSBorderWidth.thin
                    )
            )
            // Selectie-vinkje (Finder-stijl) rechtsboven.
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DSColor.Background.app, DSColor.Action.primary)
                        .padding(DSSpacing.gap3)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: featuredMaxWidth, alignment: .leading)
            .onHover { featuredHovering = $0 }
            .dsMotion(DSMotion.micro, value: featuredHovering)
            .dsMotion(DSMotion.micro, value: isSelected)
            // Plain klik = openen; ⌘/⇧ = multi-select (gedeeld via ShellModel).
            .onTapGesture {
                model.handlePortraitClick(portrait, ordered: portraits.map(\.persistentModelID), mods: NSApp.currentEvent?.modifierFlags ?? [])
            }
            .contextMenuTrigger(in: PortraitContextMenuSpace.coordinateSpace) { frame in
                model.preparePortraitContextMenu(on: portrait)
                menuTarget = portrait
                menuAnchor = frame
            }
            // Ook de uitgelichte Recent-kaart is naar een map sleepbaar.
            .draggable(PortraitDragItem(id: portrait.persistentModelID))
    }

    private var uploadBar: some View {
        Button { model.presentOpenPanel() } label: {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(DSColor.Foreground.subtle)
                Text("Upload portrait")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.subtle)
                DSBadge("⌘U", type: .neutral)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: 44)
            .background(DSColor.Background.card, in: Capsule())
            .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("u", modifiers: .command)
    }
}
