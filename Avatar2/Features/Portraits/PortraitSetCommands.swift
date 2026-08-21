// Edit-menu commands voor Match Framing / Match Lighting / Set Background
// (HIG 1.1–1.3): dezelfde acties als het gallery-contextmenu, met shortcuts
// en disable wanneer de selectie te klein is.

import SwiftUI

struct PortraitSetAction {
    var selectedCount: Int
    var matchFraming: () -> Void
    var matchLighting: () -> Void
    var setBackground: () -> Void
}

private struct PortraitSetKey: FocusedValueKey {
    typealias Value = PortraitSetAction
}

extension FocusedValues {
    var portraitSet: PortraitSetAction? {
        get { self[PortraitSetKey.self] }
        set { self[PortraitSetKey.self] = newValue }
    }
}

struct PortraitSetCommands: View {
    @FocusedValue(\.portraitSet) private var portraitSet

    var body: some View {
        let count = portraitSet?.selectedCount ?? 0
        Button("Match Framing") { portraitSet?.matchFraming() }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(portraitSet == nil || count < 2)
        Button("Match Lighting") { portraitSet?.matchLighting() }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(portraitSet == nil || count < 2)
        Button("Set Background…") { portraitSet?.setBackground() }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(portraitSet == nil || count < 1)
    }
}
