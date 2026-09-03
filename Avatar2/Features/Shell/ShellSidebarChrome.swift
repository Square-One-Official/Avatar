// Vaste venster-chrome voor de left-nav: traffic-light-strook + sidebar-toggle.
// Losgekoppeld van de animerende nav-body zodat OS-controls niet meeschuiven
// wanneer de sidebar in- of uitklapt.

import AppKit
import AvatarUI
import SwiftUI

struct SidebarToggleButton: View {
    let isSidebarVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: DSIconSize.base, weight: .regular))
                .foregroundStyle(DSColor.Foreground.muted)
                .frame(width: ShellMetrics.sidebarToggleWidth, height: ShellMetrics.sidebarToggleWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
    }
}

struct ShellSidebarChrome: View {
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // UXS-29(v2): de toggle centreert op de verlaagde traffic-light-lijn
            // (native unified-toolbar-hoogte) — dezelfde rij, ín de kaart.
            SidebarToggleButton(isSidebarVisible: isSidebarVisible, action: onToggleSidebar)
                .frame(height: ShellMetrics.windowControlsRowHeight)
                .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
                .padding(.top, ShellMetrics.windowControlsCenterFromTop - ShellMetrics.windowControlsRowHeight / 2)
        }
        .frame(height: LeftNavView.windowChromeHeight, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Houdt de OS-traffic-lights op een vaste vensterpositie — onafhankelijk
/// van sidebar-animaties of content-layout shifts.
struct WindowTrafficLightStabilizer: View {
    @Environment(\.dsVectorExport) private var vectorExport
    var body: some View {
        if vectorExport { Color.clear } else { WindowTrafficLightStabilizerRepresentable() }
    }
}

struct WindowTrafficLightStabilizerRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TrafficLightAnchorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrafficLightAnchorView)?.stabilise()
    }
}

private final class TrafficLightAnchorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stabilise()
    }

    override func layout() {
        super.layout()
        stabilise()
    }

    func stabilise() {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        // UXS-29(v2)/UX34: native verlaagde traffic-lights. Een lege unified
        // toolbar maakt de titelbalk hoog genoeg dat AppKit de knoppen zélf
        // lager centreert — ín de zwevende sidebar-kaart (top-inset gap3).
        // Geen frame-hacks: positie, hover én hit-testing blijven van het OS.
        if window.toolbar == nil {
            window.toolbarStyle = .unified
            let toolbar = NSToolbar(identifier: "ShellWindowChrome")
            toolbar.showsBaselineSeparator = false
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
    }
}
