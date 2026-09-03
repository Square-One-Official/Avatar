// Zwevende child-vensters voor DS-contextmenu's en toasts.
//
// In-window `.overlay`s hadden twee problemen: (1) een contextmenu bleef
// binnen het app-venster en werd aan de vensterrand afgekapt; (2) de
// z-volgorde lag vast in de `.overlay`-keten, dus een menu dat ná een toast
// opende, verdween eronder. Beide leven nu in een borderless, niet-
// activerende NSPanel als child window van het app-venster:
//   - een menu mag over de vensterrand heen (zoals een native NSMenu) en
//     klemt op het schérm, niet op het venster;
//   - wat het laatst verschijnt staat bovenop — `bringToFront()` ordent de
//     panel boven alle andere DS-panels van hetzelfde hostvenster.
// De SwiftUI-inhoud krijgt de environment van de call site mee
// (`.environment(\.self, …)`), dus @Query/modelContext/kleurschema werken
// precies als in-window. De schaduw van de inhoud valt binnen een marge
// rond de inhoud; voor toasts wordt die marge op het hostvenster geknipt
// (de panel is de clip-regio, de hosting view schuift erbinnen), zodat de
// slide-in/out er hetzelfde uitziet als de oude in-window transition.

import AppKit
import SwiftUI

// MARK: - Plaatsing (SwiftUI-space; de host rekent om naar scherm)

/// Waarbinnen een verankerd menu geklemd wordt.
public enum DSFloatingBounds: Equatable {
    /// Contextmenu: mag over de vensterrand heen, klemt op het scherm.
    case screen
    /// Popover-achtig paneel (bv. de achtergrond-kiezer): blijft binnen het
    /// hostvenster — een groot paneel dat half buiten het venster hangt oogt
    /// als een bug, niet als een menu.
    case window
}

public enum DSFloatingPlacement: Equatable {
    /// Menu: linksboven van de inhoud op dit punt in SwiftUI `.global`;
    /// geklemd binnen `bounds` (scherm of hostvenster).
    case anchoredTopLeft(CGPoint, bounds: DSFloatingBounds = .screen)
    /// Toast: in een hoek van het hostvenster, `padding` van de rand.
    case corner(Alignment, padding: CGFloat)
    /// Submenu (E57.1): rechts naast `panel` (het paneel van de trigger-rij),
    /// met de bovenkant op `row` zodat de eerste submenu-rij op de hoogte
    /// van de trigger staat; links van het paneel als het rechts niet past.
    /// Beide rects in SwiftUI `.global` van het venster van de rij.
    case besideRow(row: CGRect, panel: CGRect)
}

// MARK: - Layout (puur, testbaar; schermcoördinaten, y omhoog)

enum DSFloatingLayout {
    enum Placement: Equatable {
        case anchoredTopLeft(CGPoint, bounds: DSFloatingBounds)
        case corner(Alignment, padding: CGFloat)
        case besideRow(row: CGRect, panel: CGRect)
    }

    /// Kier tussen paneel en submenu.
    static let submenuGap: CGFloat = DSSpacing.gap1

    struct Frames: Equatable {
        /// Vensterframe van de panel = zichtbare regio (clip).
        let panel: CGRect
        /// Frame van de hosting view (inhoud + schaduwmarge) binnen de panel;
        /// mag buiten de panel steken en wordt dan afgeknipt.
        let hosting: CGRect
    }

