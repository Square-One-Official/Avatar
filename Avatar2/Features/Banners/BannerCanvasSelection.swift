// E37.8 — Canvas-selectie in Banner Studio. Welke laag is actief op het canvas
// (tekst-id of logo); achtergrond-image-reframing gebruikt géén selectie.

import Foundation

enum BannerCanvasSelection: Equatable, Sendable {
    case text(UUID)
    case logo
    case backgroundFill
}
