// Map-default bij import: wanneer de gebruiker importeert terwijl een map
// geselecteerd is, hoort het portret in die map + krijgt het de
// geconfigureerde standaardachtergrond (indien aanwezig).

import SwiftData

enum FolderImportSupport {
    /// Koppelt een vers geïmporteerd portret aan de geselecteerde map en past
    /// desgewenst de map-default achtergrond toe.
    static func attachImport(
        portrait: Portrait2,
        section: ShellModel.AppSection,
        selectedFolderID: PersistentIdentifier?,
        modelContext: ModelContext
    ) {
        guard section == .portraits,
              let folderID = selectedFolderID,
              let folder = modelContext.model(for: folderID) as? Folder2 else { return }
        portrait.folder = folder
        if let background = folder.defaultBackground {
            portrait.setBackground(background)
        }
    }
}
