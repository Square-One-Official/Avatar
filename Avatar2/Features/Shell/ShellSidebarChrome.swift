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
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DSColor.Foreground.muted)
                .frame(width: ShellMetrics.sidebarToggleWidth, height: ShellMetrics.sidebarToggleWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
    }
}

struct ShellSidebarChrome: View {
    let isSidebarVisible: Bool
    var studioFullBleed: Bool = false
    let onToggleSidebar: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if studioFullBleed {
                LinearGradient(
                    colors: [DSColor.Background.card, DSColor.Background.card.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(
                    width: ShellMetrics.topBarLeadingAfterWindowControls + ShellMetrics.sidebarToggleWidth,
                    height: LeftNavView.windowChromeHeight
                )
                .allowsHitTesting(false)
            }

            ShellSidebarChromeStrip()
                .padding(.leading, LeftNavView.edgeInset)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: isSidebarVisible ? LeftNavView.chromeRevealWidth : 0)
                }
            SidebarToggleButton(isSidebarVisible: isSidebarVisible, action: onToggleSidebar)
                .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
                .frame(height: ShellMetrics.windowControlsRowHeight)
        }
        .frame(height: ShellSidebarChromeStrip.height, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct ShellSidebarChromeStrip: View {
    /// UXS-29: de strip loopt vanaf de venstertop (y = 0) t/m de oude
    /// top-inset, zodat de traffic-lights + toggle óp kaartmateriaal liggen.
    /// Vierkante hoeken: de kaart dokt aan de venstertop (LeftNavView clipt
    /// zelf alleen de onderhoeken nog).
    static var height: CGFloat { LeftNavView.windowChromeHeight + LeftNavView.edgeInset }

    var body: some View {
        DSColor.Background.card
            .frame(width: LeftNavView.width, height: Self.height)
            .allowsHitTesting(false)
    }
}

/// Houdt de OS-traffic-lights op een vaste vensterpositie — onafhankelijk
/// van sidebar-animaties of content-layout shifts.
struct WindowTrafficLightStabilizer: NSViewRepresentable {
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

        // UXS-29: 20pt (native macOS-positie) — geeft de rode knop ademruimte
        // t.o.v. de kaartrand op x = windowEdgeInset (12).
        let leading: CGFloat = 20
        let spacing: CGFloat = 8
        var x = leading
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            let origin = button.frame.origin
            button.setFrameOrigin(NSPoint(x: x, y: origin.y))
            x += button.frame.width + spacing
        }
    }
}
