// E49.2: ⌘U (Upload portrait) als app-brede File-menu-command. Voorheen was de
// shortcut view-scoped aan de upload-knop op Home (werkte dus niet op de board/
// editor); nu volgt hij het `SettingsCommands`/`CanvasZoomCommands`-patroon —
// de shell publiceert de actie als focused scene value, het menu-item leest 'm
// terug en grijst uit tijdens onboarding. De Home-knop houdt zijn ⌘U-badge.

import SwiftUI

/// Door `ShellView` gepubliceerde actie die het import-open-panel toont
/// (`ShellModel.presentOpenPanel`); nil tijdens onboarding → item uitgegrijsd.
struct UploadPortraitAction {
    var upload: () -> Void
}

private struct UploadPortraitKey: FocusedValueKey {
    typealias Value = UploadPortraitAction
}

extension FocusedValues {
    var uploadPortrait: UploadPortraitAction? {
        get { self[UploadPortraitKey.self] }
        set { self[UploadPortraitKey.self] = newValue }
    }
}

/// Het File-menu-item "Upload Portrait…" (⌘U).
struct UploadPortraitCommands: View {
    @FocusedValue(\.uploadPortrait) private var uploadPortrait

    var body: some View {
        Button("Upload Portrait…") { uploadPortrait?.upload() }
            .keyboardShortcut("u", modifiers: .command)
            .disabled(uploadPortrait == nil)
    }
}
