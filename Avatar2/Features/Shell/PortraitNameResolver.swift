// Naamresolutie bij import (vervolg op E36.5 / PortraitNameGuess). Drie lagen,
// in volgorde van slimheid:
//   1. Beeld-metadata (IPTC ObjectName/Caption/Keywords, TIFF ImageDescription,
//      PNG Title, Exif UserComment) — fotografen en HR-tools zetten de naam
//      daar vaak in. Gaat als context mee naar laag 2; laag 3 gebruikt alleen
//      de titel-achtige velden (een caption als "Businessman smiling" mag
//      geen naam worden).
//   2. On-device model (Foundation Models, macOS 26 + Apple Intelligence aan):
//      begrijpt context en talen zonder woordenlijsten. Antwoord wordt
//      gevalideerd tegen de input (elk naamdeel moet erin voorkomen — geen
//      verzonnen namen) en is begrensd door een timeout zodat de import nooit
//      op het model wacht. Zegt het model "geen naam", dan geloven we dat.
//   3. Heuristiek (`PortraitNameGuess`) als het model ontbreekt, faalt of
//      iets onhoudbaars teruggeeft.
// Alles draait lokaal; er verlaat niets de Mac.

import Foundation
import ImageIO
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

enum PortraitNameResolver {

    private static let log = Logger(subsystem: "nl.squareone.aaavatar2", category: "PortraitName")

    /// Tests zetten dit uit zodat de uitkomst niet afhangt van Apple
    /// Intelligence op de test-Mac.
    nonisolated(unsafe) static var onDeviceModelEnabled = true

    /// Maximale wachttijd op het on-device model; daarna laag 3.
    static let modelTimeout: Duration = .seconds(4)

    /// Bron-URL (open-panel, Finder-drop, `--import-after`).
    static func resolve(url: URL) async -> String {
        let hints = ImageNameHints.read(url: url)
        return await resolve(fileName: url.lastPathComponent, hints: hints)
    }

    /// Losse beelddata zonder bestandsnaam (drop uit Photos/browser): alleen
    /// metadata kan nog een naam opleveren.
    static func resolve(data: Data) async -> String {
        let hints = ImageNameHints.read(data: data)
        guard !hints.isEmpty else { return "" }
        return await resolve(fileName: "", hints: hints)
    }

    static func resolve(fileName: String, hints: ImageNameHints) async -> String {
        if let answer = await onDeviceAnswer(fileName: fileName, hints: hints) {
            if let name = validated(answer, against: [fileName] + hints.all) {
                log.info("model → \"\(name, privacy: .private)\" for \(fileName, privacy: .private)")
                return name
            }
            log.info("model answer rejected (\"\(answer, privacy: .private)\"), falling back to heuristic")
        }
        for title in hints.titles {
            let name = PortraitNameGuess.name(fromFileName: title)
            if !name.isEmpty {
                log.info("metadata title → \"\(name, privacy: .private)\"")
                return name
            }
        }
        let name = PortraitNameGuess.name(fromFileName: fileName)
        log.info("heuristic → \"\(name, privacy: .private)\" for \(fileName, privacy: .private)")
        return name
    }

    // MARK: - Validatie

    /// Het model mag alleen naamdelen teruggeven die in de input voorkomen
    /// (bestandsnaam of metadata), maximaal 5 delen / 60 tekens. Leeg antwoord
    /// = "geen naam" en is geldig. nil = onhoudbaar → laag 3.
    static func validated(_ answer: String, against corpus: [String]) -> String? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count <= 60 else { return nil }
        let tokens = trimmed
            .split(whereSeparator: { !$0.isLetter })
            .map { fold($0) }
            .filter { !$0.isEmpty }
        guard (1...5).contains(tokens.count) else { return nil }
        let haystack = fold(corpus.joined(separator: " "))
        guard tokens.allSatisfy({ haystack.contains($0) }) else { return nil }
        return trimmed
    }

    /// Accent- en hoofdletter-ongevoelig, apostrofs weg (O'Neill ~ oneill).
    private static func fold(_ s: some StringProtocol) -> String {
        String(s).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
    }

    // MARK: - Laag 2: on-device model

    /// nil = model niet beschikbaar/uitgezet/timeout/fout → laag 3 beslist.
    private static func onDeviceAnswer(fileName: String, hints: ImageNameHints) async -> String? {
        guard onDeviceModelEnabled, !fileName.isEmpty || !hints.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return await OnDeviceNameModel.personName(fileName: fileName, hints: hints, timeout: modelTimeout)
        }
        #endif
        return nil
    }
}

