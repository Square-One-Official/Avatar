// Map-default bij import: wanneer de gebruiker importeert terwijl een map
// geselecteerd is, hoort het portret in die map + krijgt het de
// geconfigureerde standaardachtergrond (indien aanwezig).

import SwiftData

enum FolderImportSupport {
    /// Map-bestemming voor een nieuwe import, afgeleid van `openOrigin`.
    ///
    /// Niet van `section` lezen: `runCutout` zet `section` al op `.editor`
    /// vóór `persist`, zodat een section-check map-imports (en hun default-
    /// achtergrond) stilletjes overslaat. `openOrigin` is op dat moment al
    /// vastgelegd als `.portraits(folderID)` of `.home`.
    static func folderID(from origin: ShellModel.OpenOrigin) -> PersistentIdentifier? {
        switch origin {
        case .portraits(let id): return id
        case .home: return nil
        }
    }

    /// Koppelt een vers geïmporteerd portret aan de bestemming-map en past
    /// desgewenst de map-default achtergrond toe. `selectedFolderID == nil`
    /// (Home of "All portraits") laat het portret unfiled + transparant.
    static func attachImport(
        portrait: Portrait2,
        selectedFolderID: PersistentIdentifier?,
        modelContext: ModelContext
    ) {
        guard let folderID = selectedFolderID,
              let folder = modelContext.model(for: folderID) as? Folder2 else { return }
        portrait.folder = folder
        if let background = folder.defaultBackground {
            portrait.setBackground(background)
        }
    }
}
