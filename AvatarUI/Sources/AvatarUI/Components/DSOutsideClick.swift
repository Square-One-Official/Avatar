// Klik-buiten-sluiten voor in-window menu's en pickers.
//
// In-window dropdowns/pickers hadden alleen een lokaal vangvlak
// (`dsDropdownDismissOverlay`, een `Color.clear` met tap-gesture) ter grootte
// van hun eigen paneel; een klik op de canvas, de sidebar of een ander paneel
// liet het menu open staan. Dit is het generieke alternatief: zolang het menu
// open is, luistert een lokale NSEvent-monitor naar élke muisklik in de app.
// Landt die niet op het anker en niet op het menu (onzichtbare NSView-probes
// die zichzelf registreren), dan sluit het menu. De klik zelf gaat gewoon
// door (zoals een transient NSPopover) — de gebruiker hoeft niet twee keer te
// klikken om iets anders te raken. Esc sluit ook.
//
// Bewust géén global monitor / didResignActive: de eyedropper van
// `DSColorPicker` (NSColorSampler) klikt buiten de app en mag de picker
// niet sluiten.

import AppKit
import SwiftUI

// MARK: - Scope

/// Eén open menu = één scope. Bevat de "binnen"-views (anker + menu) en de
/// event-monitor. Maak 'm als `@State` in de view die anker én menu kent.
@MainActor
public final class DSOutsideClickScope {
    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private final class WeakScope {
        weak var scope: DSOutsideClickScope?
        init(_ scope: DSOutsideClickScope) { self.scope = scope }
    }

    /// Actieve scopes in open-volgorde. Een scope die ná deze opende is
    /// genest (bv. de format-dropdown in een DSColorPicker, of de type-
    /// dropdown in het board-Background-menu): een klik dáárin telt ook als
    /// "binnen" voor de ouder, ook als dat menu buiten het ouderpaneel steekt.
    private static var active: [WeakScope] = []

    private var insideViews: [WeakView] = []
    private var monitors: [Any] = []
    private var onDismiss: (() -> Void)?

    public init() {}

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }

    fileprivate func register(_ view: NSView) {
        insideViews.removeAll { $0.view == nil || $0.view === view }
        insideViews.append(WeakView(view))
    }

    fileprivate func unregister(_ view: NSView) {
        insideViews.removeAll { $0.view == nil || $0.view === view }
    }

    fileprivate func start(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        guard monitors.isEmpty else { return }
        Self.active.removeAll { $0.scope == nil }
        Self.active.append(WeakScope(self))
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, !self.isInside(event) else { return }
                self.onDismiss?()
            }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }  // Esc
            MainActor.assumeIsolated { self?.onDismiss?() }
            return nil
        }) { monitors.append(monitor) }
    }

    fileprivate func stop() {
        Self.active.removeAll { $0.scope == nil || $0.scope === self }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        onDismiss = nil
    }

    /// Deze scope + alle scopes die erna opengingen (genest).
    private var scopesCountingAsInside: [DSOutsideClickScope] {
        guard let index = Self.active.firstIndex(where: { $0.scope === self }) else { return [self] }
        return Self.active[index...].compactMap(\.scope)
    }

    /// Klik telt als "binnen" als 'ie op één van de geregistreerde views
    /// landt, of in een child window van het hostvenster (bv. een DS-
    /// contextmenu-panel of een floating toast bovenop het menu).
    private func isInside(_ event: NSEvent) -> Bool {
        let views = scopesCountingAsInside.flatMap { $0.insideViews.compactMap(\.view) }
        guard let eventWindow = event.window else { return false }
        guard let hostWindow = views.first(where: { $0.window != nil })?.window else {
            // Nog geen probe in een venster (menu net gemount): niet sluiten.
            return true
        }
        if eventWindow !== hostWindow {
            // Ook kleinkinderen (E57.6): een genest DS-submenu hangt onder het
            // submenu-window, niet direct onder het hostvenster.
            var current: NSWindow? = eventWindow.parent
            while let window = current {
                if window === hostWindow { return true }
                current = window.parent
            }
            return false
        }
        return views.contains { view in
            guard view.window === hostWindow, !view.isHiddenOrHasHiddenAncestor else { return false }
            let point = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(point)
        }
    }
}

// MARK: - Modifiers

public extension View {
    /// Markeert deze view als "binnen" voor `scope`: een klik hierop sluit het
    /// menu niet. Zet op het anker (de toggle-knop) én op het menu zelf.
    func dsOutsideClickInside(_ scope: DSOutsideClickScope) -> some View {
        background(DSOutsideClickProbe(scope: scope))
    }

    /// Activeert de klik-buiten-monitor van `scope` zolang `isActive` true is
    /// en markeert deze view als "binnen". Zet op het menu/paneel.
    func dsDismissOnOutsideClick(
        _ scope: DSOutsideClickScope,
        isActive: Bool,
        onDismiss: @escaping () -> Void
    ) -> some View {
        dsOutsideClickInside(scope)
            .modifier(DSOutsideClickLifecycle(scope: scope, isActive: isActive, onDismiss: onDismiss))
    }

    /// Binding-variant: zet `isPresented` op false bij een klik buiten
    /// anker + menu (of Esc).
    func dsDismissOnOutsideClick(
        _ scope: DSOutsideClickScope,
        isPresented: Binding<Bool>
    ) -> some View {
        dsDismissOnOutsideClick(scope, isActive: isPresented.wrappedValue) {
            isPresented.wrappedValue = false
        }
    }
}

private struct DSOutsideClickLifecycle: ViewModifier {
    let scope: DSOutsideClickScope
    let isActive: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive, initial: true) { _, active in
                if active {
                    scope.start(onDismiss: onDismiss)
                } else {
                    scope.stop()
                }
            }
            .onDisappear { scope.stop() }
    }
}

// MARK: - Probe

/// Onzichtbare NSView die z'n frame (= dat van de SwiftUI-view) meldt aan de
/// scope. `hitTest` geeft nil: kliks/hover gaan door naar de SwiftUI-view.
private struct DSOutsideClickProbe: NSViewRepresentable {
    let scope: DSOutsideClickScope

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.scope = scope
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        if nsView.scope !== scope {
            nsView.scope?.unregister(nsView)
            nsView.scope = scope
            if nsView.window != nil { scope.register(nsView) }
        }
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: ()) {
        nsView.scope?.unregister(nsView)
    }

    final class ProbeView: NSView {
        var scope: DSOutsideClickScope?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { scope?.register(self) } else { scope?.unregister(self) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
