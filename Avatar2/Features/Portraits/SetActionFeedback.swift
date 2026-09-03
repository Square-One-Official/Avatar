// E50.3 — feedback-contract van de set-brede acties (`PortraitSetActions`):
// voortgang → "klaar"-bon met optionele Undo, plus een hook om het canvas te
// verversen als een batch (of z'n undo/redo) het geselecteerde portret raakt.
// De shell (ShellModel/ShellView) vertaalt dit naar de toast rechtsonder.

import Foundation

/// Wat een set-actie aan de shell rapporteert.
struct SetActionReporter {
    /// Voortgangstekst; nil = klaar. Wist alléén een lopende busy-staat, nooit
    /// een net gemelde bon.
    var busy: (String?) -> Void
    /// Resultaat-bon zodra de actie klaar is.
    var done: (SetActionReceipt) -> Void
    /// Een batch of z'n undo/redo wijzigde dit portret (Adjust/transform/
    /// achtergrond) — de shell ververst het canvas als het 't geselecteerde is.
    var portraitDidChange: (Portrait2) -> Void
    /// E57.5: annuleer-haak voor batches (Boost/Fill in body/Apply effect):
    /// de shell toont dan een Stop-knop op de busy-toast; stoppen laat staan
    /// wat al klaar is. nil = niet (meer) te stoppen; `busy(nil)` wist 'm ook.
    var cancel: ((() -> Void)?) -> Void = { _ in }

    /// Voor smokes/tests die geen shell hebben.
    static let silent = SetActionReporter(busy: { _ in }, done: { _ in }, portraitDidChange: { _ in })
}

/// "Klaar"-bon van een set-actie. `actionName` = de naam van de undo-groep die
/// de actie registreerde (nil = niets terug te draaien: export, "already match").
struct SetActionReceipt: Identifiable, Equatable {
    let id = UUID()
    let title: String
    /// Optionele tweede regel in de toast (bv. waar het resultaat te zien is).
    let detail: String?
    let actionName: String?
    /// Compacte bevestiging (status-pill rechtsonder, zoals "Removing
    /// background…") i.p.v. de 360pt-toastkaart — voor korte, synchrone acties
    /// (Set background) waar een kaart met omschrijving te zwaar is. De pill
    /// toont alleen titel + inline Undo; `detail` wordt dan niet getoond.
    let compact: Bool
    weak var undoManager: UndoManager?

    init(title: String, detail: String? = nil, actionName: String?, compact: Bool = false, undoManager: UndoManager?) {
        self.title = title
        self.detail = detail
        self.actionName = actionName
        self.compact = compact
        self.undoManager = undoManager
    }

    static func == (lhs: SetActionReceipt, rhs: SetActionReceipt) -> Bool { lhs.id == rhs.id }

    var canUndo: Bool { actionName != nil }

    /// Toast-omschrijving: detail + de ⌘Z-hint zodra er een undo-stap is.
    var toastDescription: String? {
        let parts = [detail, canUndo ? "⌘Z also undoes this." : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Draait de actie terug — alléén als 'ie nog bovenop de undo-stack ligt.
    /// (Een gecapturede terugdraai-closure zou de NSUndoManager-stack
    /// desynchroniseren: ⌘Z zou daarna een no-op "undoen" en een valse redo
    /// registreren.) Geeft terug of er iets is teruggedraaid.
    @MainActor
    @discardableResult
    func performUndo() -> Bool {
        guard let actionName, let undoManager, undoManager.canUndo,
              undoManager.undoActionName == actionName else { return false }
        undoManager.undo()
        return true
    }
}
