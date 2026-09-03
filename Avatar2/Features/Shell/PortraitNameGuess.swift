// Persoonsnaam uit een bestandsnaam (E36.5-vervolg). Een geïmporteerde foto
// heet vaak `Thierry_Emmery_headshot_2024.jpg` of `IMG_4821.HEIC`; het
// Name-veld hoort dan "Thierry Emmery" resp. leeg te zijn — niet de rauwe
// bestandsnaam met camera-ruis. Heuristiek, geen NLP: tokens met cijfers en
// bekende ruiswoorden (img, headshot, copy, …) vallen weg, tussenvoegsels
// (van, de, der, …) blijven alleen tússen naamdelen staan, en de rest wordt
// als naam gekapitaliseerd. Daarbovenop twee offline signalen (Thierry,
// 2026-09-02: "volledig offline"): een gebundeld voornamen-lexicon
// (FirstNameLexicon) als anker — wat vóór de voornaam staat is geen naam, wat
// erna komt is de achternaam — en, als er géén voornaam in zit, een
// woordenboek-check via de systeem-spellingchecker (NSSpellChecker, Engels):
// bestaan alle overgebleven woorden gewoon ("man beard", "square one"), dan is
// het geen naam; een onbekend woord ("looijen", "farzam") blijft als
// (achter)naam staan. NLTagger is hiervoor afgewezen: zijn name-tagging hangt
// aan hoofdlettergebruik en noemt ook "Farzam"/"Madani" gewone woorden.
// Zonder overgebleven naamdelen → "" (het veld toont dan "Add name", zoals bij
// naamloze Data-drops).

import AppKit
import Foundation

enum PortraitNameGuess {

    /// `url` → persoonsnaam of "" als de bestandsnaam er geen bevat.
    static func name(from url: URL) -> String {
        name(fromFileName: url.lastPathComponent)
    }

    /// `fileName` (met of zonder extensie) → persoonsnaam of "".
    static func name(fromFileName fileName: String) -> String {
        let stem = stripExtension(fileName)
        // Figma-/design-export met een expliciet naamveld (`Name=Fren`,
        // `Type=Photo, Name=Anna de Winter`): de waarde ís de naam — ook als
        // die niet in het lexicon staat of toevallig een woord is.
        if let value = namedPropertyValue(in: stem) {
            let trusted = derive(stem: value, trusted: true)
            if !trusted.isEmpty { return trusted }
        }
        return derive(stem: stem, trusted: false)
    }

