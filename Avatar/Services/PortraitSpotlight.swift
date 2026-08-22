import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes portraits in Spotlight so users can find them via Cmd+Space.
@MainActor
enum PortraitSpotlight {
    private static let domain = "nl.avatar.app.portraits"

    static func index(_ portrait: Portrait) {
        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        attributes.title = portrait.name.isEmpty ? Loc.unnamed : portrait.name
        if !portrait.tags.isEmpty {
            attributes.keywords = portrait.tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            attributes.contentDescription = portrait.tags
        } else {
            attributes.contentDescription = Loc.portraitsPlural
        }
        attributes.identifier = portrait.id.uuidString

        let item = CSSearchableItem(
            uniqueIdentifier: portrait.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                dlog("spotlight index failed: \(error.localizedDescription)")
            }
        }
    }

    static func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: ids.map(\.uuidString)
        ) { error in
            if let error {
                dlog("spotlight delete failed: \(error.localizedDescription)")
            }
        }
    }

    static func reindexAll(portraits: [Portrait]) {
        let items: [CSSearchableItem] = portraits.map { portrait in
            let attributes = CSSearchableItemAttributeSet(contentType: .image)
            attributes.title = portrait.name.isEmpty ? Loc.unnamed : portrait.name
            if !portrait.tags.isEmpty {
                attributes.keywords = portrait.tags
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                attributes.contentDescription = portrait.tags
            }
            attributes.identifier = portrait.id.uuidString
            return CSSearchableItem(
                uniqueIdentifier: portrait.id.uuidString,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { error in
                if let error {
                    dlog("spotlight reindex failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