    /// Waar de inhoud (zónder schaduwmarge) op het scherm komt.
    /// - anchoredTopLeft: op het anker; klemt met `padding` binnen `screen`
    ///   (`.screen`) of binnen het zichtbare deel van `parent` (`.window`).
    ///   Past het niet, dan blijft de linker-/bovenrand zichtbaar.
    /// - corner: hoek van `parent` (content-rect van het hostvenster).
    static func contentFrame(
        placement: Placement,
        size: CGSize,
        parent: CGRect,
        screen: CGRect,
        padding: CGFloat = DSSpacing.gap2
    ) -> CGRect {
        switch placement {
        case .anchoredTopLeft(let topLeft, let bounds):
            // `.window`: klem op het zichtbare deel van het hostvenster; past
            // de inhoud daar (per as) niet in, dan op het scherm — een paneel
            // dat over de vensterrand valt is beter dan één die van het
            // scherm af valt.
            var hBox = screen
            var vBox = screen
            if bounds == .window {
                let visible = parent.intersection(screen)
                if !visible.isNull, visible.width - 2 * padding >= size.width { hBox = visible }
                if !visible.isNull, visible.height - 2 * padding >= size.height { vBox = visible }
            }
            let x = min(
                max(topLeft.x, hBox.minX + padding),
                max(hBox.minX + padding, hBox.maxX - size.width - padding)
            )
            let upper = vBox.maxY - padding
            let lower = vBox.minY + padding + size.height
            let top = max(min(topLeft.y, upper), min(lower, upper))
            return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
        case .corner(let alignment, let inset):
            let x: CGFloat
            switch alignment.horizontal {
            case .leading: x = parent.minX + inset
            case .trailing: x = parent.maxX - inset - size.width
            default: x = parent.midX - size.width / 2
            }
            let y: CGFloat
            switch alignment.vertical {
            case .top: y = parent.maxY - inset - size.height
            case .bottom: y = parent.minY + inset
            default: y = parent.midY - size.height / 2
            }
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        case .besideRow(let row, let panel):
            // Rechts van het paneel; past het niet (met `padding` tot de
            // schermrand), dan links ervan; past ook dát niet, dan tegen de
            // rechter schermrand — een overlap is beter dan buiten beeld.
            var x = panel.maxX + submenuGap
            if x + size.width + padding > screen.maxX {
                x = panel.minX - submenuGap - size.width
            }
            if x < screen.minX + padding {
                x = max(screen.minX + padding, screen.maxX - padding - size.width)
            }
            // Bovenkant van het submenu-paneel op de bovenkant van de rij
            // min de lijst-inset: de eerste submenu-rij staat dan precies op
            // de hoogte van de trigger-rij (y omhoog → rij-top = maxY).
            let preferredTop = row.maxY + DSMenuLayout.listInset
            let upper = screen.maxY - padding
            let lower = screen.minY + padding + size.height
            let top = max(min(preferredTop, upper), min(lower, upper))
            return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
        }
    }

    /// Menu's mogen over de vensterrand heen (clip = scherm) — ook een
    /// venster-geklemd paneel: z'n schaduw mag als bij een popover over de
    /// vensterrand vallen. Toasts blijven binnen het hostvenster (clip =
    /// parent), net als de oude overlay.
    static func clipRect(placement: Placement, parent: CGRect, screen: CGRect) -> CGRect {
        switch placement {
        case .anchoredTopLeft, .besideRow: return screen
        case .corner: return parent
        }
    }

    /// Panelframe = (inhoud + marge) ∩ clip; hosting-frame relatief daaraan.
    static func frames(content: CGRect, margin: NSEdgeInsets, clip: CGRect) -> Frames {
        let bleed = CGRect(
            x: content.minX - margin.left,
            y: content.minY - margin.bottom,
            width: content.width + margin.left + margin.right,
            height: content.height + margin.top + margin.bottom
        )
        var panel = bleed.intersection(clip)
        if panel.isNull { panel = CGRect(origin: bleed.origin, size: .zero) }
        let hosting = CGRect(
            x: bleed.minX - panel.minX,
            y: bleed.minY - panel.minY,
            width: bleed.width,
            height: bleed.height
        )
        return Frames(panel: panel, hosting: hosting)
    }
}

// MARK: - Modus

/// Gedrag van een verankerd zwevend menu/paneel (`DSContextMenuOverlay`).
public enum DSFloatingKind: Equatable {
    /// Contextmenu: transient, zoals een native NSMenu.
    case menu
    /// Popover-achtig paneel (bv. de achtergrond-kiezer op een selectie).
    case panel
}

public enum DSFloatingMode {
    /// Contextmenu: sluit op klik buiten het menu (ook buiten de app), Esc,
    /// app-deactivatie en verplaatsen/resizen van het hostvenster. Wordt
    /// nooit key: het hostvenster houdt de focus.
    case menu(onDismiss: () -> Void)
    /// Popover-achtig paneel: sluit op klik buiten het paneel (binnen de app),
    /// Esc en verplaatsen/resizen van het hostvenster — maar overleeft een
    /// app-/vensterwissel (Cmd-Tab, klik in een andere app en terug), zoals
    /// de andere overlays van de shell-host. Kan key worden, zodat
    /// tekstvelden erin (hex-invoer, zoekveld, prompt) toetsen en plakken
    /// ontvangen; een menu-panel dat nooit key wordt laat een TextField
    /// stil vallen.
    case panel(onDismiss: () -> Void)
    /// Toast: blijft staan; volgt het hostvenster; slide-in/out zoals
    /// `.dsSlide(.trailing)` (reduce motion → alleen fade).
    case toast

