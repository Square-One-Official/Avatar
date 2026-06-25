// Platform-chrome skeleton (E34.4). Een code-getekend, minimalistisch wireframe
// dat nét genoeg LinkedIn / X / Instagram leest — zónder ruis. Alléén het
// onderwerp (de profielfoto) is scherp en in kleur; al het andere is vlak,
// neutraal grijs (DS-tokens, auto-theming). De avatar-plek per platform komt uit
// `SocialPlatform`-geometrie zodat preview en cover-export gelijk lopen.
//
// Aesthetic skill: hiërarchie via realisme (niet via grootte) — het oog landt op
// de avatar-in-context. Terughoudendheid: simpele afgeronde blokken voor navbar,
// naam/headline, knoppen en een post/grid-zone; geen nep-tekst, logo's of foto's.

import AvatarUI
import PhosphorSwift
import SwiftUI

struct PlatformChrome<Banner: View, Avatar: View>: View {
    let platform: SocialPlatform
    /// Vaste kaartbreedte; alle geometrie wordt hieruit afgeleid (voorspelbaar in
    /// zowel de enkel-weergave als de "All"-grid).
    var width: CGFloat
    /// De cover/banner-laag (LinkedIn/X). Ongebruikt voor Instagram.
    @ViewBuilder var banner: () -> Banner
    /// De scherpe, ronde profielfoto (de parent levert het rauwe beeld; deze view
    /// clipt 'm rond + zet de platform-ring eromheen).
    @ViewBuilder var avatar: () -> Avatar

    var body: some View {
        Group {
            switch platform {
            case .linkedIn: linkedIn
            case .x: xChrome
            case .instagram: instagram
            }
        }
        .frame(width: width)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                .strokeBorder(DSColor.Foreground.divider, lineWidth: 1)
        )
    }

    // MARK: LinkedIn — cover 4:1, avatar linksonder, headline + feed-card

    private var linkedIn: some View {
        let bandH = width / 4                                  // 4:1
        let d = bandH * (platform.profileDiameterFraction ?? 0.62)
        let pad = width * 0.05
        return VStack(alignment: .leading, spacing: 0) {
            navBar(Ph.linkedinLogo.fill)
            coverBand(height: bandH, avatarDiameter: d)
            VStack(alignment: .leading, spacing: pad * 0.5) {
                Color.clear.frame(height: d / 2 - pad * 0.5)   // ruimte onder de overlappende avatar
                skel(width * 0.46, width * 0.032)              // naam
                skel(width * 0.30, width * 0.024)              // functie/headline
                skel(width * 0.20, width * 0.022)              // locatie
                pill(width * 0.20, width * 0.05)               // "Connect"-knop
                Color.clear.frame(height: pad * 0.5)
                feedCard(height: width * 0.16)                 // vage feed-kaart
            }
            .padding(.horizontal, pad)
            .padding(.bottom, pad)
        }
    }

    // MARK: X — cover 3:1, avatar linksonder (half onder de band), tweets

    private var xChrome: some View {
        let bandH = width / 3                                  // 3:1
        let d = bandH * (platform.profileDiameterFraction ?? 0.56)
        let pad = width * 0.05
        return VStack(alignment: .leading, spacing: 0) {
            navBar(Ph.xLogo.fill)
            coverBand(height: bandH, avatarDiameter: d)
            VStack(alignment: .leading, spacing: pad * 0.5) {
                HStack(alignment: .top) {
                    Color.clear.frame(height: d / 2 - pad * 0.5)
                    Spacer()
                    pill(width * 0.18, width * 0.05)           // "Follow"-knop rechtsboven
                }
                skel(width * 0.32, width * 0.032)              // naam
                skel(width * 0.22, width * 0.024)              // @handle
                Color.clear.frame(height: pad * 0.3)
                tweetRow()
                tweetRow()
            }
            .padding(.horizontal, pad)
            .padding(.bottom, pad)
        }
    }

    // MARK: Instagram — geen cover, gecentreerde avatar + stats + 3×3 grid

    private var instagram: some View {
        let pad = width * 0.05
        let d = width * 0.22
        return VStack(spacing: pad * 0.8) {
            navBar(Ph.instagramLogo.fill)

            HStack(spacing: pad) {
                ringedAvatar(diameter: d)
                // Stats: 3 kolommen (getal + label).
                HStack(spacing: pad) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: width * 0.012) {
                            skel(width * 0.10, width * 0.03)
                            skel(width * 0.12, width * 0.02)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, pad)

            VStack(alignment: .leading, spacing: width * 0.012) {
                skel(width * 0.4, width * 0.022)               // bio
                skel(width * 0.28, width * 0.022)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, pad)

            grid()                                             // 3×3 post-grid
        }
        .padding(.bottom, pad)
    }

    // MARK: - Building blocks

    /// Slanke platform-navbalk met het merk-logo (monochroom, subtiel) + een paar
    /// nav-stubs rechts — nét genoeg om het platform te herkennen, ruisvrij.
    private func navBar(_ logo: Image) -> some View {
        let h = width * 0.085
        return HStack(spacing: width * 0.02) {
            logo
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: h * 0.46)
                .foregroundStyle(DSColor.Foreground.subtle)
            Spacer()
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(DSColor.Background.neutralStronger)
                    .frame(width: h * 0.3, height: h * 0.3)
            }
        }
        .padding(.horizontal, width * 0.04)
        .frame(height: h)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cover-band met de banner-laag + de overlappende, geringde profielfoto
    /// linksonder (LinkedIn/X). De avatar valt half onder de band → géén clip.
    private func coverBand(height bandH: CGFloat, avatarDiameter d: CGFloat) -> some View {
        let center = platform.profileCenterInCover ?? UnitPoint(x: 0.14, y: 1.0)
        return banner()
            .frame(width: width, height: bandH)
            .clipped()
            .overlay(alignment: .topLeading) {
                ringedAvatar(diameter: d)
                    .position(x: width * center.x, y: bandH * center.y)
            }
            // De overlay mag onder de band uitsteken (avatar-overlap).
            .frame(width: width, height: bandH, alignment: .topLeading)
            .zIndex(1)
    }

    /// De scherpe, ronde profielfoto met een platform-ring (kaartkleur) eromheen.
    private func ringedAvatar(diameter d: CGFloat) -> some View {
        avatar()
            .frame(width: d, height: d)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DSColor.Background.card, lineWidth: max(2, d * 0.04)))
            .shadow(color: DSColor.Background.shadow.opacity(0.25), radius: d * 0.03, y: d * 0.01)
    }

    private func skel(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.full, style: .continuous)
            .fill(DSColor.Background.neutralStronger)
            .frame(width: w, height: max(3, h))
    }

    private func pill(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.full, style: .continuous)
            .fill(DSColor.Background.neutralStrongest)
            .frame(width: w, height: h)
    }

    private func feedCard(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .fill(DSColor.Background.inset)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private func tweetRow() -> some View {
        HStack(alignment: .top, spacing: width * 0.03) {
            Circle().fill(DSColor.Background.neutralStronger)
                .frame(width: width * 0.07, height: width * 0.07)
            VStack(alignment: .leading, spacing: width * 0.012) {
                skel(width * 0.5, width * 0.022)
                skel(width * 0.36, width * 0.022)
            }
            Spacer()
        }
        .padding(.top, width * 0.01)
    }

    private func grid() -> some View {
        let gap = width * 0.015
        let cell = (width - 2 * gap - width * 0.0) / 3
        return VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                            .fill(DSColor.Background.inset)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
}
