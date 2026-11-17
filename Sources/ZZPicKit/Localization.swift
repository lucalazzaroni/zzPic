import Foundation

/// Returns the localized version of `key` from the app bundle's `Localizable.strings`.
/// English strings are used as keys, so a missing translation falls back to English.
public func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Localized format string, e.g. `LF("%ld of %ld", 3, 42)`.
public func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: args)
}
