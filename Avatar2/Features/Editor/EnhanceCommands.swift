// Enhance-acties in de macOS-menubalk. Zelfde focused-scene-value-brug als
// CanvasZoomCommands: de editor publiceert de closures, dit menu leest ze
// terug. Geen editor in beeld → items uitgegrijsd.

import SwiftUI

struct EnhanceCommands {
    var retouch: () -> Void = {}
    var retouchOn = false
    var studioLight: () -> Void = {}
    var studioLightOn = false
    var portrait: () -> Void = {}
    var portraitOn = false
    var colorise: () -> Void = {}
    var alreadyInColour = false
    var fillBody: () -> Void = {}
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

struct EnhanceMenuCommands: View {
    @FocusedValue(\.enhanceCommands) private var enhance

    var body: some View {
        Toggle("Retouch", isOn: Binding(
            get: { enhance?.retouchOn ?? false },
            set: { _ in enhance?.retouch() }
        ))
        .keyboardShortcut("r")
        .disabled(enhance == nil)

        Toggle("Studio Light", isOn: Binding(
            get: { enhance?.studioLightOn ?? false },
            set: { _ in enhance?.studioLight() }
        ))
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .disabled(enhance == nil)

        Toggle("Portrait", isOn: Binding(
            get: { enhance?.portraitOn ?? false },
            set: { _ in enhance?.portrait() }
        ))
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(enhance == nil)

        Divider()

        Button("Colorise") { enhance?.colorise() }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .help(enhance?.alreadyInColour == true
                  ? ColoriseAlreadyColourCopy.help
                  : ColoriseAlreadyColourCopy.defaultHelp)
            .disabled(enhance == nil)

        Button("Fill in body") { enhance?.fillBody() }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(enhance == nil)

        Divider()

        Button("Reset Adjustments") { enhance?.resetAdjustments() }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!(enhance?.canResetAdjustments ?? false))
    }
}
