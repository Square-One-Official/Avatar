import SwiftUI

/// Lets menu commands talk to the key window's `AppState` without
/// capturing a stale environment from Settings (which also has an
/// `AppState` but shouldn't own Import/Delete).
private struct AppStateFocusedKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusedKey.self] }
        set { self[AppStateFocusedKey.self] = newValue }
    }
}

/// File / Edit / View / Find commands. Debug stays in `AvatarApp`.
struct AvatarCommands: Commands {
    @FocusedValue(\.appState) private var appState
    @AppStorage("showAlignmentGuide") private var showAlignmentGuide = false

    private var canExport: Bool { !(appState?.selectedPortraitIDs.isEmpty ?? true) }
    private var canDelete: Bool { !(appState?.selectedPortraitIDs.isEmpty ?? true) }
    private var canToggleInspector: Bool {
        guard let appState else { return false }
        return appState.selectedPortraitID != nil && appState.selectedPortraitIDs.count <= 1
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(Loc.importPhoto) {
                appState?.requestImport()
            }
            .keyboardShortcut("n")
            .disabled(appState == nil)

            Button(Loc.openEllipsis) {
                appState?.requestImport()
            }
            .keyboardShortcut("o")
            .disabled(appState == nil)
        }

        CommandGroup(after: .newItem) {
            Button(Loc.export) {
                appState?.requestExport()
            }
            .keyboardShortcut("e")
            .disabled(!canExport)
        }

        CommandGroup(after: .pasteboard) {
            Button(deleteTitle) {
                appState?.requestDelete()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!canDelete)
        }

        CommandGroup(after: .textEditing) {
            Button(Loc.find) {
                appState?.focusLibrarySearch()
            }
            .keyboardShortcut("f")
            .disabled(appState == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(appState?.sidebarHidden == true ? Loc.showSidebar : Loc.hideSidebar) {
                appState?.sidebarHidden.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(appState == nil)

            Button(appState?.showInspector == true ? Loc.hideInspector : Loc.showInspector) {
                appState?.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!canToggleInspector)

            Divider()

            Toggle(Loc.alignmentShowGuide, isOn: $showAlignmentGuide)
        }
    }

    private var deleteTitle: String {
        let count = appState?.selectedPortraitIDs.count ?? 0
        if count > 1 {
            return "\(Loc.delete) \(count) \(Loc.portraitsPlural)"
        }
        return Loc.delete
    }
}
