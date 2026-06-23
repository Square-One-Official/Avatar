import Foundation

extension URL {
    /// Veilig om in een externe app/browser te openen via `NSWorkspace.open`?
    /// Alleen web- en het eigen `aaavatar`-scheme zijn toegestaan; dit blokkeert
    /// `file://`, custom app-schemes e.d. zodat een door de backend of het CMS
    /// aangeleverde URL nooit een willekeurige handler kan starten.
    var isAllowedExternalScheme: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return ["http", "https", "aaavatar"].contains(scheme)
    }
}
