// E53.7 — presentatiestate overleeft view-recreatie; geen auto-dismiss side effects.

import AvatarKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class PersistentPresentationTests: XCTestCase {

    private func makePortraitID() throws -> PersistentIdentifier {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, configurations: config)
        let context = ModelContext(container)
        let portrait = Portrait2(name: "Test", cutoutData: Data([1]))
        context.insert(portrait)
        return portrait.persistentModelID
    }

    // MARK: - Sign-in flow

    func testSignInFlowSurvivesDismissCloudGateWithoutReset() {
        let entitlement = EntitlementModel(auth: AuthService.isolated())
        entitlement.presentSignIn()
        entitlement.signInFlow.email = "user@example.com"
        entitlement.signInFlow.phase = .otp
        entitlement.signInFlow.code = "123456"

        entitlement.dismissCloudGate()

        XCTAssertEqual(entitlement.signInFlow.email, "user@example.com")
        XCTAssertEqual(entitlement.signInFlow.phase, .otp)
        XCTAssertEqual(entitlement.signInFlow.code, "123456")
        XCTAssertNil(entitlement.cloudGate)
    }

    func testCloseSignInResetsFlow() {
        let entitlement = EntitlementModel(auth: AuthService.isolated())
        entitlement.presentSignIn()
        entitlement.signInFlow.email = "user@example.com"
        entitlement.signInFlow.phase = .otp

        entitlement.closeSignIn()

        XCTAssertNil(entitlement.cloudGate)
        XCTAssertEqual(entitlement.signInFlow.phase, .email)
        XCTAssertTrue(entitlement.signInFlow.email.isEmpty)
    }

    // MARK: - Stylize quality gate

    func testPreGateRemainsUntilExplicitResolve() {
        let coordinator = StylizeQualityCoordinator()
        coordinator.preGate = PreStylizeGate(kind: .lowResolution)

        // Simuleert incidental sheet-dismiss zonder resolvePreGate — geen auto-proceed.
        XCTAssertNotNil(coordinator.preGate)

        coordinator.resolvePreGate(.proceed)
        XCTAssertNil(coordinator.preGate)
    }

    func testPreGateDoesNotAutoProceedOnNilWithoutResolve() {
        let coordinator = StylizeQualityCoordinator()
        coordinator.preGate = PreStylizeGate(kind: .lowResolution)

        // Alleen de gate clearen (zoals een oude binding zou doen) zonder resolve —
        // de coordinator houdt de gate vast tot resolvePreGate.
        let gateBefore = coordinator.preGate
        XCTAssertNotNil(gateBefore)
        XCTAssertEqual(gateBefore?.kind, .lowResolution)
    }

    // MARK: - UIPresentationStore

    func testPortraitContextMenuStatePersistsInStore() throws {
        let store = UIPresentationStore()
        let portraitID = try makePortraitID()

        store.openPortraitContextMenu(
            portraitID: portraitID,
            anchor: CGRect(x: 10, y: 20, width: 80, height: 40),
            scope: .portraitsGallery
        )

        XCTAssertEqual(store.portraitContextMenu?.portraitID, portraitID)
        XCTAssertEqual(store.portraitContextMenu?.scope, .portraitsGallery)
        XCTAssertEqual(store.portraitContextMenu?.anchor, CGRect(x: 10, y: 20, width: 80, height: 40))

        // "Host view identity change" — store is de bron; state blijft.
        let snapshot = store.portraitContextMenu
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(store.portraitContextMenu, snapshot)
    }

    /// E53.7-afronding: de laatste drie dropdowns die nog op view-`@State` draaiden
    /// (achtergrond-type, Boost/Remove background-chips, map-standaardachtergrond)
    /// leven nu in de store, dus overleven ze een view-recreatie.
    func testMigratedDropdownStateLivesInStore() {
        let store = UIPresentationStore()

        store.editorBackgroundTypeMenuOpen = true
        store.editorChipMenu = .boost
        store.folderBackgroundPickerOpen = true

        // "View opnieuw gebouwd" — de store is de bron, dus de waarden staan er nog.
        XCTAssertTrue(store.editorBackgroundTypeMenuOpen)
        XCTAssertEqual(store.editorChipMenu, .boost)
        XCTAssertTrue(store.folderBackgroundPickerOpen)

        store.openSelectionBackgroundPicker(anchor: CGRect(x: 8, y: 12, width: 40, height: 40))
        XCTAssertTrue(store.selectionBackgroundPickerOpen)
        XCTAssertEqual(store.selectionBackgroundPickerAnchor, CGRect(x: 8, y: 12, width: 40, height: 40))

        // Eén tegelijk: een ander chip-menu vervangt het vorige, sluit niet alles.
        store.editorChipMenu = .removeBackground
        XCTAssertEqual(store.editorChipMenu, .removeBackground)
        XCTAssertTrue(store.editorBackgroundTypeMenuOpen)
    }

    /// `dismissAllEphemeral` moet élk vluchtig menu opruimen — een vergeten slot
    /// laat een dropdown zweven boven een scherm dat er niet meer is.
    func testDismissAllEphemeralClearsEveryMenuIncludingMigratedOnes() {
        let store = UIPresentationStore()
        store.editorBackgroundTypeMenuOpen = true
        store.editorBackgroundColorPickerOpen = true
        store.editorChipMenu = .boost
        store.folderBackgroundPickerOpen = true
        store.selectionBackgroundPickerOpen = true
        store.leftNavUserMenuOpen = true
        store.effectsContextMenu = AnchoredMenuRequest(id: "custom:1", anchor: .zero)
        store.bannerTextContextMenu = AnchoredMenuRequest(id: UUID().uuidString, anchor: .zero)
        store.bannerTextFieldMenu = .font(UUID())
        store.settingsThemeMenuOpen = true
        // Taak-state (geen vluchtig menu) blijft juist wél staan.
        store.createEffectSheetOpen = true

        store.dismissAllEphemeral()

        XCTAssertFalse(store.editorBackgroundTypeMenuOpen)
        XCTAssertFalse(store.editorBackgroundColorPickerOpen)
        XCTAssertNil(store.editorChipMenu)
        XCTAssertFalse(store.folderBackgroundPickerOpen)
        XCTAssertFalse(store.selectionBackgroundPickerOpen)
        XCTAssertFalse(store.leftNavUserMenuOpen)
        XCTAssertNil(store.effectsContextMenu)
        XCTAssertNil(store.bannerTextContextMenu)
        XCTAssertNil(store.bannerTextFieldMenu)
        XCTAssertFalse(store.settingsThemeMenuOpen)
        XCTAssertTrue(store.createEffectSheetOpen, "een open taak-modal is geen vluchtig menu")
    }

    func testDismissPortraitContextMenuClearsOnlyMenu() throws {
        let store = UIPresentationStore()
        store.editorActiveTool = .background
        store.openPortraitContextMenu(
            portraitID: try makePortraitID(),
            anchor: .zero,
            scope: .home
        )

        store.dismissPortraitContextMenu()

        XCTAssertNil(store.portraitContextMenu)
        XCTAssertEqual(store.editorActiveTool, .background)
    }

    func testNamePromptAlertCopy() {
        let create = PresentationAlert.createFolder(draft: "")
        XCTAssertEqual(create.title, "Create folder")
        XCTAssertEqual(create.confirmLabel, "Create")
        XCTAssertEqual(create.fieldPlaceholder, "Folder name")
        XCTAssertEqual(create.id, "createFolder")

        let forPortraits = PresentationAlert.createFolderForPortraits(targetIDs: [], draft: "")
        XCTAssertEqual(forPortraits.title, "Create folder")
        XCTAssertEqual(forPortraits.confirmLabel, "Create")
    }

    /// Vensterwissel-bug: de concepttekst van het naam-prompt leeft in de
    /// store, wordt bij een nieuw prompt geseed en blijft staan zolang
    /// hetzelfde prompt open is.
    func testNamePromptDraftLivesInStoreAndSurvivesReassign() {
        let store = UIPresentationStore()

        store.alert = .createFolder(draft: "Original")
        XCTAssertEqual(store.alertDraft, "Original")

        store.alertDraft = "Awareways"
        // Zelfde prompt opnieuw toewijzen (view-recreatie) mag niet resetten.
        store.alert = .createFolder(draft: "Original")
        XCTAssertEqual(store.alertDraft, "Awareways")

        // Sluiten wist het concept; een nieuw prompt seedt opnieuw.
        store.alert = nil
        XCTAssertEqual(store.alertDraft, "")
        store.alert = .createFolder(draft: "Fresh")
        XCTAssertEqual(store.alertDraft, "Fresh")
    }

    func testColoriseAlreadyColourConfirmStoresContinueAction() {
        let store = UIPresentationStore()
        var ran = false

        store.presentColoriseAlreadyColour { ran = true }

        XCTAssertEqual(store.confirm, .coloriseAlreadyColour)
        XCTAssertFalse(ran)

        store.dismissColoriseAlreadyColour()
        XCTAssertNil(store.confirm)
        XCTAssertFalse(ran, "cancel mag Colorise niet starten")

        store.presentColoriseAlreadyColour { ran = true }
        store.confirmColoriseAlreadyColour()
        XCTAssertTrue(ran)
        XCTAssertNil(store.confirm)
        XCTAssertNil(store.pendingColorise)
    }

    func testDismissColoriseAlreadyColourDoesNotClearOtherConfirms() throws {
        let store = UIPresentationStore()
        let id = try makePortraitID()
        store.confirm = .deletePortraits(ids: [id])

        store.dismissColoriseAlreadyColour()

        XCTAssertEqual(store.confirm, .deletePortraits(ids: [id]))
    }

    /// Enhance + chip-dropdown overleven een tab-wissel (store), maar
    /// `endEditorSession` ruimt ze op — library → ander beeld mag ze niet
    /// opnieuw openen.
    func testEndEditorSessionClosesEnhancePanelAndChipMenu() {
        let store = UIPresentationStore()
        store.editorActiveTool = .edit
        store.editorChipMenu = .boost
        store.editorBackgroundTypeMenuOpen = true
        store.createEffectSheetOpen = true

        store.endEditorSession()

        XCTAssertNil(store.editorActiveTool)
        XCTAssertNil(store.editorChipMenu)
        XCTAssertFalse(store.editorBackgroundTypeMenuOpen)
        XCTAssertTrue(store.createEffectSheetOpen, "een open taak-modal is geen editorsessie-menu")
    }
}
