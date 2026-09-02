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

public enum DSFloatingPlacement: Equatable {
    /// Menu: linksboven van de inhoud op dit punt in SwiftUI `.global`;
    /// geklemd binnen het zichtbare scherm.
    case anchoredTopLeft(CGPoint)
    /// Toast: in een hoek van het hostvenster, `padding` van de rand.
    case corner(Alignment, padding: CGFloat)
}

// MARK: - Layout (puur, testbaar; schermcoördinaten, y omhoog)

enum DSFloatingLayout {
    enum Placement: Equatable {
        case anchoredTopLeft(CGPoint)
        case corner(Alignment, padding: CGFloat)
    }

    struct Frames: Equatable {
        /// Vensterframe van de panel = zichtbare regio (clip).
        let panel: CGRect
        /// Frame van de hosting view (inhoud + schaduwmarge) binnen de panel;
        /// mag buiten de panel steken en wordt dan afgeknipt.
        let hosting: CGRect
    }

    /// Waar de inhoud (zónder schaduwmarge) op het scherm komt.
    /// - anchoredTopLeft: op het anker; klemt binnen `screen` met `padding`.
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
        case .anchoredTopLeft(let topLeft):
            let x = min(
                max(topLeft.x, screen.minX + padding),
                max(screen.minX + padding, screen.maxX - size.width - padding)
            )
            let upper = screen.maxY - padding
            let lower = screen.minY + padding + size.height
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
        }
    }

    /// Menu's mogen over de vensterrand heen (clip = scherm); toasts blijven
    /// binnen het hostvenster (clip = parent), net als de oude overlay.
    static func clipRect(placement: Placement, parent: CGRect, screen: CGRect) -> CGRect {
        switch placement {
        case .anchoredTopLeft: return screen
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

public enum DSFloatingMode {
    /// Contextmenu: sluit op klik buiten het menu (ook buiten de app), Esc,
    /// app-deactivatie en verplaatsen/resizen van het hostvenster.
    case menu(onDismiss: () -> Void)
    /// Toast: blijft staan; volgt het hostvenster; slide-in/out zoals
    /// `.dsSlide(.trailing)` (reduce motion → alleen fade).
    case toast

    /// Schaduwmarge rond de inhoud. Menu: `dsMenuSurface` (radius 12, y 12).
    /// Toast: DSToast (radius 40, y 40 — de gehalveerde Shadows/Default).
    var margin: NSEdgeInsets {
        switch self {
        case .menu: return NSEdgeInsets(top: 12, left: 24, bottom: 36, right: 24)
        case .toast: return NSEdgeInsets(top: 40, left: 80, bottom: 120, right: 80)
        }
    }

    var isMenu: Bool {
        if case .menu = self { return true }
        return false
    }
}

// MARK: - Panel + hosting view

final class DSFloatingPanel: NSPanel {
    /// Voor debugging/tests: welke modus deze panel host.
    fileprivate(set) var isToast = false

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

    // Nooit key/main: het hostvenster houdt focus; Esc loopt via een
    // event-monitor. SwiftUI-hover en -clicks werken zonder key-status
    // (acceptsFirstMouse op de hosting view).
    override var canBecomeKey: Bool { false }
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
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
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
                    switch self.mode {
                    case .menu(let onDismiss): onDismiss()
                    case .toast: self.relayout(animated: false)
                    }
                }
            })
        }

        guard case .menu(let onDismiss) = mode else { return }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onDismiss() }
        })
        // Klik buiten het menu — in een ander venster van de app (het
        // hostvenster zelf heeft óók de in-window scrim) of buiten de app.
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let panel = self.panel
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: { event in
            if event.window !== panel {
                MainActor.assumeIsolated { onDismiss() }
            }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: { _ in
            MainActor.assumeIsolated { onDismiss() }
        }) { monitors.append(monitor) }
        // Esc sluit het menu; de panel is nooit key, dus via een monitor.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { onDismiss() }
            return nil
        }) { monitors.append(monitor) }
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
        case .anchoredTopLeft(let global):
            let local = CGPoint(x: global.x - hostGlobalFrame.minX, y: global.y - hostGlobalFrame.minY)
            guard let window = view.window else { return .anchoredTopLeft(local) }
            let inWindow = view.convert(local, to: nil)
            return .anchoredTopLeft(window.convertPoint(toScreen: inWindow))
        }
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
