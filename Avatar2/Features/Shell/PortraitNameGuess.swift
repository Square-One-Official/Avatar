// Persoonsnaam uit een bestandsnaam (E36.5-vervolg). Een geïmporteerde foto
// heet vaak `Thierry_Emmery_headshot_2024.jpg` of `IMG_4821.HEIC`; het
// Name-veld hoort dan "Thierry Emmery" resp. leeg te zijn — niet de rauwe
// bestandsnaam met camera-ruis. Heuristiek, geen NLP: tokens met cijfers en
// bekende ruiswoorden (img, headshot, copy, …) vallen weg, tussenvoegsels
// (van, de, der, …) blijven alleen tússen naamdelen staan, en de rest wordt
// als naam gekapitaliseerd. Zonder overgebleven naamdelen → "" (het veld
// toont dan "Add name", zoals bij naamloze Data-drops).

import Foundation

enum PortraitNameGuess {

    /// `url` → persoonsnaam of "" als de bestandsnaam er geen bevat.
    static func name(from url: URL) -> String {
        name(fromFileName: url.lastPathComponent)
    }

    /// `fileName` (met of zonder extensie) → persoonsnaam of "".
    static func name(fromFileName fileName: String) -> String {
        let stem = stripExtension(fileName)
        // Eerst het hele token tegen de ruislijst ("LinkedIn") en de
        // cijfer-check (CDN-hash "74ZFkSVk" valt als geheel af), pas daarna
        // camelCase-splitsen ("ThierryEmmery") — anders wordt "Linked" of
        // "ZFk" een naam.
        let tokens = tokenize(stem)
            .filter { !noiseWords.contains($0.lowercased()) }
            .compactMap(lettersOnly)
            .flatMap(splitCamelCase)
        let kept = tokens.compactMap(classify)
        let trimmed = trimParticles(kept)
        guard trimmed.contains(where: { if case .name = $0 { return true } else { return false } }) else {
            return ""
        }
        return trimmed.map(\.rendered).joined(separator: " ")
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
    }

    /// Alleen de laatste extensie (`team.profile.jpeg` → `team.profile`); een
    /// stem zonder punt blijft intact. Een "extensie" die geen bekend
    /// beeldtype is (`anna.de.winter`) blijft staan en wordt gewoon gesplitst.
    private static func stripExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        return imageExtensions.contains(ext) ? String(fileName[..<dot]) : fileName
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

    private static let separators: Set<Character> = ["-", "_", " ", ".", "+", "(", ")", "[", "]", ",", "&", "@", "#"]

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
        "download", "downloads", "export", "exported", "import", "imported", "attachment",
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
        "the", "a", "an", "and", "of", "for", "with", "met", "en", "een", "voor", "bij", "zonder", "without",
        "at", "om", "on", "am", "pm", "uur",
        // bekende afbeeldingsextensies als token (bv. "anna.png.jpg")
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "avif", "psd",
    ]
}
