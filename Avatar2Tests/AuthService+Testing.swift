import AvatarKit
import Foundation

extension AuthService {
    /// Test-instantie met in-memory sessieopslag. Gebruik in tests altijd
    /// deze i.p.v. `AuthService()`: de test-host is de echte app en deelt
    /// haar sandbox-container, dus de default file-storage zou het echte
    /// sessiebestand van de ontwikkelaar lezen en bij `signOut()` wissen
    /// (plus alle refresh-tokens serverzijde intrekken).
    @MainActor
    static func isolated() -> AuthService {
        AuthService(storage: AuthSessionMemoryStorage())
    }
}
