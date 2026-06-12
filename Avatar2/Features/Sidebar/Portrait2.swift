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
    @Attribute(.externalStorage) var cutoutData: Data

    init(name: String = "", role: String = "", createdAt: Date = .now, cutoutData: Data) {
        self.name = name
        self.role = role
        self.createdAt = createdAt
        self.cutoutData = cutoutData
    }
}
