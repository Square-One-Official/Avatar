// E49.2: één bron voor de publieke aaavatar.nl-links. De privacy-URL stond op
// drie plekken hardcoded en was in Settings/About `/privacy` (404) i.p.v. het
// live `/privacy-policy` — één constante voorkomt dat ze uit elkaar lopen.

import Foundation

enum AppLinks {
    static let website = URL(string: "https://aaavatar.nl")!
    static let termsOfService = URL(string: "https://aaavatar.nl/terms-of-service")!
    static let privacyPolicy = URL(string: "https://aaavatar.nl/privacy-policy")!
}
