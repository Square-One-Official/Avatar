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

/// Editor enhance actions published by `EnhancePanel` so the menu bar can
/// drive the same apply/undo/reset paths as the inspector tiles.
struct EnhanceCommands {
    var autoAlign: () -> Void = {}
    var canAutoAlign = false
    var toggleMagicRetouch: () -> Void = {}
    var canMagicRetouch = false
    var isMagicRetouched = false
    var toggleFillBody: () -> Void = {}
    var canFillBody = false
    var isFillBodyApplied = false
    var showFillBody = false
    var toggleColorize: () -> Void = {}
    var canColorize = false
    var isColorized = false
    var showColorize = false
    var resetAdjustments: () -> Void = {}
    var canResetAdjustments = false
}

private struct EnhanceCommandsKey: FocusedValueKey {
    typealias Value = EnhanceCommands
}

extension FocusedValues {
    var enhanceCommands: EnhanceCommands? {
        get { self[EnhanceCommandsKey.self] }
        set { self[EnhanceCommandsKey.self] = newValue }
    }
}

/// File / Edit / View / Find commands. Debug stays in `AvatarApp`.
struct AvatarCommands: Commands {
    @FocusedValue(\.appState) private var appState
    @FocusedValue(\.enhanceCommands) private var enhance
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

        CommandMenu(Loc.enhanceMenu) {
            Button(Loc.autoAlignFace) {
                enhance?.autoAlign()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!(enhance?.canAutoAlign ?? false))

            Divider()

            Toggle(Loc.magicRetouch, isOn: Binding(
                get: { enhance?.isMagicRetouched ?? false },
                set: { _ in enhance?.toggleMagicRetouch() }
            ))
            .keyboardShortcut("r")
            .disabled(!(enhance?.canMagicRetouch ?? false))

            if enhance?.showFillBody ?? false {
                Toggle(Loc.fillBody, isOn: Binding(
                    get: { enhance?.isFillBodyApplied ?? false },
                    set: { _ in enhance?.toggleFillBody() }
                ))
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!(enhance?.canFillBody ?? false))
            }

            if enhance?.showColorize ?? false {
                Toggle(Loc.colorize, isOn: Binding(
                    get: { enhance?.isColorized ?? false },
                    set: { _ in enhance?.toggleColorize() }
                ))
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!(enhance?.canColorize ?? false))
            }

            Divider()

            Button(Loc.resetAdjustments) {
                enhance?.resetAdjustments()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!(enhance?.canResetAdjustments ?? false))
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
