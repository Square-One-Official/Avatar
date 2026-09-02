import AppKit
import SwiftData

extension Notification.Name {
    /// Select a portrait by UUID (posted from the Dock menu).
    static let aaavatarSelectPortrait = Notification.Name("nl.avatar.app.selectPortrait")
}

/// AppKit bridge for Dock menu + anything else SwiftUI scenes can't host.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var modelContainer: ModelContainer?

    func configure(appState: AppState, container: ModelContainer) {
        self.appState = appState
        self.modelContainer = container
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Clears a stuck Google OAuth spinner when the user returns from
        // the browser without completing sign-in.
        appState?.auth.handleAppBecameActive()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let importItem = NSMenuItem(
            title: Loc.importPhoto,
            action: #selector(dockImport),
            keyEquivalent: ""
        )
        importItem.target = self
        menu.addItem(importItem)

        let recent = recentPortraits(limit: 5)
        if !recent.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: Loc.dockRecent, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for portrait in recent {
                let title = portrait.name.isEmpty ? Loc.unnamed : portrait.name
                let item = NSMenuItem(
                    title: title,
                    action: #selector(dockOpenPortrait(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = portrait.id.uuidString
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc private func dockImport() {
        NotificationCenter.default.post(name: .aaavatarRequestImport, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func dockOpenPortrait(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString) else { return }
        NotificationCenter.default.post(name: .aaavatarSelectPortrait, object: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func recentPortraits(limit: Int) -> [Portrait] {
        guard let container = modelContainer else { return [] }
        let context = container.mainContext
        var descriptor = FetchDescriptor<Portrait>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
