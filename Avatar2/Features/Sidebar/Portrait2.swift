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
    /// Originele importfoto (E06.2 hold-to-compare): ingedrukt houden toont
    /// dit i.p.v. de cutout. Optioneel + externalStorage; bestaande rijen
    /// (migratie default nil) verbergen de compare-knop.
    @Attribute(.externalStorage) var originalData: Data?

    /// Canvas-transform (E06.4) in 1024-units canvasruimte (v1-conventie):
    /// het cutout-beeld tekent op (offsetX, offsetY) × scale binnen het
    /// 1:1-canvas. scale 0 = nog geen transform — de editor toont dan de
    /// berekende fill-fit en persisteert pas bij het eerste gebaar.
    /// Lichtgewicht migratie via de defaults.
    var offsetX: Double = 0
    var offsetY: Double = 0
    var scale: Double = 0

    init(
        name: String = "",
        role: String = "",
        createdAt: Date = .now,
        cutoutData: Data,
        originalData: Data? = nil
    ) {
        self.name = name
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.cutoutData = cutoutData
        self.originalData = originalData
    }

    /// Markeer als zojuist bewerkt.
    func touch() {
        updatedAt = .now
    }
}
