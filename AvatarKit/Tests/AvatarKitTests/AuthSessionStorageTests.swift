import CryptoKit
import Foundation
import XCTest
@testable import AvatarKit

final class AuthSessionStorageTests: XCTestCase {
    private var directory: URL!
    private var storage: AuthSessionFileStorage!

    override func setUpWithError() throws {
        // Vaste testsleutel zodat de Keychain niet wordt aangeraakt — de
        // ongesigneerde testrunner mag het login-keychain niet vervuilen.
        AuthSessionEncryption.keyOverrideForTesting = SymmetricKey(size: .bits256)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthSessionStorageTests-\(UUID().uuidString)")
        storage = AuthSessionFileStorage(directory: directory)
    }

    override func tearDownWithError() throws {
        AuthSessionEncryption.keyOverrideForTesting = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTrip() throws {
        let blob = Data(#"{"access_token":"abc","refresh_token":"def"}"#.utf8)
        try storage.store(key: "supabase.auth.token", value: blob)
        let back = try storage.retrieve(key: "supabase.auth.token")
        XCTAssertEqual(back, blob)
    }

    func testOpDiskIsVersleuteld() throws {
        let blob = Data(#"{"access_token":"geheim"}"#.utf8)
        try storage.store(key: "supabase.auth.token", value: blob)
        let raw = try Data(contentsOf: directory.appendingPathComponent("supabase.auth.token.bin"))
        XCTAssertEqual(raw.first, AuthSessionEncryption.magic)
        XCTAssertNil(String(data: raw, encoding: .utf8)?.range(of: "geheim"))
    }

    func testRemove() throws {
        try storage.store(key: "k", value: Data([1, 2, 3]))
        try storage.remove(key: "k")
        XCTAssertNil(try storage.retrieve(key: "k"))
        // Idempotent.
        try storage.remove(key: "k")
    }

    func testStaleSleutelGeeftGeenSessie() throws {
        let blob = Data(#"{"access_token":"abc"}"#.utf8)
        try storage.store(key: "k", value: blob)
        // Nieuwe sleutel ≈ signing-wijziging: decrypt faalt → nil + cleanup.
        AuthSessionEncryption.keyOverrideForTesting = SymmetricKey(size: .bits256)
        XCTAssertNil(try storage.retrieve(key: "k"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("k.bin").path
        ))
    }

    func testPlaintextWordtGeweigerd() throws {
        // 2.0 doet geen plaintext-migratie meer: een niet-versleuteld bestand
        // (bijv. door een aanvaller geplant) wordt geweigerd en opgeruimd i.p.v.
        // als geldige sessie geaccepteerd.
        let url = directory.appendingPathComponent("k.bin")
        let plaintext = Data(#"{"access_token":"legacy"}"#.utf8)
        try plaintext.write(to: url)
        XCTAssertNil(try storage.retrieve(key: "k"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testKeyEscaping() throws {
        try storage.store(key: "rare/key met spaties", value: Data([7]))
        XCTAssertEqual(try storage.retrieve(key: "rare/key met spaties"), Data([7]))
    }
}
