import Foundation

/// Levert het Supabase-bearer-token aan `BackendClient`. In v1 conformeert
/// `AuthManager`; de 2.0-AuthService (E01.6) conformeert hier ook aan zodat
/// dezelfde client in beide apps werkt.
@MainActor
public protocol AccessTokenProviding: AnyObject {
    var accessToken: String? { get }
}
