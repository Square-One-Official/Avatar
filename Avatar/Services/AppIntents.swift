import AppIntents
import Foundation

extension Notification.Name {
    /// Posted by App Intents / Shortcuts to open the import panel in the running app.
    static let aaavatarRequestImport = Notification.Name("nl.avatar.app.requestImport")
}

/// Opens Aaavatar and presents the photo import panel.
struct ImportPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Photo"
    static var description = IntentDescription("Opens Aaavatar and shows the import photo panel.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .aaavatarRequestImport, object: nil)
        }
        return .result()
    }
}

struct AvatarAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportPhotoIntent(),
            phrases: [
                "Import a photo in \(.applicationName)",
                "Import photo with \(.applicationName)",
            ],
            shortTitle: "Import Photo",
            systemImageName: "photo.badge.plus"
        )
    }
}
