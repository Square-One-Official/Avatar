import AppKit
import AvatarKit

/// Voorbereide bron voor de Enhance-tegel-previews van één portret: PNG-decode,
/// downscale en gezichtsdetectie één keer, off-main, zodra de editor het
/// portret decodeert — niet pas bij paneel-open. Het paneel doet dan alleen
/// nog de goedkope compositie per tegel (ms-werk op ≤ 256 px).
///
/// Waarom: bij een verse app-start duurde de eerste Enhance-open >1 s voordat
/// de tegel-achtergronden verschenen (feedback Thierry 2026-09-03): 7 tegels
/// deden elk hun eigen vol-res Lanczos + Vision-pass, parallel en koud, en de
/// PNG-decode van de cutout viel op de main-thread.
struct EnhancePreviewPrep: @unchecked Sendable, Equatable {
    /// Identiteit voor `.task(id:)` — elke nieuwe prep is een nieuwe render.
    let token = UUID()
    let subject: EnhanceTilePreview.PreparedSubject
    /// Originele foto / effect-achtergrond op tegelformaat (Remove background).
    let backdrop: CGImage?

    static func == (lhs: EnhancePreviewPrep, rhs: EnhancePreviewPrep) -> Bool {
        lhs.token == rhs.token
    }

    /// Decodeert en bereidt voor op een achtergrond-task. `source` = rauwe
    /// cutout, `backdrop` = originele foto (of effect-achtergrond).
    static func make(source: NSImage, backdrop: NSImage?) async -> EnhancePreviewPrep? {
        let boxed = SendableNSImagePair(source: source, backdrop: backdrop)
        return await Task.detached(priority: .userInitiated) { () -> EnhancePreviewPrep? in
            guard let cg = boxed.source.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let prepared = EnhanceTilePreview.prepare(subject: cg)
            else { return nil }
            if Task.isCancelled { return nil }
            let small = boxed.backdrop
                .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                .flatMap(EnhanceTilePreview.prepareBackdrop)
            return EnhancePreviewPrep(subject: prepared, backdrop: small)
        }.value
    }
}

/// NSImage is niet Sendable, maar lezen (decode naar CGImage) vanaf een
/// achtergrond-thread is veilig zolang niemand 'm ondertussen muteert — de
/// editor houdt de gedecodeerde beelden immutable vast.
private struct SendableNSImagePair: @unchecked Sendable {
    let source: NSImage
    let backdrop: NSImage?
}
