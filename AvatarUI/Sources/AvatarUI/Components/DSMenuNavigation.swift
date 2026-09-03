// Keyboard- en hover-model voor DS-contextmenu's (E57.1).
//
// Een rechtermuis-menu (`DSContextMenuOverlay`) heeft één `DSMenuTree`; elk
// `DSContextMenuPanel` daarin — het hoofdpaneel én elk open submenu — is een
// `DSMenuLevel`. Rijen (`DSMenuRow`/`DSMenuSubmenu`) registreren zich bij hun
// niveau mét hun frame, zodat ↑/↓ de zichtbare volgorde volgen zonder dat het
// paneel z'n inhoud hoeft te kennen. Hover en keyboard delen dezelfde
// `focusedID`: het gemarkeerde item is altijd het item dat een Return zou
// activeren, zoals in een native NSMenu.
//
// Zonder tree (in-window dropdowns via `dsDropdownMenu`, board-menu's) is er
// geen niveau: rijen vallen dan terug op hun eigen hover-highlight en een
// `DSMenuSubmenu` opent/sluit op klik en hover zonder keyboard.

import AppKit
import SwiftUI

// MARK: - Niveau

@MainActor
@Observable
public final class DSMenuLevel {
    struct Row {
        var frame: CGRect = .zero
        var isSubmenu = false
        var isDisabled = false
        var activate: () -> Void = {}
    }

    @ObservationIgnored private(set) var rows: [UUID: Row] = [:]
    /// Rij-id's in zichtbare volgorde (op frame, boven → onder).
    @ObservationIgnored private(set) var order: [UUID] = []
    /// Gemarkeerde rij: hover óf keyboard.
    public internal(set) var focusedID: UUID?
    /// Het submenu dat op dit niveau open staat (max. één).
    public internal(set) var openSubmenuID: UUID?
    @ObservationIgnored weak var parent: DSMenuLevel?
    /// Gezet door een keyboard-open (→/Return): het kind focust z'n eerste
    /// rij zodra het verschijnt. Een hover-open laat het kind ongemarkeerd.
    @ObservationIgnored var pendingChildFocus = false

    init(parent: DSMenuLevel? = nil) {
        self.parent = parent
    }

    // MARK: Registratie

    func register(_ id: UUID, isSubmenu: Bool, isDisabled: Bool, activate: @escaping () -> Void) {
        var row = rows[id] ?? Row()
        row.isSubmenu = isSubmenu
        row.isDisabled = isDisabled
        row.activate = activate
        rows[id] = row
        resort()
    }

    func updateFrame(_ id: UUID, _ frame: CGRect) {
        guard let row = rows[id], row.frame != frame else { return }
        rows[id]?.frame = frame
        resort()
    }

    func setDisabled(_ id: UUID, _ disabled: Bool) {
        guard rows[id] != nil else { return }
        rows[id]?.isDisabled = disabled
        if disabled, focusedID == id { focusedID = nil }
    }

    func unregister(_ id: UUID) {
        rows[id] = nil
        if focusedID == id { focusedID = nil }
        if openSubmenuID == id { openSubmenuID = nil }
        resort()
    }

    private func resort() {
        order = rows
            .sorted { a, b in
                if a.value.frame.minY != b.value.frame.minY { return a.value.frame.minY < b.value.frame.minY }
                return a.value.frame.minX < b.value.frame.minX
            }
            .map(\.key)
    }

    // MARK: Hover

    func hoverEntered(_ id: UUID) {
        guard let row = rows[id], !row.isDisabled else { return }
        focusedID = id
    }

    /// Een rij waarvan het submenu open staat blijft gemarkeerd (shadcn
    /// `data-state=open`); andere rijen laten hun markering los.
    func hoverExited(_ id: UUID) {
        if focusedID == id, openSubmenuID != id { focusedID = nil }
    }

    // MARK: Keyboard

    var enabledOrder: [UUID] {
        order.filter { !(rows[$0]?.isDisabled ?? true) }
    }

