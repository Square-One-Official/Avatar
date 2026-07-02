// E42 — Sheet-presentatie op een stabiele host (overleeft toolbar/tab-wissels).

import SwiftUI

@MainActor
@Observable
final class GenerateBackgroundPresenter {
    static let shared = GenerateBackgroundPresenter()

    var isPresented = false
    private(set) var context: BackgroundGenerationContext = .portrait
    private(set) var applyAfterSave = true
    private var onSavedHandler: ((Data) -> Void)?

    func present(
        context: BackgroundGenerationContext,
        applyAfterSave: Bool = true,
        onSaved: @escaping (Data) -> Void
    ) {
        self.context = context
        self.applyAfterSave = applyAfterSave
        self.onSavedHandler = onSaved
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        onSavedHandler = nil
    }

    func complete(with data: Data) {
        onSavedHandler?(data)
        dismiss()
    }
}

extension View {
    /// Presenteert `GenerateBackgroundSheet` op deze host — blijft open bij
    /// toolbar-/tab-wissels in de editor. Alleen sluitbaar via × of Cancel.
    func generateBackgroundSheet(entitlement: EntitlementModel?) -> some View {
        modifier(GenerateBackgroundSheetHost(entitlement: entitlement))
    }
}

private struct GenerateBackgroundSheetHost: ViewModifier {
    var entitlement: EntitlementModel?
    @Bindable private var presenter = GenerateBackgroundPresenter.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presenter.isPresented, onDismiss: { presenter.dismiss() }) {
                GenerateBackgroundSheet(
                    context: presenter.context,
                    entitlement: entitlement,
                    applyAfterSave: presenter.applyAfterSave,
                    onSaved: { presenter.complete(with: $0) }
                )
                .interactiveDismissDisabled(true)
            }
    }
}
