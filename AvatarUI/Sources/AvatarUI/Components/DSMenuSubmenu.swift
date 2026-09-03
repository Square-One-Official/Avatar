// Menu-rij met genest submenu (E57.1) — het shadcn-/NSMenu-gedrag:
//   - opent náást de rij (rechts; links als het rechts niet past) in een
//     eigen child window, met de eerste submenu-rij op de hoogte van de
//     trigger-rij;
//   - hover-intent: opent na een korte rust op de rij, sluit pas als de
//     muis op een ándere rij van hetzelfde niveau rust — de kier naar het
//     submenu en een diagonale beweging erheen sluiten 'm dus niet;
//   - klik op de rij opent ook (smokes, en wie liever klikt);
//   - keyboard via `DSMenuTree`: → opent en focust de eerste rij, ← sluit;
//   - onbeperkt nestbaar (elk submenu is weer een `DSContextMenuPanel`).
//
// Figma toont geen submenu's; dit is de interpretatie in de geest van het
// DS-menu (zelfde rij, zelfde kaart). Zie plan/E57 voor de Figma-TODO's.

import SwiftUI

public struct DSMenuSubmenu<Content: View>: View {
    private let title: String
    private let icon: Image
    private let shortcut: String?
    private let disabled: Bool
    private let minWidth: CGFloat
    private let content: Content

    @Environment(DSMenuLevel.self) private var level: DSMenuLevel?
    @State private var id = UUID()
    @State private var rowFrame: CGRect = .zero
    /// Zonder niveau (in-window dropdown): open/dicht op klik en hover.
    @State private var fallbackOpen = false
    @State private var session = Session()

    /// Hover-intent. Open na korte rust op de rij; het sluiten krijgt wat
    /// meer gratie zodat de muis over de kier naar het submenu kan.
    public static var openDelay: Duration { .milliseconds(150) }
    public static var closeDelay: Duration { .milliseconds(250) }

    @MainActor
    private final class Session {
        var task: Task<Void, Never>?
        var pointerInSubmenu = false
    }

    public init(
        _ title: String,
        icon: String,
        shortcut: String? = nil,
        disabled: Bool = false,
        minWidth: CGFloat = 200,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title, icon: Image(systemName: icon), shortcut: shortcut,
            disabled: disabled, minWidth: minWidth, content: content
        )
    }

    public init(
        _ title: String,
        icon: Image,
        shortcut: String? = nil,
        disabled: Bool = false,
        minWidth: CGFloat = 200,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.disabled = disabled
        self.minWidth = minWidth
        self.content = content()
    }

    private var isOpen: Bool {
        if let level { return level.openSubmenuID == id }
        return fallbackOpen
    }

    public var body: some View {
        DSMenuRowContent(
            id: id,
            title: title,
            icon: icon,
            destructive: false,
            showsChevron: true,
            shortcut: shortcut,
            disabled: disabled,
            isSubmenu: true,
            accessory: EmptyView(),
            action: open
        )
        .onHover { hovering in
            if hovering { scheduleOpen() } else { scheduleClose() }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .global), initial: true) { _, new in
                        rowFrame = new
                    }
            }
        }
        .background {
            if isOpen {
                // De rij vult het paneel minus `listInset`; het paneelframe
                // volgt daaruit, zodat het submenu naast de kaart landt en
                // niet naast de rij.
                DSFloatingWindowAnchor(
                    placement: .besideRow(
                        row: rowFrame,
                        panel: rowFrame.insetBy(dx: -DSMenuLayout.listInset, dy: 0)
                    ),
                    mode: .menu(onDismiss: close),
                    identity: id
                ) {
                    DSSubmenuPanel(title: title, minWidth: minWidth, onPointer: pointerChanged) {
                        content
                    }
                }
            }
        }
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityHint("Opens a submenu")
        .onDisappear { session.task?.cancel() }
    }

    // MARK: - Open/dicht

    private func open() {
        session.task?.cancel()
        guard !disabled else { return }
        if let level {
            level.openSubmenu(id, focusChild: false)
        } else {
            fallbackOpen = true
        }
    }

    private func close() {
        session.task?.cancel()
        session.pointerInSubmenu = false
        if let level {
            if level.openSubmenuID == id { level.closeSubmenu() }
        } else {
            fallbackOpen = false
        }
    }

    private func pointerChanged(_ inside: Bool) {
        session.pointerInSubmenu = inside
        guard inside else { return }
        session.task?.cancel()
        // Diagonaal over een sibling het submenu in: de trigger blijft het
        // gemarkeerde item, niet de rij die onderweg geraakt werd.
        level?.hoverEntered(id)
    }

    private func scheduleOpen() {
        session.task?.cancel()
        guard !disabled, !isOpen else { return }
        session.task = Task { @MainActor in
            try? await Task.sleep(for: Self.openDelay)
            guard !Task.isCancelled else { return }
            open()
        }
    }

    private func scheduleClose() {
        session.task?.cancel()
        guard isOpen else { return }
        session.task = Task { @MainActor in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled, !session.pointerInSubmenu else { return }
            // Zonder niveau blijft 'ie open tot een klik (geen sibling-info).
            guard let level else { return }
            // Alleen sluiten als de muis inmiddels op een andere rij van dit
            // niveau rust; weg van het menu = open laten (zoals NSMenu).
            if let focused = level.focusedID, focused != id { close() }
        }
    }
}

// MARK: - Paneel in het child window

private struct DSSubmenuPanel<Content: View>: View {
    let title: String
    let minWidth: CGFloat
    let onPointer: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    @State private var appeared = false

    var body: some View {
        DSContextMenuPanel(minWidth: minWidth) {
            content()
        }
        .accessibilityLabel(title)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -DSSpacing.gap1)
        .onHover(perform: onPointer)
        .onAppear {
            DSMotion.animate(DSMotion.micro) { appeared = true }
        }
    }
}