    /// Schaduwmarge rond de inhoud: de panel is de clip-regio, dus de marge
    /// moet de héle blur bevatten. Een SwiftUI-`shadow(radius:)` loopt ~3×
    /// de radius door; een krappere marge knipt de schaduw hard af tot een
    /// rechthoek rond de kaart. Menu: `dsMenuSurface` (`DSPanelShadow`);
    /// toast: DSToast (de gehalveerde Shadows/Default).
    var margin: NSEdgeInsets {
        switch self {
        case .menu, .panel:
            return Self.shadowMargin(radius: DSPanelShadow.radius, yOffset: DSPanelShadow.yOffset)
        case .toast:
            return Self.shadowMargin(
                radius: DSShadow.default.radius / 2,
                yOffset: DSShadow.default.offset.height / 2
            )
        }
    }

    /// Hoeveel een `shadow(radius:y:)` buiten de inhoud kan tekenen.
    static let shadowBlurExtent: CGFloat = 3

    static func shadowMargin(radius: CGFloat, yOffset: CGFloat) -> NSEdgeInsets {
        let blur = radius * shadowBlurExtent
        return NSEdgeInsets(
            top: max(0, blur - yOffset),
            left: blur,
            bottom: blur + yOffset,
            right: blur
        )
    }

    /// Menu-achtig (geen toast): verankerd, sluit via `onDismiss`.
    var isMenu: Bool {
        onDismiss != nil
    }

    var isPanel: Bool {
        if case .panel = self { return true }
        return false
    }

    var onDismiss: (() -> Void)? {
        switch self {
        case .menu(let onDismiss), .panel(let onDismiss): return onDismiss
        case .toast: return nil
        }
    }

    public init(kind: DSFloatingKind, onDismiss: @escaping () -> Void) {
        switch kind {
        case .menu: self = .menu(onDismiss: onDismiss)
        case .panel: self = .panel(onDismiss: onDismiss)
        }
    }
}

// MARK: - Panel + hosting view

final class DSFloatingPanel: NSPanel {
    /// Voor debugging/tests: welke modus deze panel host.
    fileprivate(set) var isToast = false
    /// `.panel`-modus: mag key worden (tekstvelden). Menu's en toasts nooit.
    fileprivate(set) var allowsKeyboardFocus = false

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // de inhoud tekent z'n eigen DS-schaduw
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        isMovableByWindowBackground = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    // Menu/toast nooit key, nooit main: het hostvenster houdt focus; Esc
    // loopt via een event-monitor. SwiftUI-hover en -clicks werken zonder
    // key-status (acceptsFirstMouse op de hosting view). Een `.panel` wordt
    // key bij een klik erin (`becomesKeyOnlyIfNeeded = false`: ook een klik
    // op een tegel, niet alleen op een tekstveld — een SwiftUI-TextField in
    // een NSHostingView meldt zich niet betrouwbaar als `needsPanelToBecomeKey`).
    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }
}

final class DSFloatingHostingView: NSHostingView<AnyView> {
    var onIntrinsicSizeChange: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Interne state-wissels in de inhoud (bv. een submenu-flyout) veranderen
    // de ideale maat; de controller meet dan opnieuw en herplaatst.
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }
}

// MARK: - Controller

@MainActor
final class DSFloatingPanelController {
    let panel = DSFloatingPanel()
    private let container = NSView()
    private let hosting: DSFloatingHostingView
    let mode: DSFloatingMode
    private var placement: DSFloatingLayout.Placement
    private weak var parent: NSWindow?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var isAttached = false
    private var isClosing = false
    private var relayoutScheduled = false
    private var lastFrames: DSFloatingLayout.Frames?

    init(mode: DSFloatingMode, placement: DSFloatingLayout.Placement, rootView: AnyView) {
        self.mode = mode
        self.placement = placement
        hosting = DSFloatingHostingView(rootView: rootView)
        panel.isToast = !mode.isMenu
        panel.allowsKeyboardFocus = mode.isPanel
        panel.becomesKeyOnlyIfNeeded = !mode.isPanel
        container.wantsLayer = true
        hosting.wantsLayer = true
        container.addSubview(hosting)
        panel.contentView = container
        hosting.onIntrinsicSizeChange = { [weak self] in self?.scheduleRelayout() }
    }

    // MARK: Lifecycle

