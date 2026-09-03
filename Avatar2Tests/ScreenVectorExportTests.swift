// Vector-catalogus van de hoofdschermen en menu's (Figma-sync via SVG) —
// tegenhanger van AvatarUI's DSVectorCatalogExportTests. Rendert de echte
// ShellView met een gezaaide in-memory store (SmokeSeed) in elke scherm-
// staat naar een vector-PDF; `AvatarUI/scripts/export-screens.sh` draait dit
// en zet om naar SVG. Geen assert. Draait uitsluitend met:
//   TEST_RUNNER_SCREEN_VECTOR_DUMP_DIR=<map|TMP>
// ("TMP" = container-tempmap van de sandboxed test-host; pad staat in de log.)

import AppKit
import AvatarKit
import AvatarUI
import Combine
import SwiftData
import SwiftUI
import XCTest
@testable import Avatar2

@MainActor
final class ScreenVectorExportTests: XCTestCase {
    private var outDir: URL!
    private var written = 0
    /// Settings/About lezen de UpdateManager uit de environment; Sparkle mag
    /// in de test niet starten → no-op engine.
    private final class NoopEngine: UpdaterEngine {
        var automaticallyChecksForUpdates = false
        var canCheckForUpdates = false
        var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
        var lastUpdateCheckDate: Date? { nil }
        func start() throws {}
        func checkForUpdates() {}
    }
    private lazy var updates = UpdateManager(makeEngine: { _ in NoopEngine() })
    private let windowSize = CGSize(width: 1100, height: 760)

