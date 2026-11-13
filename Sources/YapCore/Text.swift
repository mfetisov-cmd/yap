import Foundation

/// Interface text: English, or Russian when Russian comes first in the languages macOS gives Yap
/// (System Settings → General → Language & Region, or Yap's own entry under Applications there).
enum Language {
    static let isRussian = Locale.preferredLanguages.first?.hasPrefix("ru") == true
}

func ui(_ english: String, ru russian: String) -> String {
    Language.isRussian ? russian : english
}

/// Text shown in more than one place.
enum Phrase {
    static var copied: String { ui("Copied, press ⌘V to paste", ru: "Скопировано, вставь ⌘V") }
}
