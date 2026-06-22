// E27.6 (Tier 3): observable thumbnail-store met OFF-MAIN decode + begrensd
// geheugen. Vervangt de synchrone `BoardThumbnailCache`: een cache-miss levert
// `nil` (de kaart toont z'n placeholder-achtergrond) en start een achtergrond-
// decode; bij voltooiing muteert de geobserveerde `images`-dict → de board
// her-rendert en pakt de net-gedecodeerde thumb op. Gekeyd op
// (id, updatedAt, maxPixelSize) — net als `SidebarThumbnailCache` — dus elke
// edit die `updatedAt` bumpt (geverifieerd: alle cutout-/adjust-paden roepen
// `touch()`) ververst vanzelf. Een FIFO-cap begrenst het geheugen bij honderden
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

    /// Bron-compat met de oude `BoardThumbnailCache`: met (id, updatedAt)-keying is
    /// invalidatie automatisch (een edit bumpt `updatedAt` → nieuwe key → verse
    /// decode), dus dit is een no-op. Behouden zodat de bestaande call-sites
    /// (undo-closures e.d.) ongemoeid blijven.
    func invalidate(_ portrait: Portrait2) {}

    private static func key(_ portrait: Portrait2, _ maxDimension: CGFloat) -> String {
        "\(portrait.persistentModelID.hashValue)-\(portrait.updatedAt.timeIntervalSince1970)-\(Int(maxDimension.rounded()))"
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
