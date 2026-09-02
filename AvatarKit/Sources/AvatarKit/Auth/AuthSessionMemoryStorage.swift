import Auth
import Foundation

/// In-memory `AuthLocalStorage` voor tests en smokes. Bestaat zodat een
/// `AuthService` in een test-host (die in dezelfde sandbox-container draait
/// als de echte app) nooit het echte sessiebestand leest, overschrijft of
/// verwijdert — en dus ook nooit een `/logout` met de echte sessie doet.
/// Start altijd leeg: er is geen sessie, dus `signOut()` is een no-op.
public final class AuthSessionMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func store(key: String, value: Data) throws {
        lock.withLock { values[key] = value }
    }

    public func retrieve(key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    public func remove(key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}
