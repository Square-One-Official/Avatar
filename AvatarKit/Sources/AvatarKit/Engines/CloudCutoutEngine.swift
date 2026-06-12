import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cloud-pad: Magic Cutout via de backend — BiRefNet op Replicate,
/// aangeroepen door het bestaande `/v1/cutout`. Dunne adapter rond
/// `BackendClient.cutout`: CGImage → PNG → upload/run → PNG-met-alpha →
/// CGImage. Uploadflow (signed PUT naar Supabase Storage, zodat Vercel's
/// body-cap nooit speelt), creditaftrek en foutsemantiek (402 →
/// `BackendError.noCredits`, 401 → `.unauthorized`, …) leven in
/// BackendClient en propageren ongewijzigd naar de aanroeper.
///
/// `creditsRemaining` uit de response wordt hier bewust genegeerd: het
/// engine-protocol heeft daar geen kanaal voor, en in 2.0 is `me()` /
/// het entitlement-model de bron van waarheid voor saldo-weergave.
public struct CloudCutoutEngine: CutoutEngine {
    public enum Failure: Error, Equatable {
        case encodeFailed
        case decodeFailed
    }

    public let kind: CutoutEngineKind = .replicate

    private let client: BackendClient

    public init(client: BackendClient) {
        self.client = client
    }

    /// Beschikbaar zodra er een sessie is. Bewust géén netwerk-probe of
    /// credit-check — dat zou elke routerbeslissing een roundtrip kosten;
    /// de backend zelf is de waarheid op het moment van de call (402/401).
    public var isAvailable: Bool {
        get async { await client.hasSession }
    }

    public func cutout(_ image: CGImage) async throws -> CGImage {
        guard let png = Self.pngData(from: image) else {
            throw Failure.encodeFailed
        }
        let (resultPNG, _) = try await client.cutout(imagePNG: png)
        guard let result = Self.cgImage(fromPNG: resultPNG) else {
            throw Failure.decodeFailed
        }
        return result
    }

    // MARK: - PNG ↔ CGImage (intern, ook door tests gebruikt)

    static func pngData(from image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    static func cgImage(fromPNG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
