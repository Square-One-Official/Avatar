import Foundation
@testable import AvatarKit

/// E47.1 — URLProtocol-stub als test-seam voor `BackendClient`.
///
/// `BackendClient` accepteert al een `URLSession` via z'n init, dus de minst
/// invasieve seam is een sessie waarvan de configuratie dit protocol als
/// enige handler heeft: elke request (incl. de Storage-PUT van
/// `uploadInputPNG`) komt hier binnen en wordt via een pad-gebaseerde
/// routetabel beantwoord. Geen productie-API's geraakt; bestaande call sites
/// blijven ongemoeid.
final class BackendStubURLProtocol: URLProtocol {
    /// Eén gestubde respons: HTTP-status + body, of een transportfout.
    enum Stub {
        case http(status: Int, body: Data)
        case failure(Error)

        static func json(_ status: Int, _ json: String) -> Stub {
            .http(status: status, body: Data(json.utf8))
        }
    }

    /// Routetabel op URL-pad ("/v1/stylize" → stub). De langste matchende
    /// prefix wint zodat één entry ook query-varianten dekt.
    /// nonisolated(unsafe) + lock: URLProtocol draait op een sessie-thread.
    nonisolated(unsafe) private static var routes: [String: Stub] = [:]
    nonisolated(unsafe) private(set) static var requestLog: [URLRequest] = []
    private static let lock = NSLock()

    static func setStub(_ stub: Stub, forPath path: String) {
        lock.lock(); defer { lock.unlock() }
        routes[path] = stub
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        routes = [:]
        requestLog = []
    }

    private static func stub(forPath path: String) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        if let exact = routes[path] { return exact }
        return routes
            .filter { path.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .value
    }

    private static func log(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requestLog.append(request)
    }

    /// Sessie waarvan élke request door deze stub loopt.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackendStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.log(request)
        let path = request.url?.path ?? ""
        guard let url = request.url, let stub = Self.stub(forPath: path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch stub {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .http(let status, let body):
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// `BackendClient` houdt z'n auth-provider `unowned` vast — de test moet de
/// stub dus zelf in leven houden.
final class BackendStubAuth: AccessTokenProviding {
    var accessToken: String?
    init(accessToken: String? = "test-token") {
        self.accessToken = accessToken
    }
}
