import SwiftUI
import UniformTypeIdentifiers
import AppKit

private let dropZoneBlue = Color.appBrand

struct ImportDropZone: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
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
            // Flat brand-blue tint that appears only while a drag is over the
            // zone. Opacity over the dark background reads as a lighter,
            // dark-mode-friendly shade without any glow or border chrome.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dropZoneBlue.opacity(hovering ? 0.18 : 0))
                .padding(40)
                .animation(.easeOut(duration: 0.18), value: hovering)
        )
        .onDrop(of: [.fileURL, .image], isTargeted: $hovering) { providers in
            PortraitDropHandler.handle(providers: providers,
                                       context: context,
                                       appState: appState)
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
        .animation(.easeOut(duration: 0.20), value: appState.errorBanner)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let allowed = FreeTierGate.allowedImportCount(requested: panel.urls.count,
                                                      appState: appState)
        guard allowed > 0 else { return }
        // Random subset when the picker selection exceeds the remaining
        // free allowance — mirrors the drag-drop batch behaviour in
        // `PortraitDropHandler.handle`.
        for url in panel.urls.shuffled().prefix(allowed) {
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

