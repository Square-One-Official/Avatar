import SwiftUI

/// Modal surface that announces a new feature. Shown over the main
/// window after sign-in completes (or after the welcome sheet, since
/// they share the same trigger). Contents are authored in the Payload
/// CMS — the macOS app only knows how to render them.
///
/// Layout mirrors `WelcomeSignInSheet`: ~440 wide, image-headlined,
/// single primary action plus a dismiss. Dismissal flows through
/// `AnnouncementService.dismiss(_:action:)` so the seen-state lands
/// server-side regardless of which path the user took (CTA, "Got it",
/// or window close).
struct AnnouncementSheet: View {
    let announcement: Announcement

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(AnnouncementService.self) private var service

    /// Disambiguates two close paths so we don't run the dismiss handler
    /// twice (once on the button, once on `.onDisappear`). Setting this
    /// before calling `dismiss()` lets the disappear hook see "already
    /// handled" and skip the redundant POST.
    @State private var didMarkSeen = false

    var body: some View {
        VStack(spacing: 0) {
            if let url = announcement.imageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.appSurface)
                            .overlay(ProgressView().controlSize(.small))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color.appSurface)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    @unknown default:
                        Rectangle().fill(Color.appSurface)
                    }
                }
                .frame(height: 220)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(announcement.title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !announcement.body.isEmpty {
                    Text(attributedBody)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 22)

            VStack(spacing: 10) {
                if let cta = announcement.cta {
                    Button {
                        openURL(cta.url)
                        Task { await markSeen(action: .ctaClicked) }
                        dismiss()
                    } label: {
                        Text(cta.label)
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appBrand)
                    .keyboardShortcut(.defaultAction)
                }

                Button {
                    Task { await markSeen(action: .dismissed) }
                    dismiss()
                } label: {
                    Text(announcement.cta == nil ? "Got it" : "Maybe later")
                        .font(.callout)
                        .foregroundStyle(announcement.cta == nil ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .onDisappear {
            // Belt-and-braces: if the user closed via the window
            // chrome (red traffic light), still mark seen.
            guard !didMarkSeen else { return }
            Task { await service.dismiss(announcement, action: .dismissed) }
        }
    }

    private func markSeen(action: AnnouncementService.DismissAction) async {
        didMarkSeen = true
        await service.dismiss(announcement, action: action)
    }

    /// Render the Markdown body into an AttributedString. Falls back to
    /// the raw string when parsing fails so the user always sees the
    /// content, even if formatting silently degrades.
    private var attributedBody: AttributedString {
        if let parsed = try? AttributedString(
            markdown: announcement.body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return parsed
        }
        return AttributedString(announcement.body)
    }
}
