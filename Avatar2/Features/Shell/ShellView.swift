// Main shell-wortel (E05). 5.1 = first-use-empty-state, 5.2 = import
// (drag-drop over het hele venster + bestandskiezer → PipelineRouter).
// E04.5-fix (bevindingen 2/3/6): tijdens een drag vervangt de Figma-
// dropzone de first-use-inhoud (gedrag: heel venster blijft droptarget);
// de status-pill hangt op vensterniveau rechtsonder (positie uit de
// frames); de Name/Role-header staat in de flow bóven de canvas-kaart —
// nooit over de foto.

import AvatarUI
import SwiftUI
import UniformTypeIdentifiers

struct ShellView: View {
    let entitlement: EntitlementModel
    @State private var model: ShellModel

    init(entitlement: EntitlementModel) {
        self.entitlement = entitlement
        _model = State(initialValue: ShellModel(entitlement: entitlement))
    }

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // Sidebar (E05.4) schuift rechts in; het canvas centreert mee in de
        // resterende ruimte (één spring, geen layoutshift).
        HStack(spacing: 0) {
            mainArea
            if model.isSidebarVisible {
                SidebarView(
                    selectedID: model.selectedPortrait?.persistentModelID,
                    onSelect: { model.select($0) },
                    onAdd: { model.presentOpenPanel() }
                )
                // Losstaande kaart met marge rondom (bevinding 8; frame-
                // inzet 4) — zelfde inset waarmee de kaartradius
                // concentrisch rekent (bevinding 17).
                .padding(SidebarView.edgeInset)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(duration: 0.35), value: model.isSidebarVisible)
        .background(DSColor.Background.app)
        .preferredColorScheme(.dark)
        .task {
            model.modelContext = modelContext
            // Punt 13: niet-lege store → laatst bewerkte/geselecteerde
            // portret direct op canvas; first-use alleen bij écht leeg.
            model.restoreSelectionAtLaunch()
            #if DEBUG
            // Smoke-run-haak: `--show-settings [pagina]` wordt in
            // ShellModel.init gelezen (vóór first render, geen venster-race);
            // zie de toelichting daar. Compiled out of Release.
            let args = ProcessInfo.processInfo.arguments
            // E04.7/E07.1: `--open-panel <tool>` wordt door EditorView zelf
            // uit de proces-argumenten gelezen (geen race).
            // E05.6: `--force-hair-nudge` toont de nudge voor de smoke.
            if args.contains("--force-hair-nudge") { model.debugForceHairNudge() }
            // E05.7: `--seed-set` dupliceert het portret en opent de sidebar.
            if args.contains("--seed-set") { model.debugSeedSecondPortraitAndOpenSidebar() }
            // E08.2: `--export-png <pad> [pro]` schrijft de export-PNG van het
            // huidige portret weg voor visuele verificatie (free = watermerk).
            if let i = args.firstIndex(of: "--export-png"), args.indices.contains(i + 1),
               let portrait = model.selectedPortrait {
                let pro = args.contains("pro")
                // Sandbox: schrijf in de container-tmp en log het pad.
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(URL(fileURLWithPath: args[i + 1]).lastPathComponent)
                if let data = PortraitExporter.makePNG(for: portrait, watermark: !pro) {
                    try? data.write(to: url)
                    NSLog("EXPORT_PNG_WRITTEN \(url.path)")
                }
            }
            #endif
        }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            if model.isShowingSettings {
                // Punt 14: Settings vervangt de canvas-weergave binnen het
                // hoofdvenster; topbar (quota + gear) blijft als overlay
                // staan. Esc sluit (verborgen cancel-knop, werkt
                // venster-breed); de gear toggelt.
                SettingsRootView(entitlement: entitlement)
                    .background(
                        Button("") { model.isShowingSettings = false }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .accessibilityHidden(true)
                    )
            } else {
                // Header in de flow, los bóven de kaart (bevinding 6) —
                // Figma Frame 2: y=32, kaart begint op 108.
                if showsPortraitHeader {
                    PortraitHeader(model: model)
                        .padding(.top, DSSpacing.gap8)
                }
                canvas
            }
        }
        // Punt 19: top-uitlijning — de VStack centreerde verticaal,
        // waardoor de kaart bij lage vensters onder de quota-rij kroop;
        // header hoort vast bovenaan (Figma y=32), de foto is het enige
        // flexibele element.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Heel het venster is droptarget (Fitts, review-besluit); de
        // Figma-dropzone (App / Dropzone, 4017:1622) is puur visueel.
        .onDrop(of: [.fileURL, .image], isTargeted: $model.isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            // Geen dropzone bovenop Settings (punt 14): de drop zelf wordt
            // in handleDrop genegeerd zolang Settings open staat.
            if model.isDropTargeted && !model.isShowingSettings {
                DropzoneOverlay()
                    .allowsHitTesting(false)
            }
        }
        // Topbar (E04.5): quota + Upgrade links, gear rechts — 1-op-1
        // de "top"-strook uit de App-frames. De gear toggelt de in-window
        // Settings (punt 14) en toont de active-state zolang die open is.
        .overlay(alignment: .top) {
            ShellTopBar(
                model: entitlement,
                isSettingsActive: model.isShowingSettings,
                onToggleSettings: { model.isShowingSettings.toggle() },
                canExport: model.canExport && !model.isShowingSettings,
                onExport: { model.exportCurrentPortrait() }
            )
        }
        // Status-pill op vensterniveau (bevinding 3): de frames zetten
        // hem rechtsonder in het venster (Isolating 4017:1862 x816–988,
        // Image added 4017:1849), niet aan de foto geplakt.
        .overlay(alignment: .bottomTrailing) {
            if let label = isolatingStatusLabel {
                IsolatingStatusPill(label: label)
                    .padding(DSSpacing.gap4)
            }
        }
        // E05.6: eenmalige hifi-haar-nudge — subtiel onderin, geen modal.
        .overlay(alignment: .bottom) {
            if model.showHairNudge && !model.isShowingSettings {
                HairNudgeBanner(
                    onDownload: { model.acceptHairNudge() },
                    onDismiss: { model.dismissHairNudge() }
                )
                .padding(.bottom, DSSpacing.gap4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.showHairNudge)
        .animation(.easeOut(duration: 0.15), value: model.isDropTargeted)
    }

    private var showsPortraitHeader: Bool {
        switch model.canvas {
        case .processing, .revealing, .result: true
        case .empty, .failed: false
        }
    }

    private var isolatingStatusLabel: String? {
        switch model.canvas {
        case .processing: "Removing background..."
        case .revealing: "Cutting out hair..."
        default: nil
        }
    }

    @ViewBuilder
    private var canvas: some View {
        switch model.canvas {
        case .empty:
            // Tijdens een drag verdwijnt de first-use-inhoud en blijft
            // alleen de dropzone over (bevinding 2).
            if model.isDropTargeted {
                DSColor.Background.app
            } else {
                FirstUseEmptyState {
                    model.presentOpenPanel()
                }
            }
        case .processing(let original):
            IsolatingCanvas(original: original, cutout: nil)
        case .revealing(let original, let cutout):
            IsolatingCanvas(original: original, cutout: cutout)
        case .result(let cutout):
            // Editor-framework (E06.1): toolbar + panel-systeem rond het
            // resultaat; foto-verkleining regelt de DS-container centraal.
            // Images-tool toggelt de sidebar (E05.4).
            EditorView(
                portrait: cutout,
                portraitModel: model.selectedPortrait,
                entitlement: entitlement,
                onApplyResult: { model.applyEffectResult($0) },
                isSidebarVisible: $model.isSidebarVisible
            )
        case .failed(let message):
            VStack(spacing: DSSpacing.gap4) {
                Text(message)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .multilineTextAlignment(.center)
                DSNeutralButton("Choose another file…") {
                    model.presentOpenPanel()
                }
            }
            .padding(DSSpacing.gap8)
        }
    }

    /// Figma App / Dropzone (4017:1622): Frame 11 465×456 gecentreerd,
    /// r-4xl, dashed b-medium in lime, vulling lime ~5% (gesampled — het
    /// frame exposeert er geen variabele voor), "Drop it" in H3 primary.
    private struct DropzoneOverlay: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.xl4)
                    .fill(DSColor.Action.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: DSRadius.xl4)
                    .strokeBorder(
                        DSColor.Action.primary,
                        style: StrokeStyle(lineWidth: DSBorderWidth.medium, dash: [2, 4])
                    )
                Text("Drop it")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
            }
            .frame(width: 465, height: 456)
        }
    }

    private func portrait(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(DSSpacing.gap8)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Punt 14: tijdens Settings geen imports — de canvas-weergave is
        // niet zichtbaar, een stille import zou verwarren.
        guard !model.isShowingSettings else { return false }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    await model.importImage(from: url)
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    await model.importImage(data: data)
                }
            }
            return true
        }
        return false
    }
}