    func attach(to parent: NSWindow, placement: DSFloatingLayout.Placement) {
        guard !isAttached, !isClosing else { return }
        isAttached = true
        self.parent = parent
        self.placement = placement
        panel.level = parent.level
        panel.appearance = parent.effectiveAppearance
        relayout(animated: false)
        bringToFront()
        installObservers(parent: parent)
        if case .toast = mode { animateEnter() }
    }

    func update(rootView: AnyView, placement: DSFloatingLayout.Placement, bringForward: Bool) {
        hosting.rootView = rootView
        let placementChanged = placement != self.placement
        self.placement = placement
        if let parent { panel.appearance = parent.effectiveAppearance }
        if isAttached {
            relayout(animated: false)
            if bringForward || placementChanged { bringToFront() }
        }
    }

    /// Bovenop alle andere DS-panels van dit hostvenster (recency-regel).
    /// AppKit houdt child windows in de volgorde waarin ze zijn toegevoegd en
    /// zet die bij elke ordering-operatie opnieuw; een `order(.above,
    /// relativeTo:)` op een sibling beklijft daarom niet. Opnieuw toevoegen
    /// als laatste child wél.
    func bringToFront() {
        guard let parent, isAttached, !isClosing else { return }
        if parent.childWindows?.contains(where: { $0 === panel }) == true {
            parent.removeChildWindow(panel)
        }
        parent.addChildWindow(panel, ordered: .above)
    }

    func close(animated: Bool) {
        guard !isClosing else { return }
        isClosing = true
        removeObservers()
        let finish = { [self] in
            // Een key `.panel` geeft de focus expliciet terug aan het
            // hostvenster (anders kiest AppKit zelf een venster).
            let wasKey = panel.isKeyWindow
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            if wasKey { parent?.makeKey() }
        }
        if animated, isAttached { animateExit(completion: finish) } else { finish() }
    }

    // MARK: Layout