    func testDumpScreens() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREEN_VECTOR_DUMP_DIR"] else { throw XCTSkip("SCREEN_VECTOR_DUMP_DIR niet gezet") }
        let base = dir == "TMP" ? NSTemporaryDirectory() : dir
        outDir = URL(fileURLWithPath: base).appendingPathComponent("screen-vectors")
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let schema = Schema([Portrait2.self, Folder2.self, Banner2.self, BannerDoc.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        SmokeSeed.populate(context)
        let folders = try context.fetch(FetchDescriptor<Folder2>()).sorted { $0.name < $1.name }
        let portraits = try context.fetch(FetchDescriptor<Portrait2>()).sorted { $0.name < $1.name }
        XCTAssertFalse(portraits.isEmpty, "SmokeSeed leverde geen portretten")

        let entitlement = EntitlementModel(auth: AuthService.isolated())
        let model = ShellModel(entitlement: entitlement)
        model.modelContext = context
        model.restoreSelectionAtLaunch()
        await waitForCanvas(model)

        func shell(_ name: String, warm: Bool = false) async {
            // Grid-schermen: elke tegel rendert z'n thumbnail async (ThumbnailRenderer,
            // ~1s per tegel) → veel ruimer settelen dan de rest.
            await render(name, ShellView(entitlement: entitlement, model: model)
                .frame(width: windowSize.width, height: windowSize.height), container: container,
                settle: .seconds(warm ? 15 : 3))
        }

        // Home + Portraits
        model.showHome(); await shell("Home", warm: true)
        model.presentation.leftNavUserMenuOpen = true; await shell("Home__user-menu", warm: true)
        model.presentation.leftNavUserMenuOpen = false
        model.showPortraits(); await shell("Portraits__all", warm: true)
        if let folder = folders.first {
            model.showPortraits(folderID: folder.persistentModelID); await shell("Portraits__folder", warm: true)
        }
        model.showPortraits()
        model.selectedPortraitIDs = Set(portraits.prefix(3).map(\.persistentModelID))
        model.isSelectingPortraits = true
        await shell("Portraits__multi-select", warm: true)
        model.selectedPortraitIDs = []; model.isSelectingPortraits = false

        // Editor + panelen + canvas-menu's
        if let portrait = portraits.first {
            model.openPortrait(portrait)
            await waitForCanvas(model)
            await shell("Editor")
            for tool in EditorTool.allCases where tool != .images {
                model.presentation.editorActiveTool = tool
                await shell("Editor__panel-\(tool.rawValue)")
            }
            model.presentation.editorActiveTool = nil
            for menu in [CanvasToolbarMenu.frame, .background] {
                model.presentation.editorCanvasMenu = menu
                await shell("Editor__menu-\(menu)")
            }
            model.presentation.editorCanvasMenu = nil
            for chip in [ChipMenu.boost, .removeBackground] {
                model.presentation.editorActiveTool = .edit
                model.presentation.editorChipMenu = chip
                await shell("Editor__chip-\(chip)")
            }
            model.presentation.editorChipMenu = nil; model.presentation.editorActiveTool = nil
            model.isSidebarVisible = true; await shell("Editor__sidebar"); model.isSidebarVisible = false
            model.showSocialPreview(); await shell("SocialPreview", warm: true); model.isShowingSocialPreview = false
        }

        // Settings
        for page in SettingsPage.allCases {
            model.openSettings(page: page); await shell("Settings__\(page.rawValue)")
        }
        model.presentation.settingsThemeMenuOpen = true
        model.openSettings(page: .preferences); await shell("Settings__preferences-theme-menu")
        model.presentation.settingsThemeMenuOpen = false
        model.isShowingSettings = false
        model.showHome()

        // Losse sheets / flows
        if let portrait = portraits.first {
            await render("ExportSheet", ExportSheet(portraitID: portrait.persistentModelID, isPro: false, onClose: {}), container: container)
            await render("RenameSheet", RenameSheet(portrait: portrait), container: container)
        }
        await render("PaywallSheet", PaywallSheet(model: entitlement), container: container)
        await render("ManageBackgroundsSheet", ManageBackgroundsSheet(entitlement: entitlement), container: container)
        let onboarding = OnboardingModel(auth: AuthService.isolated(), defaults: UserDefaults(suiteName: "screen-vector-export")!)
        for step in [OnboardingModel.Step.splash, .email, .otp, .privacy, .download] {
            onboarding.debugForce(step: step)
            await render("Onboarding__\(step)", OnboardingFlow(model: onboarding, entitlement: entitlement)
                .frame(width: windowSize.width, height: windowSize.height), container: container)
        }
        await render("Board", BoardView(model: model, entitlement: entitlement, onOpen: { _ in })
            .frame(width: windowSize.width, height: windowSize.height), container: container)

        // Menu's (zweven in de app in een child window → hier los gerenderd)
        if let portrait = portraits.first {
            await render("Menu__portrait-context", PortraitDSContextMenu(
                portrait: portrait, model: model, entitlement: entitlement, folders: folders,
                selectedTargets: { [portrait] }, modelContext: context, undoManager: nil,
                onDismiss: {}, onRequestDelete: { _ in }, onRequestNewFolder: { _ in }, onRequestSetBackground: { _ in }
            ), container: container)
            await render("Menu__portrait-edit-submenu", DSContextMenuPanel(minWidth: 220) {
                PortraitEditSubmenu(targets: [portrait], model: model, entitlement: entitlement, undoManager: nil, onDismiss: {})
            }, container: container)
        }
        if let folder = folders.first {
            let items = portraits.filter { $0.folder?.persistentModelID == folder.persistentModelID }
            await render("Menu__folder-context", FolderDSContextMenu(
                folder: folder, items: items, folders: folders, model: model,
                modelContext: context, undoManager: nil, onDismiss: {}
            ), container: container)
        }
        print("SCREEN_VECTOR_DUMP: \(written) bestanden in \(outDir.path)")
    }




    /// Tijdelijke probe: tegel-thumbnail in export-modus.
    func testTileProbe() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SCREEN_VECTOR_DUMP_DIR"] else { throw XCTSkip("SCREEN_VECTOR_DUMP_DIR niet gezet") }
        let base = dir == "TMP" ? NSTemporaryDirectory() : dir
        outDir = URL(fileURLWithPath: base).appendingPathComponent("probes")
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let schema = Schema([Portrait2.self, Folder2.self, Banner2.self, BannerDoc.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        SmokeSeed.populate(container.mainContext)
        let portraits = try container.mainContext.fetch(FetchDescriptor<Portrait2>()).sorted { $0.name < $1.name }
        let p = portraits[0]
        let spec = PortraitThumbnailRenderer.Spec(
            cutoutData: p.cutoutData, originalData: p.effectBackgroundData ?? p.originalData,
            backgroundImageData: p.backgroundImageData, backgroundColorHex: p.backgroundColorHex,
            useOriginalBackground: p.useOriginalBackground, portraitBlur: p.portraitBlur,
            offsetX: p.offsetX, offsetY: p.offsetY, scale: p.scale,
            exposure: p.adjustExposure, contrast: p.adjustContrast,
            saturation: p.adjustSaturation, temperature: p.adjustTemperature, side: 200)
        let cg = PortraitThumbnailRenderer.render(spec)
        print("TILEPROBE render200 = \(cg.map { "\($0.width)x\($0.height)" } ?? "nil")")
        await render("T1-composite", PortraitComposite(portrait: p, maxDimension: 200).frame(width: 200, height: 200), container: container, settle: .seconds(0.5))
        await render("T2-measured", PortraitCompositeMeasured(portrait: p).frame(width: 200, height: 200), container: container, settle: .seconds(0.5))
        print("SCREEN_VECTOR_DUMP: \(written) bestanden in \(outDir.path)")
    }

    // MARK: - Helpers

    private func waitForCanvas(_ model: ShellModel, timeout: Duration = .seconds(10)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if case .result = model.canvas { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Eerst een raster-render zodat de view-boom bestaat en async werk
    /// (thumbnails, previews, @Query) kan landen; daarna de vector-render.
    private func render(_ name: String, _ view: some View, container: ModelContainer, settle: Duration = .seconds(2)) async {
        let content = view
            .modelContainer(container)
            .environment(updates)
            .environment(\.colorScheme, .dark)
            .dsVectorExport()
        let renderer = ImageRenderer(content: content)
        _ = renderer.cgImage
        try? await Task.sleep(for: settle)
        let url = outDir.appendingPathComponent("\(name)-dark.pdf")
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        written += 1
    }
}
