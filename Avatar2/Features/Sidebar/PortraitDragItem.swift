// PoC (left-nav): sleep-payload om een portret van Home of de Portraits-grid
// naar een map in de left-nav te slepen. Draagt alléén de SwiftData-identiteit
// (`PersistentIdentifier`, Codable) over de pasteboard — de drop-kant haalt het
// echte Portrait2 op via `modelContext.model(for:)`. Eigen geëxporteerd UTType
// zodat deze interne sleep niet botst met de venster-brede foto-import
// (.fileURL/.image) in ShellView.

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PortraitDragItem: Codable, Transferable {
    let id: PersistentIdentifier

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .aaavatarPortraitRef)
    }
}

extension UTType {
    /// Geëxporteerd in Info.plist (project.yml → Avatar2 `UTExportedTypeDeclarations`).
    static let aaavatarPortraitRef = UTType(exportedAs: "nl.squareone.aaavatar2.portrait-ref")
}
