import ReadRevsCore
import Foundation

struct TargetPreset: Identifiable, Hashable {
    var id: String { target.id }
    let title: String
    let target: StoreTarget
}

enum ResearchPresets {
    private struct StorefrontPreset {
        let country: String
        let languageName: String
        let languageCode: String
        let storeCode: String

        var targetPreset: TargetPreset {
            TargetPreset(
                title: "\(languageName) · \(storeCode.uppercased())",
                target: StoreTarget(language: languageCode, store: storeCode)
            )
        }
    }

    // Keep the original research markets first, then list additional markets by country.
    private static let storefronts = [
        StorefrontPreset(country: "Czechia", languageName: "Czech", languageCode: "cs", storeCode: "cz"),
        StorefrontPreset(country: "United States", languageName: "English", languageCode: "en", storeCode: "us"),
        StorefrontPreset(country: "United Kingdom", languageName: "English", languageCode: "en", storeCode: "gb"),
        StorefrontPreset(country: "Spain", languageName: "Spanish", languageCode: "es", storeCode: "es"),
        StorefrontPreset(country: "Germany", languageName: "German", languageCode: "de", storeCode: "de"),
        StorefrontPreset(country: "France", languageName: "French", languageCode: "fr", storeCode: "fr"),
        StorefrontPreset(country: "Korea", languageName: "Korean", languageCode: "ko", storeCode: "kr"),
        StorefrontPreset(country: "Afghanistan", languageName: "Persian", languageCode: "fa", storeCode: "af"),
        StorefrontPreset(country: "Albania", languageName: "Albanian", languageCode: "sq", storeCode: "al"),
        StorefrontPreset(country: "Algeria", languageName: "Arabic", languageCode: "ar", storeCode: "dz"),
        StorefrontPreset(country: "Andorra", languageName: "Catalan", languageCode: "ca", storeCode: "ad"),
        StorefrontPreset(country: "Angola", languageName: "Portuguese", languageCode: "pt", storeCode: "ao"),
        StorefrontPreset(country: "Argentina", languageName: "Spanish", languageCode: "es", storeCode: "ar"),
        StorefrontPreset(country: "Armenia", languageName: "Armenian", languageCode: "hy", storeCode: "am"),
        StorefrontPreset(country: "Australia", languageName: "English", languageCode: "en", storeCode: "au"),
        StorefrontPreset(country: "Austria", languageName: "German", languageCode: "de", storeCode: "at"),
        StorefrontPreset(country: "Azerbaijan", languageName: "Azerbaijani", languageCode: "az", storeCode: "az"),
        StorefrontPreset(country: "Bahamas", languageName: "English", languageCode: "en", storeCode: "bs"),
        StorefrontPreset(country: "Bahrain", languageName: "Arabic", languageCode: "ar", storeCode: "bh"),
        StorefrontPreset(country: "Bangladesh", languageName: "Bengali", languageCode: "bn", storeCode: "bd"),
        StorefrontPreset(country: "Barbados", languageName: "English", languageCode: "en", storeCode: "bb"),
        StorefrontPreset(country: "Belarus", languageName: "Russian", languageCode: "ru", storeCode: "by"),
        StorefrontPreset(country: "Belgium", languageName: "Dutch", languageCode: "nl", storeCode: "be"),
        StorefrontPreset(country: "Belize", languageName: "English", languageCode: "en", storeCode: "bz"),
        StorefrontPreset(country: "Benin", languageName: "French", languageCode: "fr", storeCode: "bj"),
        StorefrontPreset(country: "Bhutan", languageName: "English", languageCode: "en", storeCode: "bt"),
        StorefrontPreset(country: "Bolivia", languageName: "Spanish", languageCode: "es", storeCode: "bo"),
        StorefrontPreset(country: "Bosnia and Herzegovina", languageName: "Bosnian", languageCode: "bs", storeCode: "ba"),
        StorefrontPreset(country: "Botswana", languageName: "English", languageCode: "en", storeCode: "bw"),
        StorefrontPreset(country: "Brazil", languageName: "Portuguese", languageCode: "pt", storeCode: "br"),
        StorefrontPreset(country: "Brunei", languageName: "Malay", languageCode: "ms", storeCode: "bn"),
        StorefrontPreset(country: "Bulgaria", languageName: "Bulgarian", languageCode: "bg", storeCode: "bg"),
        StorefrontPreset(country: "Burkina Faso", languageName: "French", languageCode: "fr", storeCode: "bf"),
        StorefrontPreset(country: "Cabo Verde", languageName: "Portuguese", languageCode: "pt", storeCode: "cv"),
        StorefrontPreset(country: "Cambodia", languageName: "Khmer", languageCode: "km", storeCode: "kh"),
        StorefrontPreset(country: "Cameroon", languageName: "French", languageCode: "fr", storeCode: "cm"),
        StorefrontPreset(country: "Canada", languageName: "English", languageCode: "en", storeCode: "ca"),
        StorefrontPreset(country: "Chile", languageName: "Spanish", languageCode: "es", storeCode: "cl"),
        StorefrontPreset(country: "China mainland", languageName: "Chinese", languageCode: "zh", storeCode: "cn"),
        StorefrontPreset(country: "Colombia", languageName: "Spanish", languageCode: "es", storeCode: "co"),
        StorefrontPreset(country: "Costa Rica", languageName: "Spanish", languageCode: "es", storeCode: "cr"),
        StorefrontPreset(country: "Cote d'Ivoire", languageName: "French", languageCode: "fr", storeCode: "ci"),
        StorefrontPreset(country: "Croatia", languageName: "Croatian", languageCode: "hr", storeCode: "hr"),
        StorefrontPreset(country: "Cyprus", languageName: "Greek", languageCode: "el", storeCode: "cy"),
        StorefrontPreset(country: "Denmark", languageName: "Danish", languageCode: "da", storeCode: "dk"),
        StorefrontPreset(country: "Dominican Republic", languageName: "Spanish", languageCode: "es", storeCode: "do"),
        StorefrontPreset(country: "Ecuador", languageName: "Spanish", languageCode: "es", storeCode: "ec"),
        StorefrontPreset(country: "Egypt", languageName: "Arabic", languageCode: "ar", storeCode: "eg"),
        StorefrontPreset(country: "El Salvador", languageName: "Spanish", languageCode: "es", storeCode: "sv"),
        StorefrontPreset(country: "Estonia", languageName: "Estonian", languageCode: "et", storeCode: "ee"),
        StorefrontPreset(country: "Fiji", languageName: "English", languageCode: "en", storeCode: "fj"),
        StorefrontPreset(country: "Finland", languageName: "Finnish", languageCode: "fi", storeCode: "fi"),
        StorefrontPreset(country: "Gabon", languageName: "French", languageCode: "fr", storeCode: "ga"),
        StorefrontPreset(country: "Gambia", languageName: "English", languageCode: "en", storeCode: "gm"),
        StorefrontPreset(country: "Georgia", languageName: "Georgian", languageCode: "ka", storeCode: "ge"),
        StorefrontPreset(country: "Ghana", languageName: "English", languageCode: "en", storeCode: "gh"),
        StorefrontPreset(country: "Greece", languageName: "Greek", languageCode: "el", storeCode: "gr"),
        StorefrontPreset(country: "Guatemala", languageName: "Spanish", languageCode: "es", storeCode: "gt"),
        StorefrontPreset(country: "Guyana", languageName: "English", languageCode: "en", storeCode: "gy"),
        StorefrontPreset(country: "Honduras", languageName: "Spanish", languageCode: "es", storeCode: "hn"),
        StorefrontPreset(country: "Hong Kong", languageName: "Chinese", languageCode: "zh", storeCode: "hk"),
        StorefrontPreset(country: "Hungary", languageName: "Hungarian", languageCode: "hu", storeCode: "hu"),
        StorefrontPreset(country: "Iceland", languageName: "Icelandic", languageCode: "is", storeCode: "is"),
        StorefrontPreset(country: "India", languageName: "English", languageCode: "en", storeCode: "in"),
        StorefrontPreset(country: "Indonesia", languageName: "Indonesian", languageCode: "id", storeCode: "id"),
        StorefrontPreset(country: "Iraq", languageName: "Arabic", languageCode: "ar", storeCode: "iq"),
        StorefrontPreset(country: "Ireland", languageName: "English", languageCode: "en", storeCode: "ie"),
        StorefrontPreset(country: "Israel", languageName: "Hebrew", languageCode: "he", storeCode: "il"),
        StorefrontPreset(country: "Italy", languageName: "Italian", languageCode: "it", storeCode: "it"),
        StorefrontPreset(country: "Jamaica", languageName: "English", languageCode: "en", storeCode: "jm"),
        StorefrontPreset(country: "Japan", languageName: "Japanese", languageCode: "ja", storeCode: "jp"),
        StorefrontPreset(country: "Jordan", languageName: "Arabic", languageCode: "ar", storeCode: "jo"),
        StorefrontPreset(country: "Kazakhstan", languageName: "Russian", languageCode: "ru", storeCode: "kz"),
        StorefrontPreset(country: "Kenya", languageName: "English", languageCode: "en", storeCode: "ke"),
        StorefrontPreset(country: "Kuwait", languageName: "Arabic", languageCode: "ar", storeCode: "kw"),
        StorefrontPreset(country: "Kyrgyzstan", languageName: "Russian", languageCode: "ru", storeCode: "kg"),
        StorefrontPreset(country: "Laos", languageName: "Lao", languageCode: "lo", storeCode: "la"),
        StorefrontPreset(country: "Latvia", languageName: "Latvian", languageCode: "lv", storeCode: "lv"),
        StorefrontPreset(country: "Lebanon", languageName: "Arabic", languageCode: "ar", storeCode: "lb"),
        StorefrontPreset(country: "Lithuania", languageName: "Lithuanian", languageCode: "lt", storeCode: "lt"),
        StorefrontPreset(country: "Luxembourg", languageName: "French", languageCode: "fr", storeCode: "lu"),
        StorefrontPreset(country: "Macao", languageName: "Chinese", languageCode: "zh", storeCode: "mo"),
        StorefrontPreset(country: "Madagascar", languageName: "French", languageCode: "fr", storeCode: "mg"),
        StorefrontPreset(country: "Malawi", languageName: "English", languageCode: "en", storeCode: "mw"),
        StorefrontPreset(country: "Malaysia", languageName: "Malay", languageCode: "ms", storeCode: "my"),
        StorefrontPreset(country: "Maldives", languageName: "English", languageCode: "en", storeCode: "mv"),
        StorefrontPreset(country: "Mali", languageName: "French", languageCode: "fr", storeCode: "ml"),
        StorefrontPreset(country: "Malta", languageName: "English", languageCode: "en", storeCode: "mt"),
        StorefrontPreset(country: "Mauritius", languageName: "English", languageCode: "en", storeCode: "mu"),
        StorefrontPreset(country: "Mexico", languageName: "Spanish", languageCode: "es", storeCode: "mx"),
        StorefrontPreset(country: "Moldova", languageName: "Romanian", languageCode: "ro", storeCode: "md"),
        StorefrontPreset(country: "Mongolia", languageName: "Mongolian", languageCode: "mn", storeCode: "mn"),
        StorefrontPreset(country: "Montenegro", languageName: "Serbian", languageCode: "sr", storeCode: "me"),
        StorefrontPreset(country: "Morocco", languageName: "Arabic", languageCode: "ar", storeCode: "ma"),
        StorefrontPreset(country: "Mozambique", languageName: "Portuguese", languageCode: "pt", storeCode: "mz"),
        StorefrontPreset(country: "Myanmar", languageName: "Burmese", languageCode: "my", storeCode: "mm"),
        StorefrontPreset(country: "Namibia", languageName: "English", languageCode: "en", storeCode: "na"),
        StorefrontPreset(country: "Nepal", languageName: "Nepali", languageCode: "ne", storeCode: "np"),
        StorefrontPreset(country: "Netherlands", languageName: "Dutch", languageCode: "nl", storeCode: "nl"),
        StorefrontPreset(country: "New Zealand", languageName: "English", languageCode: "en", storeCode: "nz"),
        StorefrontPreset(country: "Nicaragua", languageName: "Spanish", languageCode: "es", storeCode: "ni"),
        StorefrontPreset(country: "Niger", languageName: "French", languageCode: "fr", storeCode: "ne"),
        StorefrontPreset(country: "Nigeria", languageName: "English", languageCode: "en", storeCode: "ng"),
        StorefrontPreset(country: "North Macedonia", languageName: "Macedonian", languageCode: "mk", storeCode: "mk"),
        StorefrontPreset(country: "Norway", languageName: "Norwegian", languageCode: "nb", storeCode: "no"),
        StorefrontPreset(country: "Oman", languageName: "Arabic", languageCode: "ar", storeCode: "om"),
        StorefrontPreset(country: "Pakistan", languageName: "English", languageCode: "en", storeCode: "pk"),
        StorefrontPreset(country: "Panama", languageName: "Spanish", languageCode: "es", storeCode: "pa"),
        StorefrontPreset(country: "Paraguay", languageName: "Spanish", languageCode: "es", storeCode: "py"),
        StorefrontPreset(country: "Peru", languageName: "Spanish", languageCode: "es", storeCode: "pe"),
        StorefrontPreset(country: "Philippines", languageName: "English", languageCode: "en", storeCode: "ph"),
        StorefrontPreset(country: "Poland", languageName: "Polish", languageCode: "pl", storeCode: "pl"),
        StorefrontPreset(country: "Portugal", languageName: "Portuguese", languageCode: "pt", storeCode: "pt"),
        StorefrontPreset(country: "Puerto Rico", languageName: "Spanish", languageCode: "es", storeCode: "pr"),
        StorefrontPreset(country: "Qatar", languageName: "Arabic", languageCode: "ar", storeCode: "qa"),
        StorefrontPreset(country: "Romania", languageName: "Romanian", languageCode: "ro", storeCode: "ro"),
        StorefrontPreset(country: "Russia", languageName: "Russian", languageCode: "ru", storeCode: "ru"),
        StorefrontPreset(country: "Rwanda", languageName: "English", languageCode: "en", storeCode: "rw"),
        StorefrontPreset(country: "Saudi Arabia", languageName: "Arabic", languageCode: "ar", storeCode: "sa"),
        StorefrontPreset(country: "Senegal", languageName: "French", languageCode: "fr", storeCode: "sn"),
        StorefrontPreset(country: "Serbia", languageName: "Serbian", languageCode: "sr", storeCode: "rs"),
        StorefrontPreset(country: "Seychelles", languageName: "English", languageCode: "en", storeCode: "sc"),
        StorefrontPreset(country: "Singapore", languageName: "English", languageCode: "en", storeCode: "sg"),
        StorefrontPreset(country: "Slovakia", languageName: "Slovak", languageCode: "sk", storeCode: "sk"),
        StorefrontPreset(country: "Slovenia", languageName: "Slovenian", languageCode: "sl", storeCode: "si"),
        StorefrontPreset(country: "South Africa", languageName: "English", languageCode: "en", storeCode: "za"),
        StorefrontPreset(country: "Sri Lanka", languageName: "English", languageCode: "en", storeCode: "lk"),
        StorefrontPreset(country: "Suriname", languageName: "Dutch", languageCode: "nl", storeCode: "sr"),
        StorefrontPreset(country: "Sweden", languageName: "Swedish", languageCode: "sv", storeCode: "se"),
        StorefrontPreset(country: "Switzerland", languageName: "German", languageCode: "de", storeCode: "ch"),
        StorefrontPreset(country: "Taiwan", languageName: "Chinese", languageCode: "zh", storeCode: "tw"),
        StorefrontPreset(country: "Tanzania", languageName: "Swahili", languageCode: "sw", storeCode: "tz"),
        StorefrontPreset(country: "Thailand", languageName: "Thai", languageCode: "th", storeCode: "th"),
        StorefrontPreset(country: "Trinidad and Tobago", languageName: "English", languageCode: "en", storeCode: "tt"),
        StorefrontPreset(country: "Tunisia", languageName: "Arabic", languageCode: "ar", storeCode: "tn"),
        StorefrontPreset(country: "Türkiye", languageName: "Turkish", languageCode: "tr", storeCode: "tr"),
        StorefrontPreset(country: "Uganda", languageName: "English", languageCode: "en", storeCode: "ug"),
        StorefrontPreset(country: "Ukraine", languageName: "Ukrainian", languageCode: "uk", storeCode: "ua"),
        StorefrontPreset(country: "United Arab Emirates", languageName: "Arabic", languageCode: "ar", storeCode: "ae"),
        StorefrontPreset(country: "Uruguay", languageName: "Spanish", languageCode: "es", storeCode: "uy"),
        StorefrontPreset(country: "Uzbekistan", languageName: "Uzbek", languageCode: "uz", storeCode: "uz"),
        StorefrontPreset(country: "Venezuela", languageName: "Spanish", languageCode: "es", storeCode: "ve"),
        StorefrontPreset(country: "Vietnam", languageName: "Vietnamese", languageCode: "vi", storeCode: "vn"),
        StorefrontPreset(country: "Zambia", languageName: "English", languageCode: "en", storeCode: "zm"),
        StorefrontPreset(country: "Zimbabwe", languageName: "English", languageCode: "en", storeCode: "zw"),
    ]

    static let targets = storefronts.map(\.targetPreset)

    static let genres = ["Education", "Games", "Travel", "Reference", "Entertainment", "Lifestyle"]

    static let storeTitles = Dictionary(
        uniqueKeysWithValues: storefronts.map { ($0.storeCode, $0.country) }
    )

    private static let targetsByStore = Dictionary(
        uniqueKeysWithValues: targets.map { ($0.target.store, $0.target) }
    )

    static func target(for storeCode: String) -> StoreTarget? {
        let normalizedCode = storeCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return targetsByStore[normalizedCode]
    }
}
