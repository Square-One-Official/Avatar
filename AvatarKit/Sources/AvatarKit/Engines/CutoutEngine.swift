import CoreGraphics
import Foundation

/// De drie cutout-paden uit de 1.x-pipeline. Volgorde = voorkeursvolgorde
/// van de router wanneer geen expliciete keuze is gemaakt.
public enum CutoutEngineKind: String, CaseIterable, Sendable {
    /// Apple Vision person-segmentation (on-device, default).
    case vision
    /// Gedownload ORMBG-model (on-device, opt-in download).
    case ormbg
    /// Replicate cloud (`men1scus/birefnet`), Pro-pad.
    case replicate
}

/// Eén achtergrond-verwijder-engine. Implementaties komen in E02
/// (`AvatarKit/Engines/`, team AI).
public protocol CutoutEngine: Sendable {
    var kind: CutoutEngineKind { get }

    /// Of de engine nu bruikbaar is (model gedownload, netwerk, entitlement).
    var isAvailable: Bool { get async }

    /// Snijdt de persoon uit en geeft een afbeelding met alpha terug.
    func cutout(_ image: CGImage) async throws -> CGImage
}

public enum CutoutEngineError: Error, Equatable {
    case unavailable(CutoutEngineKind)
    case noEngineAvailable
}
