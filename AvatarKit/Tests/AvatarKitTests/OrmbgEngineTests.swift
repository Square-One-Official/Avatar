import CoreML
import XCTest
@testable import AvatarKit

/// Het echte ORMBG-model is een download van ~45 MB en hoort niet in een
/// unit-test; deze tests dekken de modelvrije delen: matte-extractie uit
/// synthetische model-output, de float16-decodering, beschikbaarheid
/// zonder installatie en de SHA-256-gate-helper.
final class OrmbgEngineTests: XCTestCase {

    // MARK: - Matte-extractie uit MLMultiArray

    /// Verticale gradiënt als (1,1,H,W) float32-tensor, zoals een
    /// DIS-matting-head hem teruggeeft.
    private func gradientProvider(dataType: MLMultiArrayDataType) throws -> MLFeatureProvider {
        let h = 8, w = 8
        let array = try MLMultiArray(shape: [1, 1, NSNumber(value: h), NSNumber(value: w)],
                                     dataType: dataType)
        for y in 0..<h {
            for x in 0..<w {
                array[y * w + x] = NSNumber(value: Float(y) / Float(h - 1))
            }
        }
        return try MLDictionaryFeatureProvider(dictionary: [
            "var_4090": MLFeatureValue(multiArray: array)
        ])
    }

    func testExtractMaskFromFloat32MultiArray() throws {
        let mask = OrmbgEngine.extractMask(from: try gradientProvider(dataType: .float32))
        let unwrapped = try XCTUnwrap(mask)
        XCTAssertEqual(unwrapped.extent.width, 8)
        XCTAssertEqual(unwrapped.extent.height, 8)
    }

    func testExtractMaskFromFloat16MultiArray() throws {
        let mask = OrmbgEngine.extractMask(from: try gradientProvider(dataType: .float16))
        let unwrapped = try XCTUnwrap(mask)
        XCTAssertEqual(unwrapped.extent.width, 8)
        XCTAssertEqual(unwrapped.extent.height, 8)
    }

    func testExtractMaskReturnsNilWithoutUsableOutput() throws {
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "irrelevant": MLFeatureValue(string: "geen tensor")
        ])
        XCTAssertNil(OrmbgEngine.extractMask(from: provider))
    }

    // MARK: - Float16-decodering

    func testFloat16BitsToFloat() {
        XCTAssertEqual(OrmbgEngine.float16BitsToFloat(0x0000), 0)
        XCTAssertEqual(OrmbgEngine.float16BitsToFloat(0x3C00), 1)      // 1.0
        XCTAssertEqual(OrmbgEngine.float16BitsToFloat(0xBC00), -1)     // -1.0
        XCTAssertEqual(OrmbgEngine.float16BitsToFloat(0x3800), 0.5)    // 0.5
        XCTAssertEqual(OrmbgEngine.float16BitsToFloat(0x7C00), .infinity)
        XCTAssertTrue(OrmbgEngine.float16BitsToFloat(0x7E00).isNaN)
        // Subnormaal: kleinste positieve half = 2^-24.
        XCTAssertEqual(OrmbgEngine.float16BitsToFloat(0x0001), Float(exactly: pow(2.0, -24))!)
    }

    // MARK: - Beschikbaarheid en store

    func testEngineUnavailableWithoutInstalledModel() async {
        let store = OrmbgModelStore(baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ormbg-test-\(UUID().uuidString)", isDirectory: true))
        let engine = OrmbgEngine(store: store)
        let available = await engine.isAvailable
        XCTAssertFalse(available)
    }

    func testCutoutWithoutModelThrowsUnavailable() async {
        let store = OrmbgModelStore(baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ormbg-test-\(UUID().uuidString)", isDirectory: true))
        let engine = OrmbgEngine(store: store)
        let fixture = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            .makeImage()!
        do {
            _ = try await engine.cutout(fixture)
            XCTFail("Verwachtte unavailable zonder geïnstalleerd model")
        } catch let error as CutoutEngineError {
            XCTAssertEqual(error, .unavailable(.ormbg))
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }

    func testInstalledModelURLFindsModelDirOnDisk() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ormbg-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = OrmbgModelStore(baseDirectory: base)
        XCTAssertNil(store.installedModelURL())

        let modelDir = base.appendingPathComponent("v1/matting-model.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        XCTAssertEqual(store.installedModelURL(), modelDir)
    }

    // MARK: - SHA-256

    func testSHA256MatchesKnownDigest() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha-test-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        // NIST-testvector voor SHA-256("abc").
        XCTAssertEqual(try OrmbgModelStore.sha256(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
