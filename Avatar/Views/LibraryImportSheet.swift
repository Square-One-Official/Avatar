import SwiftUI
import SwiftData

/// Conflict-resolution sheet shown after the user picks a back-up file to
/// import. Surfaces how many portraits will be added vs. how many already
/// exist with the same UUID, and lets the user decide what to do with the
/// overlap (default: assign fresh UUIDs so duplicates appear instead of
/// overwriting anything — the safe choice when importing someone else's
/// library).
struct LibraryImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let preview: LibraryArchive.ImportPreview

    @State private var selection: LibraryArchive.Resolution = .alwaysNew
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.libraryImportSheetTitle)
                    .font(.title2.weight(.semibold))
                Text(Loc.libraryImportSheetSummary(
                    new: preview.newCount,
                    conflicts: preview.conflictCount
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 18)

            if preview.conflictCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Loc.libraryImportSheetQuestion)
                        .font(.subheadline.weight(.medium))
                    optionRow(
                        title: Loc.libraryImportOptionAlwaysNewTitle,
                        desc: Loc.libraryImportOptionAlwaysNewDesc,
                        value: .alwaysNew
                    )
                    optionRow(
                        title: Loc.libraryImportOptionOverwriteTitle,
                        desc: Loc.libraryImportOptionOverwriteDesc,
                        value: .overwriteExisting
                    )
                    optionRow(
                        title: Loc.libraryImportOptionSkipTitle,
                        desc: Loc.libraryImportOptionSkipDesc,
                        value: .skipExisting
                    )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(Loc.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(Loc.libraryImportConfirm) { runImport() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
    }

    @ViewBuilder
    private func optionRow(title: String, desc: String, value: LibraryArchive.Resolution) -> some View {
        Button {
            selection = value
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selection == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selection == value ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selection == value ? Color.accentColor.opacity(0.10) : Color.appSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selection == value ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.18),
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runImport() {
        isImporting = true
        do {
            let summary = try LibraryArchive.performImport(
                preview: preview,
                resolution: selection,
                context: context
            )
            appState.note(Loc.libraryImportSummary(
                added: summary.added,
                overwritten: summary.overwritten,
                skipped: summary.skipped
            ))
            dismiss()
        } catch {
            isImporting = false
            let msg = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            appState.fail(Loc.libraryImportFailed(msg))
        }
    }
}