    var focusedIsSubmenu: Bool {
        guard let id = focusedID else { return false }
        return rows[id]?.isSubmenu ?? false
    }

    /// ↑/↓: door de ingeschakelde rijen, met wrap. Zonder markering start
    /// ↓ bovenaan en ↑ onderaan.
    func moveFocus(by delta: Int) {
        let ids = enabledOrder
        guard !ids.isEmpty else { return }
        guard let current = focusedID, let index = ids.firstIndex(of: current) else {
            focusedID = delta >= 0 ? ids.first : ids.last
            return
        }
        let count = ids.count
        focusedID = ids[((index + delta) % count + count) % count]
    }

    func focusFirst() {
        focusedID = enabledOrder.first
    }

    /// Return/Space: activeert de gemarkeerde rij; een submenu-rij opent en
    /// geeft z'n kind de eerste rij.
    @discardableResult
    func activateFocused() -> Bool {
        guard let id = focusedID, let row = rows[id], !row.isDisabled else { return false }
        if row.isSubmenu {
            openSubmenu(id, focusChild: true)
        } else {
            row.activate()
        }
        return true
    }

    func openSubmenu(_ id: UUID, focusChild: Bool) {
        focusedID = id
        pendingChildFocus = focusChild
        openSubmenuID = id
    }

    func closeSubmenu() {
        pendingChildFocus = false
        openSubmenuID = nil
    }
}

// MARK: - Boom

@MainActor
@Observable
public final class DSMenuTree {
    @ObservationIgnored private(set) var levels: [DSMenuLevel] = []

    public init() {}

    func attach(_ level: DSMenuLevel) {
        guard !levels.contains(where: { $0 === level }) else { return }
        levels.append(level)
    }

    func detach(_ level: DSMenuLevel) {
        levels.removeAll { $0 === level }
    }

    /// Het diepste niveau waarvan de keten van open submenu's intact is:
    /// daar landen de pijltjestoetsen. Volgorde van aan-/afmelden doet er
    /// niet toe (een sibling-submenu dat opent vóór het vorige is afgemeld).
    var active: DSMenuLevel? {
        guard var current = levels.first(where: { $0.parent == nil }) else { return nil }
        while current.openSubmenuID != nil,
              let child = levels.first(where: { $0.parent === current }) {
            current = child
        }
        return current
    }

    public enum Key: Equatable {
        case up, down, left, right, activate
    }

    /// true = verwerkt (het event niet meer doorgeven).
    @discardableResult
    func handle(_ key: Key) -> Bool {
        guard let level = active else { return false }
        switch key {
        case .down:
            level.moveFocus(by: 1)
        case .up:
            level.moveFocus(by: -1)
        case .right:
            if level.focusedIsSubmenu, let id = level.focusedID {
                level.openSubmenu(id, focusChild: true)
            }
        case .left:
            // Op het hoofdniveau doet ← niets, maar het menu slikt 'm wel —
            // zoals een NSMenu (de toets bereikt de app erachter niet).
            level.parent?.closeSubmenu()
        case .activate:
            level.activateFocused()
        }
        return true
    }

    /// Toets → menu-actie; nil voor alles wat het menu niet aangaat (dat
    /// event loopt door, incl. ⌘-shortcuts en Esc — Esc sluit via de
    /// floating-panel-monitor het hele menu).
    static func key(for event: NSEvent) -> Key? {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch event.keyCode {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 36, 76, 49: return .activate // Return, keypad-Enter, spatie
        default: return nil
        }
    }
}

// MARK: - Toetsen-monitor

/// De menu-panels worden nooit key (het hostvenster houdt de focus), dus
/// pijltjes/Return komen via een lokale event-monitor binnen — zelfde route
/// als Esc in `DSFloatingPanelController`.
@MainActor
final class DSMenuKeyMonitor {
    private var monitor: Any?

    func install(tree: DSMenuTree) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let key = DSMenuTree.key(for: event) else { return event }
            let handled = MainActor.assumeIsolated { tree.handle(key) }
            return handled ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