    /// Waarde achter `name=`/`naam=` tot de volgende eigenschap (`,` `;` `/`).
    private static func namedPropertyValue(in stem: String) -> String? {
        let lower = stem.lowercased()
        for key in ["name=", "naam="] {
            guard let range = lower.range(of: key) else { continue }
            let rest = stem[range.upperBound...]
            let value = rest.prefix { !",;/|".contains($0) }.trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }

    /// Kern van de heuristiek. `trusted`: de tokens komen uit een expliciet
    /// naamveld — de woordenboek-afwijzing (geen voornaam + gewone woorden)
    /// blijft dan uit; ruis en cijfers vallen wél af.
    private static func derive(stem: String, trusted: Bool) -> String {
        // Eerst het hele token tegen de ruislijst ("LinkedIn") en de
        // cijfer-check (CDN-hash "74ZFkSVk" valt als geheel af), pas daarna
        // camelCase-splitsen ("ThierryEmmery") — anders wordt "Linked" of
        // "ZFk" een naam. Een punt-segment dat een hash bevat
        // (`farzam-madani.CATT_2ZK_jTHvU`) valt in z'n geheel weg — ook de
        // cijfervrije brokjes ("CATT") erin zijn geen naamdelen.
        let tokens = stem.split(separator: ".")
            .filter { !isHashSegment(String($0)) }
            .flatMap { tokenize(String($0)) }
            .filter { !noiseWords.contains($0.lowercased()) }
            .compactMap(lettersOnly)
            .flatMap(splitCamelCase)
        let kept = tokens.compactMap(classify)
        let refined = refine(trimParticles(kept), trusted: trusted)
        guard refined.contains(where: \.isName) else { return "" }
        return refined.map(\.rendered).joined(separator: " ")
    }

    // MARK: - Stappen

    private enum Token {
        case name(String)
        case particle(String)

        var rendered: String {
            switch self {
            case .name(let s): return s
            case .particle(let s): return s
            }
        }

        var isName: Bool { if case .name = self { return true } else { return false } }
        var isFirstName: Bool { if case .name(let s) = self { return FirstNameLexicon.contains(s) } else { return false } }
    }

    // MARK: - Voornaam-anker + woordenboek-check

    /// Mét voornaam (lexicon): alles vóór de voornaam valt af — behalve het
    /// "Achternaam Voornaam"-patroon (precies twee naamdelen, `EMMERY_THIERRY`)
    /// — en ná de achternaam stopt de naam bij het eerste gewone woord
    /// (`sanne-jansen-presentation` → "Sanne Jansen"). Zónder voornaam: alleen
    /// een naam als minstens één woord géén woordenboekwoord is.
    private static func refine(_ tokens: [Token], trusted: Bool = false) -> [Token] {
        let names = tokens.filter(\.isName)
        guard !names.isEmpty else { return [] }
        guard let anchor = tokens.firstIndex(where: \.isFirstName) else {
            if trusted { return tokens }
            let words = names.map(\.rendered)
            return words.allSatisfy(isDictionaryWord) ? [] : tokens
        }
        let surnameFirst = names.count == 2 && tokens.firstIndex(where: \.isName) != anchor
            && tokens.lastIndex(where: \.isName) == anchor
        if surnameFirst { return tokens }
        var result: [Token] = []
        var surnameParts = 0
        for token in tokens[anchor...] {
            if token.isName, result.count > 0 {
                if surnameParts >= 1, !token.isFirstName, isDictionaryWord(token.rendered) { break }
                surnameParts += 1
            }
            result.append(token)
        }
        return trimParticles(result)
    }

    /// Engelse spellingchecker: correct gespeld = bekend gewoon woord ("beard",
    /// "square", "winter"); onbekend ("looijen", "farzam", "emmery") = naam.
    /// Kleine letters, anders geldt een hoofdletter als eigennaam. NSSpellChecker
    /// hoort op de main thread; de resolver roept dit vanaf een detached Task.
    private static func isDictionaryWord(_ word: String) -> Bool {
        let check = {
            let range = NSSpellChecker.shared.checkSpelling(
                of: word.lowercased(), startingAt: 0, language: "en", wrap: false,
                inSpellDocumentWithTag: 0, wordCount: nil
            )
            return range.location == NSNotFound
        }
        return Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
    }

    /// Alleen de laatste extensie (`team.profile.jpeg` → `team.profile`); een
    /// stem zonder punt blijft intact. Een "extensie" die geen bekend
    /// beeldtype is (`anna.de.winter`) blijft staan en wordt gewoon gesplitst.
    private static func stripExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        return imageExtensions.contains(ext) ? String(fileName[..<dot]) : fileName
    }

    /// CDN-/export-hash tussen de punten (`name.CATT_2ZK_jTHvU.webp`): één of
    /// meer delen met cijfers middenin of hash-achtig hoofdlettergebruik.
    private static func isHashSegment(_ segment: String) -> Bool {
        // `lettersOnly` = nil voor letters-met-cijfers-middenin ("Z1GiMhz") en
        // hash-achtig hoofdlettergebruik ("74ZFkSVk" → "ZFkSVk", "jTHvU");
        // "anna01"/"2024anna" blijven gewoon namen (randcijfers vallen af).
        tokenize(segment).contains { part in
            part.contains(where: \.isLetter) && lettersOnly(part) == nil
        }
    }

