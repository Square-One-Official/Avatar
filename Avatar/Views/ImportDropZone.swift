import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

/// Brand periwinkle blue used throughout the import drop zone — cards, link,
/// banner title, and the dashed border dots.
private let dropZoneBlue = Color(red: 0x9A / 255.0, green: 0xB7 / 255.0, blue: 1.0)

struct ImportDropZone: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var portraits: [Portrait]
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 28) {
            CardStack()
                .frame(height: 168)

            VStack(spacing: 4) {
                Text(Loc.dropHere)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                Button(action: pickFiles) {
                    Text(Loc.orBrowseFiles)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(dropZoneBlue)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // Outer aura — softly bleeds past the dashed border so the
                // whole zone reads as "lit up" the moment a drag enters.
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(dropZoneBlue)
                    .blur(radius: 38)
                    .opacity(hovering ? 0.42 : 0)

                // Inner glaze — a barely-there blue wash inside the dashed
                // frame, gives the surface itself a hint of color.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(dropZoneBlue.opacity(hovering ? 0.07 : 0))

                // Dashed border — brightens to full opacity on target.
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(dropZoneBlue.opacity(hovering ? 1.0 : 0.55))
            }
            .padding(40)
            .animation(.easeOut(duration: 0.28), value: hovering)
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $hovering) { providers in
            PortraitDropHandler.handle(providers: providers,
                                       existingPortraitCount: portraits.count,
                                       context: context,
                                       appState: appState)
        }
        .overlay(alignment: .bottom) {
            if showsProUpsell {
                ProUpsellBanner()
                    .padding(.bottom, 72)
                    .padding(.horizontal, 56)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .overlay {
            if appState.isProcessing {
                ProcessingStatusView()
            }
            if let banner = appState.errorBanner {
                VStack {
                    Spacer()
                    StatusChip(severity: banner.severity,
                               message: banner.message,
                               onDismiss: { appState.dismissBanner() })
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsProUpsell)
        .animation(.easeOut(duration: 0.20), value: appState.errorBanner)
    }

    private var showsProUpsell: Bool {
        !appState.proEntitlement.isPro
            && !appState.isProcessing
            && appState.errorBanner == nil
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        guard FreeTierGate.allowImport(incoming: panel.urls.count,
                                       existingPortraitCount: portraits.count,
                                       appState: appState) else { return }
        for url in panel.urls {
            ImportFlow.importFile(url: url, context: context, appState: appState)
        }
    }
}

// MARK: - Card stack

private struct CardStack: View {
    @State private var hovering = false

    private let spread: CGFloat = 16

    var body: some View {
        ZStack {
            PortraitCard(size: CGSize(width: 102, height: 122), iconSize: 22)
                .rotationEffect(.degrees(hovering ? -14 : -10))
                .offset(x: -56 - (hovering ? spread : 0), y: 10)

            PortraitCard(size: CGSize(width: 102, height: 122), iconSize: 22)
                .rotationEffect(.degrees(hovering ? 14 : 10))
                .offset(x: 56 + (hovering ? spread : 0), y: 10)

            PortraitCard(size: CGSize(width: 110, height: 138), iconSize: 26)
        }
        .frame(width: 280, height: 168)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.55, bounce: 0.28), value: hovering)
    }
}

private struct PortraitCard: View {
    let size: CGSize
    let iconSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.appSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(dropZoneBlue)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Pro upsell banner

/// Shown at the bottom of the dropzone for free users. Two states:
///   1. Trial available — Magic Cutout title + "First N are on us · M left"
///      subtitle + a Toggle bound to `magicCutoutPrefs.enabled`. Lets the
///      user decide between burning a free Pro cutout vs. saving it for
///      later and using on-device Subject Lift.
///   2. Trial exhausted — same title, "Free trial used — Upgrade…"
///      subtitle, and the original green Upgrade pill that opens the
///      paywall sheet.
private struct ProUpsellBanner: View {
    @Environment(AppState.self) private var appState
    // Bound to the same UserDefaults key as `MagicCutoutPreferences.enabled`.
    // The prefs object's computed property isn't @Observable-tracked, so a
    // binding through it writes through but never re-renders the toggle.
    @AppStorage("magicCutoutEnabled") private var magicCutoutEnabled: Bool = true
    @State private var hovering = false

    private var proGreen: Color {
        Color(red: 0.20, green: 0.85, blue: 0.55)
    }

    private var trialRemaining: Int {
        appState.proEntitlement.freeCutoutsRemaining
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.dropZoneProTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dropZoneBlue)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailingControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.14 : 0.08))
        )
        .frame(maxWidth: 420)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var subtitle: String {
        trialRemaining > 0
            ? Loc.dropZoneProFreeRemaining(trialRemaining)
            : Loc.dropZoneProExhausted
    }

    @ViewBuilder
    private var trailingControl: some View {
        if trialRemaining > 0 {
            // @AppStorage writes the same UserDefaults key that
            // `MagicCutoutPreferences.enabled` reads, so import-flow gating
            // through `prefs.enabled` continues to see the right value.
            Toggle("", isOn: $magicCutoutEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(proGreen)
        } else {
            Button {
                appState.showProUpgradeSheet = true
            } label: {
                Text(Loc.dropZoneProUpgrade)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(proGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(proGreen.opacity(0.15))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(proGreen.opacity(0.30))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}