    /// Inhoud van maat veranderd (submenu-flyout open/dicht): opnieuw meten
    /// en herplaatsen, gecoalesceerd naar de volgende runloop-tick zodat het
    /// niet middenin een SwiftUI-layoutpass gebeurt.
    func scheduleRelayout() {
        guard isAttached, !isClosing, !relayoutScheduled else { return }
        relayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            relayoutScheduled = false
            relayout(animated: false)
        }
    }

    private func relayout(animated: Bool) {
        guard let parent, !isClosing else { return }
        let margin = mode.margin
        let fitting = hosting.fittingSize
        let contentSize = CGSize(
            width: max(0, fitting.width - margin.left - margin.right),
            height: max(0, fitting.height - margin.top - margin.bottom)
        )
        let parentRect = parent.convertToScreen(parent.contentLayoutRect)
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parentRect
        let content = DSFloatingLayout.contentFrame(
            placement: placement, size: contentSize, parent: parentRect, screen: screen
        )
        let clip = DSFloatingLayout.clipRect(placement: placement, parent: parentRect, screen: screen)
        let frames = DSFloatingLayout.frames(content: content, margin: margin, clip: clip)
        guard frames != lastFrames else { return }
        lastFrames = frames
        panel.setFrame(frames.panel, display: true)
        hosting.frame = frames.hosting
    }

    // MARK: Toast-animatie (spiegelt `.dsSlide(.trailing)`: enter 0.25 /
    // exit 0.20 op de DS-ease-out; reduce motion → alleen opacity)

    private var offscreenTrailingFrame: CGRect {
        var frame = hosting.frame
        frame.origin.x = panel.frame.width - mode.margin.left
        return frame
    }

    private func animateEnter() {
        let target = hosting.frame
        let reduce = DSMotion.reduceMotionEnabled
        if reduce { hosting.alphaValue = 0 } else { hosting.frame = offscreenTrailingFrame }
        runAnimation(duration: DSMotion.Duration.enter, { [hosting] in
            if reduce { hosting.animator().alphaValue = 1 } else { hosting.animator().frame = target }
        }, completion: {})
    }

    private func animateExit(completion: @escaping () -> Void) {
        let reduce = DSMotion.reduceMotionEnabled
        let target = offscreenTrailingFrame
        runAnimation(duration: DSMotion.Duration.exit, { [hosting] in
            if reduce { hosting.animator().alphaValue = 0 } else { hosting.animator().frame = target }
        }, completion: completion)
    }

    private func runAnimation(duration: Double, _ changes: @escaping () -> Void, completion: @escaping () -> Void) {
        let c = DSMotion.easeOutControlPoints
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: c.0, c.1, c.2, c.3)
            context.allowsImplicitAnimation = true
            changes()
        }, completionHandler: completion)
    }

    // MARK: Observers

    private func installObservers(parent: NSWindow) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(animated: false) }
        })
        let parentGeometry: [Notification.Name] = [NSWindow.didMoveNotification, NSWindow.didResizeNotification]
        for name in parentGeometry {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let onDismiss = self.mode.onDismiss { onDismiss() }
                    else { self.relayout(animated: false) }
                }
            })
        }

        guard let onDismiss = mode.onDismiss else { return }
        // Alleen een menu is transient: app-deactivatie en een klik buiten de
        // app sluiten het. Een `.panel` blijft staan bij een venster-/app-
        // wissel (de gebruiker klikt óók op een ander venster om te wisselen).
        if case .menu = mode {
            observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onDismiss() }
            })
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mouseDown, handler: { _ in
                MainActor.assumeIsolated { onDismiss() }
            }) { monitors.append(monitor) }
        }
        // Klik buiten het menu/paneel, binnen de app — in een ander venster
        // (het hostvenster zelf heeft óók de in-window scrim). Een klik in
        // een submenu (child window van deze panel, E57.1) is "binnen".
        let panel = self.panel
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: Self.mouseDown, handler: { event in
            if !Self.isInside(event.window, panelOrDescendantOf: panel) {
                MainActor.assumeIsolated { onDismiss() }
            }
            return event
        }) { monitors.append(monitor) }
        // Esc sluit het menu; de panel is nooit key, dus via een monitor.
        // Een submenu (child van een andere DS-panel, E57.1) laat Esc door:
        // het hoofdmenu sluit dan het geheel — de volgorde waarin AppKit
        // lokale monitors aanroept is niet gegarandeerd, dus het submenu mag
        // 'm niet als eerste opslokken.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return event }
            if panel.parent is DSFloatingPanel { return event }
            MainActor.assumeIsolated { onDismiss() }
            return nil
        }) { monitors.append(monitor) }
    }

    private static let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// `window` is de panel zelf of hangt (via `parent`) eronder — een
    /// submenu-window telt als binnen z'n menu.
    static func isInside(_ window: NSWindow?, panelOrDescendantOf panel: NSWindow) -> Bool {
        var current = window
        while let w = current {
            if w === panel { return true }
            current = w.parent
        }
        return false
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

// MARK: - Representable

/// Onzichtbare (0×0) ankerview in de SwiftUI-boom; bezit de panel-controller
/// en rekent SwiftUI `.global` om naar schermcoördinaten via z'n NSWindow.
struct DSFloatingWindowHost<Identity: Equatable>: NSViewRepresentable {
    let placement: DSFloatingPlacement
    /// Frame van deze view in SwiftUI `.global` (uit de GeometryReader van
    /// `DSFloatingWindowAnchor`).
    let hostGlobalFrame: CGRect
    let mode: DSFloatingMode
    /// Verandert de identiteit (nieuwe toast, ander anker), dan gaat de panel
    /// opnieuw naar voren — "wat het laatst verschijnt staat bovenop".
    let identity: Identity
    let environment: EnvironmentValues
    let content: AnyView

    final class Coordinator {
        var controller: DSFloatingPanelController?
        var identity: Identity?
    }

    final class AnchorView: NSView {
        var onMoveToWindow: (() -> Void)?
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onMoveToWindow?()
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView(frame: .zero)
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        let coordinator = context.coordinator
        // Maat-observatie in SwiftUI zelf: `invalidateIntrinsicContentSize`
        // op de hosting view vuurt niet betrouwbaar bij interne state-wissels
        // (het "Move to folder"-flyout maakte de HStack breder, maar de panel
        // hield z'n oude frame → inhoud gecentreerd en aan beide kanten
        // afgeknipt). De GeometryReader ziet elke maatwijziging van de
        // inhoud en laat de controller opnieuw meten/plaatsen.
        let rootView = AnyView(
            content
                .environment(\.self, environment)
                .padding(EdgeInsets(mode.margin))
                .fixedSize()
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.size) { [weak coordinator] _, _ in
                                coordinator?.controller?.scheduleRelayout()
                            }
                    }
                }
        )
        let identityChanged = coordinator.identity != identity
        coordinator.identity = identity

        if coordinator.controller == nil {
            coordinator.controller = DSFloatingPanelController(
                mode: mode,
                placement: resolvedPlacement(in: view),
                rootView: rootView
            )
        } else {
            coordinator.controller?.update(
                rootView: rootView,
                placement: resolvedPlacement(in: view),
                bringForward: identityChanged
            )
        }

        // Bij de eerste update hangt de view nog niet in een venster; dan
        // koppelt `viewDidMoveToWindow` — met een vérse plaatsing, want de
        // scherm-omrekening heeft het venster nodig.
        view.onMoveToWindow = { [weak coordinator, weak view] in
            guard let view, let window = view.window, let controller = coordinator?.controller else { return }
            controller.attach(to: window, placement: resolvedPlacement(in: view))
        }
        if let window = view.window {
            coordinator.controller?.attach(to: window, placement: resolvedPlacement(in: view))
        }
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        view.onMoveToWindow = nil
        let animated = !(coordinator.controller?.mode.isMenu ?? true)
        coordinator.controller?.close(animated: animated)
        coordinator.controller = nil
    }

    /// SwiftUI `.global` → scherm (y omhoog). De ankerview is flipped, dus
    /// een lokaal punt met SwiftUI-oriëntatie converteert direct.
    private func resolvedPlacement(in view: AnchorView) -> DSFloatingLayout.Placement {
        switch placement {
        case .corner(let alignment, let padding):
            return .corner(alignment, padding: padding)
        case .anchoredTopLeft(let global, let bounds):
            let local = CGPoint(x: global.x - hostGlobalFrame.minX, y: global.y - hostGlobalFrame.minY)
            guard let window = view.window else { return .anchoredTopLeft(local, bounds: bounds) }
            let inWindow = view.convert(local, to: nil)
            return .anchoredTopLeft(window.convertPoint(toScreen: inWindow), bounds: bounds)
        case .besideRow(let row, let panel):
            return .besideRow(row: screenRect(row, in: view), panel: screenRect(panel, in: view))
        }
    }

    /// SwiftUI `.global`-rect → scherm (y omhoog), via het venster van de
    /// ankerview — voor een submenu is dat het child window van het menu.
    private func screenRect(_ global: CGRect, in view: AnchorView) -> CGRect {
        let local = CGRect(
            x: global.minX - hostGlobalFrame.minX,
            y: global.minY - hostGlobalFrame.minY,
            width: global.width,
            height: global.height
        )
        guard let window = view.window else { return local }
        return window.convertToScreen(view.convert(local, to: nil))
    }
}

