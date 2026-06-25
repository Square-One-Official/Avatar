// PoC (left-nav): Home — het overzicht (Granola-stijl). Toont het laatst
// toegevoegde portret groot, met de eerdere eronder in een net rooster.
// Onderin een "Upload new portrait"-balk i.p.v. een ask-anything-veld. Bij een
// lege store toont Home onze bestaande first-use-empty-state (avatars) met een
// welkomsttekst erboven. Net-nieuw scherm — DS-tokens, in de geest van het
// hoofddesign.

import AvatarUI
import SwiftData
import SwiftUI

struct HomeView: View {
    let model: ShellModel
    let entitlement: EntitlementModel

    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]
    @State private var thumbs = ThumbnailStore()
    @State private var featuredHovering = false

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
        VStack(spacing: 0) {
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
                                PortraitGridTile(portrait: portrait, thumbs: thumbs, folders: folders, model: model) {
                                    model.openPortrait(portrait)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.gap6)
                .padding(.bottom, DSSpacing.gap6)
            }
            uploadBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Max-breedte van de featured-kaart — compacter dan de volledige
    /// vensterbreedte, maar iets groter dan voorheen (gebruikersfeedback).
    private let featuredMaxWidth: CGFloat = 420

    private func featured(_ portrait: Portrait2) -> some View {
        Button { model.openPortrait(portrait) } label: {
            // Zelfde robuuste vierkant als de grid-tegels: Color.clear bepaalt de
            // 1:1-maat, de compositie ligt eroverheen (anders dicteert de
            // achtergrond-afbeelding z'n eigen — tweemaal zo hoge — ratio).
            Color.clear
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
                            featuredHovering ? DSColor.Action.primary : DSColor.Foreground.divider,
                            lineWidth: featuredHovering ? DSBorderWidth.medium : DSBorderWidth.thin
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: featuredMaxWidth, alignment: .leading)
        .onHover { featuredHovering = $0 }
        .dsMotion(DSMotion.micro, value: featuredHovering)
    }

    private var uploadBar: some View {
        Button { model.presentOpenPanel() } label: {
            HStack(spacing: DSSpacing.gap3) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(DSColor.Foreground.subtle)
                Text("Upload a new portrait")
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.subtle)
                Spacer(minLength: 0)
                DSBadge("⌘U", type: .neutral)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: 56)
            .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous)
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("u", modifiers: .command)
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.bottom, DSSpacing.gap5)
    }
}
