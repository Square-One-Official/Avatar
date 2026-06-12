// Sidebar/set-model (E05.4). Eigen SwiftData-store van Avatar2, volledig
// los van de v1-store (andere bundle-id én eigen container) — v1 blijft
// onaangeraakt. Cutout als externe blob; thumbnails rendert de sidebar
// uit dezelfde data.

import Foundation
import SwiftData

@Model
final class Portrait2 {
    var name: String
    var role: String
    var createdAt: Date
    /// Laatst bewerkt (visuele pass punt 13) — bijgewerkt bij elke mutatie
    /// (naam/rol/cutout; achtergrond zodra dat veld bestaat). Sidebar
    /// sorteert hierop (jongste bovenaan) en launch selecteert de jongste.
    /// Migratie: lichtgewicht via de default `.distantPast`; ShellModel
    /// zet bestaande rijen eenmalig op `createdAt` (de bedoelde default —
    /// SwiftData kan niet naar een ander veld defaulten).
    var updatedAt: Date = Date.distantPast
    @Attribute(.externalStorage) var cutoutData: Data

    init(name: String = "", role: String = "", createdAt: Date = .now, cutoutData: Data) {
        self.name = name
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.cutoutData = cutoutData
    }

    /// Markeer als zojuist bewerkt.
    func touch() {
        updatedAt = .now
    }
}
