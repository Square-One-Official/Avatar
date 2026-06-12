import CoreGraphics
import Foundation
import Testing
@testable import AvatarKit

/// CloudCutoutEngine (E02.4): adapter rond BackendClient.cutout. Tests
/// draaien zonder netwerk — de drie wire-calls (upload-url, PUT, cutout)
/// worden gestubd via een custom URLProtocol op een geïnjecteerde
/// URLSession, het notSignedIn-pad faalt al vóór enige I/O.
@MainActor
struct CloudCutoutEngineTests {

    final class FakeAuth: AccessTokenProviding {
        var accessToken: String?
        init(token: String? = nil) { accessToken = token }
    }

    private nonisolated static func makeOpaqueImage(width: Int = 8, height: Int = 8) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// PNG met half-transparante rand — checkt dat alpha de roundtrip overleeft.
    nonisolated static func makeAlphaPNG() -> Data {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 8, height: 8,
                            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: 8, height: 8))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 2, y: 2, width: 4, height: 4))
        return CloudCutoutEngine.pngData(from: ctx.makeImage()!)!
    }

    // NB: BackendClient houdt `unowned let auth` (productie: AuthManager
    // overleeft de client). Tests moeten de fake dus expliciet in leven
    // houden tot ná de laatste client-call — vandaar withExtendedLifetime.

    @Test func kindIsReplicate() {
        let auth = FakeAuth()
        withExtendedLifetime(auth) {
            let client = BackendClient(auth: auth)
            #expect(CloudCutoutEngine(client: client).kind == .replicate)
        }
    }

    @Test func unavailableWithoutSessionAvailableWith() async {
        let auth = FakeAuth()
        let client = BackendClient(auth: auth)
        let engine = CloudCutoutEngine(client: client)
        #expect(await engine.isAvailable == false)
        auth.accessToken = "token"
        #expect(await engine.isAvailable == true)
        withExtendedLifetime(auth) {}
    }

    @Test func cutoutWithoutSessionThrowsNotSignedIn() async {
        let auth = FakeAuth()
        let client = BackendClient(auth: auth)
        let engine = CloudCutoutEngine(client: client)
        await #expect(throws: BackendError.self) {
            _ = try await engine.cutout(Self.makeOpaqueImage())
        }
        withExtendedLifetime(auth) {}
    }

    @Test func pngRoundtripPreservesDimensionsAndAlpha() {
        let png = Self.makeAlphaPNG()
        let decoded = CloudCutoutEngine.cgImage(fromPNG: png)
        #expect(decoded != nil)
        #expect(decoded?.width == 8)
        #expect(decoded?.height == 8)
        #expect(decoded?.alphaInfo != CGImageAlphaInfo.none)
    }

    @Test func cutoutHappyPathThroughStubbedWire() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        let auth = FakeAuth(token: "token")
        let client = BackendClient(auth: auth, session: session)
        let engine = CloudCutoutEngine(client: client)

        let result = try await engine.cutout(Self.makeOpaqueImage())
        #expect(result.width == 8)
        #expect(result.height == 8)
        #expect(StubProtocol.sawUpload)
        withExtendedLifetime(auth) {}
    }

    /// Stubt de drie wire-calls van het cutout-pad. Routeert op pad — geen
    /// volgorde-aannames buiten wat BackendClient afdwingt.
    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var sawUpload = false

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url!
            let (status, body): (Int, Data)
            switch url.path {
            case "/v1/cutout/upload-url":
                body = try! JSONSerialization.data(withJSONObject: [
                    "url": "https://stub.invalid/put-target", "key": "uploads/k1",
                ])
                status = 200
            case "/put-target":
                Self.sawUpload = true
                body = Data()
                status = 200
            case "/v1/cutout":
                let png = CloudCutoutEngineTests.makeAlphaPNG()
                body = try! JSONSerialization.data(withJSONObject: [
                    "cutout": png.base64EncodedString(), "credits_remaining": 41,
                ])
                status = 200
            default:
                body = Data()
                status = 404
            }
            let response = HTTPURLResponse(url: url, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