// MARK: - Laag 1: metadata

/// Naam-hints uit de beeldbestand-metadata. `titles` = titel-achtige velden
/// (mag laag 3 direct gebruiken); `descriptions` = captions/keywords/comments
/// (alleen als context voor het model).
struct ImageNameHints: Equatable {
    var titles: [String] = []
    var descriptions: [String] = []

    var isEmpty: Bool { titles.isEmpty && descriptions.isEmpty }
    var all: [String] { titles + descriptions }

    static func read(url: URL) -> ImageNameHints {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return .init() }
        return read(source: source)
    }

    static func read(data: Data) -> ImageNameHints {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return .init() }
        return read(source: source)
    }

    static func read(source: CGImageSource) -> ImageNameHints {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .init()
        }
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        var hints = ImageNameHints()
        hints.titles = clean([iptc[kCGImagePropertyIPTCObjectName], png[kCGImagePropertyPNGTitle]])
        var descriptions: [Any?] = [
            iptc[kCGImagePropertyIPTCCaptionAbstract],
            tiff[kCGImagePropertyTIFFImageDescription],
            png[kCGImagePropertyPNGDescription],
            exif[kCGImagePropertyExifUserComment],
        ]
        if let keywords = iptc[kCGImagePropertyIPTCKeywords] as? [Any] { descriptions.append(contentsOf: keywords) }
        // Een description die letterlijk de titel is, hoeft niet dubbel mee.
        hints.descriptions = clean(descriptions).filter { !hints.titles.contains($0) }
        return hints
    }

    /// Strings, getrimd, 2…120 tekens, ontdubbeld in volgorde.
    private static func clean(_ values: [Any?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value -> String? in
            let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard s.count >= 2, s.count <= 120, seen.insert(s).inserted else { return nil }
            return s
        }
    }
}

// MARK: - Laag 2: Foundation Models

#if canImport(FoundationModels)
@available(macOS 26, *)
enum OnDeviceNameModel {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @Generable
    struct Answer {
        @Guide(description: """
            The full name of the person the image is a portrait of, with normal capitalisation \
            (e.g. "Anna de Winter"), using only words that appear in the input. \
            Empty string if the input contains no person name.
            """)
        var fullName: String
    }

    private static let instructions = """
        You extract a person's name from an image file name and optional image metadata. \
        File names come from cameras, exports, CDNs and HR tools. \
        Ignore camera prefixes (IMG, DSC), dates, times, random hashes, sizes, version markers and \
        words such as portrait, headshot, photo, copy, final, LinkedIn, team, profile. \
        Keep Dutch, German, French or Spanish name particles (van, de, der, von, du, el) in lowercase \
        between name parts. Company names, job titles and places are not person names. \
        If there is no person name, return an empty string. Never invent or complete a name.
        """

    /// nil bij onbeschikbaar, timeout of fout; anders het (ongevalideerde) antwoord.
    static func personName(fileName: String, hints: ImageNameHints, timeout: Duration) async -> String? {
        guard isAvailable else { return nil }
        var prompt = "File name: \(fileName.isEmpty ? "(unknown)" : fileName)"
        if !hints.titles.isEmpty { prompt += "\nMetadata title: \(hints.titles.joined(separator: " | "))" }
        if !hints.descriptions.isEmpty {
            prompt += "\nMetadata description/keywords: \(hints.descriptions.joined(separator: " | "))"
        }
        let request = prompt
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                let response = try? await session.respond(to: request, generating: Answer.self)
                return response?.content.fullName
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
#endif