private extension EdgeInsets {
    init(_ insets: NSEdgeInsets) {
        self.init(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }
}

/// Publieke wrapper: meet z'n eigen `.global`-frame en voedt de host.
public struct DSFloatingWindowAnchor<Identity: Equatable, Content: View>: View {
    private let placement: DSFloatingPlacement
    private let mode: DSFloatingMode
    private let identity: Identity
    private let content: Content

    @Environment(\.self) private var environment
    /// Vector-export: een child window bestaat niet in ImageRenderer en de
    /// NSView-host wordt als placeholder-vlak getekend → weglaten.
    @Environment(\.dsVectorExport) private var vectorExport

    public init(
        placement: DSFloatingPlacement,
        mode: DSFloatingMode,
        identity: Identity,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.mode = mode
        self.identity = identity
        self.content = content()
    }

    public var body: some View {
        if vectorExport {
            Color.clear.frame(width: 0, height: 0)
        } else {
            anchorHost
        }
    }

    private var anchorHost: some View {
        GeometryReader { geo in
            DSFloatingWindowHost(
                placement: placement,
                hostGlobalFrame: geo.frame(in: .global),
                mode: mode,
                identity: identity,
                environment: environment,
                content: AnyView(content)
            )
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - Toast-modifier

public extension View {
    /// Toont `content(item)` als zwevende toast in een child window van het
    /// hostvenster, in `alignment`-hoek met `padding`. Nieuwe `item` (≠ de
    /// vorige) → de toast gaat naar voren, ook boven een open contextmenu;
    /// een menu dat daarna opent komt op zíjn beurt weer bovenop.
    /// `item == nil` → slide-out en weg.
    func dsFloatingToast<Item: Equatable, Content: View>(
        item: Item?,
        alignment: Alignment = .bottomTrailing,
        padding: CGFloat = DSSpacing.gap5,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        overlay(alignment: alignment) {
            if let item {
                DSFloatingWindowAnchor(
                    placement: .corner(alignment, padding: padding),
                    mode: .toast,
                    identity: item
                ) {
                    content(item)
                }
            }
        }
    }
}
