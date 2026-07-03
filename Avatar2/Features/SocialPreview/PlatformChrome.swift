// Platform-chrome skeleton (E34.4). Een code-getekend, minimalistisch wireframe
// dat nét genoeg LinkedIn / X / Instagram leest — zónder ruis. Alléén het
// onderwerp (de profielfoto) is scherp en in kleur; al het andere is vlak,
// neutraal grijs (DS-tokens, auto-theming). De avatar-plek per platform komt uit
// `SocialPlatform`-geometrie zodat preview en cover-export gelijk lopen.
//
// Klik op avatar of banner opent kiezer-panelen in de parent (E34 follow-up).

import AvatarUI
import SwiftUI

struct PlatformChrome<Banner: View, Avatar: View>: View {
    let platform: SocialPlatform
    var width: CGFloat
    var coordinateSpace: CoordinateSpace = .local
    var onAvatarTap: ((CGRect) -> Void)?
    var onBannerTap: ((CGRect) -> Void)?
    @ViewBuilder var banner: () -> Banner
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
        let bandH = width / 4
        let d = bandH * (platform.profileDiameterFraction ?? 0.62)
        let pad = width * 0.05
        return VStack(alignment: .leading, spacing: 0) {
            navBar(Image("LinkedInLogo"))
            coverBand(height: bandH, avatarDiameter: d)
            VStack(alignment: .leading, spacing: pad * 0.5) {
                Color.clear.frame(height: d / 2 - pad * 0.5)
                skel(width * 0.46, width * 0.032)
                skel(width * 0.30, width * 0.024)
                skel(width * 0.20, width * 0.022)
                pill(width * 0.20, width * 0.05)
                Color.clear.frame(height: pad * 0.5)
                feedCard(height: width * 0.16)
            }
            .padding(.horizontal, pad)
            .padding(.bottom, pad)
        }
    }

    // MARK: X — cover 3:1, avatar linksonder (half onder de band), tweets

    private var xChrome: some View {
        let bandH = width / 3
        let d = bandH * (platform.profileDiameterFraction ?? 0.56)
        let pad = width * 0.05
        return VStack(alignment: .leading, spacing: 0) {
            navBar(Image("XLogo"))
            coverBand(height: bandH, avatarDiameter: d)
            VStack(alignment: .leading, spacing: pad * 0.5) {
                HStack(alignment: .top) {
                    Color.clear.frame(height: d / 2 - pad * 0.5)
                    Spacer()
                    pill(width * 0.18, width * 0.05)
                }
                skel(width * 0.32, width * 0.032)
                skel(width * 0.22, width * 0.024)
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
            navBar(Image("InstagramLogo"))

            HStack(spacing: pad) {
                tappableAvatar(diameter: d)
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
                skel(width * 0.4, width * 0.022)
                skel(width * 0.28, width * 0.022)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, pad)

            grid()
        }
        .padding(.bottom, pad)
    }

    // MARK: - Building blocks

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

    private func coverBand(height bandH: CGFloat, avatarDiameter d: CGFloat) -> some View {
        let center = platform.profileCenterInCover ?? UnitPoint(x: 0.14, y: 1.0)
        return ZStack(alignment: .topLeading) {
            banner()
                .frame(width: width, height: bandH)
                .clipped()
                .contentShape(Rectangle())
                .previewTapTarget(
                    in: coordinateSpace,
                    enabled: onBannerTap != nil,
                    hoverShape: .rectangle
                ) { onBannerTap?($0) }

            ringedAvatar(diameter: d)
                .position(x: width * center.x, y: bandH * center.y)
                .zIndex(1)
        }
        .frame(width: width, height: bandH, alignment: .topLeading)
        .zIndex(1)
    }

    private func tappableAvatar(diameter d: CGFloat) -> some View {
        ringedAvatar(diameter: d)
            .previewTapTarget(
                in: coordinateSpace,
                enabled: onAvatarTap != nil
            ) { onAvatarTap?($0) }
    }

    private func ringedAvatar(diameter d: CGFloat) -> some View {
        avatar()
            .frame(width: d, height: d)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(DSColor.Background.card, lineWidth: max(2, d * 0.04)))
            .shadow(color: DSColor.Background.shadow.opacity(0.25), radius: d * 0.03, y: d * 0.01)
            .previewTapTarget(
                in: coordinateSpace,
                enabled: onAvatarTap != nil
            ) { onAvatarTap?($0) }
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
