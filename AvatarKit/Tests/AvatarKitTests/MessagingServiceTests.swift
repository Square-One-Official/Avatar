import Foundation
import XCTest
@testable import AvatarKit

/// E17.3: het verenigde Message-model + de dismiss-filter van MessagingService.
@MainActor
final class MessagingServiceTests: XCTestCase {
    func testFilterDismissedRemovesSeenSlugs() {
        let msgs = [
            Message(slug: "a", title: "A"),
            Message(slug: "b", title: "B"),
            Message(slug: "c", title: "C"),
        ]
        let out = MessagingService.filterDismissed(msgs, dismissed: ["b"])
        XCTAssertEqual(out.map(\.slug), ["a", "c"])
    }

    func testFilterDismissedEmptyKeepsAll() {
        let msgs = [Message(slug: "a", title: "A"), Message(slug: "b", title: "B")]
        XCTAssertEqual(MessagingService.filterDismissed(msgs, dismissed: []).count, 2)
    }

    func testMessageDecodesBackendShape() throws {
        let json = """
        {
          "slug": "welcome-2",
          "title": "Welcome to Aaavatar 2",
          "body": "**Hi!**",
          "imageUrl": "https://cdn.example.com/hero.png",
          "cta": { "label": "Try it", "url": "aaavatar://effects" },
          "frequency": "once"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let m = try decoder.decode(Message.self, from: json)
        XCTAssertEqual(m.slug, "welcome-2")
        XCTAssertEqual(m.title, "Welcome to Aaavatar 2")
        XCTAssertEqual(m.imageUrl?.absoluteString, "https://cdn.example.com/hero.png")
        XCTAssertEqual(m.cta?.label, "Try it")
        XCTAssertEqual(m.cta?.url.scheme, "aaavatar")
        XCTAssertEqual(m.frequency, "once")
    }

    func testMessageDefaultsWhenFieldsMissing() throws {
        let json = #"{ "slug": "x", "title": "X" }"#.data(using: .utf8)!
        let m = try JSONDecoder().decode(Message.self, from: json)
        XCTAssertEqual(m.body, "")
        XCTAssertNil(m.imageUrl)
        XCTAssertNil(m.cta)
        XCTAssertEqual(m.frequency, "once")
    }
}
