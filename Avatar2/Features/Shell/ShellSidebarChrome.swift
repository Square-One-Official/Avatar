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
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
    }
}

struct ShellSidebarChrome: View {
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ShellSidebarChromeStrip()
                .padding(.leading, LeftNavView.edgeInset)
                .padding(.top, LeftNavView.edgeInset)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: isSidebarVisible ? LeftNavView.chromeRevealWidth : 0)
                }
            SidebarToggleButton(isSidebarVisible: isSidebarVisible, action: onToggleSidebar)
                .padding(.leading, ShellMetrics.topBarLeadingAfterWindowControls)
                .frame(height: ShellMetrics.windowControlsRowHeight)
        }
        .frame(height: LeftNavView.windowChromeHeight, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct ShellSidebarChromeStrip: View {
    var body: some View {
        DSColor.Background.card
            .frame(width: LeftNavView.width, height: LeftNavView.windowChromeHeight)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: DSRadius.concentric(inset: LeftNavView.edgeInset),
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: DSRadius.concentric(inset: LeftNavView.edgeInset),
                    style: .continuous
                )
            )
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

        let leading: CGFloat = 12
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
