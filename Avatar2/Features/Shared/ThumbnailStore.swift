// E27.6 (Tier 3): observable thumbnail-store met OFF-MAIN decode + begrensd
// geheugen. Vervangt de synchrone `BoardThumbnailCache`: een cache-miss levert
// `nil` (de kaart toont z'n placeholder-achtergrond) en start een achtergrond-
// decode; bij voltooiing muteert de geobserveerde `images`-dict → de board
// her-rendert en pakt de net-gedecodeerde thumb op. Gekeyd op
// (id, revision, maxPixelSize) — dus elke edit die `Portrait2.revision` bumpt
// (`touch()` én `bumpRevision()`; geverifieerd: alle cutout-/adjust-paden roepen
// een van beide) ververst vanzelf. Een FIFO-cap begrenst het geheugen bij honderden
// nodes. Gedeeld board + (later) sidebar.

import AppKit
import Observation
import SwiftData

@MainActor
@Observable
final class ThumbnailStore {
    /// Gedecodeerde thumbnails (geobserveerd → een lookup in `body` wordt getrackt,
    /// dus een async-voltooiing her-rendert exact de requester).
    private var images: [String: NSImage] = [:]
    /// Tijdelijke, niet-gepersisteerde editor-preview per board-node.
    private var previews: [PersistentIdentifier: NSImage] = [:]
    /// Invoeg-volgorde voor FIFO-eviction (niet geobserveerd: puur boekhouding).
    @ObservationIgnored private var order: [String] = []
    /// Keys waarvoor al een decode loopt — voorkomt dubbele Tasks bij her-evaluatie
    /// van `body`.
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let maxCount: Int
    /// Meet-haak (voor/na in de Result) — telt échte decodes, net als de oude cache.
    @ObservationIgnored private(set) var decodeCount = 0

    init(maxCount: Int = 256) { self.maxCount = maxCount }

    /// Gecachete, verkleinde thumbnail, of `nil` zolang 'ie nog decodeert
    /// (placeholder; de thumb volgt async). `adjusted` = pas de niet-destructieve
    /// Adjust-laag toe (board = WYSIWYG, default); de sidebar toont bewust de RAUWE
    /// cutout (`adjusted: false`) zoals voorheen. Side-effect-in-body is bewust:
    /// `inFlight` maakt 'm idempotent (één decode per (id, versie, maat)).
    func thumbnail(for portrait: Portrait2, maxDimension: CGFloat, adjusted: Bool = true) -> NSImage? {
        if let preview = previews[portrait.persistentModelID] { return preview }
        let key = Self.key(portrait, maxDimension)
        if let image = images[key] { return image }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        // Alleen Sendable-waarden de Task in (Data/Int/PortraitAdjust) — nooit het
        // niet-Sendable `Portrait2`/`NSImage`. Eén instance = één modus (board óf
        // sidebar), dus de adjust-keuze hoeft niet in de key.
        let data = portrait.cutoutData
        let adjust = adjusted ? portrait.adjust : .neutral
        let maxPixelSize = Int(maxDimension.rounded())
        Task { [weak self] in
            let boxed = await Self.decode(data: data, maxPixelSize: maxPixelSize, adjust: adjust)
            self?.finish(key: key, boxed: boxed)
        }
        return nil
    }

    /// Gecachete, verkleinde ORIGINELE importfoto — voor de Original-achtergrond /
    /// Portrait-blur op de board. GÉÉN Adjust-laag: die geldt alleen voor het
    /// onderwerp (net als in de editor/export blijft de achtergrond rauw). `nil`
    /// zolang 'ie decodeert of als er geen origineel is. Gekeyd op (id, maat) —
    /// `originalData` is na import onveranderlijk, dus geen `revision` nodig.
    func original(for portrait: Portrait2, maxDimension: CGFloat) -> NSImage? {
        guard let data = portrait.originalData else { return nil }
        let key = "orig-\(portrait.persistentModelID)-\(Int(maxDimension.rounded()))"
        if let image = images[key] { return image }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        let maxPixelSize = Int(maxDimension.rounded())
        Task { [weak self] in
            let boxed = await Self.decode(data: data, maxPixelSize: maxPixelSize, adjust: .neutral)
            self?.finish(key: key, boxed: boxed)
        }
        return nil
    }

    /// Gecachete, verkleinde "originele foto"-achtergrondlaag voor de board: bij een
    /// actief effect de GESTYLEDE volle foto (zodat de backdrop bij het effect past),
    /// anders de rauwe originele foto. Gekeyd op het actieve effect (`effectActiveRaw`)
    /// zodat 'ie mee-ververst als het effect wisselt — i.t.t. `original(for:)`, dat de
    /// onveranderlijke originalData cachet. `nil` zolang 'ie decodeert / als er niets is.
    func originalBackdrop(for portrait: Portrait2, maxDimension: CGFloat) -> NSImage? {
        guard let data = portrait.effectBackgroundData ?? portrait.originalData else { return nil }
        let effectKey = portrait.effectActiveRaw ?? "none"
        let key = "origbd-\(portrait.persistentModelID)-\(effectKey)-\(Int(maxDimension.rounded()))"
        if let image = images[key] { return image }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        let maxPixelSize = Int(maxDimension.rounded())
        Task { [weak self] in
            let boxed = await Self.decode(data: data, maxPixelSize: maxPixelSize, adjust: .neutral)
            self?.finish(key: key, boxed: boxed)
        }
        return nil
    }

    func setPreview(_ image: NSImage?, for portrait: Portrait2) {
        previews[portrait.persistentModelID] = image
    }

    private static func key(_ portrait: Portrait2, _ maxDimension: CGFloat) -> String {
        // De volledige identifier i.p.v. z'n 64-bit `hashValue` — even stabiel
        // binnen de sessie, maar zonder de (theoretische) hash-collisie tussen nodes.
        "\(portrait.persistentModelID)-\(portrait.revision)-\(Int(maxDimension.rounded()))"
    }

    /// Decodeer buiten de main-actor: `nonisolated async` draait op de coöperatieve
    /// pool, dus de zware ImageIO-/CoreImage-CPU blokkeert de UI niet.
    private nonisolated static func decode(
        data: Data, maxPixelSize: Int, adjust: PortraitAdjust
    ) async -> SendableCGImage? {
        ThumbnailRenderer.render(data: data, maxPixelSize: maxPixelSize, adjust: adjust)
            .map(SendableCGImage.init)
    }

    private func finish(key: String, boxed: SendableCGImage?) {
        inFlight.remove(key)
        guard let cg = boxed?.cgImage else { return }
        images[key] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        order.append(key)
        decodeCount += 1
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--board-perf") {
            NSLog("BOARD thumb decode #\(decodeCount) key=\(key)")
        }
        #endif
        // FIFO-eviction: begrens het geheugen (~maxCount × thumb-bytes) bij honderden
        // nodes. Een teruggepande, geëvicte node decodeert kort opnieuw — prima.
        while order.count > maxCount {
            let evicted = order.removeFirst()
            images[evicted] = nil
        }
    }
}