    /// Splitst op `-`, `_`, spatie, punt, `+`, haakjes, komma.
    private static func tokenize(_ stem: String) -> [String] {
        stem.split(whereSeparator: { separators.contains($0) }).map(String.init)
    }

    /// camelCase-grenzen na ≥ 3 tekens (`ThierryEmmery` → `Thierry`, `Emmery`;
    /// `McDonald`/`DeVries` blijven heel).
    private static func splitCamelCase(_ token: String) -> [String] {
        var out: [String] = []
        var current = ""
        var previous: Character?
        for ch in token {
            if let p = previous, p.isLowercase, ch.isUppercase, current.count >= 3 {
                out.append(current); current = ""
            }
            current.append(ch)
            previous = ch
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Cijfers aan de randen vallen af ("thierry2", "anna01", "2024anna" →
    /// naam; "img4821" → "img" → ruis; "p1"/"v2"/"1x" → één letter → ruis;
    /// "400px" → "px" → ruis). Cijfers middenin ("74ZFkSVk", "Z1GiMhz") of
    /// andere tekens → nil (het hele token is ruis).
    private static func lettersOnly(_ token: String) -> String? {
        let raw = String(token.drop(while: \.isNumber).reversed().drop(while: \.isNumber).reversed())
        guard !raw.isEmpty, raw.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return nil }
        // Hash-achtig ("ZFkSVk" uit `74ZFkSVk`): gemengd hoofdletterig mét twee
        // hoofdletters op rij komt in namen niet voor (McDonald/DeVries/JP wel).
        let mixed = raw != raw.lowercased() && raw != raw.uppercased()
        if mixed, zip(raw, raw.dropFirst()).contains(where: { $0.isUppercase && $1.isUppercase }) { return nil }
        return raw
    }

    /// Token → naamdeel, tussenvoegsel of ruis (nil).
    private static func classify(_ raw: String) -> Token? {
        let lower = raw.lowercased()
        if particles.contains(lower) { return .particle(lower) }
        if noiseWords.contains(lower) { return nil }
        // Losse letter zonder apostrof is een initiaal/versieletter → ruis
        // ("t" uit 't blijft via particles behouden).
        guard raw.count >= 2 else { return nil }
        return .name(capitalized(raw))
    }

    /// Tussenvoegsels alleen tússen naamdelen ("van Anna" → "Anna").
    private static func trimParticles(_ tokens: [Token]) -> [Token] {
        var result = tokens
        while let first = result.first, case .particle = first { result.removeFirst() }
        while let last = result.last, case .particle = last { result.removeLast() }
        return result
    }

    /// Volledig klein of volledig groot → Eerste-letter-groot ("thierry" →
    /// "Thierry", "EMMERY" → "Emmery"); korte all-caps (≤ 3, "JP") blijft
    /// staan als initialen; gemengd ("McDonald", "DeVries") blijft intact.
    private static func capitalized(_ raw: String) -> String {
        let isLower = raw == raw.lowercased()
        let isUpper = raw == raw.uppercased()
        if isUpper, raw.count <= 3 { return raw }
        guard isLower || isUpper else { return raw }
        return raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
    }

    // MARK: - Woordenlijsten

    /// Ook `=`, `:`, `;`, `/`, `~`, `!`, `|`: Figma exporteert varianten als
    /// `Name=Ruslan.png` of `Type=Photo, Name=Ruslan.png`.
    private static let separators: Set<Character> = [
        "-", "_", " ", ".", "+", "(", ")", "[", "]", ",", "&", "@", "#", "=", ":", ";", "/", "~", "!", "|", "{", "}",
    ]

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "avif",
        "dng", "raw", "cr2", "cr3", "nef", "arw", "orf", "rw2", "psd",
    ]

    /// Tussenvoegsels (NL/DE/FR/ES/IT/PT/AR) — blijven klein, alleen tussen naamdelen.
    private static let particles: Set<String> = [
        "van", "de", "den", "der", "des", "het", "te", "ten", "ter", "tot", "op", "in", "'t", "’t",
        "von", "zu", "zum", "zur", "und",
        "du", "la", "le", "les", "el", "al", "y", "e", "da", "das", "do", "dos", "di", "del", "della", "dello",
        "bin", "ibn", "af", "av",
    ]

    /// Camera-/bewerkings-/rol-ruis die géén naamdeel is. Bewust breed:
    /// een gemiste ruisterm kost een handmatige rename, een ten onrechte
    /// geschrapt naamdeel ook — dus alleen woorden die vrijwel nooit een
    /// voor- of achternaam zijn.
    private static let noiseWords: Set<String> = [
        // camera/bestand
        "img", "image", "images", "dsc", "dscn", "dcim", "pxl", "mvimg", "pano", "scan", "screenshot", "screen",
        "shot", "capture", "snapshot", "file", "untitled", "unnamed", "unknown", "temp", "tmp", "test", "sample",
        "download", "downloads", "exported", "import", "imported", "attachment",
        // fototermen
        "photo", "photos", "foto", "fotos", "pic", "pics", "picture", "pictures", "portrait", "portraits", "portret",
        "portretten", "headshot", "headshots", "profile", "profiel", "profilepic", "profilepicture", "avatar",
        "avatars", "selfie", "mugshot", "passphoto", "pasfoto", "photoshoot", "shoot", "studio", "camera",
        "photography", "photographer",
        // bewerking/versie
        "copy", "kopie", "final", "finale", "def", "definitief", "edit", "edited", "edits", "retouched", "retouch",
        "cutout", "crop", "cropped", "square", "round", "circle", "bw", "zw", "color", "colour", "kleur",
        "new", "nieuw", "nieuwe", "old", "oud", "oude", "orig", "original", "origineel", "raw", "ai", "gen",
        "generated", "version", "versie", "draft", "concept", "print", "web", "web2", "social", "linkedin",
        "instagram", "twitter", "facebook", "slack", "teams", "zoom", "site", "website", "intranet",
        // formaat/kwaliteit
        "hq", "hd", "lr", "hires", "highres", "lowres", "small", "medium", "large", "xl", "big", "mini",
        "thumb", "thumbnail", "thumbnails", "px", "dpi", "resized", "resize", "scaled", "compressed", "optimized",
        "optimised", "min", "max", "full", "fullsize", "landscape", "vertical", "horizontal", "iphone", "phone",
        // organisatie/rol
        "team", "staff", "employee", "employees", "medewerker", "medewerkers", "collega", "colleague", "member",
        "members", "people", "person", "personeel", "hr", "office", "kantoor", "company", "bedrijf", "corporate",
        "business", "work", "werk", "official", "officieel", "press", "pers",
        // kleur/achtergrond
        "white", "wit", "black", "zwart", "grey", "gray", "grijs", "blue", "blauw", "green", "groen",
        "background", "achtergrond", "bg", "transparent", "transparant", "nobg", "removed",
        // bijwoorden/lidwoorden die als bestandsnaamvulling voorkomen
        "the", "a", "an", "and", "of", "for", "with", "met", "en", "voor", "bij", "zonder", "without",
        "at", "om", "am", "pm", "uur",
        // telwoorden als bestandsnaamvulling ("Square One", "photo two")
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "een", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien",
        // Figma-/design-export-eigenschappen ("Name=Ruslan", "State=Default", "Size=Large")
        "name", "naam", "state", "default", "variant", "property", "type", "size", "frame", "group", "component",
        "instance", "layer", "rectangle", "ellipse", "mask", "style", "theme", "light", "dark", "mode", "hover",
        "active", "selected", "true", "false", "yes", "no", "on", "off", "export", "asset", "assets", "icon", "logo",
        // bekende afbeeldingsextensies als token (bv. "anna.png.jpg")
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "avif", "psd",
    ]
}
